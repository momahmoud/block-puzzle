import 'dart:math' as math;

import 'dealer.dart';
import 'grid.dart';
import 'level_patterns.dart';
import 'level_tuning.dart';

enum GoalType { score, lines, gems, ice }

/// Something the player must reach to finish a level.
class LevelGoal {
  const LevelGoal(this.type, this.target);

  final GoalType type;
  final int target;
}

/// One level: a starting board, gems and ice on some of its blocks, the
/// goals, and how many pieces may be placed.
class LevelSpec {
  const LevelSpec({
    required this.number,
    required this.cells,
    required this.gems,
    required this.goals,
    required this.moves,
    this.ice = const {},
    this.dailyDay,
  });

  static const int perChapter = 20;
  static const List<String> chapters = [
    'Warm Up',
    'Gem Mine',
    'Ice Cave',
    'Crossroads',
    'Crystal Falls',
    'Deep Freeze',
    'Treasure Vault',
    'Storm Peak',
    'Night Sky',
    'Grand Master',
  ];
  static final int count = chapters.length * perChapter;

  /// First level with gems, and first with ice.
  static const int gemsFrom = 6;
  static const int iceFrom = 41;

  final int number;

  /// Starting board, [row][col], 0 = empty, otherwise a colour id.
  final List<List<int>> cells;

  /// Squares (row * 8 + col) holding a gem. Each sits on a starting block.
  final Set<int> gems;

  /// Frozen squares (row * 8 + col). Each sits on a starting block.
  final Set<int> ice;

  final List<LevelGoal> goals;
  final int moves;

  /// Set on a daily challenge: the day it belongs to (see DailyChallenge).
  final int? dailyDay;
  bool get isDaily => dailyDay != null;

  /// 0-based chapter index.
  int get chapter => (number - 1) ~/ perChapter;
  String get chapterName => chapters[chapter];

  /// Every tenth level is a harder one.
  bool get isHard => number % 10 == 0;

  double get difficulty => difficultyOf(number);

  /// Stars for winning with [movesLeft] moves to spare.
  int starsFor(int movesLeft) {
    final spare = movesLeft / moves;
    if (spare >= 0.25) return 3;
    if (spare >= 0.1) return 2;
    return 1;
  }

  /// How hard level [n] should be, 0..1. Rises across the game and within
  /// each chapter, with a spike on every tenth level and a breather after.
  static double difficultyOf(int n) {
    final c = (n - 1) ~/ perChapter;
    final pos = (n - 1) % perChapter;
    var d = 0.6 * c / (chapters.length - 1) + 0.4 * pos / (perChapter - 1);
    if (n % 10 == 0) {
      d += 0.15;
    } else if (n % 10 == 1 && n > 1) {
      d -= 0.1;
    }
    return d.clamp(0.0, 1.0);
  }

  /// Level [n] as played: the generated layout with its tuned move limit
  /// and targets (see tool/calibrate_levels_test.dart).
  factory LevelSpec.forNumber(int n) {
    if (n - 1 < kLevelTuning.length) {
      final t = kLevelTuning[n - 1];
      return LevelSpec.generate(n,
          variant: t[0], targetScale: t[1] / 100, moves: t[2]);
    }
    return LevelSpec.generate(n);
  }

  /// The daily challenge for [day]: the same for every player that day.
  /// Picks a mid-to-late difficulty and a layout variant no regular level
  /// uses. [moves] comes from the bot (see DailyChallenge).
  factory LevelSpec.daily(int day, {int? moves}) {
    final n = 40 + (day * 37) % 140;
    final base = LevelSpec.generate(n, variant: 10 + day % 1000);
    return LevelSpec(
      number: n,
      cells: base.cells,
      gems: base.gems,
      ice: base.ice,
      goals: base.goals,
      moves: moves ?? base.moves,
      dailyDay: day,
    );
  }

  /// A copy with a different move limit.
  LevelSpec withMoves(int moves) => LevelSpec(
        number: number,
        cells: cells,
        gems: gems,
        ice: ice,
        goals: goals,
        moves: moves,
        dailyDay: dailyDay,
      );

