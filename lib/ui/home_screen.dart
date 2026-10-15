import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_controller.dart';
import '../services/settings.dart';
import '../services/sfx.dart';
import '../services/level_progress.dart';
import '../services/stats.dart';
import 'floating_blocks.dart';
import 'game_screen.dart';
import 'level_map_screen.dart';
import 'palette.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'theme_picker.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  GameController get _game => widget.controller;

  @override
  void dispose() {
    _intro.dispose();
    _bob.dispose();
    super.dispose();
  }

  Future<void> _play({bool fresh = false}) async {
    widget.sfx.tap();
    if (fresh) {
      if (_game.hasProgress && !await confirmNewGame(context)) return;
      _game.newGame();
    } else if (_game.gameOver) {
      _game.newGame();
    }
    if (!mounted) return;
    await Navigator.of(context).push(_gameRoute());
  }

  void _openLevels() {
    widget.sfx.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LevelMapScreen(
          levels: widget.levels,
          settings: widget.settings,
          sfx: widget.sfx,
        ),
      ),
    );
  }

  Route<void> _gameRoute() => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, _, __) => GameScreen(
          controller: widget.controller,
          settings: widget.settings,
          sfx: widget.sfx,
        ),
        transitionsBuilder: (context, anim, _, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.08, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );

  /// Fades and slides a part of the screen in, one after another.
  Widget _enter(int order, Widget child) {
    return AnimatedBuilder(
      animation: _intro,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic
            .transform(((_intro.value - order * 0.1) / 0.6).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, 30 * (1 - t)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: theme.backgroundBottom,
      ),
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(gradient: theme.background),
          child: Stack(
            children: [
              const Positioned.fill(child: FloatingBlocks()),
              SafeArea(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_game, widget.stats]),
                  builder: (context, _) => _content(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(GameTheme theme) {
    final stats = widget.stats;
    final progress = _game.hasProgress;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 640;
        return Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Settings',
                iconSize: 30,
                color: Colors.white,
                icon: const Icon(Icons.settings_rounded),
                onPressed: () {
                  widget.sfx.tap();
                  showSettingsSheet(context,
                      settings: widget.settings, sfx: widget.sfx);
                },
              ),
            ),
            const Spacer(),
            _enter(0, _logo(theme, compact ? 96 : 130)),
            SizedBox(height: compact ? 12 : 20),
            _enter(1, const OutlinedText('BLOCK', size: 56)),
            _enter(
              1,
              OutlinedText('PUZZLE',
                  size: 44, colors: [Colors.white, theme.accent]),
            ),
            const Spacer(),
            _enter(
              2,
              _ModeButton(
                icon: Icons.all_inclusive_rounded,
                title: 'Classic',
                subtitle: progress
                    ? 'Continue · Score ${_game.score}'
                    : 'Best ${_game.best}',
                color: theme.button,
                onPressed: _play,
              ),
            ),
            if (progress)
              _enter(
                2,
                TextButton(
                  onPressed: () => _play(fresh: true),
                  child: const Text(
                    'New classic game',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70),
                  ),
                ),
              )
            else
              const SizedBox(height: 14),
            _enter(
              3,
              ListenableBuilder(
                listenable: widget.levels,
                builder: (context, _) {
                  final levels = widget.levels;
                  return _ModeButton(
                    icon: Icons.flag_rounded,
                    title: 'Levels',
                    subtitle: levels.allDone
                        ? 'All done · ★ ${levels.totalStars}'
                        : 'Level ${levels.unlocked} · ★ ${levels.totalStars}',
                    color: theme.block(6),
                    onPressed: _openLevels,
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 16 : 28),
            _enter(
              4,
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    StatTile(value: '${stats.gamesPlayed}', label: 'GAMES'),
                    StatTile(value: '${stats.linesCleared}', label: 'LINES'),
                    StatTile(value: '${stats.bestCombo}', label: 'BEST COMBO'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _enter(
              5,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RoundIconButton(
                    icon: Icons.palette_rounded,
                    label: 'Themes',
                    onPressed: () {
                      widget.sfx.tap();
                      showThemePicker(context,
                          settings: widget.settings, sfx: widget.sfx);
                    },
                  ),
                  RoundIconButton(
                    icon: Icons.help_outline_rounded,
                    label: 'How to play',
                    onPressed: () {
                      widget.sfx.tap();
                      showHowToPlay(context);
                    },
                  ),
                  ListenableBuilder(
                    listenable: widget.settings,
                    builder: (context, _) => RoundIconButton(
                      icon: widget.settings.sound
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: widget.settings.sound ? 'Sound on' : 'Sound off',
                      onPressed: () {
                        widget.settings.sound = !widget.settings.sound;
                        widget.sfx.tap();
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 12 : 24),
          ],
        );
      },
    );
  }

  Widget _logo(GameTheme theme, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(theme, _bob)),
    );
  }
}

/// The app icon's 3x3 cluster, each block bobbing gently.
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.theme, this.anim) : super(repaint: anim);

  final GameTheme theme;
  final Animation<double> anim;

  static const _layout = [
    [1, 1, 3],
    [1, 5, 5],
    [4, 4, 5],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 3;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        final phase = (r * 3 + c) / 9;
        final dy = math.sin((anim.value + phase) * math.pi * 2) * cell * 0.06;
        paintBlock(
          canvas,
          Rect.fromLTWH(c * cell, r * cell + dy, cell, cell),
          theme.block(_layout[r][c]),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.theme != theme;
}

/// A wide button for picking a game mode.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: SizedBox(
        width: 290,
        child: Material(
          color: Color.lerp(color, Colors.black, 0.32),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onPressed,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(color, Colors.white, 0.15)!, color],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
