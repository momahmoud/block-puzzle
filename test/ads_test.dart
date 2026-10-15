import 'package:block_puzzle/services/ads.dart';
import 'package:block_puzzle/services/purchases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('finished games count towards the interstitial across launches', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final purchases = Purchases(prefs);

    // No ad is loaded in tests, so nothing shows; the count still adds up.
    await Ads(purchases, prefs).gameFinished();
    await Ads(purchases, prefs).gameFinished(); // a "new launch"
    expect(prefs.getInt('ads.gamesSinceInterstitial'), 2);
  });

  test('nothing is counted once ads are removed', () async {
    SharedPreferences.setMockInitialValues({'flutter.iap.removeAds': true});
    final prefs = await SharedPreferences.getInstance();
    await Ads(Purchases(prefs), prefs).gameFinished();
    expect(prefs.getInt('ads.gamesSinceInterstitial'), isNull);
  });
}
