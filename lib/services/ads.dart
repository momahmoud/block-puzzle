import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'purchases.dart';

/// AdMob: rewarded ads (revive, extra moves, boosters) and an occasional
/// interstitial between games, which "Remove ads" turns off.
///
/// Consent comes first: Google's consent form is shown where the law asks
/// for it (EU/UK), and no ad is requested until AdMob says it may be.
class Ads extends ChangeNotifier {
  Ads(this._purchases, this._prefs);

  final Purchases _purchases;
  final SharedPreferences _prefs;

  /// Finished games since the last interstitial. Saved, so it adds up over
  /// short sessions instead of starting again at every launch.
  static const _gamesKey = 'ads.gamesSinceInterstitial';
  int get _gamesSinceInterstitial => _prefs.getInt(_gamesKey) ?? 0;
  set _gamesSinceInterstitial(int value) => _prefs.setInt(_gamesKey, value);

  bool _canRequest = false;
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _loadingRewarded = false;
  bool _privacyOptionsRequired = false;

  /// Lets tests (and debug builds without Play services) grant rewards.
  @visibleForTesting
  Future<bool> Function()? debugRewardOverride;

  /// True once consent allows ads and "Remove ads" was not bought: the
  /// banner may be shown.
  bool get bannerAllowed => _canRequest && !_purchases.adsRemoved;

  bool get rewardedReady => debugRewardOverride != null || _rewarded != null;

  /// True where the player must be able to change their consent later.
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  Future<void> init() async {
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Ads: consent form: ${error.message}');
          done.complete();
        }),
        (error) {
          debugPrint('Ads: consent update failed: ${error.message}');
          done.complete();
        },
      );
      await done.future;
      _privacyOptionsRequired = await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      _canRequest = await ConsentInformation.instance.canRequestAds();
      if (!_canRequest) return;
      await MobileAds.instance.initialize();
      _loadRewarded();
      _loadInterstitial();
      notifyListeners();
    } catch (e) {
      debugPrint('Ads: not available: $e');
    }
  }

  /// Opens Google's form for changing ad consent.
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) debugPrint('Ads: privacy options: ${error.message}');
      });
      _canRequest = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('Ads: privacy options unavailable: $e');
    }
  }

  void _loadRewarded() {
    if (!_canRequest || _loadingRewarded || _rewarded != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AppConfig.rewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Ads: rewarded failed to load: ${error.message}');
          _loadingRewarded = false;
          Timer(const Duration(seconds: 30), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (!_canRequest || _purchases.adsRemoved || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Ads: interstitial failed to load: ${error.message}');
          Timer(const Duration(seconds: 60), _loadInterstitial);
        },
      ),
    );
  }

  /// Shows a rewarded ad. Completes with true if the player watched it to
  /// the end and earned the reward.
  Future<bool> showRewarded() async {
    final override = debugRewardOverride;
    if (override != null) return override();
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    notifyListeners();
    final result = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!result.isCompleted) result.complete(earned);
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!result.isCompleted) result.complete(false);
        _loadRewarded();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return result.future;
  }

  /// Call when a game ends and the player moves on. Shows an interstitial
  /// every few games unless ads were removed.
  Future<void> gameFinished() async {
    if (_purchases.adsRemoved) return;
    _gamesSinceInterstitial = _gamesSinceInterstitial + 1;
    final ad = _interstitial;
    if (ad == null || _gamesSinceInterstitial < AppConfig.interstitialEveryGames) {
      final left = AppConfig.interstitialEveryGames - _gamesSinceInterstitial;
      debugPrint(ad == null && left <= 0
          ? 'Ads: interstitial due but not loaded yet'
          : 'Ads: interstitial in $left more finished game(s)');
      _loadInterstitial();
      return;
    }
    _gamesSinceInterstitial = 0;
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        done.complete();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        done.complete();
        _loadInterstitial();
      },
    );
    await ad.show();
    return done.future;
  }
}
