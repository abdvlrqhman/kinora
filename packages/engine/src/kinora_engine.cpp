// Kinora engine: one libtorrent session plus a small HTTP range server that
// streams any file of any torrent while it downloads. See kinora_engine.h.
//
// Threads
// - alert thread: drains libtorrent alerts, keeps a cached JSON status per
//   torrent and a per-piece "have" bitfield, wakes stream readers.
// - accept thread + one thread per HTTP connection (bounded): a connection
//   moves a window of piece deadlines along the read position (time-critical
//   picker), waits for each piece, then reads it straight from disk.
#include "kinora_engine.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/fingerprint.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/posix_disk_io.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/socket.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>

static_assert(sizeof(off_t) == 8, "kinora_engine needs a 64-bit off_t (_FILE_OFFSET_BITS=64)");

#if defined(__APPLE__)
#define KN_SEND_FLAGS 0
#else
#define KN_SEND_FLAGS MSG_NOSIGNAL
#endif

namespace lt = libtorrent;
using namespace std::chrono_literals;
using steady = std::chrono::steady_clock;

namespace {

constexpr const char* kEngineVersion = "0.1.0";
constexpr int kMaxClients = 24;
constexpr std::size_t kMaxEvents = 2000;
constexpr std::int64_t kMinReadahead = 24ll << 20;
constexpr std::int64_t kMaxReadahead = 384ll << 20;

// ---------------------------------------------------------------- helpers --

char* dup_string(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out == nullptr) return nullptr;
  std::memcpy(out, s.data(), s.size());
  out[s.size()] = '\0';
  return out;
}

std::string hex_of(const lt::sha1_hash& h) {
  static const char* digits = "0123456789abcdef";
  std::string out;
  out.reserve(40);
  for (char c : h) {
    auto b = static_cast<unsigned char>(c);
    out.push_back(digits[b >> 4]);
    out.push_back(digits[b & 15]);
  }
  return out;
}

// 128 bits from the OS generator; tokens guard routes reachable on the LAN.
std::string random_token() {
  static std::mutex mu;
  static std::random_device rd;
  std::lock_guard<std::mutex> lk(mu);
  char buf[33];
  std::snprintf(buf, sizeof(buf), "%08x%08x%08x%08x", rd(), rd(), rd(), rd());
  return std::string(buf, 32);
}

std::string json_escape(lt::string_view in) {
  std::string out;
  out.reserve(in.size() + 2);
  out.push_back('"');
  for (char c : in) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(c);
        }
    }
  }
  out.push_back('"');
  return out;
}

std::string error_json(const std::string& message) {
  return "{\"error\":" + json_escape(message) + "}";
}

// Percent-encodes a file name for use as the last URL segment.
std::string url_leaf(const std::string& path) {
  auto slash = path.find_last_of("/\\");
  std::string leaf = slash == std::string::npos ? path : path.substr(slash + 1);
  static const char* digits = "0123456789ABCDEF";
  std::string out;
  for (unsigned char c : leaf) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back('%');
      out.push_back(digits[c >> 4]);
      out.push_back(digits[c & 15]);
    }
  }
  return out.empty() ? std::string("file") : out;
}

std::string lower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return s;
}

std::string mime_for(const std::string& path) {
  auto dot = path.find_last_of('.');
  std::string ext = dot == std::string::npos ? "" : lower(path.substr(dot + 1));
  static const std::map<std::string, std::string> table = {
      {"mkv", "video/x-matroska"}, {"mk3d", "video/x-matroska"},
      {"mp4", "video/mp4"},        {"m4v", "video/mp4"},
      {"mov", "video/quicktime"},  {"webm", "video/webm"},
      {"avi", "video/x-msvideo"},  {"ts", "video/mp2t"},
      {"m2ts", "video/mp2t"},      {"mts", "video/mp2t"},
      {"wmv", "video/x-ms-wmv"},   {"flv", "video/x-flv"},
      {"mpg", "video/mpeg"},       {"mpeg", "video/mpeg"},
      {"mp3", "audio/mpeg"},       {"flac", "audio/flac"},
      {"m4a", "audio/mp4"},        {"srt", "text/srt"},
      {"vtt", "text/vtt"},         {"ass", "text/x-ssa"},
      {"ssa", "text/x-ssa"},       {"jpg", "image/jpeg"},
      {"png", "image/png"},
  };
  auto it = table.find(ext);
  return it == table.end() ? std::string("application/octet-stream") : it->second;
}

bool read_file(const std::string& path, std::vector<char>& out) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
  return true;
}

bool write_file_atomic(const std::string& path, const std::vector<char>& data) {
  std::string tmp = path + ".tmp";
  {
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    out.write(data.data(), static_cast<std::streamsize>(data.size()));
    if (!out) return false;
  }
  return std::rename(tmp.c_str(), path.c_str()) == 0;
}

lt::bdecode_node decode(const uint8_t* data, int32_t len, lt::error_code& ec) {
  if (data == nullptr || len <= 0) {
    ec = lt::bdecode_errors::make_error_code(lt::bdecode_errors::unexpected_eof);
    return {};
  }
  return lt::bdecode({reinterpret_cast<const char*>(data), len}, ec);
}

std::string str_of(const lt::bdecode_node& d, const char* key, const char* def = "") {
  return std::string(d.dict_find_string_value(key, def));
}

std::int64_t int_of(const lt::bdecode_node& d, const char* key, std::int64_t def) {
  return d.dict_find_int_value(key, def);
}

const char* state_name(lt::torrent_status::state_t s) {
  switch (s) {
    case lt::torrent_status::checking_files: return "checking";
    case lt::torrent_status::downloading_metadata: return "metadata";
    case lt::torrent_status::downloading: return "downloading";
    case lt::torrent_status::finished: return "finished";
    case lt::torrent_status::seeding: return "seeding";
    case lt::torrent_status::checking_resume_data: return "checking";
    default: return "unknown";
  }
}

// ---------------------------------------------------------------- model ----

struct Torrent {
  lt::torrent_handle handle;
  std::string ih;
  std::shared_ptr<const lt::torrent_info> ti;
  std::vector<std::uint8_t> have;
  int piece_len = 0;
  int num_pieces = 0;
  std::string status_json;
  // Bumped when a connection drops its deadlines, so the others re-assert.
  std::uint32_t window_epoch = 0;
};

struct Route {
  bool is_stream = false;
  std::string token;
  std::string path;  // URL path
  std::string mime;
  std::map<std::string, std::string> headers;
  std::atomic<bool> closed{false};
  // stream
  std::string ih;
  int file_index = -1;
  std::int64_t file_offset = 0;
  std::int64_t size = 0;
  std::string disk_path;
  std::int64_t bitrate = 0;
  std::int64_t readahead = 64ll << 20;
  std::atomic<std::int64_t> position{0};
  std::atomic<int> connections{0};
};

}  // namespace

struct kn_session {
  std::unique_ptr<lt::session> ses;
  std::string state_path;
  std::string resume_dir;
  bool test_mode = false;

  std::mutex mu;  // torrents, by_handle, routes, events
  std::condition_variable piece_cv;
  std::map<std::string, Torrent> torrents;
  std::unordered_map<lt::torrent_handle, std::string> by_handle;
  std::map<std::string, std::shared_ptr<Route>> routes;
  std::deque<std::string> events;
  std::atomic<int> pending_resume{0};
  int connect_failures = 0;  // alert thread only

  std::thread alert_thread;
  std::atomic<bool> stopping{false};

  std::mutex server_mu;
  int listen_fd = -1;
  int port = 0;
  std::thread accept_thread;
  std::set<int> client_fds;
  std::atomic<int> client_count{0};
};

