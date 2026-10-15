import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_controller.dart';
import 'services/level_progress.dart';
import 'services/settings.dart';
import 'services/sfx.dart';
import 'services/stats.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

const _bestKey = 'best';
const _gameKey = 'game';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final settings = Settings(prefs);
  final stats = Stats(prefs);
  final levels = LevelProgress(prefs);
  final sfx = Sfx(settings);
  sfx.init(); // loads in the background; sounds start working once ready

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
      stats.recordMove(lines: move.lines, combo: move.combo);
    }
    ..onGameEnd = stats.recordGameEnd;

  runApp(BlockPuzzleApp(
    controller: controller,
    settings: settings,
    stats: stats,
    levels: levels,
    sfx: sfx,
  ));
}

class BlockPuzzleApp extends StatelessWidget {
  const BlockPuzzleApp({
    super.key,
    required this.controller,
    required this.settings,
    required this.stats,
    required this.levels,
    required this.sfx,
  });

  final GameController controller;
  final Settings settings;
  final Stats stats;
  final LevelProgress levels;
  final Sfx sfx;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Puzzle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7B4DFF),
      ),
      builder: (context, child) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ThemeScope(
          theme: GameTheme.byId(settings.themeId),
          child: child!,
        ),
      ),
      home: HomeScreen(
        controller: controller,
        settings: settings,
        stats: stats,
        levels: levels,
        sfx: sfx,
      ),
    );
  }
}
