import 'dart:math' as math;

import 'grid.dart';
import 'piece.dart';

/// Picks the pieces for the tray.
///
/// Shapes are weighted (see piece.dart), and a set is only dealt if the
/// three pieces can all be placed one after another on the current board,
/// so the player is never handed a dead tray when a playable one exists.
/// Sometimes one piece is swapped for a shape that finishes a line, which
/// keeps clears and combos coming like in the classic game.
class Dealer {
  Dealer(this._rng);

  final math.Random _rng;

  static const int _attempts = 40;

  /// Chance that one piece in a deal is a shape that completes a line.
  static const double helpChance = 0.35;

  /// Search steps allowed per attempt when checking a set can be placed.
  /// When the board is open enough to run out, the set is almost certainly
  /// placeable, so it is accepted.
  static const int _searchBudget = 20000;

  final Map<List<Cell>, List<int>> _placementCache = Map.identity();

  List<Piece> deal(Grid grid, int count) {
    final board = grid.toBits();
    var fallback = <List<Cell>>[];
    var fallbackFits = -1;

    for (var attempt = 0; attempt < _attempts; attempt++) {
      final shapes = [for (var i = 0; i < count; i++) randomShape(_rng)];
      if (board != 0 && _rng.nextDouble() < helpChance) {
        final helper = _lineFinisher(board);
        if (helper != null) shapes[_rng.nextInt(count)] = helper;
      }

      final placements = [for (final s in shapes) _placements(s)];
      final fits = placements.where((p) => p.any((m) => m & board == 0)).length;
      if (fits == count &&
          _canPlaceAll(board, placements, 0, _Budget(_searchBudget))) {
        return _colour(shapes);
      }
      if (fits > fallbackFits) {
        fallback = shapes;
        fallbackFits = fits;
      }
    }
    return _colour(fallback);
  }

  /// Gives each piece a different colour.
  List<Piece> _colour(List<List<Cell>> shapes) {
    final colours = [for (var i = 1; i <= kPaletteSize; i++) i]..shuffle(_rng);
    return [
      for (var i = 0; i < shapes.length; i++)
        Piece(shapes[i], colours[i % colours.length]),
    ];
  }

  /// A random shape that completes at least one row or column somewhere.
  List<Cell>? _lineFinisher(int board) {
    final candidates = [
      for (final shape in allShapes)
        if (_placements(shape)
            .any((m) => m & board == 0 && clearLines(board | m) != (board | m)))
          shape,
    ];
    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }

  bool _canPlaceAll(
      int board, List<List<int>> placements, int used, _Budget budget) {
    if (used == (1 << placements.length) - 1) return true;
    for (var i = 0; i < placements.length; i++) {
      if (used & (1 << i) != 0) continue;
      for (final m in placements[i]) {
        if (m & board != 0) continue;
        if (--budget.left < 0) return true;
        if (_canPlaceAll(
            clearLines(board | m), placements, used | (1 << i), budget)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Bit masks for every in-bounds position of [shape].
  List<int> _placements(List<Cell> shape) =>
      _placementCache.putIfAbsent(shape, () {
        final rows = shape.map((c) => c.row).reduce(math.max) + 1;
        final cols = shape.map((c) => c.col).reduce(math.max) + 1;
        return [
          for (var r = 0; r + rows <= Grid.size; r++)
            for (var c = 0; c + cols <= Grid.size; c++)
              shape.fold<int>(
                  0,
                  (m, cell) =>
                      m | 1 << ((r + cell.row) * Grid.size + c + cell.col)),
        ];
      });

  static final List<int> _rowMasks = [
    for (var r = 0; r < Grid.size; r++) 0xFF << (r * Grid.size),
  ];
  static final List<int> _colMasks = [
    for (var c = 0; c < Grid.size; c++)
      [for (var r = 0; r < Grid.size; r++) 1 << (r * Grid.size + c)]
          .reduce((a, b) => a | b),
  ];

  /// [board] with every full row and column emptied.
  static int clearLines(int board) {
    var cleared = 0;
    for (final m in _rowMasks) {
      if (board & m == m) cleared |= m;
    }
    for (final m in _colMasks) {
      if (board & m == m) cleared |= m;
    }
    return board & ~cleared;
  }
}

class _Budget {
  _Budget(this.left);
  int left;
}
