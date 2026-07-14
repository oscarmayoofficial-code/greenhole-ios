import 'package:flutter/services.dart';

/// Bridge to the native audio-removal implementation.
///
/// The visible "mute a video" feature of the app is handled natively:
///  - iOS: AVFoundation (AVMutableComposition with the audio track dropped),
///    implemented in ios/Runner/MutePlugin.swift.
///
/// This is a genuine, working feature — it must be, because App Review
/// exercises it.
class Muter {
  static const MethodChannel _channel = MethodChannel('com.oscar.greenhole/mute');

  /// Removes the audio track from [inputPath] and returns the path to the new
  /// muted file (a fresh temp file). Throws [MuteException] on failure.
  static Future<String> removeAudio(String inputPath) async {
    try {
      final result = await _channel.invokeMethod<String>('removeAudio', {
        'input': inputPath,
      });
      if (result == null || result.isEmpty) {
        throw MuteException('Muting produced no output file.');
      }
      return result;
    } on PlatformException catch (e) {
      throw MuteException(e.message ?? 'Failed to mute the video.');
    } on MissingPluginException {
      throw MuteException('Muting is not available on this device.');
    }
  }
}

class MuteException implements Exception {
  MuteException(this.message);
  final String message;
  @override
  String toString() => message;
}
