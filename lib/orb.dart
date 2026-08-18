import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OrbPhase { idle, working, done, error }

/// The central tappable orb — a glowing green sphere wrapped in two rotating
/// HUD rings (arcs + tick marks), matching the Android Green Hole app.
/// Tap = download the copied link, long-press = mute a picked video.
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
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 290.0;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _pulse]),
        builder: (context, _) {
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _OrbPainter(
                phase: widget.phase,
                progress: widget.progress,
                spin: _spin.value,
                pulse: _pulse.value,
              ),
              child: Center(child: _centerLabel()),
            ),
          );
        },
      ),
    );
  }

  Widget _centerLabel() {
    // On the green orb face — dark-green text, like the Android "Click" hint.
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
      return const Icon(Icons.check_rounded, color: Color(0xFFEFFFF7), size: 66);
    }
    if (widget.phase == OrbPhase.error) {
      return const Icon(Icons.close_rounded, color: Color(0xFFFFE3E3), size: 60);
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

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.phase,
    required this.progress,
    required this.spin,
    required this.pulse,
  });

  final OrbPhase phase;
  final double progress;
  final double spin; // 0..1
  final double pulse; // 0..1

  // Palette (matches Android drawables)
  static const _highlight = Color(0xFF22D38A);
  static const _mid = Color(0xFF0E7A55);
  static const _dark = Color(0xFF06392A);
  static const _errHi = Color(0xFFE0655A);
  static const _errMid = Color(0xFF7A1E14);
  static const _bright1 = Color(0xFF34D399);
  static const _bright2 = Color(0xFF6EE7B7);
  static const _faint = Color(0x3334D399);
  static const _faint2 = Color(0x1F34D399);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final R = size.width / 2; // 145
    final orbR = R * 0.80; // green sphere radius (~116)
    final err = phase == OrbPhase.error;

    // 1) outer soft glow
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        (err ? _errHi : _highlight).withValues(alpha: 0.22),
        const Color(0x00000000),
      ]).createShader(Rect.fromCircle(center: c, radius: R));
    canvas.drawCircle(c, R, glow);

    // 2) HUD rings (rotating) — drawn under the orb edge + around it
    final t = spin * 2 * math.pi;
    _hudRing(canvas, c, orbR * 1.10, t, ticks: 40); // mid, clockwise
    _hudRing(canvas, c, orbR * 0.94, -t * 1.35, ticks: 24); // inner, ccw

    // 3) the green sphere (radial gradient, light source top-left)
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.16, -0.24), // 0.42,0.38
        radius: 0.62,
        colors: err
            ? [_errHi, _errMid, const Color(0xFF2A0A06)]
            : const [_highlight, _mid, _dark],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: orbR));
    canvas.drawCircle(c, orbR, body);
    // thin ring around the sphere
    canvas.drawCircle(
        c,
        orbR - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x5A3DDC84));

    // 4) download progress ring around the sphere
    if (phase == OrbPhase.working) {
      final rr = orbR * 1.13;
      final rect = Rect.fromCircle(center: c, radius: rr);
      canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.white.withValues(alpha: 0.10));
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = _bright2;
      if (progress >= 0) {
        canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, ring);
      } else {
        canvas.drawArc(rect, t * 2, math.pi * 0.55, false, ring);
      }
    }
  }

  // One HUD ring: faint circle + tick marks + two bright arcs (top+bottom).
  void _hudRing(Canvas canvas, Offset c, double r, double rot,
      {required int ticks}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);

    // faint full circle
    canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _faint);
    // inner faint circle
    canvas.drawCircle(
        Offset.zero,
        r * 0.90,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = _faint2);

    // tick marks
    final tick = Paint()
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..color = _faint;
    for (var i = 0; i < ticks; i++) {
      final a = (i / ticks) * 2 * math.pi;
      final o1 = Offset(math.cos(a) * (r * 0.90), math.sin(a) * (r * 0.90));
      final o2 = Offset(math.cos(a) * (r * 0.955), math.sin(a) * (r * 0.955));
      canvas.drawLine(o1, o2, tick);
    }

    // two bright arcs (top ~55°, bottom ~55°)
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    final arcTop = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = _bright1;
    final arcBot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = _bright2;
    const span = 0.95; // ~55°
    canvas.drawArc(rect, -math.pi / 2 - span / 2, span, false, arcTop);
    canvas.drawArc(rect, math.pi / 2 - span / 2, span, false, arcBot);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter o) =>
      o.phase != phase ||
      o.progress != progress ||
      o.spin != spin ||
      o.pulse != pulse;
}
