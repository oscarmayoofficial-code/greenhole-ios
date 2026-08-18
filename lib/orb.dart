import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum OrbPhase { idle, working, done, error }

/// The central tappable orb — an exact reproduction of the Android Green Hole
/// orb: a soft green glow, two rotating HUD rings (the actual Android vector
/// art via SVG), and the green sphere on top. Tap = download, long-press = mute.
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    required this.phase,
    required this.progress,
    this.linkReady = false,
    this.onTap,
    this.onLongPress,
  });

  final OrbPhase phase;
  final double progress; // 0..1, or -1 for indeterminate
  final bool linkReady;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();

  // Android: FrameLayout 290dp, glow 232dp, opaque orb 232-2*26 = 180dp.
  static const double _frame = 290;
  static const double _glow = 232;
  static const double _orb = 180;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.phase == OrbPhase.error;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _frame,
        height: _frame,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // soft outer glow (circle_green layer 1)
            Container(
              width: _glow,
              height: _glow,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3310B981), Color(0x1810B981), Color(0x0010B981)],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            // rotating HUD rings (exact Android vectors)
            RotationTransition(
              turns: _spin,
              child: SvgPicture.asset('assets/hud_ring_mid.svg',
                  width: _frame, height: _frame),
            ),
            RotationTransition(
              turns: ReverseAnimation(_spin),
              child: SvgPicture.asset('assets/hud_ring_inner.svg',
                  width: _frame, height: _frame),
            ),
            // green sphere on top (circle_green layer 2)
            Container(
              width: _orb,
              height: _orb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.16, -0.24), // 0.42, 0.38
                  radius: 0.62,
                  colors: err
                      ? const [Color(0xFFE0655A), Color(0xFF7A1E14), Color(0xFF2A0A06)]
                      : const [Color(0xFF22D38A), Color(0xFF0E7A55), Color(0xFF06392A)],
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(color: const Color(0x5A3DDC84), width: 2),
              ),
              alignment: Alignment.center,
              child: _centerLabel(),
            ),
            // download progress ring around the sphere
            if (widget.phase == OrbPhase.working)
              AnimatedBuilder(
                animation: _spin,
                builder: (_, _) => SizedBox(
                  width: _orb + 30,
                  height: _orb + 30,
                  child: CustomPaint(
                    painter: _ProgressPainter(widget.progress, _spin.value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _centerLabel() {
    if (widget.phase == OrbPhase.working) {
      final txt = widget.progress >= 0
          ? '${(widget.progress * 100).toStringAsFixed(0)}%'
          : '';
      return Text(txt,
          style: const TextStyle(
              color: Color(0xFFEFFFF7),
              fontSize: 30,
              fontWeight: FontWeight.bold));
    }
    if (widget.phase == OrbPhase.done) {
      return const Icon(Icons.check_rounded, color: Color(0xFFEFFFF7), size: 64);
    }
    if (widget.phase == OrbPhase.error) {
      return const Icon(Icons.close_rounded, color: Color(0xFFFFE3E3), size: 58);
    }
    if (widget.linkReady) {
      return const Text('Tap',
          style: TextStyle(
              color: Color(0xFF04231A),
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2));
    }
    return const SizedBox.shrink();
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.progress, this.spin);
  final double progress;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white.withValues(alpha: 0.10));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = const Color(0xFF6EE7B7);
    final rect = Rect.fromCircle(center: c, radius: r);
    if (progress >= 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, ring);
    } else {
      canvas.drawArc(rect, spin * 2 * math.pi, math.pi * 0.55, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter o) =>
      o.progress != progress || o.spin != spin;
}
