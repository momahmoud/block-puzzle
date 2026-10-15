import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Achievements, with their Play Games and Game Center ids. Create one in
/// each console with these ids (or replace the Android ids with the ones
/// Play Console generates).
enum Award {
  firstClear('first_clear', 'REPLACE_ME', 'Clear your first line'),
  combo5('combo_5', 'REPLACE_ME', 'Reach a 5 combo'),
  combo10('combo_10', 'REPLACE_ME', 'Reach a 10 combo'),
  allClear('all_clear', 'REPLACE_ME', 'Empty the whole board'),
  score1000('score_1000', 'REPLACE_ME', 'Score 1,000 in Classic'),
  score5000('score_5000', 'REPLACE_ME', 'Score 5,000 in Classic'),
  score10000('score_10000', 'REPLACE_ME', 'Score 10,000 in Classic'),
  lines500('lines_500', 'REPLACE_ME', 'Clear 500 lines'),
  chapter1('chapter_1', 'REPLACE_ME', 'Finish chapter 1'),
  chapter5('chapter_5', 'REPLACE_ME', 'Finish chapter 5'),
  allLevels('all_levels', 'REPLACE_ME', 'Finish all 200 levels'),
  streak7('streak_7', 'REPLACE_ME', 'Play the daily challenge 7 days in a row');

  const Award(this.iosId, this.androidId, this.title);

  final String iosId;
  final String androidId;
  final String title;
}

/// Google Play Games / Game Center: leaderboards and achievements.
///
/// Everything here is best effort: if the player is not signed in, or
/// [AppConfig.gameServicesEnabled] is off, calls quietly do nothing.
/// Unlocked achievements are remembered locally so each is sent once.
class GameServices extends ChangeNotifier {
  GameServices(this._prefs);

  static const _key = 'awards';

  final SharedPreferences _prefs;
  bool _signedIn = false;

  bool get enabled => AppConfig.gameServicesEnabled;
  bool get signedIn => _signedIn;

  Set<String> get _unlocked => (_prefs.getStringList(_key) ?? const []).toSet();

  Future<void> signIn() async {
    if (!enabled) return;
    try {
      await GamesServices.signIn();
      _signedIn = await GamesServices.isSignedIn;
      notifyListeners();
      // Send anything earned while signed out.
      for (final a in Award.values) {
        if (_unlocked.contains(a.name)) _send(a);
      }
    } catch (e) {
      debugPrint('GameServices: sign in failed: $e');
    }
  }

  void unlock(Award award) {
    final unlocked = _unlocked;
    if (!unlocked.add(award.name)) return;
    _prefs.setStringList(_key, unlocked.toList());
    _send(award);
  }

  void _send(Award award) {
    if (!enabled || !_signedIn) return;
    GamesServices.unlock(
      achievement: Achievement(androidID: award.androidId, iOSID: award.iosId),
    ).catchError((Object e) {
      debugPrint('GameServices: unlock failed: $e');
      return null;
    });
  }

  void submitClassicScore(int score) => _submit(
        AppConfig.classicLeaderboardAndroid,
        AppConfig.classicLeaderboardIOS,
        score,
      );

  void submitStars(int stars) => _submit(
        AppConfig.starsLeaderboardAndroid,
        AppConfig.starsLeaderboardIOS,
        stars,
      );

  void _submit(String androidId, String iosId, int value) {
    if (!enabled || !_signedIn || value <= 0) return;
    GamesServices.submitScore(
      score: Score(
          androidLeaderboardID: androidId,
          iOSLeaderboardID: iosId,
          value: value),
    ).catchError((Object e) {
      debugPrint('GameServices: submit failed: $e');
      return null;
    });
  }

  Future<void> showLeaderboards() async {
    if (!_signedIn) await signIn();
    if (!_signedIn) return;
    try {
      await GamesServices.showLeaderboards();
    } catch (e) {
      debugPrint('GameServices: leaderboards failed: $e');
    }
  }

  Future<void> showAchievements() async {
    if (!_signedIn) await signIn();
    if (!_signedIn) return;
    try {
      await GamesServices.showAchievements();
    } catch (e) {
      debugPrint('GameServices: achievements failed: $e');
    }
  }
}
