import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/levels.dart';

/// Stars earned on each level. A level is unlocked once the one before it
/// has been won.
class LevelProgress extends ChangeNotifier {
  LevelProgress(this._prefs) : _stars = _load(_prefs);

  static const _key = 'levels.stars';

  final SharedPreferences _prefs;

  /// Best stars per level, index 0 = level 1. Only won levels are listed.
  final List<int> _stars;

  static List<int> _load(SharedPreferences prefs) {
    final saved = prefs.getStringList(_key) ?? const [];
    return [for (final s in saved) (int.tryParse(s) ?? 0).clamp(0, 3)];
  }

  int starsFor(int level) => level <= _stars.length ? _stars[level - 1] : 0;

  /// Levels won so far.
  int get completed => _stars.where((s) => s > 0).length;

  int get totalStars => _stars.fold(0, (a, b) => a + b);

  /// The furthest level that can be played.
  int get unlocked => math.min(_stars.length + 1, LevelSpec.count);

  bool isUnlocked(int level) => level <= unlocked;

  bool get allDone => _stars.length >= LevelSpec.count;

  /// Saves a win. Keeps the best star count for each level.
  void record(int level, int stars) {
    if (stars <= 0 || level < 1 || level > LevelSpec.count) return;
    while (_stars.length < level) {
      _stars.add(0);
    }
    _stars[level - 1] = math.max(_stars[level - 1], stars);
    _prefs.setStringList(_key, [for (final s in _stars) '$s']);
    notifyListeners();
  }
}
