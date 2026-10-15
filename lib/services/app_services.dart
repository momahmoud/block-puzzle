import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_controller.dart';
import 'ads.dart';
import 'boosters.dart';
import 'daily_challenge.dart';
import 'game_services.dart';
import 'level_progress.dart';
import 'music.dart';
import 'purchases.dart';
import 'settings.dart';
import 'sfx.dart';
import 'stats.dart';

/// Everything the screens share, created once at start-up.
class AppServices {
  AppServices(this.prefs)
      : settings = Settings(prefs),
        stats = Stats(prefs),
        levels = LevelProgress(prefs),
        boosters = Boosters(prefs),
        daily = DailyChallenge(prefs),
        purchases = Purchases(prefs),
        games = GameServices(prefs) {
    sfx = Sfx(settings);
    music = Music(settings);
    ads = Ads(purchases, prefs);
  }

  final SharedPreferences prefs;
  final Settings settings;
  final Stats stats;
  final LevelProgress levels;
  final Boosters boosters;
  final DailyChallenge daily;
  final Purchases purchases;
  final GameServices games;
  late final Sfx sfx;
  late final Music music;
  late final Ads ads;

  /// Starts the parts that talk to the platform. Each fails quietly.
  Future<void> start() async {
    sfx.init();
    music.init();
    await purchases.init();
    ads.init();
    games.signIn();
  }

  /// Shows a rewarded ad with the music paused. True if it was watched.
  Future<bool> watchAd() async {
    music.hold();
    try {
      return await ads.showRewarded();
    } finally {
      music.release();
    }
  }

  /// Awards for what a placement did.
  void afterMove(GameController game, MoveResult move) {
    if (move.lines > 0) games.unlock(Award.firstClear);
    if (move.combo >= 5) games.unlock(Award.combo5);
    if (move.combo >= 10) games.unlock(Award.combo10);
    if (move.allClear) games.unlock(Award.allClear);
    if (!game.isLevel) {
      if (game.score >= 1000) games.unlock(Award.score1000);
      if (game.score >= 5000) games.unlock(Award.score5000);
      if (game.score >= 10000) games.unlock(Award.score10000);
    }
    if (stats.linesCleared >= 500) games.unlock(Award.lines500);
  }

  /// Saves a level win and its awards.
  void afterLevelWin(int level, int stars) {
    levels.record(level, stars);
    if (levels.isUnlocked(21)) games.unlock(Award.chapter1);
    if (levels.isUnlocked(101)) games.unlock(Award.chapter5);
    if (levels.allDone) games.unlock(Award.allLevels);
    games.submitStars(levels.totalStars);
  }

  /// Records the daily challenge win. Returns the booster earned, if this
  /// was the first win today.
  Booster? afterDailyWin() {
    if (!daily.complete()) return null;
    if (daily.streak >= 7) games.unlock(Award.streak7);
    final reward = Booster.values[daily.today % Booster.values.length];
    boosters.add(reward);
    return reward;
  }
}
