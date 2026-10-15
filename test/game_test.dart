import 'dart:convert';
import 'dart:math' as math;

import 'package:block_puzzle/game/dealer.dart';
import 'package:block_puzzle/game/game_controller.dart';
import 'package:block_puzzle/game/grid.dart';
import 'package:block_puzzle/game/levels.dart';
import 'package:block_puzzle/game/piece.dart';
import 'package:flutter_test/flutter_test.dart';

Piece line(int n, {bool vertical = false}) => Piece([
      for (var i = 0; i < n; i++) vertical ? Cell(i, 0) : Cell(0, i),
    ], 1);

void main() {
  group('Grid', () {
    test('places a piece on an empty board', () {
      final g = Grid();
      expect(g.canPlace(line(3), 0, 0), isTrue);
      g.place(line(3), 0, 0);
      expect(g.cells[0][2], 1);
      expect(g.cells[0][3], 0);
    });

    test('rejects out-of-bounds and overlapping placements', () {
      final g = Grid();
      expect(g.canPlace(line(3), 0, 6), isFalse);
      expect(g.canPlace(line(3), 0, -1), isFalse);
      expect(g.canPlace(line(3), 7, 0), isTrue);
      expect(g.canPlace(line(3, vertical: true), 6, 0), isFalse);
      g.place(line(3), 0, 0);
      expect(g.canPlace(line(1), 0, 0), isFalse);
    });

    test('clears a full row', () {
      final g = Grid();
      g.place(line(5), 0, 0);
      g.place(line(3), 0, 5);
      final result = g.clearLines();
      expect(result.rows, [0]);
      expect(result.cols, isEmpty);
      expect(g.cells[0].every((v) => v == 0), isTrue);
    });

    test('clears a full column', () {
      final g = Grid();
      g.place(line(5, vertical: true), 0, 2);
      g.place(line(3, vertical: true), 5, 2);
      final result = g.clearLines();
      expect(result.cols, [2]);
      expect(result.rows, isEmpty);
    });

    test('a crossing row and column both count and clear together', () {
      final g = Grid();
      g.place(line(7), 0, 1);
      g.place(line(7, vertical: true), 1, 0);
      g.place(line(1), 0, 0);
      final result = g.clearLines();
      expect(result.rows, [0]);
      expect(result.cols, [0]);
      expect(result.lines, 2);
      expect(g.cells.every((row) => row.every((v) => v == 0)), isTrue);
    });

    test('canFitAnywhere is false when no gap is big enough', () {
      final g = Grid();
      for (var r = 0; r < Grid.size; r++) {
        for (var c = 0; c < Grid.size; c++) {
          g.cells[r][c] = 1;
        }
      }
      g.cells[3][3] = 0;
      expect(g.canFitAnywhere(line(1)), isTrue);
      expect(g.canFitAnywhere(line(2)), isFalse);
    });
  });

  group('Piece shapes', () {
    test('every shape is normalised and unique', () {
      final keys = <String>{};
      for (final shape in allShapes) {
        expect(shape.map((c) => c.row).reduce(math.min), 0);
        expect(shape.map((c) => c.col).reduce(math.min), 0);
        expect(shape.map((c) => c.row).reduce(math.max), lessThan(5));
        expect(shape.map((c) => c.col).reduce(math.max), lessThan(5));
        keys.add(shape.map((c) => '${c.row},${c.col}').join(';'));
      }
      expect(keys.length, allShapes.length);
    });
  });

  group('GameController', () {
    test('starts with three pieces and an empty score', () {
      final game = GameController(random: math.Random(1));
      expect(game.tray.length, 3);
      expect(game.tray.every((p) => p != null), isTrue);
      expect(game.score, 0);
      expect(game.gameOver, isFalse);
    });

    test('placing a piece adds its size to the score', () {
      final game = GameController(random: math.Random(1));
      final piece = game.tray[0]!;
      expect(game.place(0, 0, 0), isTrue);
      expect(game.score, piece.size);
      expect(game.tray[0], isNull);
    });

    test('refills the tray after all three pieces are used', () {
      final game = GameController(random: math.Random(2));
      for (var i = 0; i < 3; i++) {
        final piece = game.tray[i]!;
        var placed = false;
        for (var r = 0; r < Grid.size && !placed; r++) {
          for (var c = 0; c < Grid.size && !placed; c++) {
            if (game.grid.canPlace(piece, r, c)) {
              placed = game.place(i, r, c);
            }
          }
        }
        expect(placed, isTrue);
      }
      expect(game.tray.length, 3);
      expect(game.tray.every((p) => p != null), isTrue);
    });

    test('a line clear scores the bonus and starts a combo', () {
      final game = GameController(random: math.Random(1));
      for (var c = 0; c < 7; c++) {
        game.grid.cells[0][c] = 1;
      }
      game.grid.cells[7][7] = 1; // so it is not an all clear
      game.tray = [line(1), line(1), line(1)];
      expect(game.place(0, 0, 7), isTrue);
      expect(game.lastClear.rows, [0]);
      expect(game.combo, 1);
      expect(game.score, 1 + 10);
    });

    test('game over when no remaining piece fits', () {
      final game = GameController(random: math.Random(1));
      for (var r = 0; r < Grid.size; r++) {
        for (var c = 0; c < Grid.size; c++) {
          game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
        }
      }
      game.tray = [line(1), line(2), line(2)];
      expect(game.place(0, 0, 1), isTrue);
      expect(game.gameOver, isTrue);
    });
  });

  group('Scoring and combos', () {
    test('multi-line clears and combos score more', () {
      expect(GameController.lineScore(1, 1), 10);
      expect(GameController.lineScore(2, 1), 30);
      expect(GameController.lineScore(3, 1), 60);
      expect(GameController.lineScore(1, 3), 30);
      expect(GameController.lineScore(0, 5), 0);
    });

    test('a combo survives two quiet moves and ends on the third', () {
      final game = GameController(random: math.Random(1));
      for (var c = 0; c < 7; c++) {
        game.grid.cells[0][c] = 1;
        game.grid.cells[1][c] = 1;
      }
      game.grid.cells[7][7] = 1; // keeps the board from being all clear
      game.tray = [line(1), line(1), line(1)];
      expect(game.place(0, 0, 7), isTrue);
      expect(game.combo, 1);

      // Two placements without a clear keep the streak alive...
      game.tray = [line(1), line(1), line(1)];
      game.place(0, 5, 0);
      game.place(1, 5, 2);
      expect(game.combo, 1);

      // ...and the next clear is combo step 2.
      final before = game.score;
      expect(game.place(2, 1, 7), isTrue);
      expect(game.combo, 2);
      expect(game.score - before, 1 + GameController.lineScore(1, 2));

      // Three quiet placements end it.
      game.tray = [line(1), line(1), line(1)];
      game.place(0, 6, 0);
      game.place(1, 6, 2);
      expect(game.combo, 2);
      game.tray = [line(1), line(1), line(1)];
      game.place(0, 6, 4);
      expect(game.combo, 0);
    });

    test('emptying the board gives the all clear bonus', () {
      final game = GameController(random: math.Random(1));
      for (var c = 0; c < 7; c++) {
        game.grid.cells[0][c] = 1;
      }
      game.tray = [line(1), line(1), line(1)];
      expect(game.place(0, 0, 7), isTrue);
      expect(game.lastMove!.allClear, isTrue);
      expect(game.score, 1 + 10 + GameController.allClearBonus);
    });

    test('lastMove reports the removed squares', () {
      final game = GameController(random: math.Random(1));
      for (var c = 0; c < 7; c++) {
        game.grid.cells[2][c] = 3;
      }
      game.tray = [line(1), line(1), line(1)];
      game.place(0, 2, 7);
      final cleared = game.lastMove!.clear.cells;
      expect(cleared.length, 8);
      expect(cleared.where((c) => c.colorId == 3).length, 7);
    });
  });

  group('Dealer', () {
    test('bit-mask line clearing matches the grid', () {
      final g = Grid();
      g.place(line(8), 3, 0);
      for (var r = 0; r < Grid.size; r++) {
        if (r != 3) g.cells[r][5] = 2;
      }
      g.cells[6][1] = 4;
      final bits = Dealer.clearLines(g.toBits());
      g.clearLines();
      expect(bits, g.toBits());
    });

    test('deals pieces that can all be placed when possible', () {
      final rng = math.Random(3);
      for (var trial = 0; trial < 200; trial++) {
        final g = Grid();
        for (var r = 0; r < Grid.size; r++) {
          for (var c = 0; c < Grid.size; c++) {
            if (rng.nextDouble() < 0.45) g.cells[r][c] = 1;
          }
        }
        g.clearLines();
        final pieces = Dealer(rng).deal(g, 3);
        expect(pieces.length, 3);
        // Every dealt piece must at least fit by itself whenever any of the
        // smallest pieces could.
        if (g.canFitAnywhere(line(1)) && g.canFitAnywhere(line(2))) {
          expect(pieces.where(g.canFitAnywhere), isNotEmpty);
        }
      }
    });

    test('pieces in one deal have different colours', () {
      final pieces = Dealer(math.Random(5)).deal(Grid(), 3);
      expect(pieces.map((p) => p.colorId).toSet().length, 3);
    });
  });

  group('Saving', () {
    test('a game survives a save and restore', () {
      final game = GameController(random: math.Random(4));
      game.place(0, 0, 0);
      final json =
          jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>;

      final restored = GameController(random: math.Random(9));
      expect(restored.restore(json), isTrue);
      expect(restored.score, game.score);
      expect(restored.grid.toBits(), game.grid.toBits());
      expect(restored.tray[0], isNull);
      expect(restored.tray[1]!.cells, game.tray[1]!.cells);
      expect(restored.tray[1]!.colorId, game.tray[1]!.colorId);
    });

    test('a broken save is ignored', () {
      final game = GameController(random: math.Random(4));
      final score = game.score;
      expect(game.restore({'grid': 'nope'}), isFalse);
      expect(game.score, score);
      expect(game.tray.length, 3);
    });
  });

  group('Ice', () {
    test('a clear breaks the ice and keeps the block, the next removes it', () {
      final g = Grid();
      for (var c = 0; c < 8; c++) {
        g.cells[0][c] = 2;
      }
      g.ice.add(3);
      var result = g.clearLines();
      expect(result.iceBroken, [3]);
      expect(g.cells[0][3], 2);
      expect(g.ice, isEmpty);
      expect(result.cells.length, 7);

      for (var c = 0; c < 8; c++) {
        g.cells[0][c] = 2;
      }
      result = g.clearLines();
      expect(result.iceBroken, isEmpty);
      expect(g.cells[0].every((v) => v == 0), isTrue);
    });

    test('an iced square on a crossing row and column only loses its ice', () {
      final g = Grid();
      for (var i = 0; i < 8; i++) {
        g.cells[2][i] = 1;
        g.cells[i][5] = 1;
      }
      g.ice.add(2 * 8 + 5);
      final result = g.clearLines();
      expect(result.lines, 2);
      expect(g.cells[2][5], 1);
      expect(result.iceBroken, [2 * 8 + 5]);
    });
  });

  group('Boosters', () {
    test('undo takes back a placement and its clear', () {
      final game = GameController(random: math.Random(1));
      for (var c = 0; c < 7; c++) {
        game.grid.cells[0][c] = 1;
      }
      game.grid.cells[7][7] = 1;
      game.tray = [line(1), line(1), line(1)];
      final before = game.grid.toBits();
      game.place(0, 0, 7);
      expect(game.score, greaterThan(0));
      expect(game.canUndo, isTrue);
      expect(game.undo(), isTrue);
      expect(game.grid.toBits(), before);
      expect(game.score, 0);
      expect(game.tray[0], isNotNull);
      expect(game.canUndo, isFalse);
    });

    test('a bomb clears the 3x3 around a square and collects gems', () {
      final level = LevelSpec(
        number: 1,
        cells: [
          for (var r = 0; r < 8; r++)
            [for (var c = 0; c < 8; c++) r < 3 && c < 3 ? 2 : 0],
        ],
        gems: const {9},
        ice: const {0},
        goals: const [LevelGoal(GoalType.gems, 1)],
        moves: 10,
      );
      final game = GameController(random: math.Random(1), level: level);
      final removed = game.bomb(1, 1);
      expect(removed.length, 9);
      expect(game.grid.isEmpty, isTrue);
      expect(game.gemsCollected, 1);
      expect(game.won, isTrue);
      expect(game.movesLeft, 10);
    });

    test('rotate turns a tray piece', () {
      final game = GameController(random: math.Random(1));
      game.tray = [line(3), null, null];
      game.rotate(0);
      expect(game.tray[0]!.rows, 3);
      expect(game.tray[0]!.cols, 1);
    });

    test('revive clears space once, after running out of space', () {
      var ended = 0;
      final game = GameController(random: math.Random(1))
        ..onGameEnd = () => ended++;
      for (var r = 0; r < Grid.size; r++) {
        for (var c = 0; c < Grid.size; c++) {
          game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
        }
      }
      game.tray = [line(1), line(2), line(2)];
      game.place(0, 0, 1);
      expect(game.canRevive, isTrue);
      expect(ended, 1);
      expect(game.revive(), isTrue);
      expect(game.gameOver, isFalse);
      expect(game.canRevive, isFalse);
      expect(ended, 1);
    });

    test('extra moves after running out of moves, once', () {
      final level = LevelSpec(
        number: 1,
        cells: List.generate(8, (_) => List.filled(8, 0)),
        gems: const {},
        goals: const [LevelGoal(GoalType.lines, 5)],
        moves: 1,
      );
      final game = GameController(random: math.Random(1), level: level);
      game.tray = [line(1), line(1), line(1)];
      game.place(0, 0, 0);
      expect(game.endReason, EndReason.outOfMoves);
      expect(game.addMoves(), isTrue);
      expect(game.movesLeft, GameController.extraMoves);
      expect(game.gameOver, isFalse);
      game.movesLeft = 1;
      game.place(1, 3, 3);
      expect(game.canAddMoves, isFalse);
    });
  });
}
