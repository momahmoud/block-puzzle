import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Booster { bomb, rotate, undo }

/// How many of each booster the player has. New players start with a few;
/// more come from rewarded ads and the daily challenge.
class Boosters extends ChangeNotifier {
  Boosters(this._prefs)
      : _counts = {
          for (final b in Booster.values)
            b: _prefs.getInt(_key(b)) ?? startingCount,
        };

  static const int startingCount = 2;

  static String _key(Booster b) => 'boosters.${b.name}';

  final SharedPreferences _prefs;
  final Map<Booster, int> _counts;

  int count(Booster b) => _counts[b]!;

  void add(Booster b, [int n = 1]) {
    _counts[b] = count(b) + n;
    _prefs.setInt(_key(b), count(b));
    notifyListeners();
  }

  /// Uses one. Returns false if there are none.
  bool use(Booster b) {
    if (count(b) <= 0) return false;
    _counts[b] = count(b) - 1;
    _prefs.setInt(_key(b), count(b));
    notifyListeners();
    return true;
  }
}
