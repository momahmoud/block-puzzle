import 'package:flutter/material.dart';

import 'palette.dart';
import 'theme.dart';
import 'widgets.dart';

/// A one-time explanation of a new block type ('ice' or 'gems').
Future<void> showTipDialog(BuildContext context, String tip) {
  final theme = GameTheme.of(context);
  final (title, text) = switch (tip) {
    'ice' => (
        'Frozen blocks',
        'A frozen block survives one line clear: the first clear breaks the ice, the next one removes the block.',
      ),
    _ => (
        'Gems',
        'Clear the row or column a gem sits in to collect it. A bomb collects gems too.',
      ),
  };
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: theme.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Colors.white24, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'NEW!',
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: Colors.white60),
            ),
            OutlinedText(title, size: 30),
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: CustomPaint(
                  size: const Size(200, 64), painter: _TipPainter(tip, theme)),
            ),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.35)),
            const SizedBox(height: 20),
            ChunkyButton(
                label: 'Got it', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    ),
  );
}

/// Ice: frozen block, cracked block, gone. Gems: a row of blocks with a gem.
class _TipPainter extends CustomPainter {
  const _TipPainter(this.tip, this.theme);

  final String tip;
  final GameTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.height * 0.8;
    final y = (size.height - cell) / 2;
    final arrow = Paint()
      ..color = Colors.white54
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (tip == 'ice') {
      final color = theme.block(5);
      final xs = [0.0, size.width / 2 - cell / 2, size.width - cell];
      paintBlock(canvas, Rect.fromLTWH(xs[0], y, cell, cell), color);
      paintIce(canvas, Rect.fromLTWH(xs[0], y, cell, cell));
      paintBlock(canvas, Rect.fromLTWH(xs[1], y, cell, cell), color);
      paintEmpty(canvas, Rect.fromLTWH(xs[2], y, cell, cell), theme.emptyCell);
      for (var i = 0; i < 2; i++) {
        final from = xs[i] + cell + 8, to = xs[i + 1] - 8;
        canvas.drawLine(
            Offset(from, size.height / 2), Offset(to, size.height / 2), arrow);
        canvas.drawLine(Offset(to - 6, size.height / 2 - 6),
            Offset(to, size.height / 2), arrow);
        canvas.drawLine(Offset(to - 6, size.height / 2 + 6),
            Offset(to, size.height / 2), arrow);
      }
    } else {
      final small = size.width / 5;
      for (var i = 0; i < 5; i++) {
        final rect =
            Rect.fromLTWH(i * small, (size.height - small) / 2, small, small);
        paintBlock(canvas, rect, theme.block(1 + i));
        if (i == 2) paintGem(canvas, rect);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TipPainter old) =>
      old.tip != tip || old.theme != theme;
}