namespace {

// The process-wide session when the app asked for a shared one.
std::mutex g_shared_mu;
kn_session* g_shared = nullptr;

void push_event(kn_session* s, std::string json) {
  // caller holds s->mu
  s->events.push_back(std::move(json));
  while (s->events.size() > kMaxEvents) s->events.pop_front();
}

void push_log(kn_session* s, const std::string& message) {
  std::lock_guard<std::mutex> lk(s->mu);
  push_event(s, "{\"type\":\"log\",\"message\":" + json_escape(message) + "}");
}

// Fills piece info + have bitfield. Caller holds s->mu.
void init_pieces(Torrent& t, const lt::typed_bitfield<lt::piece_index_t>* pieces) {
  if (!t.ti) return;
  t.piece_len = t.ti->piece_length();
  t.num_pieces = t.ti->num_pieces();
  t.have.assign(static_cast<std::size_t>(t.num_pieces), 0);
  if (pieces != nullptr && pieces->size() == t.num_pieces) {
    for (int i = 0; i < t.num_pieces; ++i) {
      if ((*pieces)[lt::piece_index_t{i}]) t.have[static_cast<std::size_t>(i)] = 1;
    }
  }
}

std::string status_json(const lt::torrent_status& st, const std::string& ih) {
  std::ostringstream o;
  o << "{\"ih\":\"" << ih << "\""
    << ",\"name\":" << json_escape(st.name)
    << ",\"state\":\"" << state_name(st.state) << "\""
    << ",\"paused\":" << ((st.flags & lt::torrent_flags::paused) ? "true" : "false")
    << ",\"has_metadata\":" << (st.has_metadata ? "true" : "false")
    << ",\"progress\":" << st.progress
    << ",\"total_wanted\":" << st.total_wanted
    << ",\"total_wanted_done\":" << st.total_wanted_done
    << ",\"total_done\":" << st.total_done
    << ",\"download_rate\":" << st.download_payload_rate
    << ",\"upload_rate\":" << st.upload_payload_rate
    << ",\"num_peers\":" << st.num_peers
    << ",\"num_seeds\":" << st.num_seeds
    << ",\"list_peers\":" << st.list_peers
    << ",\"list_seeds\":" << st.list_seeds
    << ",\"num_complete\":" << st.num_complete
    << ",\"num_incomplete\":" << st.num_incomplete
    << ",\"connect_candidates\":" << st.connect_candidates
    << ",\"all_time_download\":" << st.all_time_download
    << ",\"all_time_upload\":" << st.all_time_upload
    << ",\"save_path\":" << json_escape(st.save_path)
    << ",\"error\":" << (st.errc ? json_escape(st.errc.message()) : std::string("null"))
    << "}";
  return o.str();
}

std::string resume_path(kn_session* s, const std::string& ih) {
  if (s->resume_dir.empty()) return {};
  return s->resume_dir + "/" + ih + ".fastresume";
}

void request_resume(kn_session* s, const lt::torrent_handle& h, bool only_if_modified) {
  if (s->resume_dir.empty() || !h.is_valid()) return;
  lt::resume_data_flags_t flags = lt::torrent_handle::save_info_dict;
  if (only_if_modified) flags |= lt::torrent_handle::only_if_modified;
  s->pending_resume.fetch_add(1);
  h.save_resume_data(flags);
}

// ---------------------------------------------------------------- alerts ---

void handle_alert(kn_session* s, lt::alert* a) {
  if (auto* p = lt::alert_cast<lt::piece_finished_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(p->handle);
    if (it == s->by_handle.end()) return;
    Torrent& t = s->torrents[it->second];
    int idx = static_cast<int>(p->piece_index);
    if (idx >= 0 && idx < static_cast<int>(t.have.size())) t.have[static_cast<std::size_t>(idx)] = 1;
    s->piece_cv.notify_all();
    return;
  }
  if (auto* su = lt::alert_cast<lt::state_update_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    for (const auto& st : su->status) {
      auto it = s->by_handle.find(st.handle);
      if (it == s->by_handle.end()) continue;
      s->torrents[it->second].status_json = status_json(st, it->second);
    }
    return;
  }
  if (auto* m = lt::alert_cast<lt::metadata_received_alert>(a)) {
    auto ti = m->handle.torrent_file();
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(m->handle);
    if (it == s->by_handle.end()) return;
    Torrent& t = s->torrents[it->second];
    t.ti = ti;
    init_pieces(t, nullptr);
    push_event(s, "{\"type\":\"metadata\",\"ih\":\"" + t.ih + "\"}");
    request_resume(s, m->handle, false);
    return;
  }
  if (auto* c = lt::alert_cast<lt::torrent_checked_alert>(a)) {
    lt::torrent_status st = c->handle.status(lt::torrent_handle::query_pieces);
    auto ti = c->handle.torrent_file();
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(c->handle);
    if (it == s->by_handle.end()) return;
    Torrent& t = s->torrents[it->second];
    if (ti) {
      t.ti = ti;
      init_pieces(t, &st.pieces);
    }
    s->piece_cv.notify_all();
    push_event(s, "{\"type\":\"checked\",\"ih\":\"" + t.ih + "\"}");
    return;
  }
  if (auto* f = lt::alert_cast<lt::torrent_finished_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(f->handle);
    if (it == s->by_handle.end()) return;
    push_event(s, "{\"type\":\"finished\",\"ih\":\"" + it->second + "\"}");
    request_resume(s, f->handle, false);
    return;
  }
  if (auto* r = lt::alert_cast<lt::save_resume_data_alert>(a)) {
    s->pending_resume.fetch_sub(1);
    std::string ih = hex_of(r->params.info_hashes.get_best());
    std::string path = resume_path(s, ih);
    if (!path.empty()) {
      std::vector<char> buf = lt::write_resume_data_buf(r->params);
      if (!write_file_atomic(path, buf)) push_log(s, "resume write failed: " + path);
    }
    return;
  }
  if (lt::alert_cast<lt::save_resume_data_failed_alert>(a) != nullptr) {
    s->pending_resume.fetch_sub(1);
    return;
  }
  if (auto* e = lt::alert_cast<lt::torrent_error_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(e->handle);
    std::string ih = it == s->by_handle.end() ? "" : it->second;
    push_event(s, "{\"type\":\"error\",\"ih\":\"" + ih + "\",\"message\":" +
                      json_escape(e->error.message() + " " + e->filename()) + "}");
    s->piece_cv.notify_all();
    return;
  }
  if (auto* fe = lt::alert_cast<lt::file_error_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(fe->handle);
    std::string ih = it == s->by_handle.end() ? "" : it->second;
    push_event(s, "{\"type\":\"file_error\",\"ih\":\"" + ih + "\",\"message\":" +
                      json_escape(fe->error.message() + " " + fe->filename()) + "}");
    return;
  }
  if (auto* mv = lt::alert_cast<lt::storage_moved_alert>(a)) {
    std::string path = mv->storage_path();
    auto ti = mv->handle.torrent_file();
    lt::renamed_files renames = mv->handle.get_renamed_files();
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(mv->handle);
    std::string ih = it == s->by_handle.end() ? "" : it->second;
    push_event(s, "{\"type\":\"moved\",\"ih\":\"" + ih + "\",\"path\":" + json_escape(path) + "}");
    // Open streams read from the old path; repoint them.
    if (ti) {
      for (auto& kv : s->routes) {
        if (kv.second->ih != ih || !kv.second->is_stream) continue;
        kv.second->disk_path =
            renames.file_path(ti->layout(), lt::file_index_t{kv.second->file_index}, path);
      }
    }
    return;
  }
  if (auto* mf = lt::alert_cast<lt::storage_moved_failed_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->by_handle.find(mf->handle);
    std::string ih = it == s->by_handle.end() ? "" : it->second;
    push_event(s, "{\"type\":\"move_failed\",\"ih\":\"" + ih + "\",\"message\":" +
                      json_escape(mf->error.message() + " " + mf->file_path()) + "}");
    return;
  }
  if (auto* ls = lt::alert_cast<lt::listen_succeeded_alert>(a)) {
    std::lock_guard<std::mutex> lk(s->mu);
    push_event(s, "{\"type\":\"listen\",\"port\":" + std::to_string(ls->port) + "}");
    return;
  }
  // Diagnostics for "finding people sharing it": what trackers answered and
  // why connections failed (the first 20, then every 100th).
  if (auto* r = lt::alert_cast<lt::tracker_reply_alert>(a)) {
    push_log(s, r->message());
    return;
  }
  if (auto* d = lt::alert_cast<lt::peer_disconnected_alert>(a)) {
    int n = s->connect_failures;
    if (d->op == lt::operation_t::connect && (n < 20 || n % 100 == 0)) push_log(s, d->message());
    if (d->op == lt::operation_t::connect) s->connect_failures = n + 1;
    return;
  }
  if (a->category() & lt::alert_category::error) {
    push_log(s, a->message());
  }
}

void alert_loop(kn_session* s) {
  auto last_update = steady::now() - 10s;
  auto last_resume = steady::now();
  std::vector<lt::alert*> alerts;
  while (!s->stopping.load()) try {
    s->ses->wait_for_alert(250ms);
    alerts.clear();
    s->ses->pop_alerts(&alerts);
    for (lt::alert* a : alerts) {
      try {
        handle_alert(s, a);
      } catch (const std::exception& e) {
        push_log(s, std::string("alert handler: ") + e.what());
      }
    }
    auto now = steady::now();
    if (now - last_update >= 500ms) {
      s->ses->post_torrent_updates();
      last_update = now;
    }
    if (now - last_resume >= 30s) {
      last_resume = now;
      std::vector<lt::torrent_handle> handles;
      {
        std::lock_guard<std::mutex> lk(s->mu);
        for (auto& kv : s->torrents) handles.push_back(kv.second.handle);
      }
      for (auto& h : handles) {
        try {
          if (h.need_save_resume_data()) request_resume(s, h, true);
        } catch (...) {
          // Removed meanwhile.
        }
      }
    }
  } catch (const std::exception& e) {
    push_log(s, std::string("alert loop: ") + e.what());
  } catch (...) {
  }
}

// --------------------------------------------------------------- settings --

void apply_config(lt::settings_pack& sp, const lt::bdecode_node& c, bool initial,
                  bool test_mode) {
  auto set_bool = [&](const char* key, lt::settings_pack::bool_types name) {
    std::int64_t v = int_of(c, key, -1);
    if (v >= 0) sp.set_bool(name, v != 0);
  };
  auto set_int = [&](const char* key, lt::settings_pack::int_types name) {
    std::int64_t v = int_of(c, key, -1);
    if (v >= 0) sp.set_int(name, static_cast<int>(v));
  };

  if (initial) {
    sp.set_int(lt::settings_pack::alert_mask,
               lt::alert_category::status | lt::alert_category::error |
                   lt::alert_category::storage | lt::alert_category::piece_progress |
                   lt::alert_category::file_progress | lt::alert_category::tracker |
                   lt::alert_category::connect);
    sp.set_str(lt::settings_pack::peer_fingerprint,
               lt::generate_fingerprint("KN", 0, 1, 0, 0));
    sp.set_int(lt::settings_pack::alert_queue_size, 4000);
    // Peers: every discovery and transport on (SceneBox disabled uTP/UPnP/LSD).
    sp.set_bool(lt::settings_pack::enable_dht, true);
    sp.set_bool(lt::settings_pack::enable_lsd, true);
    sp.set_bool(lt::settings_pack::enable_upnp, true);
    sp.set_bool(lt::settings_pack::enable_natpmp, true);
    sp.set_bool(lt::settings_pack::enable_outgoing_utp, true);
    sp.set_bool(lt::settings_pack::enable_incoming_utp, true);
    sp.set_bool(lt::settings_pack::enable_outgoing_tcp, true);
    sp.set_bool(lt::settings_pack::enable_incoming_tcp, true);
    sp.set_bool(lt::settings_pack::announce_to_all_trackers, true);
    sp.set_bool(lt::settings_pack::announce_to_all_tiers, true);
    sp.set_int(lt::settings_pack::connections_limit, 200);
    sp.set_int(lt::settings_pack::connection_speed, 40);
    sp.set_int(lt::settings_pack::torrent_connect_boost, 40);
    sp.set_int(lt::settings_pack::peer_connect_timeout, 10);
    sp.set_int(lt::settings_pack::handshake_timeout, 10);
    sp.set_int(lt::settings_pack::piece_timeout, 10);
    sp.set_int(lt::settings_pack::request_queue_time, 3);
    // A peer whose first connection failed is tried again after 15 s (not
    // 60): with few peers, waiting a minute is a minute of black screen.
    sp.set_int(lt::settings_pack::min_reconnect_time, 15);
    sp.set_int(lt::settings_pack::max_out_request_queue, 1500);
    sp.set_int(lt::settings_pack::whole_pieces_threshold, 20);
    sp.set_int(lt::settings_pack::stop_tracker_timeout, 1);
    sp.set_int(lt::settings_pack::aio_threads, 4);
    sp.set_int(lt::settings_pack::hashing_threads, 2);
    sp.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_enabled);
    sp.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_enabled);
    sp.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_both);
    sp.set_str(lt::settings_pack::dht_bootstrap_nodes,
               "router.bittorrent.com:6881,dht.transmissionbt.com:6881,"
               "router.utorrent.com:6881,dht.libtorrent.org:25401,"
               "dht.aelitis.com:6881");
    std::int64_t port = int_of(c, "listen_port", 0);
    std::string listen = str_of(c, "listen_interfaces");
    if (listen.empty()) {
      std::string p = std::to_string(port);
      listen = test_mode ? "127.0.0.1:" + p : "0.0.0.0:" + p + ",[::]:" + p;
    }
    sp.set_str(lt::settings_pack::listen_interfaces, listen);
    if (test_mode) {
      sp.set_bool(lt::settings_pack::enable_dht, false);
      sp.set_bool(lt::settings_pack::enable_lsd, false);
      sp.set_bool(lt::settings_pack::enable_upnp, false);
      sp.set_bool(lt::settings_pack::enable_natpmp, false);
      sp.set_bool(lt::settings_pack::allow_multiple_connections_per_ip, true);
    }
  }

  std::string ua = str_of(c, "user_agent");
  if (!ua.empty()) sp.set_str(lt::settings_pack::user_agent, ua);
  std::string out_if = str_of(c, "outgoing_interfaces", "\x01");
  if (out_if != "\x01") sp.set_str(lt::settings_pack::outgoing_interfaces, out_if);
  std::string boot = str_of(c, "dht_bootstrap_nodes");
  if (!boot.empty()) sp.set_str(lt::settings_pack::dht_bootstrap_nodes, boot);
  if (!test_mode) {
    set_bool("dht", lt::settings_pack::enable_dht);
    set_bool("lsd", lt::settings_pack::enable_lsd);
    set_bool("upnp", lt::settings_pack::enable_upnp);
    set_bool("natpmp", lt::settings_pack::enable_natpmp);
  }
  set_bool("utp", lt::settings_pack::enable_outgoing_utp);
  set_bool("utp", lt::settings_pack::enable_incoming_utp);
  set_bool("anonymous_mode", lt::settings_pack::anonymous_mode);
  set_int("connections_limit", lt::settings_pack::connections_limit);
  set_int("download_rate_limit", lt::settings_pack::download_rate_limit);
  set_int("upload_rate_limit", lt::settings_pack::upload_rate_limit);
}

