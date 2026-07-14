import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Remote app configuration served from the same backend the Android app uses.
///
/// GET https://oscarvid.com/app-config.json?t=`millis`
/// -> { "server_all": bool, "server": "https://...", "srv_platforms": [...],
///      "server_platforms": [...], "min_version": int }
class AppConfig {
  AppConfig({
    required this.server,
    required this.serverAll,
    required this.serverPlatforms,
    required this.minVersion,
  });

  /// Base URL every download is routed through. On iOS we do not bundle an
  /// on-device extractor, so *all* links go through the server regardless of
  /// [serverAll] / [serverPlatforms] — those are kept only to honour a future
  /// server override of the base URL and the force-update gate.
  final String server;
  final bool serverAll;
  final List<String> serverPlatforms;
  final int minVersion;

  static const String _defaultServer = 'https://oscarvid.com';

  factory AppConfig.fallback() => AppConfig(
        server: _defaultServer,
        serverAll: false,
        serverPlatforms: const [],
        minVersion: 0,
      );

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final rawServer = (j['server'] as String?)?.trim();
    final platforms = <String>[];
    for (final key in const ['srv_platforms', 'server_platforms']) {
      final v = j[key];
      if (v is List) {
        platforms.addAll(v.map((e) => e.toString().toLowerCase()));
      }
    }
    return AppConfig(
      server: (rawServer != null && rawServer.isNotEmpty)
          ? rawServer
          : _defaultServer,
      serverAll: j['server_all'] == true,
      serverPlatforms: platforms,
      minVersion: (j['min_version'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Progress callback: [received] and [total] are byte counts. [total] is 0 when
/// the server does not advertise a length.
typedef ProgressCallback = void Function(int received, int total);

class DownloadResult {
  DownloadResult({required this.file, required this.suggestedName});
  final File file;
  final String suggestedName;
}

class DownloadException implements Exception {
  DownloadException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class Downloader {
  Downloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // A non-"mozilla" User-Agent makes the backend answer FB/IG/TikTok links with
  // a fast 302 straight to the CDN instead of proxying the bytes itself.
  static const String _userAgent = 'GreenHole-iOS/1.0';

  /// Fetch the remote config; never throws — falls back to defaults on any error.
  Future<AppConfig> fetchConfig() async {
    try {
      final uri = Uri.parse(
          '${AppConfig.fallback().server}/app-config.json?t=${_cacheBust()}');
      final res = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = res.body.trim();
        if (body.startsWith('{')) {
          final decoded = _decode(body);
          if (decoded != null) return AppConfig.fromJson(decoded);
        }
      }
    } catch (_) {
      // fall through to defaults
    }
    return AppConfig.fallback();
  }

  /// Resolve [pageUrl] via the backend and stream the video to a temp file.
  ///
  /// Handles both backend response modes transparently:
  ///  - 302 redirect to a CDN mp4 (FB reels / IG / TikTok / Threads), and
  ///  - a proxied `video/mp4` byte stream (YouTube / FB watch / Snapchat / MP3).
  Future<DownloadResult> download(
    String pageUrl, {
    required AppConfig config,
    String quality = 'best',
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final endpoint = Uri.parse('${config.server}/download').replace(
      queryParameters: {'url': pageUrl, 'quality': quality},
    );

    final request = http.Request('GET', endpoint)
      ..followRedirects = true
      ..maxRedirects = 8
      ..headers['User-Agent'] = _userAgent
      ..headers['Accept'] = '*/*';

    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 45));

    if (streamed.statusCode == 429) {
      throw DownloadException(
          'Too many requests — please wait a moment and try again.',
          statusCode: 429);
    }
    if (streamed.statusCode == 503) {
      throw DownloadException('Server is busy — please try again shortly.',
          statusCode: 503);
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw DownloadException('Could not fetch this video (HTTP '
          '${streamed.statusCode}). The link may be private or unsupported.',
          statusCode: streamed.statusCode);
    }

    final name = _fileName(streamed);
    final total = _totalBytes(streamed);

    final dir = await getTemporaryDirectory();
    final safeName = _sanitize(name);
    final outFile = File('${dir.path}/$safeName');
    if (await outFile.exists()) {
      await outFile.delete();
    }
    final sink = outFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        if (cancel?.isCancelled == true) {
          await sink.close();
          await outFile.delete();
          throw DownloadException('Download cancelled.');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await outFile.exists()) await outFile.delete();
      if (e is DownloadException) rethrow;
      throw DownloadException('Download failed: $e');
    }

    if (received == 0) {
      if (await outFile.exists()) await outFile.delete();
      throw DownloadException('The server returned an empty file.');
    }

    return DownloadResult(file: outFile, suggestedName: safeName);
  }

  void dispose() => _client.close();

  // --- helpers -------------------------------------------------------------

  int _cacheBust() => DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic>? _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  int _totalBytes(http.StreamedResponse res) {
    final x = res.headers['x-total-bytes'];
    final parsedX = x == null ? null : int.tryParse(x.trim());
    if (parsedX != null && parsedX > 0) return parsedX;
    return res.contentLength ?? 0;
  }

  String _fileName(http.StreamedResponse res) {
    final cd = res.headers['content-disposition'];
    if (cd != null) {
      // filename*=UTF-8''<percent-encoded>
      final ext = RegExp("filename\\*=UTF-8''([^;]+)", caseSensitive: false)
          .firstMatch(cd);
      if (ext != null) {
        try {
          return Uri.decodeComponent(ext.group(1)!.trim());
        } catch (_) {}
      }
      // filename="..."
      final basic =
          RegExp('filename="?([^";]+)"?', caseSensitive: false).firstMatch(cd);
      if (basic != null) return basic.group(1)!.trim();
    }
    final ct = res.headers['content-type'] ?? '';
    final ext = ct.contains('audio') ? 'mp3' : 'mp4';
    return 'greenhole_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  String _sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (s.isEmpty) s = 'greenhole_video.mp4';
    if (!RegExp(r'\.[A-Za-z0-9]{2,4}$').hasMatch(s)) s = '$s.mp4';
    return s.length > 120 ? s.substring(s.length - 120) : s;
  }
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
