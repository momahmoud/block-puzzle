import 'piece.dart';

/// A square removed by a line clear, with the colour it had.
typedef ClearedCell = ({int row, int col, int colorId});

/// Rows and columns removed by one placement.
class ClearResult {
  const ClearResult(this.rows, this.cols,
      [this.cells = const [], this.iceBroken = const []]);

  static const ClearResult none = ClearResult([], []);

  final List<int> rows;
  final List<int> cols;

  /// Every square that was removed (each one once).
  final List<ClearedCell> cells;

  /// Frozen squares (row * 8 + col) whose ice broke. Their blocks stay.
  final List<int> iceBroken;

  int get lines => rows.length + cols.length;
}

/// The 8x8 board. 0 = empty, otherwise the colour id of the block.
class Grid {
  Grid() : cells = List.generate(size, (_) => List.filled(size, 0));

  Grid.fromJson(List<dynamic> flat)
      : cells = List.generate(
          size,
          (r) => List.generate(size, (c) => flat[r * size + c] as int),
        );

  static const int size = 8;

  final List<List<int>> cells;

  /// Frozen squares (row * 8 + col). A line clear breaks the ice instead of
  /// removing the block; the next clear removes it.
  final Set<int> ice = {};

  List<int> toJson() => [for (final row in cells) ...row];

  bool get isEmpty => cells.every((row) => row.every((v) => v == 0));

  /// Filled squares as a bit mask, bit (row * 8 + col).
  int toBits() {
    var bits = 0;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (cells[r][c] != 0) bits |= 1 << (r * size + c);
      }
    }
    return bits;
  }

  bool canPlace(Piece piece, int row, int col) {
    for (final c in piece.cells) {
      final r = row + c.row;
      final k = col + c.col;
      if (r < 0 || r >= size || k < 0 || k >= size) return false;
      if (cells[r][k] != 0) return false;
    }
    return true;
  }

  /// Puts [piece] on the board. Call [canPlace] first.
  void place(Piece piece, int row, int col) {
    assert(canPlace(piece, row, col));
    for (final c in piece.cells) {
      cells[row + c.row][col + c.col] = piece.colorId;
    }
  }

  /// Clears every full row and column at once, so a row and a column that
  /// cross both count and the crossing square is cleared only once.
  ClearResult clearLines() {
    final fullRows = [
      for (var r = 0; r < size; r++)
        if (cells[r].every((v) => v != 0)) r,
    ];
    final fullCols = [
      for (var c = 0; c < size; c++)
        if (cells.every((row) => row[c] != 0)) c,
    ];
    final removed = <ClearedCell>[];
    final iceBroken = <int>[];
    final seen = <int>{};
    void remove(int r, int c) {
      final key = r * size + c;
      if (cells[r][c] == 0 || !seen.add(key)) return;
      if (ice.remove(key)) {
        iceBroken.add(key);
        return;
      }
      removed.add((row: r, col: c, colorId: cells[r][c]));
      cells[r][c] = 0;
    }

    for (final r in fullRows) {
      for (var c = 0; c < size; c++) {
        remove(r, c);
      }
    }
    for (final c in fullCols) {
      for (var r = 0; r < size; r++) {
        remove(r, c);
      }
    }
    return ClearResult(fullRows, fullCols, removed, iceBroken);
  }

  /// True if [piece] fits somewhere on the board.
  bool canFitAnywhere(Piece piece) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (canPlace(piece, r, c)) return true;
      }
    }
    return false;
  }
}