// ----------------------------------------------------------------- server --

bool send_all(int fd, const char* data, std::size_t len) {
  while (len > 0) {
    ssize_t n = ::send(fd, data, len, KN_SEND_FLAGS);
    if (n < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    data += n;
    len -= static_cast<std::size_t>(n);
  }
  return true;
}

bool client_alive(int fd) {
  char c;
  ssize_t n = ::recv(fd, &c, 1, MSG_PEEK | MSG_DONTWAIT);
  if (n == 0) return false;
  if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) return false;
  return true;
}

struct Request {
  std::string method;
  std::string path;
  std::map<std::string, std::string> headers;  // lowercase keys
};

bool read_request(int fd, Request& req) {
  std::string buf;
  char chunk[2048];
  while (buf.find("\r\n\r\n") == std::string::npos) {
    if (buf.size() > 16384) return false;
    ssize_t n = ::recv(fd, chunk, sizeof(chunk), 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return false;
    buf.append(chunk, static_cast<std::size_t>(n));
  }
  std::istringstream in(buf.substr(0, buf.find("\r\n\r\n")));
  std::string line;
  if (!std::getline(in, line)) return false;
  if (!line.empty() && line.back() == '\r') line.pop_back();
  std::istringstream rl(line);
  std::string version;
  rl >> req.method >> req.path >> version;
  if (req.method.empty() || req.path.empty()) return false;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    auto colon = line.find(':');
    if (colon == std::string::npos) continue;
    std::string key = lower(line.substr(0, colon));
    std::string value = line.substr(colon + 1);
    value.erase(0, value.find_first_not_of(" \t"));
    req.headers[key] = value;
  }
  return true;
}

