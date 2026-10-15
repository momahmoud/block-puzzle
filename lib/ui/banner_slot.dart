import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config.dart';
import '../services/app_services.dart';

/// An anchored adaptive banner along the bottom of the screen. Takes no
/// space until an ad has loaded, and goes away for good when "Remove ads"
/// is bought.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key, required this.app});

  final AppServices app;

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  int? _width;
  Timer? _retry;

  Listenable get _changes =>
      Listenable.merge([widget.app.ads, widget.app.purchases]);

  @override
  void initState() {
    super.initState();
    _changes.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      _dropAd();
      _update();
    }
  }

  @override
  void dispose() {
    _changes.removeListener(_update);
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    if (!widget.app.ads.bannerAllowed) {
      if (_ad != null) setState(_dropAd);
      return;
    }
    if (_ad == null && !_loading) _load();
  }

  void _dropAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  Future<void> _load() async {
    final width = _width;
    if (width == null) return;
    _loading = true;
    try {
      // The standard anchored size (about 50-60pt). The newer "large"
      // anchored banner is up to ~130pt tall, which shrinks the board too
      // much, so the older call is used on purpose.
      // ignore: deprecated_member_use
      final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (!mounted || size == null || !widget.app.ads.bannerAllowed) return;
      final ad = BannerAd(
        adUnitId: AppConfig.bannerAdUnit,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('Ads: banner failed to load: ${error.message}');
            ad.dispose();
            if (!mounted) return;
            setState(() {
              _ad = null;
              _loaded = false;
            });
            _retry?.cancel();
            _retry = Timer(const Duration(seconds: 45), _update);
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (e) {
      debugPrint('Ads: banner unavailable: $e');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // Until an ad arrives, just keep clear of the home indicator.
    if (ad == null || !_loaded) {
      return const SafeArea(top: false, child: SizedBox(width: double.infinity));
    }
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.25),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
