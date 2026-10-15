import 'dart:io' show Platform;

/// Store, ad and game-service settings in one place. Replace the
/// placeholders before release; see README "Before releasing".
abstract final class AppConfig {
  static const String privacyPolicyUrl =
      'https://momahmoud.github.io/Fluxy-Labs/privacy-policy.html';

  // ------------------------------------------------------------- AdMob
  // These are Google's public TEST ad units, safe to use while developing.
  // Replace them with your own from https://admob.google.com before release
  // (and the app IDs in AndroidManifest.xml and ios/Runner/Info.plist).
  static String get rewardedAdUnit => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  static String get interstitialAdUnit => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  /// Adaptive banner at the bottom of the game screen.
  static String get bannerAdUnit => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/9214589741'
      : 'ca-app-pub-3940256099942544/2435281174';

  /// Show an interstitial at most once per this many finished games.
  static const int interstitialEveryGames = 3;

  // ------------------------------------------------------------- purchases
  /// Non-consumable product that turns off interstitial ads. Create it with
  /// this id in Play Console (and App Store Connect).
  static const String removeAdsProductId = 'remove_ads';

  // ------------------------------------------------------------- game services
  /// Set to true once the IDs below and android/app/src/main/res/values/
  /// games-ids.xml come from your Play Console (and Game Center) setup.
  static const bool gameServicesEnabled = false;

  static const String classicLeaderboardAndroid = 'REPLACE_ME';
  static const String classicLeaderboardIOS = 'classic_best';
  static const String starsLeaderboardAndroid = 'REPLACE_ME';
  static const String starsLeaderboardIOS = 'level_stars';
}