void send_status(int fd, const char* status, const std::string& extra = "") {
  std::string head = std::string("HTTP/1.1 ") + status +
                     "\r\nContent-Length: 0\r\nConnection: close\r\n" + extra + "\r\n";
  send_all(fd, head.data(), head.size());
}

// Parses "bytes=a-b" / "bytes=a-" / "bytes=-n". Returns false if unsatisfiable.
bool parse_range(const std::string& value, std::int64_t size, std::int64_t& start,
                 std::int64_t& end) {
  start = 0;
  end = size - 1;
  if (value.empty()) return true;
  std::string v = lower(value);
  if (v.rfind("bytes=", 0) != 0) return true;  // ignore unknown units
  v = v.substr(6);
  auto comma = v.find(',');
  if (comma != std::string::npos) v = v.substr(0, comma);  // first range only
  auto dash = v.find('-');
  if (dash == std::string::npos) return false;
  std::string a = v.substr(0, dash), b = v.substr(dash + 1);
  char* endp = nullptr;
  if (a.empty()) {
    std::int64_t n = std::strtoll(b.c_str(), &endp, 10);
    if (n <= 0) return false;
    start = std::max<std::int64_t>(0, size - n);
  } else {
    start = std::strtoll(a.c_str(), &endp, 10);
    if (!b.empty()) end = std::min<std::int64_t>(size - 1, std::strtoll(b.c_str(), &endp, 10));
  }
  return start >= 0 && start < size && start <= end;
}

struct Window {
  int first = -1;
  int last = -1;
  std::uint32_t epoch = 0;
  steady::time_point issued{};
};

void clear_window(kn_session* s, const Route& r, Window& w) {
  if (w.first < 0) return;
  lt::torrent_handle h;
  std::vector<std::uint8_t> have;
  {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->torrents.find(r.ih);
    if (it == s->torrents.end()) return;
    h = it->second.handle;
    have = it->second.have;
    ++it->second.window_epoch;
  }
  try {
    for (int p = w.first; p <= w.last; ++p) {
      if (p < static_cast<int>(have.size()) && !have[static_cast<std::size_t>(p)]) {
        h.reset_piece_deadline(lt::piece_index_t{p});
      }
    }
  } catch (...) {
    // Torrent removed meanwhile.
  }
  w = Window{};
}

// Moves this connection's deadline window so it starts at `piece`.
void move_window(kn_session* s, const Route& r, Window& w, int piece) {
  lt::torrent_handle h;
  std::vector<std::uint8_t> have;
  int plen = 0;
  std::uint32_t epoch = 0;
  {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->torrents.find(r.ih);
    if (it == s->torrents.end() || it->second.piece_len <= 0) return;
    h = it->second.handle;
    have = it->second.have;
    plen = it->second.piece_len;
    epoch = it->second.window_epoch;
  }
  int file_last = static_cast<int>((r.file_offset + std::max<std::int64_t>(r.size, 1) - 1) / plen);
  int count = static_cast<int>(std::clamp<std::int64_t>(r.readahead / plen, 4, 512));
  int first = piece;
  int last = std::min(file_last, piece + count - 1);
  auto now = steady::now();
  bool fresh = w.first < 0 || first < w.first || first - w.first >= std::max(1, count / 8) ||
               now - w.issued > 2s || w.epoch != epoch;
  if (!fresh) return;
  int step = r.bitrate > 0
                 ? static_cast<int>(std::clamp<std::int64_t>(
                       static_cast<std::int64_t>(plen) * 1000 / r.bitrate, 20, 3000))
                 : 150;
  try {
    if (w.first >= 0) {
      for (int p = w.first; p <= w.last; ++p) {
        if ((p < first || p > last) && p < static_cast<int>(have.size()) &&
            !have[static_cast<std::size_t>(p)]) {
          h.reset_piece_deadline(lt::piece_index_t{p});
        }
      }
    }
    for (int p = first; p <= last; ++p) {
      if (p < static_cast<int>(have.size()) && !have[static_cast<std::size_t>(p)]) {
        h.set_piece_deadline(lt::piece_index_t{p}, (p - first) * step);
      }
    }
  } catch (...) {
    return;  // torrent removed meanwhile
  }
  w.first = first;
  w.last = last;
  w.epoch = epoch;
  w.issued = now;
}

// Blocks until `piece` is on disk. False when the client left, the route
// closed, the torrent vanished or nothing arrived for a long time.
bool wait_piece(kn_session* s, Route& r, Window& w, int piece, int fd) {
  auto give_up = steady::now() + 180s;
  auto next_check = steady::now() + 250ms;
  for (;;) {
    {
      std::unique_lock<std::mutex> lk(s->mu);
      auto it = s->torrents.find(r.ih);
      if (it == s->torrents.end()) return false;
      const std::vector<std::uint8_t>& have = it->second.have;
      if (piece >= 0 && piece < static_cast<int>(have.size()) &&
          have[static_cast<std::size_t>(piece)]) {
        return true;
      }
      if (s->stopping.load() || r.closed.load()) return false;
      s->piece_cv.wait_for(lk, 250ms);
    }
    auto now = steady::now();
    if (now < next_check) continue;
    next_check = now + 250ms;
    if (!client_alive(fd) || now > give_up) return false;
    move_window(s, r, w, piece);  // re-asserts deadlines every 2 s
  }
}

std::map<std::string, std::string> headers_of(kn_session* s, const Route& r) {
  std::lock_guard<std::mutex> lk(s->mu);
  return r.headers;
}

