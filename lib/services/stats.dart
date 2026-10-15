import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifetime totals shown on the home screen.
class Stats extends ChangeNotifier {
  Stats(this._prefs)
      : gamesPlayed = _prefs.getInt(_gamesKey) ?? 0,
        linesCleared = _prefs.getInt(_linesKey) ?? 0,
        bestCombo = _prefs.getInt(_comboKey) ?? 0;

  static const _gamesKey = 'stats.games';
  static const _linesKey = 'stats.lines';
  static const _comboKey = 'stats.bestCombo';

  final SharedPreferences _prefs;
  int gamesPlayed;
  int linesCleared;
  int bestCombo;

  void recordMove({required int lines, required int combo}) {
    if (lines == 0) return;
    linesCleared += lines;
    bestCombo = math.max(bestCombo, combo);
    _prefs.setInt(_linesKey, linesCleared);
    _prefs.setInt(_comboKey, bestCombo);
    notifyListeners();
  }

  void recordGameEnd() {
    gamesPlayed++;
    _prefs.setInt(_gamesKey, gamesPlayed);
    notifyListeners();
  }
}
