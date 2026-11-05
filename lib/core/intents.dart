import 'dart:async';

import 'package:flutter/services.dart';

/// Android intents in and out, through the `pawress/intents` channel in
/// MainActivity.kt: pawchive.pw links opened or shared into the app, sharing
/// a file or offering it to "Set as" (wallpaper, contact photo), opening a
/// downloaded file or its folder, and whether the network is metered.
class AndroidIntents {
  AndroidIntents._();

  static const _channel = MethodChannel('pawress/intents');

  /// Links that arrive while Pawress is already running.
  static final links = StreamController<String>.broadcast();
  static bool _listening = false;

  static bool? _metered;
  static DateTime _meteredAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        links.add(call.arguments as String);
      }
    });
  }

  /// The link or shared text that launched the app, handed out once.
  static Future<String?> initialLink() => _call<String>('initialLink');

  /// Opens Android's share sheet for a file in the app's `shared` cache
  /// folder.
  static Future<bool> shareFile(String path, String mime) async =>
      await _call<bool>('shareFile', {'path': path, 'mime': mime}) ?? false;

  /// Offers an image to apps that can use it, such as the wallpaper picker.
  static Future<bool> setAs(String path, String mime) async =>
      await _call<bool>('setAs', {'path': path, 'mime': mime}) ?? false;

  /// Opens a saved file (a SAF document URI) in an app that can view it.
  static Future<bool> viewFile(String uri, String mime) async =>
      await _call<bool>('viewFile', {'uri': uri, 'mime': mime}) ?? false;

  /// Opens a SAF folder (a tree URI from the folder picker) in the phone's
  /// file browser.
  static Future<bool> viewFolder(String treeUri) async =>
      await _call<bool>('viewFolder', {'uri': treeUri}) ?? false;

  /// Whether the active network is metered (usually mobile data). Asked at
  /// most every 30 seconds.
  static Future<bool> isMetered() async {
    final now = DateTime.now();
    if (_metered != null &&
        now.difference(_meteredAt) < const Duration(seconds: 30)) {
      return _metered!;
    }
    _metered = await _call<bool>('isMetered') ?? false;
    _meteredAt = now;
    return _metered!;
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