void serve_stream(kn_session* s, int fd, const Request& req, std::shared_ptr<Route> r) {
  std::int64_t start = 0, end = 0;
  auto range_it = req.headers.find("range");
  bool ranged = range_it != req.headers.end();
  if (!parse_range(ranged ? range_it->second : "", r->size, start, end)) {
    send_status(fd, "416 Range Not Satisfiable",
                "Content-Range: bytes */" + std::to_string(r->size) + "\r\n");
    return;
  }
  std::ostringstream head;
  head << (ranged ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n")
       << "Content-Type: " << r->mime << "\r\n"
       << "Content-Length: " << (end - start + 1) << "\r\n"
       << "Accept-Ranges: bytes\r\n"
       << "Cache-Control: no-store\r\n"
       << "Connection: close\r\n";
  if (ranged) head << "Content-Range: bytes " << start << "-" << end << "/" << r->size << "\r\n";
  for (const auto& kv : headers_of(s, *r)) head << kv.first << ": " << kv.second << "\r\n";
  head << "\r\n";
  std::string hs = head.str();
  if (!send_all(fd, hs.data(), hs.size()) || req.method == "HEAD") return;

  int plen = 0;
  {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->torrents.find(r->ih);
    if (it == s->torrents.end()) return;
    plen = it->second.piece_len;
  }
  if (plen <= 0) return;

  r->connections.fetch_add(1);
  Window w;
  int file_fd = -1;
  struct Cleanup {
    kn_session* s;
    Route* r;
    Window* w;
    int* fd;
    ~Cleanup() {
      if (*fd >= 0) ::close(*fd);
      clear_window(s, *r, *w);
      r->connections.fetch_sub(1);
    }
  } cleanup{s, r.get(), &w, &file_fd};
  std::vector<char> buf(256 * 1024);
  std::int64_t pos = start;
  bool ok = true;
  while (ok && pos <= end && !r->closed.load() && !s->stopping.load()) {
    int piece = static_cast<int>((r->file_offset + pos) / plen);
    r->position.store(pos);
    move_window(s, *r, w, piece);
    if (!wait_piece(s, *r, w, piece, fd)) break;
    if (file_fd < 0) {
      std::string path;
      {
        std::lock_guard<std::mutex> lk(s->mu);  // move_storage may repoint it
        path = r->disk_path;
      }
      file_fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
      if (file_fd < 0) {
        push_log(s, "stream open failed: " + path + " " + std::strerror(errno));
        break;
      }
    }
    std::int64_t piece_end = static_cast<std::int64_t>(piece + 1) * plen - r->file_offset;
    std::int64_t chunk_end = std::min(end + 1, piece_end);
    while (pos < chunk_end) {
      std::size_t want = static_cast<std::size_t>(
          std::min<std::int64_t>(static_cast<std::int64_t>(buf.size()), chunk_end - pos));
      ssize_t n = ::pread(file_fd, buf.data(), want, static_cast<off_t>(pos));
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) {
        ok = false;
        break;
      }
      if (!send_all(fd, buf.data(), static_cast<std::size_t>(n))) {
        ok = false;
        break;
      }
      pos += n;
    }
  }
}

void serve_file(kn_session* s, int fd, const Request& req, std::shared_ptr<Route> r) {
  struct stat st {};
  if (::stat(r->disk_path.c_str(), &st) != 0) {
    send_status(fd, "404 Not Found");
    return;
  }
  std::int64_t size = st.st_size;
  std::int64_t start = 0, end = 0;
  auto range_it = req.headers.find("range");
  bool ranged = range_it != req.headers.end();
  if (size == 0) {
    ranged = false;
    end = -1;
  } else if (!parse_range(ranged ? range_it->second : "", size, start, end)) {
    send_status(fd, "416 Range Not Satisfiable",
                "Content-Range: bytes */" + std::to_string(size) + "\r\n");
    return;
  }
  std::ostringstream head;
  head << (ranged ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n")
       << "Content-Type: " << r->mime << "\r\n"
       << "Content-Length: " << (end - start + 1) << "\r\n"
       << "Accept-Ranges: bytes\r\n"
       << "Connection: close\r\n";
  if (ranged) head << "Content-Range: bytes " << start << "-" << end << "/" << size << "\r\n";
  for (const auto& kv : headers_of(s, *r)) head << kv.first << ": " << kv.second << "\r\n";
  head << "\r\n";
  std::string hs = head.str();
  if (!send_all(fd, hs.data(), hs.size()) || req.method == "HEAD") return;
  int file_fd = ::open(r->disk_path.c_str(), O_RDONLY | O_CLOEXEC);
  if (file_fd < 0) return;
  std::vector<char> buf(256 * 1024);
  std::int64_t pos = start;
  while (pos <= end && !r->closed.load()) {
    std::size_t want = static_cast<std::size_t>(
        std::min<std::int64_t>(static_cast<std::int64_t>(buf.size()), end + 1 - pos));
    ssize_t n = ::pread(file_fd, buf.data(), want, static_cast<off_t>(pos));
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0 || !send_all(fd, buf.data(), static_cast<std::size_t>(n))) break;
    pos += n;
  }
  ::close(file_fd);
}

void handle_client(kn_session* s, int fd) {
  timeval tv{15, 0};
  ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  timeval stv{60, 0};
  ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &stv, sizeof(stv));
#if defined(__APPLE__)
  int one = 1;
  ::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
  try {
    Request req;
    if (read_request(fd, req)) {
      if (req.method != "GET" && req.method != "HEAD") {
        send_status(fd, "405 Method Not Allowed", "Allow: GET, HEAD\r\n");
      } else {
        // /s/<token>/<name> or /f/<token>/<name>
        std::string path = req.path.substr(0, req.path.find('?'));
        std::shared_ptr<Route> route;
        if (path.size() > 3 && path[0] == '/' && (path[1] == 's' || path[1] == 'f') &&
            path[2] == '/') {
          std::string rest = path.substr(3);
          std::string token = rest.substr(0, rest.find('/'));
          std::lock_guard<std::mutex> lk(s->mu);
          auto it = s->routes.find(token);
          if (it != s->routes.end() && it->second->is_stream == (path[1] == 's')) route = it->second;
        }
        if (!route) {
          send_status(fd, "404 Not Found");
        } else if (route->is_stream) {
          serve_stream(s, fd, req, route);
        } else {
          serve_file(s, fd, req, route);
        }
      }
    }
  } catch (const std::exception& e) {
    push_log(s, std::string("http client: ") + e.what());
  }
  {
    std::lock_guard<std::mutex> lk(s->server_mu);
    s->client_fds.erase(fd);
  }
  ::shutdown(fd, SHUT_RDWR);
  ::close(fd);
  s->client_count.fetch_sub(1);
}

void accept_loop(kn_session* s) {
  while (!s->stopping.load()) {
    pollfd pfd{s->listen_fd, POLLIN, 0};
    int rc = ::poll(&pfd, 1, 250);
    if (rc <= 0) continue;
    int fd = ::accept(s->listen_fd, nullptr, nullptr);
    if (fd < 0) continue;
    if (s->client_count.load() >= kMaxClients) {
      send_status(fd, "503 Service Unavailable");
      ::close(fd);
      continue;
    }
    int one = 1;
    ::setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    {
      std::lock_guard<std::mutex> lk(s->server_mu);
      s->client_fds.insert(fd);
    }
    s->client_count.fetch_add(1);
    try {
      std::thread(handle_client, s, fd).detach();
    } catch (...) {
      {
        std::lock_guard<std::mutex> lk(s->server_mu);
        s->client_fds.erase(fd);
      }
      ::close(fd);
      s->client_count.fetch_sub(1);
    }
  }
}

