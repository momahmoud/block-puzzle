import 'dart:math' as math;

import 'package:block_puzzle/game/dealer.dart';
import 'package:block_puzzle/game/game_controller.dart';
import 'package:block_puzzle/game/grid.dart';
import 'package:block_puzzle/game/level_tuning.dart';
import 'package:block_puzzle/game/levels.dart';
import 'package:block_puzzle/game/piece.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/level_bot.dart';

void main() {
  test('every level starts without a full line and with gems on blocks', () {
    for (var n = 1; n <= LevelSpec.count; n++) {
      final level = LevelSpec.forNumber(n);
      final g = Grid();
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          g.cells[r][c] = level.cells[r][c];
        }
      }
      expect(Dealer.clearLines(g.toBits()), g.toBits(), reason: 'level $n');
      for (final gem in level.gems) {
        expect(level.cells[gem ~/ 8][gem % 8], isNot(0), reason: 'level $n');
      }
      for (final ice in level.ice) {
        expect(level.cells[ice ~/ 8][ice % 8], isNot(0), reason: 'level $n');
        expect(level.gems.contains(ice), isFalse, reason: 'level $n');
      }
      expect(level.moves, greaterThan(5), reason: 'level $n');
      expect(level.goals, isNotEmpty);
    }
  });

  test('levels are the same every time', () {
    final a = LevelSpec.forNumber(117);
    final b = LevelSpec.forNumber(117);
    expect(a.cells, b.cells);
    expect(a.gems, b.gems);
    expect(a.moves, b.moves);
  });

  test('a level is won when its goals are met and lost when moves run out', () {
    final level = LevelSpec(
      number: 1,
      cells: [
        [1, 1, 1, 1, 1, 1, 1, 0],
        for (var i = 0; i < 7; i++) List.filled(8, 0),
      ],
      gems: const {0},
      goals: const [LevelGoal(GoalType.gems, 1)],
      moves: 2,
    );
    final game = GameController(random: math.Random(1), level: level);
    expect(game.movesLeft, 2);
    game.tray = [
      Piece(const [Cell(0, 0)], 1),
      Piece(const [Cell(0, 0)], 1),
      null
    ];
    game.place(0, 5, 5);
    expect(game.movesLeft, 1);
    expect(game.gameOver, isFalse);
    game.place(1, 0, 7);
    expect(game.gemsCollected, 1);
    expect(game.won, isTrue);
    expect(game.stars, 1);

    final lose = GameController(random: math.Random(1), level: level);
    lose.tray = [
      Piece(const [Cell(0, 0)], 1),
      Piece(const [Cell(0, 0)], 1),
      null
    ];
    lose.place(0, 5, 5);
    lose.place(1, 6, 6);
    expect(lose.gameOver, isTrue);
    expect(lose.endReason, EndReason.outOfMoves);
    expect(lose.stars, 0);
  });

  test('the tuning table covers every level', () {
    expect(kLevelTuning.length, LevelSpec.count);
    expect(LevelSpec.count, 200);
  });

  test('chapters, hard levels and the difficulty curve', () {
    expect(LevelSpec.forNumber(1).chapterName, 'Warm Up');
    expect(LevelSpec.forNumber(200).chapterName, 'Grand Master');
    expect(LevelSpec.forNumber(30).isHard, isTrue);
    expect(LevelSpec.forNumber(31).isHard, isFalse);
    // Harder within a chapter, a spike on the tenth level, a dip after it.
    expect(LevelSpec.difficultyOf(19), greaterThan(LevelSpec.difficultyOf(2)));
    expect(LevelSpec.difficultyOf(30), greaterThan(LevelSpec.difficultyOf(29)));
    expect(LevelSpec.difficultyOf(31), lessThan(LevelSpec.difficultyOf(29)));
    expect(
        LevelSpec.difficultyOf(185), greaterThan(LevelSpec.difficultyOf(25)));
  });

  test(
      'gems appear from level ${LevelSpec.gemsFrom} and ice from level ${LevelSpec.iceFrom}',
      () {
    for (var n = 1; n < LevelSpec.gemsFrom; n++) {
      expect(LevelSpec.forNumber(n).gems, isEmpty, reason: 'level $n');
    }
    for (var n = 1; n < LevelSpec.iceFrom; n++) {
      expect(LevelSpec.forNumber(n).ice, isEmpty, reason: 'level $n');
    }
    expect(LevelSpec.forNumber(LevelSpec.gemsFrom).goals.first.type,
        GoalType.gems);
    expect(
        LevelSpec.forNumber(LevelSpec.iceFrom).goals.first.type, GoalType.ice);
  });

  test('the bot beats every level within its move limit', () {
    final hopeless = <int>[];
    for (var n = 1; n <= LevelSpec.count; n++) {
      final level = LevelSpec.forNumber(n);
      var wins = 0;
      for (var s = 0; s < 24 && wins == 0; s++) {
        final moves = botMovesToWin(level, s);
        if (moves != null && moves <= level.moves) wins++;
      }
      if (wins == 0) hopeless.add(n);
    }
    expect(hopeless, isEmpty, reason: 'levels the bot never beat: $hopeless');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
