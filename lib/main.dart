import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'downloader.dart';
import 'mute.dart';
import 'orb.dart';

const String kAlbum = 'Green Hole';
final RegExp _urlRe = RegExp(r'https?://[^\s]+', caseSensitive: false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GreenHoleApp());
}

class GreenHoleApp extends StatelessWidget {
  const GreenHoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green Hole',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05140C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF35E08B),
          secondary: Color(0xFF35E08B),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Downloader _downloader = Downloader();
  final ImagePicker _picker = ImagePicker();

  AppConfig _config = AppConfig.fallback();
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  OrbPhase _phase = OrbPhase.idle;
  String _status = '';
  double _progress = 0; // 0..1, or -1 for indeterminate
  String? _clipboardUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _config = await _downloader.fetchConfig();

    // Links shared into the app while it was closed.
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    _handleShared(initial);
    ReceiveSharingIntent.instance.reset();

    // Links shared while the app is already running.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleShared,
      onError: (_) {},
    );

    await _refreshClipboard();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _downloader.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshClipboard();
    }
  }

  // --- input sources -------------------------------------------------------

  Future<void> _refreshClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final url = _extractUrl(data?.text);
      if (url != _clipboardUrl && mounted) {
        setState(() => _clipboardUrl = url);
      }
    } catch (_) {
      // clipboard access can be denied; ignore
    }
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    for (final f in files) {
      final url = _extractUrl(f.path);
      if (url != null) {
        // let the first frame settle before we start work
        Future.delayed(
            const Duration(milliseconds: 400), () => _startDownload(url));
        return;
      }
    }
  }

  String? _extractUrl(String? raw) {
    if (raw == null) return null;
    final m = _urlRe.firstMatch(raw.trim());
    return m?.group(0);
  }

  // --- actions -------------------------------------------------------------

  Future<void> _onOrbTap() async {
    await _refreshClipboard();
    final url = _clipboardUrl;
    if (url == null) {
      _showSnack('Copy a video link first, then tap the circle.');
      return;
    }
    await _startDownload(url);
  }

  Future<void> _startDownload(String url) async {
    if (_busy) return;
    _busy = true;
    _setPhase(OrbPhase.working, 'Fetching video…', progress: -1);
    try {
      final result = await _downloader.download(
        url,
        config: _config,
        onProgress: (received, total) {
          if (total > 0) {
            final pct = (received * 100 / total).clamp(0, 100);
            _setPhase(OrbPhase.working, 'Downloading… ${pct.toStringAsFixed(0)}%',
                progress: received / total);
          } else {
            final mb = received / (1024 * 1024);
            _setPhase(OrbPhase.working,
                'Downloading… ${mb.toStringAsFixed(1)} MB',
                progress: -1);
          }
        },
      );
      _setPhase(OrbPhase.working, 'Saving to Photos…', progress: -1);
      await _ensurePhotosAccess();
      await Gal.putVideo(result.file.path, album: kAlbum);
      await _safeDelete(result.file.path);
      _setPhase(OrbPhase.done, 'Saved to Photos ✓');
    } catch (e) {
      _setPhase(OrbPhase.error, _friendly(e));
    } finally {
      _busy = false;
    }
  }

  Future<void> _onOrbLongPress() async {
    if (_busy) return;
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    _busy = true;
    _setPhase(OrbPhase.working, 'Removing sound…', progress: -1);
    try {
      final mutedPath = await Muter.removeAudio(picked.path);
      _setPhase(OrbPhase.working, 'Saving to Photos…', progress: -1);
      await _ensurePhotosAccess();
      await Gal.putVideo(mutedPath, album: kAlbum);
      await _safeDelete(mutedPath);
      _setPhase(OrbPhase.done, 'Muted video saved to Photos ✓');
    } catch (e) {
      _setPhase(OrbPhase.error, _friendly(e));
    } finally {
      _busy = false;
    }
  }

  Future<void> _ensurePhotosAccess() async {
    if (await Gal.hasAccess()) return;
    final granted = await Gal.requestAccess();
    if (!granted) {
      throw Exception('Photos access denied. Enable it in Settings to save.');
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  String _friendly(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  // --- ui helpers ----------------------------------------------------------

  void _setPhase(OrbPhase p, String status, {double progress = 0}) {
    if (!mounted) return;
    setState(() {
      _phase = p;
      _status = status;
      _progress = progress;
    });
    if (p == OrbPhase.done || p == OrbPhase.error) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _phase == p) {
          setState(() => _phase = OrbPhase.idle);
        }
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final linkReady = _phase == OrbPhase.idle && _clipboardUrl != null;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.16),
            radius: 1.15,
            colors: [Color(0xFF171A18), Color(0xFF040605)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // info (top-left)
              Positioned(
                top: 6,
                left: 6,
                child: IconButton(
                  icon: SvgPicture.asset('assets/ic_info.svg',
                      width: 26, height: 26),
                  onPressed: _showInfo,
                ),
              ),
              // support / donate (top-right)
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  icon: SvgPicture.asset('assets/ic_heart.svg',
                      width: 24, height: 24),
                  onPressed: _showSupport,
                ),
              ),
              // brand
              const Positioned(
                top: 78,
                left: 0,
                right: 0,
                child: Text(
                  'GREEN HOLE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFD9DEE2),
                      fontSize: 19,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 7),
                ),
              ),
              // center: orb + status
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Orb(
                      phase: _phase,
                      progress: _progress,
                      linkReady: linkReady,
                      onTap: _busy ? null : _onOrbTap,
                      onLongPress: _busy ? null : _onOrbLongPress,
                    ),
                    const SizedBox(height: 18),
                    _StatusText(
                        phase: _phase,
                        status: _status,
                        clipboardUrl: _clipboardUrl),
                  ],
                ),
              ),
              // bottom: VIDEOS
              Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: InkWell(
                    onTap: _showVideos,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/ic_videos.svg',
                              width: 30, height: 30),
                          const SizedBox(height: 5),
                          const Text('VIDEOS',
                              style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 12,
                                  letterSpacing: 3)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupport() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Support Green Hole'),
        content: const Text(
          'Green Hole is free. If it helps you, please leave a nice rating on '
          'the App Store — that keeps it going. Thank you! 💚',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showVideos() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your videos'),
        content: const Text(
          'Saved videos are in your Photos app, in the "Green Hole" album.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('How to use Green Hole'),
        content: const Text(
          'Green Hole is a simple tool for your videos.\n\n'
          '• Copy a video link, then TAP the circle to save it to your Photos.\n\n'
          '• HOLD (long-press) the circle to pick a video and remove its sound.\n\n'
          'You can also Share a link from another app into Green Hole.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.phase,
    required this.status,
    required this.clipboardUrl,
  });

  final OrbPhase phase;
  final String status;
  final String? clipboardUrl;

  @override
  Widget build(BuildContext context) {
    if (phase != OrbPhase.idle && status.isNotEmpty) {
      final color = phase == OrbPhase.error
          ? const Color(0xFFFF6B6B)
          : phase == OrbPhase.done
              ? const Color(0xFF35E08B)
              : Colors.white;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(status,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 15)),
      );
    }
    if (clipboardUrl != null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text('Link ready — tap the circle to save',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF34D399), fontSize: 13)),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text('Copy a video link, then tap  ·  hold to remove sound',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13)),
    );
  }
}
