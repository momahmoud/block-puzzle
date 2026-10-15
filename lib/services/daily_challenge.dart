import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/level_bot.dart';
import '../game/levels.dart';

/// One shared level a day, plus the player's streak of days in a row.
///
/// The level comes from the UTC date, so everyone gets the same one. Its
/// move limit is worked out on the device by the level bot (in a
/// background isolate) and cached for the day.
class DailyChallenge extends ChangeNotifier {
  DailyChallenge(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _lastKey = 'daily.lastDone';
  static const _streakKey = 'daily.streak';
  static const _bestKey = 'daily.bestStreak';
  static String _movesKey(int day) => 'daily.moves.$day';

  static final DateTime _epoch = DateTime.utc(2026);

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// Days since 1 Jan 2026, UTC.
  int get today => _clock().toUtc().difference(_epoch).inDays;

  int get _lastDone => _prefs.getInt(_lastKey) ?? -100;

  bool get doneToday => _lastDone == today;

  /// Current streak; it is kept while today's or yesterday's was done.
  int get streak =>
      _lastDone >= today - 1 ? (_prefs.getInt(_streakKey) ?? 0) : 0;

  int get bestStreak => _prefs.getInt(_bestKey) ?? 0;

  /// Today's level, with its move limit.
  Future<LevelSpec> level() async {
    final day = today;
    final cached = _prefs.getInt(_movesKey(day));
    final int moves = cached ?? await compute<int, int>(_movesFor, day);
    if (cached == null) _prefs.setInt(_movesKey(day), moves);
    return LevelSpec.daily(day, moves: moves);
  }

  /// Records today's win. Returns true the first time today, when the
  /// player earns the daily reward.
  bool complete() {
    final day = today;
    if (_lastDone == day) return false;
    final next = _lastDone == day - 1 ? streak + 1 : 1;
    _prefs.setInt(_lastKey, day);
    _prefs.setInt(_streakKey, next);
    if (next > bestStreak) _prefs.setInt(_bestKey, next);
    notifyListeners();
    return true;
  }
}

int _movesFor(int day) {
  final spec = LevelSpec.daily(day);
  return calibrateMoves(spec, winRate: 0.6) ?? (spec.moves * 1.3).round();
}
