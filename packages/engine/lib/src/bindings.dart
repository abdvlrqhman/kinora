import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opaque native session.
final class KnSession extends Opaque {}

typedef _StrFn = Pointer<Utf8> Function();
typedef _FreeN = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);
typedef _NewN = Pointer<KnSession> Function(
  Pointer<Uint8>,
  Int32,
  Pointer<Pointer<Utf8>>,
);
typedef _NewD = Pointer<KnSession> Function(
  Pointer<Uint8>,
  int,
  Pointer<Pointer<Utf8>>,
);
typedef _SesN = Void Function(Pointer<KnSession>);
typedef _SesD = void Function(Pointer<KnSession>);
typedef _SesIntN = Int32 Function(Pointer<KnSession>);
typedef _SesIntD = int Function(Pointer<KnSession>);
typedef _SesBytesIntN = Int32 Function(
  Pointer<KnSession>,
  Pointer<Uint8>,
  Int32,
);
typedef _SesBytesIntD = int Function(Pointer<KnSession>, Pointer<Uint8>, int);
typedef _SesBytesStrN = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Uint8>,
  Int32,
);
typedef _SesBytesStrD = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Uint8>,
  int,
);
typedef _SesStrIntN = Int32 Function(Pointer<KnSession>, Pointer<Utf8>);
typedef _SesStrIntD = int Function(Pointer<KnSession>, Pointer<Utf8>);
typedef _SesStrStrN = Pointer<Utf8> Function(Pointer<KnSession>, Pointer<Utf8>);
typedef _SesStrStrD = Pointer<Utf8> Function(Pointer<KnSession>, Pointer<Utf8>);
typedef _SesStrN = Pointer<Utf8> Function(Pointer<KnSession>);
typedef _SesStrD = Pointer<Utf8> Function(Pointer<KnSession>);
typedef _RemoveN = Int32 Function(Pointer<KnSession>, Pointer<Utf8>, Int32);
typedef _RemoveD = int Function(Pointer<KnSession>, Pointer<Utf8>, int);
typedef _PrioN = Int32 Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Int32>,
  Int32,
);
typedef _PrioD = int Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Int32>,
  int,
);
typedef _PeerN = Int32 Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Int32,
);
typedef _PeerD = int Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
);
typedef _PeerLikeN = Int32 Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _PeerLikeD = int Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _OpenN = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Int32,
  Pointer<Uint8>,
  Int32,
);
typedef _OpenD = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  int,
  Pointer<Uint8>,
  int,
);
typedef _ServeN = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _ServeD = Pointer<Utf8> Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _HeadersN = Int32 Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Int32,
);
typedef _HeadersD = int Function(
  Pointer<KnSession>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
);

/// Raw function table of the native library.
final class EngineBindings {
  /// Looks up every symbol in [lib].
  EngineBindings(DynamicLibrary lib)
    : version = lib.lookupFunction<_StrFn, _StrFn>('kn_version'),
      freeString = lib.lookupFunction<_FreeN, _FreeD>('kn_free_string'),
      sessionNew = lib.lookupFunction<_NewN, _NewD>('kn_session_new'),
      sessionFree = lib.lookupFunction<_SesN, _SesD>('kn_session_free'),
      sessionApply = lib.lookupFunction<_SesBytesIntN, _SesBytesIntD>(
        'kn_session_apply',
      ),
      sessionSaveState = lib.lookupFunction<_SesIntN, _SesIntD>(
        'kn_session_save_state',
      ),
      listenPort = lib.lookupFunction<_SesIntN, _SesIntD>(
        'kn_session_listen_port',
      ),
      add = lib.lookupFunction<_SesBytesStrN, _SesBytesStrD>('kn_add'),
      remove = lib.lookupFunction<_RemoveN, _RemoveD>('kn_remove'),
      pause = lib.lookupFunction<_SesStrIntN, _SesStrIntD>('kn_pause'),
      resume = lib.lookupFunction<_SesStrIntN, _SesStrIntD>('kn_resume'),
      setFilePriorities = lib.lookupFunction<_PrioN, _PrioD>(
        'kn_set_file_priorities',
      ),
      files = lib.lookupFunction<_SesStrStrN, _SesStrStrD>('kn_files'),
      statusAll = lib.lookupFunction<_SesStrN, _SesStrD>('kn_status_all'),
      pollEvents = lib.lookupFunction<_SesStrN, _SesStrD>('kn_poll_events'),
      saveResume = lib.lookupFunction<_SesStrIntN, _SesStrIntD>(
        'kn_save_resume',
      ),
      connectPeer = lib.lookupFunction<_PeerN, _PeerD>('kn_connect_peer'),
      moveStorage = lib.lookupFunction<_PeerLikeN, _PeerLikeD>(
        'kn_move_storage',
      ),
      serverPort = lib.lookupFunction<_SesIntN, _SesIntD>('kn_server_port'),
      streamOpen = lib.lookupFunction<_OpenN, _OpenD>('kn_stream_open'),
      streamClose = lib.lookupFunction<_SesStrIntN, _SesStrIntD>(
        'kn_stream_close',
      ),
      streamStats = lib.lookupFunction<_SesStrStrN, _SesStrStrD>(
        'kn_stream_stats',
      ),
      serveFile = lib.lookupFunction<_ServeN, _ServeD>('kn_serve_file'),
      routeHeaders = lib.lookupFunction<_HeadersN, _HeadersD>(
        'kn_route_headers',
      ),
      routeClose = lib.lookupFunction<_SesStrIntN, _SesStrIntD>(
        'kn_route_close',
      );

  /// Opens the platform library ([path] or `KINORA_ENGINE_LIB` override it).
  static DynamicLibrary open([String? path]) {
    final override = path ?? Platform.environment['KINORA_ENGINE_LIB'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return DynamicLibrary.open('kinora_engine.framework/kinora_engine');
      } on ArgumentError {
        return DynamicLibrary.process(); // statically linked pods
      }
    }
    return DynamicLibrary.open('libkinora_engine.so');
  }

  final _StrFn version;
  final _FreeD freeString;
  final _NewD sessionNew;
  final _SesD sessionFree;
  final _SesBytesIntD sessionApply;
  final _SesIntD sessionSaveState;
  final _SesIntD listenPort;
  final _SesBytesStrD add;
  final _RemoveD remove;
  final _SesStrIntD pause;
  final _SesStrIntD resume;
  final _PrioD setFilePriorities;
  final _SesStrStrD files;
  final _SesStrD statusAll;
  final _SesStrD pollEvents;
  final _SesStrIntD saveResume;
  final _PeerD connectPeer;
  final _PeerLikeD moveStorage;
  final _SesIntD serverPort;
  final _OpenD streamOpen;
  final _SesStrIntD streamClose;
  final _SesStrStrD streamStats;
  final _ServeD serveFile;
  final _HeadersD routeHeaders;
  final _SesStrIntD routeClose;

  /// Copies and frees a string returned by the engine (null stays null).
  String? take(Pointer<Utf8> p) {
    if (p == nullptr) return null;
    try {
      return p.toDartString();
    } finally {
      freeString(p);
    }
  }
}
