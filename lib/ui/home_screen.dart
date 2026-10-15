import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_controller.dart';
import '../services/app_services.dart';
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
    required this.app,
  });

  final GameController controller;
  final AppServices app;

  Settings get settings => app.settings;
  Sfx get sfx => app.sfx;
  LevelProgress get levels => app.levels;
  Stats get stats => app.stats;

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
        builder: (context) => LevelMapScreen(app: widget.app),
      ),
    );
  }

  Route<void> _gameRoute() => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, _, __) =>
            GameScreen(controller: widget.controller, app: widget.app),
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
    final progress = _game.hasProgress;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 720;
        // Fills the screen when there is room and scrolls when there is
        // not, e.g. with large text.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Themes',
                        iconSize: 28,
                        color: Colors.white,
                        icon: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFD25A),
                              Color(0xFFFF7A45),
                              Color(0xFFE5487A)
                            ],
                          ).createShader(bounds),
                          child: const Icon(Icons.palette_rounded, size: 32),
                        ),
                        onPressed: () {
                          widget.sfx.tap();
                          showThemePicker(context,
                              settings: widget.settings, sfx: widget.sfx);
                        },
                      ),
                      if (widget.app.games.enabled) ...[
                        IconButton(
                          tooltip: 'Leaderboard',
                          iconSize: 28,
                          color: Colors.white,
                          icon: const GameIcon('leaderboard', size: 32),
                          onPressed: widget.app.games.showLeaderboards,
                        ),
                        IconButton(
                          tooltip: 'Awards',
                          iconSize: 28,
                          color: Colors.white,
                          icon: const GameIcon('trophy', size: 32),
                          onPressed: widget.app.games.showAchievements,
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: 'Settings',
                        iconSize: 28,
                        color: Colors.white,
                        icon: const GameIcon('settings', size: 32),
                        onPressed: () {
                          widget.sfx.tap();
                          showSettingsSheet(context, app: widget.app);
                        },
                      ),
                    ],
                  ),
                  const Spacer(flex: 2),
                  _enter(0, _logo(theme, compact ? 72 : 100)),
                  SizedBox(height: compact ? 10 : 18),
                  _enter(1, OutlinedText('BLOCK', size: compact ? 42 : 52)),
                  _enter(
                      1,
                      OutlinedText('PUZZLE',
                          size: compact ? 32 : 40,
                          colors: [Colors.white, theme.accent])),
                  const SizedBox(height: 14),
                  _enter(
                    1,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CrownIcon(size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'Best ${_game.best}',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kGold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  _enter(
                    2,
                    _ModeButton(
                      icon: const Icon(Icons.all_inclusive_rounded,
                          color: Colors.white, size: 28),
                      title: 'Classic',
                      subtitle: progress
                          ? 'Continue · Score ${_game.score}'
                          : 'Endless mode',
                      color: theme.button,
                      onPressed: _play,
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: progress
                        ? TextButton(
                            onPressed: () => _play(fresh: true),
                            child: const Text(
                              'New game',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70),
                            ),
                          )
                        : null,
                  ),
                  _enter(
                    3,
                    SizedBox(
                      width: 290,
                      child: Row(
                        children: [
                          Expanded(
                            child: ListenableBuilder(
                              listenable: widget.levels,
                              builder: (context, _) => _ModeTile(
                                icon: const GameIcon('map', size: 36),
                                title: 'Levels',
                                subtitle: widget.levels.allDone
                                    ? '★ ${widget.levels.totalStars}'
                                    : 'Level ${widget.levels.unlocked}',
                                color: theme.block(6),
                                onPressed: _openLevels,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: widget.app.daily,
                              builder: (context, _) {
                                final daily = widget.app.daily;
                                return _ModeTile(
                                  icon: const GameIcon('calendar', size: 36),
                                  title: 'Daily',
                                  subtitle: daily.doneToday
                                      ? 'Done ✓'
                                      : (daily.streak > 0
                                          ? '🔥 ${daily.streak}'
                                          : 'New today'),
                                  color: const Color(0xFFFF8A00),
                                  dot: !daily.doneToday,
                                  onPressed: _openDaily,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDaily() async {
    widget.sfx.tap();
    final daily = widget.app.daily;
    // Working out today's move limit takes a moment the first time.
    final spec = await daily.level();
    if (!mounted) return;
    await showLevelIntro(
      context,
      level: spec,
      stars: 0,
      onPlay: () => Navigator.of(context).push(
        levelRoute(number: spec.number, app: widget.app, spec: spec),
      ),
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

  final Widget icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
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
                  child: Center(child: icon),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22,
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
                const GameIcon('play', size: 36),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
        ],
      ),
    );
  }
}

/// A compact square-ish button for a secondary mode.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
    this.dot = false,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onPressed;

  /// A small red dot in the corner: something new to play.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Color.lerp(color, Colors.black, 0.32),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onPressed,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 5),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.white, 0.15)!, color],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    icon,
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (dot)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53950),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
