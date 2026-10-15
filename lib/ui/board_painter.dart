import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/grid.dart';
import '../game/piece.dart';
import 'palette.dart';
import 'theme.dart';

/// Paints the board, plus a preview of the piece being dragged ([ghost]).
/// Rows and columns that the drop would clear are shown in the dragged
/// piece's colour.
class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.theme,
    required this.cells,
    this.ghost,
    this.ghostRow = 0,
    this.ghostCol = 0,
    this.popCells = const {},
    this.popT = 1,
    this.greyT = 0,
    this.gems = const {},
    this.ice = const {},
  });

  final GameTheme theme;
  final List<List<int>> cells;
  final Piece? ghost;
  final int ghostRow;
  final int ghostCol;

  /// Squares just placed (row * 8 + col), which bounce while [popT] runs 0..1.
  final Set<int> popCells;
  final double popT;

  /// Game over: blocks turn grey row by row as this runs 0..1.
  final double greyT;

  /// Squares (row * 8 + col) holding a gem.
  final Set<int> gems;

  /// Frozen squares (row * 8 + col).
  final Set<int> ice;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / Grid.size;
    final pad = cell * 0.08;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(pad),
        Radius.circular(cell * 0.3),
      ),
      Paint()..color = theme.board,
    );

    final ghostCells = <int>{};
    final g = ghost;
    if (g != null) {
      for (final c in g.cells) {
        ghostCells.add((ghostRow + c.row) * Grid.size + ghostCol + c.col);
      }
    }
    bool filled(int r, int c) =>
        cells[r][c] != 0 || ghostCells.contains(r * Grid.size + c);

    final clearRows = <int>{};
    final clearCols = <int>{};
    if (g != null) {
      for (var i = 0; i < Grid.size; i++) {
        if (List.generate(Grid.size, (j) => filled(i, j)).every((v) => v)) {
          clearRows.add(i);
        }
        if (List.generate(Grid.size, (j) => filled(j, i)).every((v) => v)) {
          clearCols.add(i);
        }
      }
    }

    // Placed squares grow a little and settle back.
    final popScale = 1 + 0.12 * math.sin(math.pi * popT.clamp(0.0, 1.0));

    for (var r = 0; r < Grid.size; r++) {
      final grey = (greyT * (Grid.size + 2) - r).clamp(0.0, 1.0);
      for (var c = 0; c < Grid.size; c++) {
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        final value = cells[r][c];
        final key = r * Grid.size + c;
        final willClear =
            g != null && (clearRows.contains(r) || clearCols.contains(c));

        if (value == 0) {
          paintEmpty(canvas, rect, theme.emptyCell);
          if (ghostCells.contains(key) && g != null) {
            final color = willClear
                ? theme.block(g.colorId)
                : theme.block(g.colorId).withValues(alpha: 0.45);
            paintBlock(canvas, rect, color);
          }
          continue;
        }

        var color = willClear ? theme.block(g.colorId) : theme.block(value);
        if (grey > 0) color = Color.lerp(color, kGameOverGrey, grey)!;
        paintBlock(
          canvas,
          rect,
          color,
          scale: popCells.contains(key) ? popScale : 1,
        );
        if (gems.contains(key)) paintGem(canvas, rect, alpha: 1 - grey * 0.5);
        if (ice.contains(key)) paintIce(canvas, rect, alpha: 1 - grey * 0.4);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}

/// One bit of debris thrown out by a line clear.
class Particle {
  Particle({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
  });

  final Offset origin; // in cell units
  final Offset velocity; // cell units per animation
  final Color color;
  final double size; // fraction of a cell
  final double spin;
}

/// Animates cleared squares: they flash, shrink away, and throw particles.
/// Drawn over the board without clipping, so debris can fly past its edges.
class ClearEffectPainter extends CustomPainter {
  ClearEffectPainter({
    this.gems = const [],
    this.ice = const [],
    required this.theme,
    required this.cleared,
    required this.particles,
    required this.origin,
    required this.t,
  });

  /// Gem squares collected by this clear; they swell and fade out.
  final List<int> gems;

  /// Squares whose ice broke; shards fly off them.
  final List<int> ice;
  final GameTheme theme;
  final List<ClearedCell> cleared;
  final List<Particle> particles;

  /// Board square the wave starts from (where the piece was dropped).
  final Offset origin;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1 || cleared.isEmpty) return;
    final cell = size.width / Grid.size;

    for (final c in cleared) {
      final dist =
          (Offset(c.col.toDouble(), c.row.toDouble()) - origin).distance;
      final local = ((t - dist * 0.025) / 0.55).clamp(0.0, 1.0);
      if (local >= 1) continue;
      final rect = Rect.fromLTWH(c.col * cell, c.row * cell, cell, cell);

      final color = theme.block(c.colorId);
      final flash = local < 0.25 ? local / 0.25 : 1 - (local - 0.25) / 0.75;
      final scale = local < 0.25
          ? 1 + 0.1 * local / 0.25
          : 1.1 * (1 - Curves.easeIn.transform((local - 0.25) / 0.75));
      paintBlock(canvas, rect, Color.lerp(color, Colors.white, flash * 0.7)!,
          scale: scale);
    }

    for (final g in gems) {
      final rect = Rect.fromLTWH(
          (g % Grid.size) * cell, (g ~/ Grid.size) * cell, cell, cell);
      final grow = Curves.easeOut.transform((t / 0.6).clamp(0.0, 1.0));
      paintGem(
        canvas,
        rect.translate(0, -cell * 0.8 * grow),
        scale: 1 + 0.8 * grow,
        alpha: (1 - t).clamp(0.0, 1.0),
      );
    }

    for (final i in ice) {
      final center =
          Offset((i % Grid.size + 0.5) * cell, (i ~/ Grid.size + 0.5) * cell);
      final fly = Curves.easeOut.transform(t);
      for (var k = 0; k < 5; k++) {
        final angle = k * math.pi * 2 / 5 + i;
        canvas.save();
        canvas.translate(
          center.dx + math.cos(angle) * cell * 0.9 * fly,
          center.dy + math.sin(angle) * cell * 0.9 * fly + cell * 0.6 * t * t,
        );
        canvas.rotate(angle + t * 4);
        paintIceShard(canvas, cell * 0.32, (1 - t).clamp(0.0, 1.0));
        canvas.restore();
      }
    }

    for (final p in particles) {
      final pt = Curves.easeOut.transform(t);
      final pos = (p.origin + p.velocity * pt + Offset(0, 1.6 * t * t)) * cell;
      final alpha = (1 - t).clamp(0.0, 1.0);
      final s = p.size * cell * (1 - 0.5 * t);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s, height: s),
          Radius.circular(s * 0.25),
        ),
        Paint()..color = p.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ClearEffectPainter old) =>
      old.t != t || old.cleared != cleared;
}
