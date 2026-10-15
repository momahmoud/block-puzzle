import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'theme.dart';

/// Blocks drifting slowly upwards, for the home screen background.
class FloatingBlocks extends StatefulWidget {
  const FloatingBlocks({super.key, this.count = 16});

  final int count;

  @override
  State<FloatingBlocks> createState() => _FloatingBlocksState();
}

class _FloatingBlocksState extends State<FloatingBlocks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))
        ..repeat();

  late final List<_Drifter> _drifters = () {
    final rng = math.Random(11);
    return List.generate(widget.count, (i) {
      return _Drifter(
        x: rng.nextDouble(),
        size: 18 + rng.nextDouble() * 34,
        speed: 1 + rng.nextInt(3).toDouble(),
        phase: rng.nextDouble(),
        colorId: 1 + i % 7,
        spin: (rng.nextDouble() - 0.5) * 2,
        sway: 0.01 + rng.nextDouble() * 0.03,
        alpha: 0.18 + rng.nextDouble() * 0.22,
      );
    });
  }();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FloatingPainter(_drifters, _ctrl, theme),
        ),
      ),
    );
  }
}

class _Drifter {
  const _Drifter({
    required this.x,
    required this.size,
    required this.speed,
    required this.phase,
    required this.colorId,
    required this.spin,
    required this.sway,
    required this.alpha,
  });

  final double x;
  final double size;
  final double speed;
  final double phase;
  final int colorId;
  final double spin;
  final double sway;
  final double alpha;
}

class _FloatingPainter extends CustomPainter {
  _FloatingPainter(this.drifters, this.anim, this.theme) : super(repaint: anim);

  final List<_Drifter> drifters;
  final Animation<double> anim;
  final GameTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    for (final d in drifters) {
      final p = (t * d.speed + d.phase) % 1.0;
      final y = size.height * (1.1 - p * 1.3);
      final x =
          size.width * (d.x + math.sin((p + d.phase) * math.pi * 4) * d.sway);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(d.spin * p * math.pi);
      paintBlock(
        canvas,
        Rect.fromCenter(center: Offset.zero, width: d.size, height: d.size),
        theme.block(d.colorId).withValues(alpha: d.alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingPainter old) => old.theme != theme;
}
