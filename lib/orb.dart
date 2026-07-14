import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OrbPhase { idle, working, done, error }

/// The central tappable orb. Tap = download the copied link, long-press = mute
/// a picked video. It pulses when idle and spins a ring while working.
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    required this.phase,
    required this.progress,
    this.onTap,
    this.onLongPress,
  });

  final OrbPhase phase;
  final double progress; // 0..1, or -1 for indeterminate
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  static const Color _green = Color(0xFF35E08B);

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.phase) {
      case OrbPhase.error:
        return const Color(0xFFFF6B6B);
      case OrbPhase.done:
        return _green;
      default:
        return _green;
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _spin]),
        builder: (context, _) {
          final pulse = widget.phase == OrbPhase.idle
              ? 0.94 + 0.06 * _pulse.value
              : 1.0;
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _OrbPainter(
                accent: _accent,
                phase: widget.phase,
                progress: widget.progress,
                spin: _spin.value,
                pulse: pulse,
              ),
              child: Center(
                child: Icon(
                  _iconFor(widget.phase),
                  color: Colors.white,
                  size: 52,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(OrbPhase phase) {
    switch (phase) {
      case OrbPhase.working:
        return Icons.arrow_downward_rounded;
      case OrbPhase.done:
        return Icons.check_rounded;
      case OrbPhase.error:
        return Icons.close_rounded;
      case OrbPhase.idle:
        return Icons.download_rounded;
    }
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.accent,
    required this.phase,
    required this.progress,
    required this.spin,
    required this.pulse,
  });

  final Color accent;
  final OrbPhase phase;
  final double progress;
  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * pulse;

    // outer glow
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    // orb body
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [
          Color.lerp(accent, Colors.white, 0.25)!,
          accent,
          Color.lerp(accent, Colors.black, 0.55)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.72));
    canvas.drawCircle(center, radius * 0.72, body);

    // progress / activity ring
    if (phase == OrbPhase.working) {
      final ringRect = Rect.fromCircle(center: center, radius: radius * 0.86);
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.12);
      canvas.drawCircle(center, radius * 0.86, track);

      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = Colors.white;

      if (progress >= 0) {
        canvas.drawArc(
            ringRect, -math.pi / 2, 2 * math.pi * progress, false, ring);
      } else {
        canvas.drawArc(ringRect, 2 * math.pi * spin, math.pi * 0.6, false, ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.accent != accent ||
      old.phase != phase ||
      old.progress != progress ||
      old.spin != spin ||
      old.pulse != pulse;
}
