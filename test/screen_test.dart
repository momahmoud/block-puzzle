import 'dart:math' as math;

import 'package:block_puzzle/game/game_controller.dart';
import 'package:block_puzzle/game/grid.dart';
import 'package:block_puzzle/game/piece.dart';
import 'package:block_puzzle/main.dart';
import 'package:block_puzzle/services/app_services.dart';
import 'package:block_puzzle/services/boosters.dart';
import 'package:block_puzzle/services/level_progress.dart';
import 'package:block_puzzle/services/settings.dart';
import 'package:block_puzzle/services/stats.dart';
import 'package:block_puzzle/ui/board_painter.dart';
import 'package:block_puzzle/ui/game_screen.dart';
import 'package:block_puzzle/ui/piece_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Piece line(int n) => Piece([for (var i = 0; i < n; i++) Cell(0, i)], 2);

typedef TestApp = ({
  GameController game,
  Settings settings,
  Stats stats,
  LevelProgress levels,
  AppServices services,
});

Future<TestApp> pumpApp(
  WidgetTester tester, {
  bool tutorialDone = true,
  Size size = const Size(1170, 2532),
  double pixelRatio = 3,
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'flutter.tutorialDone': tutorialDone,
    // Tips would pop up over the first gem and ice levels.
    'flutter.tip.ice': true,
    'flutter.tip.gems': true,
    ...prefs,
  });
  final services = AppServices(await SharedPreferences.getInstance());
  // Rewarded ads always pay out in tests.
  services.ads.debugRewardOverride = () async => true;
  final game = GameController(random: math.Random(1))
    ..onMove =
        ((m) => services.stats.recordMove(lines: m.lines, combo: m.combo))
    ..onGameEnd = services.stats.recordGameEnd;
  await tester.pumpWidget(BlockPuzzleApp(controller: game, app: services));
  // The home screen animates forever, so pump a fixed time instead of settling.
  await tester.pump(const Duration(seconds: 1));
  return (
    game: game,
    settings: services.settings,
    stats: services.stats,
    levels: services.levels,
    services: services,
  );
}

/// Opens the app and starts Classic.
Future<GameController> pumpGame(WidgetTester tester) async {
  final app = await pumpApp(tester);
  await tester.tap(find.text('Classic'));
  await tester.pumpAndSettle();
  return app.game;
}

