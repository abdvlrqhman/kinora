import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

typedef _FreeSpaceC = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _FreeSpaceDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);

/// Windows: GetDiskFreeSpaceExW (the space this user may use).
int? _freeBytesWindows(String path) {
  try {
    final free = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_FreeSpaceC, _FreeSpaceDart>('GetDiskFreeSpaceExW');
    final out = calloc<Uint64>();
    final cPath = path.toNativeUtf16();
    try {
      return free(cPath, out, nullptr, nullptr) == 0 ? null : out.value;
    } finally {
      calloc.free(out);
      malloc.free(cPath);
    }
  } on Object {
    return null;
  }
}

typedef _StatvfsC = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatvfsDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

/// Free bytes on the volume that holds [path], or null when unknown.
///
/// Calls libc `statvfs`. Layouts: Linux/Android use `unsigned long` for every
/// count (`f_frsize` is word 1, `f_bavail` word 4); Darwin keeps
/// `f_bavail` as a 32-bit count at byte 24. iOS reports space without the
/// purgeable part, so it can read a little low.
int? freeBytes(String path) {
  if (Platform.isWindows) return _freeBytesWindows(path);
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isLinux)) return null;
  try {
    final lib = Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : DynamicLibrary.process();
    final statvfs = lib.lookupFunction<_StatvfsC, _StatvfsDart>('statvfs');
    final buf = calloc<Uint8>(256);
    final cPath = path.toNativeUtf8();
    try {
      if (statvfs(cPath, buf) != 0) return null;
      final words = buf.cast<UnsignedLong>();
      final frsize = words[1];
      final avail = Platform.isIOS
          ? (buf + 2 * sizeOf<UnsignedLong>() + 8).cast<Uint32>().value
          : words[4];
      return frsize * avail;
    } finally {
      calloc.free(buf);
      malloc.free(cPath);
    }
  } on Object {
    return null;
  }
}

/// Free space where downloads are saved (null when the OS won't say).
final freeSpaceProvider = FutureProvider.autoDispose<int?>(
  (ref) async => freeBytes(ref.watch(pathsProvider).downloadsRoot.path),
);
