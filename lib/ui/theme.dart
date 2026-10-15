import 'package:flutter/material.dart';

/// A colour scheme for the whole game. Every theme has exactly
/// kPaletteSize (see game/piece.dart) block colours.
class GameTheme {
  const GameTheme({
    required this.id,
    required this.name,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.board,
    required this.emptyCell,
    required this.blocks,
    required this.outline,
    required this.sheet,
    required this.button,
    required this.accent,
  });

  final String id;
  final String name;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color board;
  final Color emptyCell;
  final List<Color> blocks;

  /// Outline around big game text.
  final Color outline;

  /// Background of sheets and cards.
  final Color sheet;

  /// Main button colour.
  final Color button;

  /// Highlight colour for titles and selected things.
  final Color accent;

  Color block(int id) => blocks[(id - 1) % blocks.length];

  LinearGradient get background => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [backgroundTop, backgroundBottom],
      );

  static const GameTheme neon = GameTheme(
    id: 'neon',
    name: 'Neon Night',
    backgroundTop: Color(0xFF3A1C7A),
    backgroundBottom: Color(0xFF0E0729),
    board: Color(0xFF140B33),
    emptyCell: Color(0xFF25184F),
    blocks: [
      Color(0xFFFF4F81),
      Color(0xFFFF9B3D),
      Color(0xFFFFE04A),
      Color(0xFF6EF06B),
      Color(0xFF2EE6E6),
      Color(0xFF4F8BFF),
      Color(0xFFB565FF),
    ],
    outline: Color(0xFF12062E),
    sheet: Color(0xFF26145A),
    button: Color(0xFFFF4F81),
    accent: Color(0xFF2EE6E6),
  );

  static const GameTheme sunset = GameTheme(
    id: 'sunset',
    name: 'Sunset',
    backgroundTop: Color(0xFFFF8A5B),
    backgroundBottom: Color(0xFF6A2483),
    board: Color(0xFF3A1446),
    emptyCell: Color(0xFF55245F),
    blocks: [
      Color(0xFFFF5964),
      Color(0xFFFFB140),
      Color(0xFFFFE66D),
      Color(0xFF7BD389),
      Color(0xFF3FC1C9),
      Color(0xFF6C8CF0),
      Color(0xFFC77DFF),
    ],
    outline: Color(0xFF3B0F3F),
    sheet: Color(0xFF5A1F6E),
    button: Color(0xFFFF7A45),
    accent: Color(0xFFFFE66D),
  );

  static const GameTheme ocean = GameTheme(
    id: 'ocean',
    name: 'Ocean',
    backgroundTop: Color(0xFF3A60D0),
    backgroundBottom: Color(0xFF182868),
    board: Color(0xFF16204F),
    emptyCell: Color(0xFF1F2B63),
    blocks: [
      Color(0xFFEF5350),
      Color(0xFFFFA726),
      Color(0xFFFFD640),
      Color(0xFF66BB6A),
      Color(0xFF26C6DA),
      Color(0xFF5C7CFA),
      Color(0xFFAB47BC),
    ],
    outline: Color(0xFF14204F),
    sheet: Color(0xFF1C2D72),
    button: Color(0xFF4CC46A),
    accent: Color(0xFF7FD8FF),
  );

  static const GameTheme mint = GameTheme(
    id: 'mint',
    name: 'Mint',
    backgroundTop: Color(0xFF2FAE86),
    backgroundBottom: Color(0xFF0E3B3A),
    board: Color(0xFF0B2B29),
    emptyCell: Color(0xFF154440),
    blocks: [
      Color(0xFFFF6B6B),
      Color(0xFFFFA94D),
      Color(0xFFFFD43B),
      Color(0xFFA9E34B),
      Color(0xFF38D9A9),
      Color(0xFF4DABF7),
      Color(0xFFDA77F2),
    ],
    outline: Color(0xFF082522),
    sheet: Color(0xFF124A45),
    button: Color(0xFFFF8E3C),
    accent: Color(0xFFA9E34B),
  );

  static const GameTheme wood = GameTheme(
    id: 'wood',
    name: 'Wood',
    backgroundTop: Color(0xFFB07A45),
    backgroundBottom: Color(0xFF4A2E17),
    board: Color(0xFF3A2312),
    emptyCell: Color(0xFF5A3A1F),
    blocks: [
      Color(0xFFE5484D),
      Color(0xFFF08C2E),
      Color(0xFFF5C542),
      Color(0xFF4CB963),
      Color(0xFF2BB3C0),
      Color(0xFF4C6EF5),
      Color(0xFF9D4EDD),
    ],
    outline: Color(0xFF2A170A),
    sheet: Color(0xFF5C3A1E),
    button: Color(0xFF4CB963),
    accent: Color(0xFFF5C542),
  );

  static const List<GameTheme> all = [neon, sunset, ocean, mint, wood];

  static GameTheme byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  static GameTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.theme ??
      all.first;
}

/// Makes the current [GameTheme] available below it.
class ThemeScope extends InheritedWidget {
  const ThemeScope({super.key, required this.theme, required super.child});

  final GameTheme theme;

  @override
  bool updateShouldNotify(ThemeScope oldWidget) => oldWidget.theme != theme;
}
