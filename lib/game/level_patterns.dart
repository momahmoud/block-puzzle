import 'dart:math' as math;

import 'grid.dart';
import 'piece.dart';

/// Which squares a level starts with filled, before colouring.
typedef Shape = List<List<bool>>;

/// Builds a starting shape. [d] is difficulty 0..1: harder shapes are
/// taller and have more awkward holes.
typedef PatternBuilder = Shape Function(math.Random rng, double d);

const int _n = Grid.size;

Shape _blank() => List.generate(_n, (_) => List.filled(_n, false));

Shape _bottomRows(math.Random rng, double d) {
  final s = _blank();
  final rows = 1 + (d * 3.5).round();
  for (var r = _n - rows; r < _n; r++) {
    for (var c = 0; c < _n; c++) {
      s[r][c] = true;
    }
  }
  return s;
}

/// A tetris-like skyline: column heights wander up and down.
Shape _skyline(math.Random rng, double d) {
  final s = _blank();
  var h = 1 + rng.nextInt(2);
  final maxH = 2 + (d * 3).round();
  for (var c = 0; c < _n; c++) {
    h = (h + rng.nextInt(3) - 1).clamp(0, maxH);
    for (var r = _n - h; r < _n; r++) {
      s[r][c] = true;
    }
  }
  return s;
}

Shape _stairs(math.Random rng, double d) {
  final s = _blank();
  final top = 2 + (d * 3).round();
  final flip = rng.nextBool();
  for (var c = 0; c < _n; c++) {
    final h = ((c + 1) * top / _n).ceil();
    final col = flip ? _n - 1 - c : c;
    for (var r = _n - h; r < _n; r++) {
      s[r][col] = true;
    }
  }
  return s;
}

Shape _pyramid(math.Random rng, double d) {
  final s = _blank();
  final levels = 2 + (d * 2).round();
  for (var i = 0; i < levels; i++) {
    final r = _n - 1 - i;
    for (var c = i; c < _n - i; c++) {
      s[r][c] = true;
    }
  }
  return s;
}

Shape _pillars(math.Random rng, double d) {
  final s = _blank();
  final odd = rng.nextBool();
  for (var c = 0; c < _n; c++) {
    if (c.isOdd != odd) continue;
    final h = 2 + rng.nextInt(2 + (d * 3).round());
    for (var r = _n - h; r < _n; r++) {
      s[r][c] = true;
    }
  }
  return s;
}

Shape _frame(math.Random rng, double d) {
  final s = _blank();
  for (var i = 0; i < _n; i++) {
    s[0][i] = s[_n - 1][i] = s[i][0] = s[i][_n - 1] = true;
  }
  if (d > 0.5) {
    for (var i = 2; i < _n - 2; i++) {
      s[2][i] = s[_n - 3][i] = s[i][2] = s[i][_n - 3] = true;
    }
  }
  return s;
}

Shape _diamond(math.Random rng, double d) {
  final s = _blank();
  final radius = 2.5 + d * 1.5;
  final hollow = rng.nextBool();
  for (var r = 0; r < _n; r++) {
    for (var c = 0; c < _n; c++) {
      final dist = (r - 3.5).abs() + (c - 3.5).abs();
      s[r][c] = dist <= radius && !(hollow && dist < 1.5);
    }
  }
  return s;
}

Shape _cross(math.Random rng, double d) {
  final s = _blank();
  final thick = d > 0.5 ? 2 : 1;
  for (var i = 0; i < _n; i++) {
    for (var t = 0; t < thick; t++) {
      s[3 + t][i] = true;
      s[i][3 + t] = true;
    }
  }
  return s;
}

Shape _corners(math.Random rng, double d) {
  final s = _blank();
  final size = 2 + (d * 1.5).round();
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      s[r][c] = s[r][_n - 1 - c] =
          s[_n - 1 - r][c] = s[_n - 1 - r][_n - 1 - c] = true;
    }
  }
  return s;
}

/// Alternating squares in the lower rows: lots of single holes.
Shape _checker(math.Random rng, double d) {
  final s = _blank();
  final rows = 2 + (d * 3).round();
  final shift = rng.nextInt(2);
  for (var r = _n - rows; r < _n; r++) {
    for (var c = 0; c < _n; c++) {
      s[r][c] = (r + c + shift).isEven;
    }
  }
  return s;
}

/// Random left half, mirrored onto the right.
Shape _mirrored(math.Random rng, double d) {
  final s = _blank();
  final p = 0.22 + d * 0.25;
  for (var r = 2; r < _n; r++) {
    for (var c = 0; c < _n ~/ 2; c++) {
      if (rng.nextDouble() < p * (r / _n + 0.3)) {
        s[r][c] = s[r][_n - 1 - c] = true;
      }
    }
  }
  return s;
}

/// Two U shapes or towers on the sides with an open middle.
Shape _towers(math.Random rng, double d) {
  final s = _blank();
  final w = 2 + (d > 0.6 ? 1 : 0);
  final h = 3 + (d * 3).round();
  for (var r = _n - h; r < _n; r++) {
    for (var c = 0; c < w; c++) {
      s[r][c] = s[r][_n - 1 - c] = true;
    }
  }
  for (var c = w; c < _n - w; c++) {
    s[_n - 1][c] = true;
  }
  return s;
}

/// The patterns, easiest first. Early levels pick from the start of the
/// list, later levels from all of it.
const List<PatternBuilder> patterns = [
  _bottomRows,
  _skyline,
  _stairs,
  _pyramid,
  _pillars,
  _towers,
  _mirrored,
  _corners,
  _frame,
  _diamond,
  _cross,
  _checker,
];

/// Colours a shape in a pleasing way: two or three colours in bands,
/// stripes, a checkerboard, or rings.
List<List<int>> colourShape(Shape shape, math.Random rng) {
  final palette = [for (var i = 1; i <= kPaletteSize; i++) i]..shuffle(rng);
  final k = 2 + rng.nextInt(2);
  final style = rng.nextInt(5);
  int pick(int r, int c) => switch (style) {
        0 => palette[r % k],
        1 => palette[c % k],
        2 => palette[(r + c) % k],
        3 => palette[(((r - 3.5).abs() + (c - 3.5).abs()) ~/ 1.5) % k],
        _ => palette[rng.nextInt(k)],
      };
  return [
    for (var r = 0; r < _n; r++)
      [for (var c = 0; c < _n; c++) shape[r][c] ? pick(r, c) : 0],
  ];
}