int ensure_server(kn_session* s) {
  std::lock_guard<std::mutex> lk(s->server_mu);
  if (s->listen_fd >= 0) return s->port;
  int fd = ::socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return 0;
  int one = 1;
  ::setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  // Loopback in tests; all interfaces otherwise so a TV on the LAN can pull.
  addr.sin_addr.s_addr = htonl(s->test_mode ? INADDR_LOOPBACK : INADDR_ANY);
  addr.sin_port = 0;
  if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0 ||
      ::listen(fd, 16) != 0) {
    ::close(fd);
    return 0;
  }
  socklen_t len = sizeof(addr);
  ::getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &len);
  s->listen_fd = fd;
  s->port = ntohs(addr.sin_port);
  s->accept_thread = std::thread(accept_loop, s);
  return s->port;
}

void stop_server(kn_session* s) {
  std::thread accept;
  {
    std::lock_guard<std::mutex> lk(s->server_mu);
    accept = std::move(s->accept_thread);
  }
  if (accept.joinable()) accept.join();  // no new clients after this
  // Detached client threads use `s`: wait for every one before it's freed.
  while (s->client_count.load() > 0) {
    {
      std::lock_guard<std::mutex> lk(s->server_mu);
      for (int fd : s->client_fds) ::shutdown(fd, SHUT_RDWR);
    }
    s->piece_cv.notify_all();
    std::this_thread::sleep_for(20ms);
  }
  std::lock_guard<std::mutex> lk(s->server_mu);
  if (s->listen_fd >= 0) ::close(s->listen_fd);
  s->listen_fd = -1;
}

Torrent* find_torrent(kn_session* s, const char* ih) {
  if (ih == nullptr) return nullptr;
  auto it = s->torrents.find(ih);
  return it == s->torrents.end() ? nullptr : &it->second;
}

lt::torrent_handle handle_of(kn_session* s, const char* ih) {
  std::lock_guard<std::mutex> lk(s->mu);
  Torrent* t = find_torrent(s, ih);
  return t ? t->handle : lt::torrent_handle{};
}

std::map<std::string, std::string> decode_headers(const uint8_t* data, int32_t len) {
  std::map<std::string, std::string> out;
  lt::error_code ec;
  lt::bdecode_node d = decode(data, len, ec);
  if (ec || d.type() != lt::bdecode_node::dict_t) return out;
  for (int i = 0; i < d.dict_size(); ++i) {
    auto kv = d.dict_at(i);
    if (kv.second.type() != lt::bdecode_node::string_t) continue;
    std::string key(kv.first), value(kv.second.string_value());
    // Header injection guard.
    if (key.find_first_of("\r\n:") != std::string::npos ||
        value.find_first_of("\r\n") != std::string::npos) {
      continue;
    }
    out[key] = value;
  }
  return out;
}

}  // namespace

// ================================================================== C API ==