/// Drags tray piece [index] so it lands with its top-left on board square
/// ([row], [col]), allowing for the piece floating above the finger.
Future<void> dragTo(WidgetTester tester, GameController game, int index,
    int row, int col) async {
  final board = tester.getRect(
    find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BoardPainter),
  );
  final cell = board.width / Grid.size;
  final piece = game.tray[index]!;
  final slots = [
    for (var i = 0; i < game.tray.length; i++)
      if (game.tray[i] != null) i,
  ];
  final start =
      tester.getCenter(find.byType(PieceView).at(slots.indexOf(index)));

  final gesture = await tester.startGesture(start);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200)); // finish the lift
  final target = board.topLeft +
      Offset((col + piece.cols / 2) * cell, (row + piece.rows) * cell + 72);
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('dragging a piece onto the board places it and scores',
      (tester) async {
    final game = await pumpGame(tester);
    game.tray = [line(3), line(2), line(1)];
    game.notifyListeners();
    await tester.pumpAndSettle();

    await dragTo(tester, game, 0, 4, 2);
    expect(game.grid.cells[4][2], 2);
    expect(game.grid.cells[4][4], 2);
    expect(game.score, 3);
    expect(game.tray[0], isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a drop off the board sends the piece back', (tester) async {
    final game = await pumpGame(tester);
    final gesture = await tester.startGesture(const Offset(65, 760));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(const Offset(65, 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(game.score, 0);
    expect(game.tray.every((p) => p != null), isTrue);
  });

  testWidgets('clearing a line shows praise and points', (tester) async {
    final game = await pumpGame(tester);
    for (var c = 0; c < 6; c++) {
      game.grid.cells[3][c] = 1;
      game.grid.cells[4][c] = 1;
    }
    game.grid.cells[0][0] = 5;
    game.tray = [
      line(2),
      Piece(const [Cell(0, 0), Cell(0, 1), Cell(1, 0), Cell(1, 1)], 3),
      line(1)
    ];
    game.notifyListeners();
    await tester.pumpAndSettle();

    await dragTo(tester, game, 1, 3, 6);
    expect(game.lastMove!.lines, 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Good!'), findsWidgets);
    expect(find.text('+${game.lastMove!.points}'), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('game over shows the results card and play again restarts',
      (tester) async {
    final game = await pumpGame(tester);
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
      }
    }
    game.tray = [line(1), line(2), line(2)];
    game.place(0, 0, 1);
    expect(game.gameOver, isTrue);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // The second-chance countdown ran out while settling.
    expect(find.text('Play Again'), findsOneWidget);
    await tester.tap(find.text('Play Again'));
    await tester.pumpAndSettle();
    expect(game.gameOver, isFalse);
    expect(game.score, 0);
    expect(find.text('Play Again'), findsNothing);
  });

  testWidgets('home shows Continue for a game in progress and opens it',
      (tester) async {
    final app = await pumpApp(tester);
    expect(find.text('Best 0'), findsOneWidget);
    app.game.place(0, 0, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Continue · Score ${app.game.score}'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);

    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(app.game.score, greaterThan(0));
  });

  testWidgets('pause menu goes home and keeps the game', (tester) async {
    final game = await pumpGame(tester);
    game.place(0, 0, 0);
    final score = game.score;
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsWidgets);
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Continue · Score $score'), findsOneWidget);
    expect(game.score, score);
  });

  testWidgets('picking a theme changes it and saves it', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.byTooltip('Themes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Wood'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(app.settings.themeId, 'wood');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme'), 'wood');
  });

  testWidgets('the first game shows the drag hint until a piece is placed',
      (tester) async {
    final app = await pumpApp(tester, tutorialDone: false);
    await tester.tap(find.text('Classic'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Drag a piece onto the board'), findsWidgets);

    app.game.tray = [line(1), line(1), line(1)];
    app.game.notifyListeners();
    await tester.pump();
    await dragTo(tester, app.game, 0, 0, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(app.settings.tutorialDone, isTrue);
    expect(find.text('Drag a piece onto the board'), findsNothing);
  });

  testWidgets('a combo shows the combo badge', (tester) async {
    final game = await pumpGame(tester);
    for (var c = 0; c < 7; c++) {
      game.grid.cells[0][c] = 1;
    }
    game.grid.cells[7][7] = 1;
    game.tray = [line(1), line(1), line(1)];
    game.place(0, 0, 7);
    await tester.pumpAndSettle();
    expect(find.text('Combo 1'), findsOneWidget);
  });

  testWidgets('game over counts a game in the stats', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        app.game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
      }
    }
    app.game.tray = [line(1), line(2), line(2)];
    app.game.place(0, 0, 1);
    expect(app.stats.gamesPlayed, 1);
  });

  testWidgets('levels: map, intro, win, stars and next level', (tester) async {
    final app = await pumpApp(tester);
    expect(find.bySemanticsLabel('Levels, Level 1'), findsOneWidget);
    await tester.tap(find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('Level 2, locked'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Level 1, 0 stars'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('WARM UP · CHAPTER 1'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final game = tester.widget<GameScreen>(find.byType(GameScreen)).controller;
    expect(game.isLevel, isTrue);
    expect(find.text('Level 1'), findsOneWidget);
    expect(
        find.bySemanticsLabel('${game.movesLeft} moves left'), findsOneWidget);

    // Meet every goal on the next move.
    game.score = 100000;
    game.linesThisGame = 1000;
    game.gemsCollected = 1000;
    game.iceBroken = 1000;
    game.tray = [line(1), line(1), line(1)];
    final spot = [
      for (var r = 0; r < Grid.size; r++)
        for (var c = 0; c < Grid.size; c++)
          if (game.grid.cells[r][c] == 0) (r, c),
    ].first;
    game.place(0, spot.$1, spot.$2);
    expect(game.won, isTrue);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Complete!'), findsWidgets);
    expect(app.levels.starsFor(1), 3);
    expect(app.levels.unlocked, 2);

    await tester.tap(find.text('Next Level'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Level 2'), findsOneWidget);
  });

  testWidgets('levels: running out of moves offers a retry', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.bySemanticsLabel('Level 1, 0 stars'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final game = tester.widget<GameScreen>(find.byType(GameScreen)).controller;
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        game.grid.cells[r][c] = 0;
      }
    }
    game.movesLeft = 1;
    game.tray = [line(1), line(1), line(1)];
    game.place(0, 4, 4);
    expect(game.endReason, EndReason.outOfMoves);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A second chance is offered first.
    expect(find.text('No thanks'), findsOneWidget);
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    expect(game.gameOver, isFalse);
    expect(game.movesLeft, game.level!.moves);
  });

  testWidgets('the home screen fits a small phone', (tester) async {
    // iPhone SE: 375 x 667 points.
    await pumpApp(tester, size: const Size(750, 1334), pixelRatio: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Daily'), findsOneWidget);
  });

  testWidgets('bomb booster clears a 3x3 area', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    final game = app.game;
    for (var r = 2; r <= 4; r++) {
      for (var c = 2; c <= 4; c++) {
        game.grid.cells[r][c] = 3;
      }
    }
    game.notifyListeners();
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Bomb, 2 left'));
    await tester.pump();
    expect(find.text('Tap the board to drop the bomb'), findsOneWidget);
    final board = tester.getRect(
      find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardPainter),
    );
    final cell = board.width / Grid.size;
    await tester.tapAt(board.topLeft + Offset(3.5 * cell, 3.5 * cell));
    await tester.pump();
    expect(game.grid.isEmpty, isTrue);
    expect(app.services.boosters.count(Booster.bomb), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('an empty booster can be refilled by watching an ad',
      (tester) async {
    final app = await pumpApp(tester, prefs: {'flutter.boosters.rotate': 0});
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Rotate, watch an ad to get one'));
    await tester.pumpAndSettle();
    expect(app.services.boosters.count(Booster.rotate), 1);
  });

  testWidgets('classic game over offers a revive', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    final game = app.game;
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
      }
    }
    game.tray = [line(1), line(2), line(2)];
    game.place(0, 0, 1);
    expect(game.gameOver, isTrue);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Revive'), findsOneWidget);
    await tester.tap(find.text('Revive'));
    await tester.pumpAndSettle();
    expect(game.gameOver, isFalse);
    expect(game.revived, isTrue);
    expect(find.text('Play Again'), findsNothing);
  });

  testWidgets('the daily challenge opens from home', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Daily'));
    // The move limit is worked out in an isolate.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('SAME LEVEL FOR EVERYONE TODAY'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final game = tester.widget<GameScreen>(find.byType(GameScreen)).controller;
    expect(game.level!.isDaily, isTrue);
    expect(find.text('Daily Challenge'), findsOneWidget);
  });

  testWidgets('the second-chance offer times out into the results',
      (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    final game = app.game;
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
      }
    }
    game.tray = [line(1), line(2), line(2)];
    game.place(0, 0, 1);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Out of space!'), findsWidgets);
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Play Again'), findsOneWidget);
    expect(find.text('New Best!'), findsWidgets);
  });

  testWidgets('new game asks first, with the game-styled dialog',
      (tester) async {
    final app = await pumpApp(tester);
    app.game.place(0, 0, 0);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your unfinished game will be lost.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.game.score, greaterThan(0));
  });

  testWidgets('remove ads opens the offer from the game screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove ads'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No more ads between games'), findsOneWidget);
    // The store is not set up in tests.
    expect(find.text('Not available right now. Please try again later.'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No more ads between games'), findsNothing);
  });

  testWidgets('the remove ads button is hidden once ads are removed', (tester) async {
    await pumpApp(tester, prefs: {'flutter.iap.removeAds': true});
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove ads'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('the second-chance card shows how many undos are left', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    final game = app.game;
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        game.grid.cells[r][c] = (r + c).isEven ? 1 : 0;
      }
    }
    game.tray = [line(1), line(2), line(2)];
    game.place(0, 0, 1);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Undo  (2 left)'), findsOneWidget);
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
  });
}
