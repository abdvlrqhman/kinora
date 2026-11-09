import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Picture-in-picture (Android): the player floats when you leave the app.
final class Pip {
  Pip._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changes.add(call.arguments == true);
    });
  }
  static final instance = Pip._();

  static const _channel = MethodChannel('kinora/pip');
  final _changes = StreamController<bool>.broadcast();

  /// True while the app is shrunk into the floating window.
  Stream<bool> get changes => _changes.stream;

  /// Allows (or stops) entering PiP when the app is left, at the video's
  /// aspect ratio.
  Future<void> setAllowed({
    required bool allowed,
    int? width,
    int? height,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setAllowed', {
        'allowed': allowed,
        'width': width ?? 16,
        'height': height ?? 9,
      });
    } on PlatformException {
      // Older devices or PiP disabled by the user.
    } on MissingPluginException {
      // Tests.
    }
  }
}
