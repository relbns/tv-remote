import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture-in-picture: the video shrinks into a floating window and keeps
/// playing over whatever else is open.
///
/// Android only, from 8.0. The whole activity is what shrinks, so the page on
/// top has to know when it happens and draw nothing but the picture.
abstract final class Pip {
  static const _channel = MethodChannel('io.benesh.tvremote/pip');

  /// True while the app is showing as a floating window.
  static final active = ValueNotifier<bool>(false);

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
    });
  }

  static Future<bool> isSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  static Map<String, int> _size(Size? size) => size == null
      ? const {}
      : {'width': size.width.round(), 'height': size.height.round()};

  /// Shrink now. False when the system refused, e.g. the setting is off.
  static Future<bool> enter(Size? videoSize) async {
    _listen();
    try {
      return await _channel.invokeMethod<bool>('enter', _size(videoSize)) ??
          false;
    } on Object {
      return false;
    }
  }

  /// Whether leaving the app should shrink the video instead of stopping it.
  static Future<void> setAutoEnter(bool enabled, [Size? videoSize]) async {
    _listen();
    try {
      await _channel.invokeMethod<void>('setAutoEnter', {
        'enabled': enabled,
        ..._size(videoSize),
      });
    } on Object {
      // Unsupported device: the player simply stops when the app is left.
    }
  }
}
