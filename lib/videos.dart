import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

const String _kAlbum = 'Green Hole';

/// In-app list of the videos Green Hole has saved (the Photos "Green Hole"
/// album). Mirrors the Android VIDEOS screen: a grid of thumbnails, tap to play.
class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> {
  bool _loading = true;
  String? _error;
  List<AssetEntity> _videos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apply(() {
      _loading = true;
      _error = null;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        _fail('Photos access is needed to show your saved videos. '
            'Enable it in Settings.');
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: false,
      );
      AssetPathEntity? album;
      for (final p in paths) {
        if (p.name.toLowerCase() == _kAlbum.toLowerCase()) {
          album = p;
          break;
        }
      }
      if (album == null) {
        _apply(() {
          _loading = false;
          _videos = const [];
        });
        return;
      }
      final count = await album.assetCountAsync;
      final list = await album.getAssetListRange(
        start: 0,
        end: count < 500 ? count : 500,
      );
      _apply(() {
        _loading = false;
        _videos = list;
      });
    } catch (e) {
      _fail('Could not load videos: $e');
    }
  }

  void _apply(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _fail(String msg) {
    _apply(() {
      _loading = false;
      _error = msg;
    });
  }

  Future<void> _open(AssetEntity a) async {
    final file = await a.file;
    if (file == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PlayerPage(path: file.path),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05140C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05140C),
        foregroundColor: const Color(0xFFD9DEE2),
        elevation: 0,
        title: const Text('Your videos',
            style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 1)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)));
    }
    if (_error != null) {
      return _message(_error!);
    }
    if (_videos.isEmpty) {
      return _message(
          'No saved videos yet.\n\nCopy a video link and tap the circle to '
          'save one — it will appear here and in your Photos "Green Hole" album.');
    }
    return RefreshIndicator(
      color: const Color(0xFF10B981),
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.72,
        ),
        itemCount: _videos.length,
        itemBuilder: (_, i) => _Tile(asset: _videos[i], onTap: () => _open(_videos[i])),
      ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 15, height: 1.4)),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.asset, required this.onTap});
  final AssetEntity asset;
  final VoidCallback onTap;

  String _duration() {
    final d = asset.videoDuration;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0E1A14)),
            FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 400)),
              builder: (_, snap) {
                if (snap.data == null) return const SizedBox.shrink();
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 38),
            ),
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_duration(),
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPage extends StatefulWidget {
  const _PlayerPage({required this.path});
  final String path;

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.path));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: (!_ready || c == null)
            ? const CircularProgressIndicator(color: Color(0xFF10B981))
            : GestureDetector(
                onTap: () => setState(
                    () => c.value.isPlaying ? c.pause() : c.play()),
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
      ),
    );
  }
}
