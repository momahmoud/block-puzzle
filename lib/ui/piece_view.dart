import 'package:flutter/material.dart';

import '../game/piece.dart';
import 'palette.dart';
import 'theme.dart';

/// Draws a piece at a given square size.
class PieceView extends StatelessWidget {
  const PieceView({super.key, required this.piece, required this.cell});

  final Piece piece;
  final double cell;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: piece.cols * cell,
      height: piece.rows * cell,
      child: CustomPaint(
          painter: _PiecePainter(piece, cell, GameTheme.of(context))),
    );
  }
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter(this.piece, this.cell, this.theme);

  final Piece piece;
  final double cell;
  final GameTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final color = theme.block(piece.colorId);
    for (final c in piece.cells) {
      paintBlock(
          canvas, Rect.fromLTWH(c.col * cell, c.row * cell, cell, cell), color);
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) =>
      old.piece != piece || old.cell != cell || old.theme != theme;
}
