import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_controller.dart';
import 'services/app_services.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

const _bestKey = 'best';
const _gameKey = 'game';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final app = AppServices(prefs);

  final controller = GameController(best: prefs.getInt(_bestKey) ?? 0);
  final saved = prefs.getString(_gameKey);
  if (saved != null) {
    try {
      controller.restore(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      // A broken save just means a fresh game.
    }
  }
  controller
    ..onNewBest = (best) {
      prefs.setInt(_bestKey, best);
    }
    ..onSave = () {
      prefs.setString(_gameKey, jsonEncode(controller.toJson()));
    }
    ..onMove = (move) {
      app.stats.recordMove(lines: move.lines, combo: move.combo);
      app.afterMove(controller, move);
    }
    ..onGameEnd = () {
      app.stats.recordGameEnd();
      app.games.submitClassicScore(controller.best);
    };

  runApp(BlockPuzzleApp(controller: controller, app: app));
  // Sound, ads, purchases and sign-in start after the first frame.
  app.start();
}

class BlockPuzzleApp extends StatelessWidget {
  const BlockPuzzleApp(
      {super.key, required this.controller, required this.app});

  final GameController controller;
  final AppServices app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Puzzle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Fredoka',
        colorSchemeSeed: const Color(0xFF7B4DFF),
      ),
      builder: (context, child) => ListenableBuilder(
        listenable: app.settings,
        builder: (context, _) => ThemeScope(
          theme: GameTheme.byId(app.settings.themeId),
          child: child!,
        ),
      ),
      home: HomeScreen(controller: controller, app: app),
    );
  }
}
