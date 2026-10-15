import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_controller.dart';
import '../game/levels.dart';
import '../services/level_progress.dart';
import '../services/settings.dart';
import '../services/sfx.dart';
import 'game_screen.dart';
import 'palette.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens level [number].
Route<void> levelRoute({
  required int number,
  required Settings settings,
  required Sfx sfx,
  required LevelProgress levels,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => GameScreen(
      controller: GameController(level: LevelSpec.forNumber(number)),
      settings: settings,
      sfx: sfx,
      levels: levels,
    ),
    transitionsBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
            scale: Tween(begin: 1.08, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

String goalName(GoalType type) => switch (type) {
      GoalType.score => 'Score',
      GoalType.lines => 'Lines',
      GoalType.gems => 'Gems',
      GoalType.ice => 'Ice',
    };

String goalDescription(LevelGoal goal) => switch (goal.type) {
      GoalType.score => 'Score ${goal.target} points',
      GoalType.lines => 'Clear ${goal.target} lines',
      GoalType.gems => 'Collect ${goal.target} gems',
      GoalType.ice => 'Break ${goal.target} ice',
    };

/// The icon for a kind of goal.
class GoalIcon extends StatelessWidget {
  const GoalIcon(this.type, {super.key, this.size = 24});

  final GoalType type;
  final double size;

  @override
  Widget build(BuildContext context) => switch (type) {
        GoalType.score => Icon(Icons.star_rounded, color: kGold, size: size),
        GoalType.lines => Icon(Icons.view_week_rounded,
            color: const Color(0xFF8FE3FF), size: size),
        GoalType.gems => SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _GemIconPainter()),
          ),
        GoalType.ice => Icon(Icons.ac_unit_rounded,
            color: const Color(0xFFBDEBFF), size: size),
      };
}

class _GemIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintGem(canvas, Offset.zero & size, scale: 1.5);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A winding path of levels, from level 1 at the bottom upwards.
class LevelMapScreen extends StatefulWidget {
  const LevelMapScreen({
    super.key,
    required this.levels,
    required this.settings,
    required this.sfx,
  });

  final LevelProgress levels;
  final Settings settings;
  final Sfx sfx;

  @override
  State<LevelMapScreen> createState() => _LevelMapScreenState();
}

class _LevelMapScreenState extends State<LevelMapScreen>
    with SingleTickerProviderStateMixin {
  static const double _rowHeight = 104;
  static const double _bannerHeight = 92;
  static const double _nodeSize = 68;

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);
  ScrollController? _scroll;

  @override
  void dispose() {
    _pulse.dispose();
    _scroll?.dispose();
    super.dispose();
  }

  /// Horizontal position of level [n]'s node, as a fraction of the width.
  static double _x(int n) => 0.5 + math.sin(n * 0.85) * 0.28;

  /// Distance from the top of the map to level [n]'s row.
  double _top(int n) {
    final chapter = (n - 1) ~/ LevelSpec.perChapter;
    final bannersAbove = LevelSpec.chapters.length - 1 - chapter;
    return (LevelSpec.count - n) * _rowHeight +
        bannersAbove * _bannerHeight +
        24;
  }

  void _open(int n) {
    widget.sfx.tap();
    showLevelIntro(
      context,
      level: LevelSpec.forNumber(n),
      stars: widget.levels.starsFor(n),
      onPlay: () => Navigator.of(context).push(
        levelRoute(
            number: n,
            settings: widget.settings,
            sfx: widget.sfx,
            levels: widget.levels),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(gradient: theme.background),
          child: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: widget.levels,
              builder: (context, _) => Column(
                children: [
                  _header(),
                  Expanded(
                      child: LayoutBuilder(
                          builder: (context, box) => _map(theme, box))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final levels = widget.levels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            iconSize: 30,
            color: Colors.white,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: OutlinedText('Levels', size: 30),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: kGold, size: 22),
                const SizedBox(width: 4),
                Text(
                  '${levels.totalStars}/${LevelSpec.count * 3}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(GameTheme theme, BoxConstraints box) {
    final width = box.maxWidth;
    final height = _top(1) + _rowHeight + 24;
    // Start with the current level in view.
    _scroll ??= ScrollController(
      initialScrollOffset:
          (_top(widget.levels.unlocked) - box.maxHeight / 2 + _nodeSize / 2)
              .clamp(0.0, math.max(0.0, height - box.maxHeight)),
    );

    return SingleChildScrollView(
      controller: _scroll,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PathPainter(
                  points: [
                    for (var n = 1; n <= LevelSpec.count; n++)
                      Offset(_x(n) * width, _top(n) + _nodeSize / 2),
                  ],
                  reached: widget.levels.unlocked,
                  color: theme.accent,
                ),
              ),
            ),
            for (var c = 0; c < LevelSpec.chapters.length; c++)
              Positioned(
                left: 0,
                right: 0,
                top: _top(c * LevelSpec.perChapter + 1) + _rowHeight - 4,
                child: _chapterBanner(theme, c),
              ),
            for (var n = 1; n <= LevelSpec.count; n++)
              Positioned(
                left: _x(n) * width - _nodeSize / 2,
                top: _top(n),
                child: _node(theme, n),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chapterBanner(GameTheme theme, int c) {
    final levels = widget.levels;
    final first = c * LevelSpec.perChapter + 1;
    final reached = levels.isUnlocked(first);
    var stars = 0;
    for (var n = first; n < first + LevelSpec.perChapter; n++) {
      stars += levels.starsFor(n);
    }
    return Center(
      child: Semantics(
        label:
            'Chapter ${c + 1}, ${LevelSpec.chapters[c]}${reached ? ', $stars stars' : ', locked'}',
        excludeSemantics: true,
        child: Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: reached ? theme.sheet : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: reached
                    ? theme.accent.withValues(alpha: 0.7)
                    : Colors.white12,
                width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CHAPTER ${c + 1}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: reached ? theme.accent : Colors.white38,
                ),
              ),
              OutlinedText(LevelSpec.chapters[c], size: 22),
              const SizedBox(height: 2),
              reached
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, color: kGold, size: 16),
                        const SizedBox(width: 3),
                        Text(
                          '$stars/${LevelSpec.perChapter * 3}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70),
                        ),
                      ],
                    )
                  : const Icon(Icons.lock_rounded,
                      color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _node(GameTheme theme, int n) {
    final levels = widget.levels;
    final unlocked = levels.isUnlocked(n);
    final current = n == levels.unlocked && levels.starsFor(n) == 0;
    final stars = levels.starsFor(n);
    final color = !unlocked
        ? const Color(0xFF6B6F86)
        : current
            ? theme.button
            : theme.block(1 + (n - 1) % 7);

    Widget circle = Container(
      width: _nodeSize,
      height: _nodeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
            color: Colors.white.withValues(alpha: unlocked ? 0.9 : 0.3),
            width: 3),
        boxShadow: [
          BoxShadow(
              color: Color.lerp(color, Colors.black, 0.45)!,
              offset: const Offset(0, 5)),
          if (current)
            BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 18,
                spreadRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: unlocked
          ? OutlinedText('$n', size: 26)
          : const Icon(Icons.lock_rounded, color: Colors.white70, size: 28),
    );
    if (current) {
      circle = AnimatedBuilder(
        animation: _pulse,
        child: circle,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.07 * Curves.easeInOut.transform(_pulse.value),
          child: child,
        ),
      );
    }

    return Semantics(
      button: unlocked,
      label:
          '${unlocked ? 'Level $n, $stars stars' : 'Level $n, locked'}${n % 10 == 0 ? ', hard' : ''}',
      child: GestureDetector(
        onTap: unlocked ? () => _open(n) : null,
        child: ExcludeSemantics(
          child: SizedBox(
            width: _nodeSize,
            height: _nodeSize + 22,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                circle,
                if (n % 10 == 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53950),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                if (stars > 0)
                  Positioned(
                    bottom: 0,
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: i < stars ? kGold : Colors.white24,
                            shadows: const [
                              Shadow(color: Colors.black45, blurRadius: 3)
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dotted path joining the level nodes; bright up to the furthest unlocked.
class _PathPainter extends CustomPainter {
  const _PathPainter(
      {required this.points, required this.reached, required this.color});

  final List<Offset> points;
  final int reached;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      final lit = i + 2 <= reached;
      final paint = Paint()
        ..color = lit
            ? color.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.18);
      final dist = (b - a).distance;
      final steps = (dist / 14).floor();
      for (var s = 1; s < steps; s++) {
        canvas.drawCircle(
            Offset.lerp(a, b, s / steps)!, lit ? 4.5 : 3.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) =>
      old.reached != reached || old.color != color;
}

/// The card shown before a level starts: goals, moves and a Play button.
Future<void> showLevelIntro(
  BuildContext context, {
  required LevelSpec level,
  required int stars,
  required VoidCallback onPlay,
}) {
  final theme = GameTheme.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: theme.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Colors.white24, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${level.chapterName.toUpperCase()} · CHAPTER ${level.chapter + 1}',
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white60),
            ),
            const SizedBox(height: 4),
            OutlinedText('Level ${level.number}', size: 34),
            if (level.isHard)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.fromLTRB(8, 3, 12, 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53950),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('HARD LEVEL',
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(Icons.star_rounded,
                      size: 30, color: i < stars ? kGold : Colors.white24),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'GOALS',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white60),
              ),
            ),
            const SizedBox(height: 6),
            for (final g in level.goals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    GoalIcon(g.type, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        goalDescription(g),
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.touch_app_rounded,
                    color: Colors.white70, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'in ${level.moves} moves',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70),
                  ),
                ),
              ],
            ),
            if (level.gems.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Clear the rows or columns the gems sit in to collect them.',
                style: TextStyle(fontSize: 13, color: Colors.white60),
              ),
            ],
            if (level.ice.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Frozen blocks survive one clear: the first breaks the ice, the next removes the block.',
                style: TextStyle(fontSize: 13, color: Colors.white60),
              ),
            ],
            const SizedBox(height: 20),
            ChunkyButton(
              label: 'Play',
              icon: Icons.play_arrow_rounded,
              onPressed: () {
                Navigator.pop(context);
                onPlay();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
