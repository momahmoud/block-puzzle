import 'dart:math' as math;

import 'game_controller.dart';
import 'grid.dart';
import 'levels.dart';

final List<int> _lineMasks = [
  for (var r = 0; r < 8; r++) 0xFF << (r * 8),
  for (var c = 0; c < 8; c++)
    [for (var r = 0; r < 8; r++) 1 << (r * 8 + c)].reduce((a, b) => a | b),
];

int _popcount(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

int _mask(Iterable<int> squares) => squares.fold(0, (m, i) => m | 1 << i);

/// Plays [level] greedily: every piece in every spot, taking the one that
/// clears the most lines (several at once preferred), hits gems and ice,
/// and packs blocks tightly. Not a strong player, but steady, which makes
/// it a fair yardstick for difficulty.
///
/// Returns how many moves it took to win, or null if it got stuck or ran
/// past [cap] moves.
int? botMovesToWin(LevelSpec level, int seed, {int cap = 120}) {
  final open = level.withMoves(cap);
  final game = GameController(random: math.Random(seed), level: open);
  while (!game.gameOver) {
    final board = game.grid.toBits();
    final gemBits = _mask(game.gems);
    final iceBits = _mask(game.grid.ice);
    var best = double.negativeInfinity;
    (int, int, int)? choice;
    for (var i = 0; i < game.tray.length; i++) {
      final piece = game.tray[i];
      if (piece == null) continue;
      for (var r = 0; r + piece.rows <= Grid.size; r++) {
        for (var c = 0; c + piece.cols <= Grid.size; c++) {
          final m = piece.cells
              .fold<int>(0, (m, x) => m | 1 << ((r + x.row) * 8 + c + x.col));
          if (m & board != 0) continue;
          final placed = board | m;
          var lines = 0;
          var cleared = 0;
          for (final lm in _lineMasks) {
            if (placed & lm == lm) {
              lines++;
              cleared |= lm;
            }
          }
          final after = placed & ~(cleared & ~iceBits);
          var value = lines * lines * 10.0 +
              _popcount(cleared & gemBits) * 40 +
              _popcount(cleared & iceBits) * 30 -
              _popcount(after) * 0.3;
          // Reward touching walls and blocks; nudge towards gem and ice lines.
          for (final x in piece.cells) {
            final rr = r + x.row, cc = c + x.col;
            for (final (dr, dc) in const [(0, 1), (1, 0), (0, -1), (-1, 0)]) {
              final nr = rr + dr, nc = cc + dc;
              if (nr < 0 ||
                  nr >= 8 ||
                  nc < 0 ||
                  nc >= 8 ||
                  placed & (1 << (nr * 8 + nc)) != 0) {
                value += 1;
              }
            }
            for (final t in [...game.gems, ...game.grid.ice]) {
              if (t ~/ 8 == rr || t % 8 == cc) value += 1.2;
            }
          }
          if (value > best) {
            best = value;
            choice = (i, r, c);
          }
        }
      }
    }
    if (choice == null) break;
    game.place(choice.$1, choice.$2, choice.$3);
  }
  return game.won ? cap - game.movesLeft : null;
}

/// A move limit for [level] such that the bot wins about [winRate] of
/// [seeds] games, or null if it wins too rarely to tell.
int? calibrateMoves(LevelSpec level, {int seeds = 16, double winRate = 0.7}) {
  final wins = [for (var s = 0; s < seeds; s++) botMovesToWin(level, s)]
      .whereType<int>()
      .toList()
    ..sort();
  final need = (winRate * seeds).ceil();
  if (wins.length < need) return null;
  return math.max(5, wins[need - 1]);
}