  /// Builds level [n] (1-based). The same arguments always give the same
  /// level. [variant] picks a different layout, [targetScale] shrinks the
  /// goals, and [moves] overrides the estimated move limit.
  factory LevelSpec.generate(int n,
      {int variant = 0, double targetScale = 1, int? moves}) {
    assert(n >= 1 && n <= count);
    final rng = math.Random(n * 7919 + variant * 104729 + 13);
    final d = difficultyOf(n);
    final chapter = (n - 1) ~/ perChapter;
    final hard = n % 10 == 0;

    // --- the board
    final pool = math.min(patterns.length, 3 + n ~/ 6);
    final shape = patterns[rng.nextInt(pool)](rng, d);
    // Knock a few holes in it so lines need finishing, then cap how full it
    // is by trimming from the top, which keeps the pattern recognisable.
    final filled = <int>[];
    for (var r = 0; r < Grid.size; r++) {
      for (var c = 0; c < Grid.size; c++) {
        if (shape[r][c] && rng.nextDouble() < 0.12) shape[r][c] = false;
        if (shape[r][c]) filled.add(r * Grid.size + c);
      }
    }
    final maxCells = (16 + d * 20).round();
    for (final i in filled.take(math.max(0, filled.length - maxCells))) {
      shape[i ~/ Grid.size][i % Grid.size] = false;
    }
    final cells = colourShape(shape, rng);
    _breakFullLines(cells, rng);
    final blocks = [
      for (var r = 0; r < Grid.size; r++)
        for (var c = 0; c < Grid.size; c++)
          if (cells[r][c] != 0) r * Grid.size + c,
    ]..shuffle(rng);

    // --- the goals
    final weights = <GoalType, double>{
      GoalType.lines: 1,
      GoalType.score: chapter == 2 ? 0.7 : 1,
      if (n >= gemsFrom) GoalType.gems: chapter == 1 ? 2 : 1,
      if (n >= iceFrom) GoalType.ice: chapter == 2 ? 2 : 1,
    };
    var primary = _weighted(weights, rng);
    if (n == gemsFrom) primary = GoalType.gems;
    if (n == iceFrom) primary = GoalType.ice;
    final types = [primary];
    if (hard || (chapter >= 1 && rng.nextDouble() < 0.15 + 0.05 * chapter)) {
      types.add(_weighted({...weights}..remove(primary), rng));
    }

    final gems = <int>{};
    final ice = <int>{};
    var spare = blocks.toList();
    int target(GoalType type, double scale) {
      final s = targetScale * scale;
      return switch (type) {
        GoalType.lines => math.max(2, ((2 + d * 11) * s).round()),
        GoalType.score => math.max(50, ((60 + d * 650) * s / 10).round() * 10),
        GoalType.gems =>
          math.min(spare.length, math.max(2, ((2 + d * 10) * s).round())),
        GoalType.ice =>
          math.min(spare.length, math.max(2, ((2 + d * 8) * s).round())),
      };
    }

    final goals = <LevelGoal>[];
    for (var i = 0; i < types.length; i++) {
      final type = types[i];
      final t = target(type, i == 0 ? 1 : 0.6);
      if (type == GoalType.gems || type == GoalType.ice) {
        if (t < 1) continue;
        final picked = _spread(spare, t);
        spare = spare.where((i) => !picked.contains(i)).toList();
        (type == GoalType.gems ? gems : ice).addAll(picked);
      }
      goals.add(LevelGoal(type, t));
    }
    if (goals.isEmpty) {
      goals.add(LevelGoal(GoalType.lines, target(GoalType.lines, 1)));
    }
    // Gem and ice counts are capped by the blocks on the board, so when a
    // level is scaled up past that, it also asks for line clears.
    final onlyCollect = goals.length == 1 &&
        (goals.first.type == GoalType.gems || goals.first.type == GoalType.ice);
    if (targetScale > 1 && onlyCollect) {
      goals.add(LevelGoal(
          GoalType.lines, math.max(2, ((targetScale - 1) * 8 + 2).round())));
    }

    // Later chapters freeze a few blocks even when ice is not a goal.
    if (chapter >= 3 &&
        !types.contains(GoalType.ice) &&
        rng.nextDouble() < 0.5) {
      ice.addAll(spare.take(1 + (d * 4).round()));
    }

    return LevelSpec(
      number: n,
      cells: cells,
      gems: gems,
      ice: ice,
      goals: goals,
      moves: moves ?? _estimateMoves(goals, d),
    );
  }

  /// Takes [count] squares from [from], spread over as many different rows
  /// and columns as possible so they need separate clears.
  static List<int> _spread(List<int> from, int count) {
    final picked = <int>[];
    final rows = <int>{};
    final cols = <int>{};
    for (final i in from) {
      if (picked.length == count) break;
      if (rows.contains(i ~/ Grid.size) || cols.contains(i % Grid.size)) {
        continue;
      }
      picked.add(i);
      rows.add(i ~/ Grid.size);
      cols.add(i % Grid.size);
    }
    for (final i in from) {
      if (picked.length == count) break;
      if (!picked.contains(i)) picked.add(i);
    }
    return picked;
  }

  /// A rough move limit, used before a level has been tuned.
  static int _estimateMoves(List<LevelGoal> goals, double d) {
    var need = 0.0;
    for (final g in goals) {
      need = math.max(
          need,
          switch (g.type) {
            GoalType.lines => g.target * 2.5 + 4,
            GoalType.score => g.target / 12 + 6,
            GoalType.gems => g.target * 2.0 + 8,
            GoalType.ice => g.target * 2.0 + 8,
          });
    }
    return ((need + (goals.length - 1) * 3) * (1.2 - 0.3 * d)).round();
  }

  static GoalType _weighted(Map<GoalType, double> weights, math.Random rng) {
    final total = weights.values.fold(0.0, (a, b) => a + b);
    var pick = rng.nextDouble() * total;
    for (final e in weights.entries) {
      pick -= e.value;
      if (pick < 0) return e.key;
    }
    return weights.keys.last;
  }

  /// Removes one block from every full row or column so the level does not
  /// start with a free clear.
  static void _breakFullLines(List<List<int>> cells, math.Random rng) {
    for (var guard = 0; guard < 32; guard++) {
      var bits = 0;
      for (var r = 0; r < Grid.size; r++) {
        for (var c = 0; c < Grid.size; c++) {
          if (cells[r][c] != 0) bits |= 1 << (r * Grid.size + c);
        }
      }
      if (Dealer.clearLines(bits) == bits) return;
      for (var r = 0; r < Grid.size; r++) {
        if (cells[r].every((v) => v != 0)) cells[r][rng.nextInt(Grid.size)] = 0;
      }
      for (var c = 0; c < Grid.size; c++) {
        if (cells.every((row) => row[c] != 0)) {
          cells[rng.nextInt(Grid.size)][c] = 0;
        }
      }
    }
  }
}
