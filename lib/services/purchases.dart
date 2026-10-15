import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// The one-time "Remove ads" purchase.
///
/// The purchase is remembered locally and confirmed again by the store
/// whenever it reports it (on purchase, restore, or a later launch). There
/// is no server-side receipt check, which is fine for a cosmetic unlock.
class Purchases extends ChangeNotifier {
  Purchases(this._prefs) : _adsRemoved = _prefs.getBool(_key) ?? false;

  static const _key = 'iap.removeAds';

  final SharedPreferences _prefs;
  bool _adsRemoved;
  bool _available = false;
  bool _busy = false;
  ProductDetails? _product;
  String? _error;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool get adsRemoved => _adsRemoved;
  bool get available => _available && _product != null;
  bool get busy => _busy;

  /// Store price, e.g. "$2.99", once the product has loaded.
  String? get price => _product?.price;

  /// The last error to show the player, if any.
  String? get error => _error;

  Future<void> init() async {
    try {
      final store = InAppPurchase.instance;
      _sub = store.purchaseStream.listen(_onPurchases, onError: (Object e) {
        debugPrint('Purchases: stream error: $e');
      });
      _available = await store.isAvailable();
      if (!_available) return;
      final response =
          await store.queryProductDetails({AppConfig.removeAdsProductId});
      if (response.productDetails.isNotEmpty) {
        _product = response.productDetails.first;
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            'Purchases: not set up in the store yet: ${response.notFoundIDs}');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Purchases: not available: $e');
    }
  }

  Future<void> buyRemoveAds() async {
    final product = _product;
    if (product == null || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await InAppPurchase.instance.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      _busy = false;
      _error = 'The purchase could not be started.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!_available) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      _error = 'Purchases could not be restored.';
    }
    _busy = false;
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != AppConfig.removeAdsProductId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _setRemoved();
          _busy = false;
        case PurchaseStatus.error:
          _error = p.error?.message ?? 'The purchase failed.';
          _busy = false;
        case PurchaseStatus.canceled:
          _busy = false;
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
    notifyListeners();
  }

  void _setRemoved() {
    _adsRemoved = true;
    _prefs.setBool(_key, true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