extern "C" {

char* kn_version(void) {
  return dup_string(std::string("kinora-engine ") + kEngineVersion + " / libtorrent " +
                    lt::version());
}

void kn_free_string(char* s) { std::free(s); }

kn_session* kn_session_new(const uint8_t* config, int32_t config_len, char** error) {
  try {
    ::signal(SIGPIPE, SIG_IGN);
    lt::error_code ec;
    lt::bdecode_node c = decode(config, config_len, ec);
    if (ec || c.type() != lt::bdecode_node::dict_t) {
      if (error) *error = dup_string("invalid config");
      return nullptr;
    }
    const bool shared = int_of(c, "shared", 0) != 0;
    {
      std::lock_guard<std::mutex> lk(g_shared_mu);
      if (shared && g_shared != nullptr) {
        lt::settings_pack sp;
        apply_config(sp, c, false, g_shared->test_mode);
        g_shared->ses->apply_settings(std::move(sp));
        return g_shared;  // reattach after the UI was recreated
      }
    }
    auto s = std::make_unique<kn_session>();
    s->state_path = str_of(c, "state_path");
    s->resume_dir = str_of(c, "resume_dir");
    s->test_mode = int_of(c, "test_mode", 0) != 0;

    lt::session_params params;
    std::vector<char> state;
    if (!s->state_path.empty() && read_file(s->state_path, state) && !state.empty()) {
      try {
        params = lt::read_session_params(state, lt::session::save_dht_state);
      } catch (...) {
        params = lt::session_params{};
      }
    }
    lt::settings_pack sp;
    apply_config(sp, c, true, s->test_mode);
    params.settings = sp;
    params.disk_io_constructor = lt::posix_disk_io_constructor;  // no mmap on mobile
    s->ses = std::make_unique<lt::session>(std::move(params));
    kn_session* raw = s.release();
    raw->alert_thread = std::thread(alert_loop, raw);
    if (shared) {
      std::lock_guard<std::mutex> lk(g_shared_mu);
      g_shared = raw;
    }
    return raw;
  } catch (const std::exception& e) {
    if (error) *error = dup_string(e.what());
    return nullptr;
  }
}

void kn_session_free(kn_session* s) {
  if (s == nullptr) return;
  {
    std::lock_guard<std::mutex> lk(g_shared_mu);
    if (g_shared == s) g_shared = nullptr;
  }
  try {
    std::vector<lt::torrent_handle> handles;
    {
      std::lock_guard<std::mutex> lk(s->mu);
      for (auto& kv : s->torrents) handles.push_back(kv.second.handle);
      for (auto& kv : s->routes) kv.second->closed.store(true);
    }
    for (auto& h : handles) {
      if (h.is_valid() && h.need_save_resume_data()) request_resume(s, h, true);
    }
    for (int i = 0; i < 150 && s->pending_resume.load() > 0; ++i) std::this_thread::sleep_for(20ms);
    kn_session_save_state(s);
    s->stopping.store(true);
    stop_server(s);
    if (s->alert_thread.joinable()) s->alert_thread.join();
    s->ses.reset();
  } catch (...) {
  }
  delete s;
}

int32_t kn_session_apply(kn_session* s, const uint8_t* config, int32_t config_len) {
  try {
    lt::error_code ec;
    lt::bdecode_node c = decode(config, config_len, ec);
    if (ec || c.type() != lt::bdecode_node::dict_t) return -1;
    lt::settings_pack sp;
    apply_config(sp, c, false, s->test_mode);
    s->ses->apply_settings(std::move(sp));
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_session_save_state(kn_session* s) {
  try {
    if (s->state_path.empty()) return -1;
    lt::session_params p = s->ses->session_state(lt::session::save_dht_state);
    std::vector<char> buf = lt::write_session_params_buf(p, lt::session::save_dht_state);
    return write_file_atomic(s->state_path, buf) ? 0 : -1;
  } catch (...) {
    return -1;
  }
}

int32_t kn_session_listen_port(kn_session* s) {
  try {
    return s->ses->listen_port();
  } catch (...) {
    return 0;
  }
}

char* kn_add(kn_session* s, const uint8_t* params, int32_t params_len) {
  try {
    lt::error_code ec;
    lt::bdecode_node p = decode(params, params_len, ec);
    if (ec || p.type() != lt::bdecode_node::dict_t) return dup_string(error_json("invalid params"));

    lt::add_torrent_params atp;
    bool have_params = false;
    std::string resume = str_of(p, "resume_path");
    std::vector<char> buf;
    if (!resume.empty() && read_file(resume, buf) && !buf.empty()) {
      lt::error_code rec;
      atp = lt::read_resume_data(buf, rec);
      have_params = !rec;
    }
    if (!have_params) {
      lt::bdecode_node torrent = p.dict_find_string("torrent");
      std::string magnet = str_of(p, "magnet");
      if (torrent) {
        lt::string_view bytes = torrent.string_value();
        atp = lt::load_torrent_buffer({bytes.data(), static_cast<std::ptrdiff_t>(bytes.size())});
      } else if (!magnet.empty()) {
        lt::error_code mec;
        atp = lt::parse_magnet_uri(magnet, mec);
        if (mec) return dup_string(error_json("invalid magnet: " + mec.message()));
      } else {
        return dup_string(error_json("magnet, torrent or resume_path required"));
      }
    }

    std::string save_path = str_of(p, "save_path");
    if (!save_path.empty() && (atp.save_path.empty() || int_of(p, "force_save_path", 0))) {
      atp.save_path = save_path;
    }
    if (atp.save_path.empty()) return dup_string(error_json("save_path required"));
    std::string name = str_of(p, "name");
    if (!name.empty() && atp.name.empty()) atp.name = name;

    if (lt::bdecode_node trackers = p.dict_find_list("trackers")) {
      for (int i = 0; i < trackers.list_size(); ++i) {
        std::string tr(trackers.list_string_value_at(i));
        if (tr.empty() || std::find(atp.trackers.begin(), atp.trackers.end(), tr) != atp.trackers.end()) continue;
        atp.trackers.push_back(tr);
        if (!atp.tracker_tiers.empty()) atp.tracker_tiers.push_back(0);
      }
    }
    if (lt::bdecode_node prio = p.dict_find_list("file_priorities")) {
      atp.file_priorities.clear();
      for (int i = 0; i < prio.list_size(); ++i) {
        auto v = static_cast<std::uint8_t>(std::clamp<std::int64_t>(prio.list_int_value_at(i), 0, 7));
        atp.file_priorities.push_back(lt::download_priority_t{v});
      }
    }
    if (lt::bdecode_node peers = p.dict_find_list("peers")) {
      for (int i = 0; i < peers.list_size(); ++i) {
        std::string ep(peers.list_string_value_at(i));
        auto colon = ep.find_last_of(':');
        if (colon == std::string::npos) continue;
        std::string host = ep.substr(0, colon);
        if (host.size() > 2 && host.front() == '[') host = host.substr(1, host.size() - 2);
        lt::error_code aec;
        auto addr = lt::make_address(host, aec);
        if (aec) continue;
        atp.peers.emplace_back(addr, static_cast<std::uint16_t>(std::atoi(ep.c_str() + colon + 1)));
      }
    }
    atp.flags &= ~lt::torrent_flags::auto_managed;
    atp.flags &= ~lt::torrent_flags::paused;
    if (int_of(p, "paused", 0)) atp.flags |= lt::torrent_flags::paused;
    if (int_of(p, "seed_mode", 0)) atp.flags |= lt::torrent_flags::seed_mode;
    if (int_of(p, "sequential", 0)) atp.flags |= lt::torrent_flags::sequential_download;
    std::int64_t max_conn = int_of(p, "max_connections", -1);
    if (max_conn > 0) atp.max_connections = static_cast<int>(max_conn);
    std::int64_t dl = int_of(p, "download_limit", -1);
    if (dl >= 0) atp.download_limit = static_cast<int>(dl);
    std::int64_t ul = int_of(p, "upload_limit", -1);
    if (ul >= 0) atp.upload_limit = static_cast<int>(ul);

    lt::error_code aerr;
    lt::torrent_handle h = s->ses->add_torrent(std::move(atp), aerr);
    if (aerr || !h.is_valid()) return dup_string(error_json(aerr.message()));
    std::string ih = hex_of(h.info_hashes().get_best());
    auto ti = h.torrent_file();
    {
      std::lock_guard<std::mutex> lk(s->mu);
      Torrent& t = s->torrents[ih];
      bool fresh = !t.handle.is_valid();
      t.handle = h;
      t.ih = ih;
      s->by_handle[h] = ih;
      if (ti && (fresh || !t.ti)) {
        t.ti = ti;
        init_pieces(t, nullptr);
      }
    }
    if (ti) {
      lt::torrent_status st = h.status(lt::torrent_handle::query_pieces);
      std::lock_guard<std::mutex> lk(s->mu);
      Torrent& t = s->torrents[ih];
      init_pieces(t, &st.pieces);
      t.status_json = status_json(st, ih);
    }
    return dup_string("{\"ih\":\"" + ih + "\"}");
  } catch (const std::exception& e) {
    return dup_string(error_json(e.what()));
  }
}

int32_t kn_remove(kn_session* s, const char* ih, int32_t delete_files) {
  try {
    lt::torrent_handle h;
    {
      std::lock_guard<std::mutex> lk(s->mu);
      Torrent* t = find_torrent(s, ih);
      if (t == nullptr) return -1;
      h = t->handle;
      for (auto it = s->routes.begin(); it != s->routes.end();) {
        if (it->second->ih == ih) {
          it->second->closed.store(true);
          it = s->routes.erase(it);
        } else {
          ++it;
        }
      }
      s->by_handle.erase(h);
      s->torrents.erase(ih);
      push_event(s, std::string("{\"type\":\"removed\",\"ih\":\"") + ih + "\"}");
      s->piece_cv.notify_all();
    }
    s->ses->remove_torrent(h, delete_files ? lt::session::delete_files : lt::remove_flags_t{});
    std::string rp = resume_path(s, ih);
    if (!rp.empty()) std::remove(rp.c_str());
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_pause(kn_session* s, const char* ih) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid()) return -1;
    h.pause(lt::torrent_handle::graceful_pause);
    request_resume(s, h, true);
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_resume(kn_session* s, const char* ih) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid()) return -1;
    if (h.status().errc) h.clear_error();  // e.g. disk was full, now freed
    h.resume();
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_set_file_priorities(kn_session* s, const char* ih, const int32_t* priorities,
                               int32_t count) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid() || priorities == nullptr || count < 0) return -1;
    std::vector<lt::download_priority_t> prio;
    prio.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) {
      prio.push_back(lt::download_priority_t{static_cast<std::uint8_t>(std::clamp(priorities[i], 0, 7))});
    }
    h.prioritize_files(prio);
    return 0;
  } catch (...) {
    return -1;
  }
}

char* kn_files(kn_session* s, const char* ih) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid()) return nullptr;
    auto ti = h.torrent_file();
    if (!ti) return nullptr;
    const lt::file_storage& fs = ti->layout();
    std::ostringstream o;
    o << "[";
    for (int i = 0; i < fs.num_files(); ++i) {
      lt::file_index_t fi{i};
      if (i) o << ",";
      o << "{\"index\":" << i << ",\"path\":" << json_escape(fs.file_path(fi))
        << ",\"size\":" << fs.file_size(fi) << ",\"offset\":" << fs.file_offset(fi)
        << ",\"pad\":" << ((fs.file_flags(fi) & lt::file_storage::flag_pad_file) ? "true" : "false")
        << "}";
    }
    o << "]";
    return dup_string(o.str());
  } catch (...) {
    return nullptr;
  }
}

char* kn_status_all(kn_session* s) {
  try {
    std::lock_guard<std::mutex> lk(s->mu);
    std::string out = "[";
    bool first = true;
    for (auto& kv : s->torrents) {
      if (kv.second.status_json.empty()) continue;
      if (!first) out += ",";
      out += kv.second.status_json;
      first = false;
    }
    out += "]";
    return dup_string(out);
  } catch (...) {
    return nullptr;
  }
}

char* kn_poll_events(kn_session* s) {
  try {
    std::deque<std::string> events;
    {
      std::lock_guard<std::mutex> lk(s->mu);
      events.swap(s->events);
    }
    std::string out = "[";
    for (std::size_t i = 0; i < events.size(); ++i) {
      if (i) out += ",";
      out += events[i];
    }
    out += "]";
    return dup_string(out);
  } catch (...) {
    return nullptr;
  }
}

