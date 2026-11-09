// Kinora engine: libtorrent session + local HTTP range server.
//
// Conventions
// - Every function is safe to call from any thread; no C++ exception crosses
//   this boundary.
// - Inputs that carry many options are bencoded dictionaries (len + bytes).
// - Returned `char*` are UTF-8 JSON (or plain text) allocated with malloc;
//   free them with kn_free_string. NULL means "not available".
// - Torrents are addressed by their info-hash as 40 lowercase hex chars.
#ifndef KINORA_ENGINE_H
#define KINORA_ENGINE_H

#include <stdint.h>

#if defined(_WIN32)
#define KN_API __declspec(dllexport)
#else
#define KN_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct kn_session kn_session;

// Version string, e.g. "kinora-engine 0.1.0 / libtorrent 2.1.2.0".
KN_API char* kn_version(void);
KN_API void kn_free_string(char* s);

// Session ------------------------------------------------------------------
// config: bencoded dict, see packages/engine/lib/src/config.dart for keys.
// On failure returns NULL and, if error != NULL, sets *error (free it).
KN_API kn_session* kn_session_new(const uint8_t* config, int32_t config_len,
                                  char** error);
// Saves state (DHT nodes) if a state_path was configured, then shuts down.
KN_API void kn_session_free(kn_session* s);
// Applies runtime settings (rate limits, connection limits…). Same keys as
// the config dict; unknown keys are ignored. Returns 0 on success.
KN_API int32_t kn_session_apply(kn_session* s, const uint8_t* config,
                                int32_t config_len);
// Writes session state (DHT routing table) to the configured state_path.
KN_API int32_t kn_session_save_state(kn_session* s);
// BitTorrent listen port (0 if not listening yet).
KN_API int32_t kn_session_listen_port(kn_session* s);

// Torrents -----------------------------------------------------------------
// params: bencoded dict (magnet | torrent | resume, save_path, trackers…).
// Returns {"ih":"…"} or {"error":"…"}.
KN_API char* kn_add(kn_session* s, const uint8_t* params, int32_t params_len);
KN_API int32_t kn_remove(kn_session* s, const char* ih, int32_t delete_files);
KN_API int32_t kn_pause(kn_session* s, const char* ih);
KN_API int32_t kn_resume(kn_session* s, const char* ih);
// priorities: array of 0..7, one per file.
KN_API int32_t kn_set_file_priorities(kn_session* s, const char* ih,
                                      const int32_t* priorities, int32_t count);
// JSON array of files, or NULL before metadata arrives.
KN_API char* kn_files(kn_session* s, const char* ih);
// JSON array of the latest status of every torrent (cached, non-blocking).
KN_API char* kn_status_all(kn_session* s);
// JSON array of events since the previous call (metadata, finished, error…).
KN_API char* kn_poll_events(kn_session* s);
KN_API int32_t kn_save_resume(kn_session* s, const char* ih);
KN_API int32_t kn_connect_peer(kn_session* s, const char* ih, const char* ip,
                               int32_t port);

// Stream server ------------------------------------------------------------
// Port of the HTTP server (starts lazily, binds all interfaces).
KN_API int32_t kn_server_port(kn_session* s);
// Opens a stream for one file. opts: bencoded dict {bitrate, readahead_secs}.
// Returns {"token":"…","path":"/s/<token>/<name>","size":N} or {"error":…}.
KN_API char* kn_stream_open(kn_session* s, const char* ih, int32_t file_index,
                            const uint8_t* opts, int32_t opts_len);
KN_API int32_t kn_stream_close(kn_session* s, const char* token);
// {"size","have_bytes","buffered_ahead","position","connections"} or NULL.
KN_API char* kn_stream_stats(kn_session* s, const char* token);
// Serves a local file (download, subtitle). Returns {"token","path"}.
KN_API char* kn_serve_file(kn_session* s, const char* path, const char* mime);
// Extra response headers for a route (token), as a bencoded dict of strings.
KN_API int32_t kn_route_headers(kn_session* s, const char* token,
                                const uint8_t* headers, int32_t headers_len);
KN_API int32_t kn_route_close(kn_session* s, const char* token);

#ifdef __cplusplus
}
#endif

#endif  // KINORA_ENGINE_H
