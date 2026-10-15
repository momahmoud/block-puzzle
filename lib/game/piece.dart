import 'dart:math' as math;

/// Number of distinct block colours. Must match the palette in ui/palette.dart.
const int kPaletteSize = 7;

/// One square of a piece, relative to the piece's top-left corner.
class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '($row,$col)';
}

/// A draggable block shape. [colorId] is 1..[kPaletteSize].
class Piece {
  const Piece(this.cells, this.colorId);

  final List<Cell> cells;
  final int colorId;

  int get rows => cells.map((c) => c.row).reduce(math.max) + 1;
  int get cols => cells.map((c) => c.col).reduce(math.max) + 1;

  /// Number of squares in the piece.
  int get size => cells.length;

  Map<String, Object> toJson() => {
        'cells': [
          for (final c in cells) ...[c.row, c.col]
        ],
        'color': colorId,
      };

  static Piece fromJson(Map<String, dynamic> json) {
    final flat = (json['cells'] as List).cast<int>();
    return Piece([
      for (var i = 0; i + 1 < flat.length; i += 2) Cell(flat[i], flat[i + 1]),
    ], json['color'] as int);
  }
}

// Base shapes, drawn as text. '#' is a filled square, and the number is how
// often the shape is dealt relative to the others. Rotations and mirror
// images are generated below and share their base shape's weight.
const List<(List<String>, double)> _baseShapes = [
  (['#'], 1.0),
  (['##'], 2.5),
  (['###'], 3.0),
  (['####'], 2.5),
  (['#####'], 1.5),
  (['##', '##'], 3.0),
  (['###', '###'], 2.0),
  (['###', '###', '###'], 1.2),
  (['#.', '##'], 3.0),
  (['#..', '#..', '###'], 1.8),
  (['#..', '###'], 3.0),
  (['.#.', '###'], 2.0),
  (['##.', '.##'], 2.0),
];

List<Cell> _normalize(Iterable<Cell> input) {
  final cells = input.toList();
  final minRow = cells.map((c) => c.row).reduce(math.min);
  final minCol = cells.map((c) => c.col).reduce(math.min);
  final out = cells.map((c) => Cell(c.row - minRow, c.col - minCol)).toList()
    ..sort((a, b) =>
        a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
  return out;
}

List<Cell> _rotate(List<Cell> cells) =>
    _normalize(cells.map((c) => Cell(c.col, -c.row)));

List<Cell> _mirror(List<Cell> cells) =>
    _normalize(cells.map((c) => Cell(c.row, -c.col)));

String _key(List<Cell> cells) =>
    cells.map((c) => '${c.row},${c.col}').join(';');

/// Every distinct shape (all rotations and mirror images, no duplicates),
/// with how often each one should be dealt.
final List<({List<Cell> cells, double weight})> _weightedShapes = () {
  final seen = <String>{};
  final out = <({List<Cell> cells, double weight})>[];
  for (final (rows, weight) in _baseShapes) {
    final base = <Cell>[];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        if (rows[r][c] == '#') base.add(Cell(r, c));
      }
    }
    final variants = <List<Cell>>[];
    final normalized = _normalize(base);
    for (final mirrored in [false, true]) {
      var shape = mirrored ? _mirror(normalized) : normalized;
      for (var i = 0; i < 4; i++) {
        if (seen.add(_key(shape))) variants.add(shape);
        shape = _rotate(shape);
      }
    }
    for (final v in variants) {
      out.add((cells: v, weight: weight / variants.length));
    }
  }
  return out;
}();

/// Every distinct shape (all rotations and mirror images, no duplicates).
final List<List<Cell>> allShapes = [for (final s in _weightedShapes) s.cells];

final double _totalWeight = _weightedShapes.fold(0, (sum, s) => sum + s.weight);

/// A random shape, picked by weight.
List<Cell> randomShape(math.Random rng) {
  var pick = rng.nextDouble() * _totalWeight;
  for (final s in _weightedShapes) {
    pick -= s.weight;
    if (pick < 0) return s.cells;
  }
  return _weightedShapes.last.cells;
}

/// A random shape in a random colour.
Piece randomPiece(math.Random rng) =>
    Piece(randomShape(rng), 1 + rng.nextInt(kPaletteSize));