int32_t kn_save_resume(kn_session* s, const char* ih) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid()) return -1;
    request_resume(s, h, false);
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_connect_peer(kn_session* s, const char* ih, const char* ip, int32_t port) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid() || ip == nullptr) return -1;
    lt::error_code ec;
    auto addr = lt::make_address(ip, ec);
    if (ec) return -1;
    h.connect_peer(lt::tcp::endpoint(addr, static_cast<std::uint16_t>(port)));
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_move_storage(kn_session* s, const char* ih, const char* path) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid() || path == nullptr || *path == '\0') return -1;
    h.move_storage(path, lt::move_flags_t::always_replace_files);
    return 0;
  } catch (...) {
    return -1;
  }
}

char* kn_file_progress(kn_session* s, const char* ih) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid() || !h.torrent_file()) return nullptr;
    std::vector<std::int64_t> done = h.file_progress(lt::torrent_handle::piece_granularity);
    std::string out = "[";
    for (std::size_t i = 0; i < done.size(); ++i) {
      if (i) out += ",";
      out += std::to_string(done[i]);
    }
    out += "]";
    return dup_string(out);
  } catch (...) {
    return nullptr;
  }
}

int32_t kn_server_port(kn_session* s) {
  try {
    return ensure_server(s);
  } catch (...) {
    return 0;
  }
}

char* kn_stream_open(kn_session* s, const char* ih, int32_t file_index, const uint8_t* opts,
                     int32_t opts_len) {
  try {
    lt::torrent_handle h = handle_of(s, ih);
    if (!h.is_valid()) return dup_string(error_json("unknown torrent"));
    auto ti = h.torrent_file();
    if (!ti) return dup_string(error_json("no_metadata"));
    const lt::file_storage& fs = ti->layout();
    if (file_index < 0 || file_index >= fs.num_files()) return dup_string(error_json("bad file index"));
    lt::file_index_t fi{file_index};

    auto prio = h.get_file_priorities();
    if (static_cast<std::size_t>(file_index) < prio.size() &&
        prio[static_cast<std::size_t>(file_index)] == lt::dont_download) {
      prio[static_cast<std::size_t>(file_index)] = lt::default_priority;
      h.prioritize_files(prio);
    }

    auto route = std::make_shared<Route>();
    route->is_stream = true;
    route->token = random_token();
    route->ih = ih;
    route->file_index = file_index;
    route->file_offset = fs.file_offset(fi);
    route->size = fs.file_size(fi);
    lt::torrent_status st = h.status();
    route->disk_path = h.get_renamed_files().file_path(fs, fi, st.save_path);
    std::string rel = fs.file_path(fi);
    route->mime = mime_for(rel);
    route->path = "/s/" + route->token + "/" + url_leaf(rel);

    lt::error_code ec;
    lt::bdecode_node o = decode(opts, opts_len, ec);
    if (!ec && o.type() == lt::bdecode_node::dict_t) {
      route->bitrate = std::max<std::int64_t>(0, int_of(o, "bitrate", 0));
      std::int64_t secs = int_of(o, "readahead_secs", 90);
      if (route->bitrate > 0) route->readahead = route->bitrate * secs;
    }
    route->readahead = std::clamp(route->readahead, kMinReadahead, kMaxReadahead);

    // Container index lives at both ends (MP4 moov, MKV cues): fetch first.
    int plen = ti->piece_length();
    int first = static_cast<int>(route->file_offset / plen);
    int last = static_cast<int>((route->file_offset + std::max<std::int64_t>(route->size, 1) - 1) / plen);
    for (int p = first; p <= std::min(first + 1, last); ++p) {
      if (!h.have_piece(lt::piece_index_t{p})) h.set_piece_deadline(lt::piece_index_t{p}, 0);
    }
    for (int p = std::max(first, last - 1); p <= last; ++p) {
      if (!h.have_piece(lt::piece_index_t{p})) h.set_piece_deadline(lt::piece_index_t{p}, 100);
    }
    {
      std::lock_guard<std::mutex> lk(s->mu);
      Torrent* t = find_torrent(s, ih);
      if (t != nullptr && t->have.empty()) {
        t->ti = ti;
        lt::torrent_status full = h.status(lt::torrent_handle::query_pieces);
        init_pieces(*t, &full.pieces);
      }
      s->routes[route->token] = route;
    }
    if (ensure_server(s) == 0) return dup_string(error_json("server failed to start"));
    return dup_string("{\"token\":\"" + route->token + "\",\"path\":" + json_escape(route->path) +
                      ",\"size\":" + std::to_string(route->size) + "}");
  } catch (const std::exception& e) {
    return dup_string(error_json(e.what()));
  }
}

int32_t kn_stream_close(kn_session* s, const char* token) { return kn_route_close(s, token); }

char* kn_stream_stats(kn_session* s, const char* token) {
  try {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->routes.find(token ? token : "");
    if (it == s->routes.end() || !it->second->is_stream) return nullptr;
    const Route& r = *it->second;
    Torrent* t = find_torrent(s, r.ih.c_str());
    if (t == nullptr || t->piece_len <= 0) return nullptr;
    std::int64_t plen = t->piece_len;
    std::int64_t file_end = r.file_offset + r.size;
    std::int64_t have_bytes = 0;
    for (std::int64_t p = r.file_offset / plen; p * plen < file_end && p < static_cast<std::int64_t>(t->have.size()); ++p) {
      if (!t->have[static_cast<std::size_t>(p)]) continue;
      std::int64_t a = std::max(p * plen, r.file_offset), b = std::min((p + 1) * plen, file_end);
      have_bytes += b - a;
    }
    std::int64_t pos = r.position.load();
    std::int64_t abs = r.file_offset + pos;
    std::int64_t p = abs / plen;
    while (p < static_cast<std::int64_t>(t->have.size()) && p * plen < file_end && t->have[static_cast<std::size_t>(p)]) ++p;
    std::int64_t ahead = std::max<std::int64_t>(0, std::min(p * plen, file_end) - abs);
    std::ostringstream o;
    o << "{\"size\":" << r.size << ",\"have_bytes\":" << have_bytes << ",\"buffered_ahead\":" << ahead
      << ",\"position\":" << pos << ",\"connections\":" << r.connections.load() << "}";
    return dup_string(o.str());
  } catch (...) {
    return nullptr;
  }
}

char* kn_serve_file(kn_session* s, const char* path, const char* mime) {
  try {
    if (path == nullptr) return dup_string(error_json("path required"));
    auto route = std::make_shared<Route>();
    route->token = random_token();
    route->disk_path = path;
    route->mime = (mime && *mime) ? std::string(mime) : mime_for(path);
    route->path = "/f/" + route->token + "/" + url_leaf(path);
    {
      std::lock_guard<std::mutex> lk(s->mu);
      s->routes[route->token] = route;
    }
    if (ensure_server(s) == 0) return dup_string(error_json("server failed to start"));
    return dup_string("{\"token\":\"" + route->token + "\",\"path\":" + json_escape(route->path) + "}");
  } catch (const std::exception& e) {
    return dup_string(error_json(e.what()));
  }
}

int32_t kn_route_headers(kn_session* s, const char* token, const uint8_t* headers,
                         int32_t headers_len) {
  try {
    auto parsed = decode_headers(headers, headers_len);
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->routes.find(token ? token : "");
    if (it == s->routes.end()) return -1;
    it->second->headers = std::move(parsed);
    return 0;
  } catch (...) {
    return -1;
  }
}

int32_t kn_route_close(kn_session* s, const char* token) {
  try {
    std::lock_guard<std::mutex> lk(s->mu);
    auto it = s->routes.find(token ? token : "");
    if (it == s->routes.end()) return -1;
    it->second->closed.store(true);
    s->routes.erase(it);
    s->piece_cv.notify_all();
    return 0;
  } catch (...) {
    return -1;
  }
}

}  // extern "C"
