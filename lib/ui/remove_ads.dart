import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../services/purchases.dart';
import 'widgets.dart';

/// The Remove ads offer: what it does, the price, buy and restore.
/// Closes itself (with a thank-you) once the purchase goes through.
Future<void> showRemoveAdsOffer(BuildContext context, AppServices app) {
  app.sfx.tap();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, __) => _RemoveAdsOffer(purchases: app.purchases),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.8, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _RemoveAdsOffer extends StatefulWidget {
  const _RemoveAdsOffer({required this.purchases});

  final Purchases purchases;

  @override
  State<_RemoveAdsOffer> createState() => _RemoveAdsOfferState();
}

class _RemoveAdsOfferState extends State<_RemoveAdsOffer> {
  Purchases get _p => widget.purchases;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _p.addListener(_onChange);
  }

  @override
  void dispose() {
    _p.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_p.adsRemoved && !_closing) {
      _closing = true;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
          const SnackBar(content: Text('Ads removed. Thank you!')));
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 56),
                  child: GameCard(
                    padding: const EdgeInsets.fromLTRB(22, 70, 22, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const OutlinedText('Remove ads', size: 30),
                        const SizedBox(height: 14),
                        const _Perk(
                            icon: Icons.check_circle_rounded,
                            text: 'No more ads between games'),
                        const _Perk(
                            icon: Icons.check_circle_rounded,
                            text: 'Pay once, keep it forever'),
                        const _Perk(
                          icon: Icons.info_outline_rounded,
                          text:
                              'Revive and boosters stay free with optional ads',
                          muted: true,
                        ),
                        const SizedBox(height: 18),
                        if (p.available)
                          p.busy
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                )
                              : ChunkyButton(
                                  label: p.price == null
                                      ? 'Remove ads'
                                      : 'Remove ads · ${p.price}',
                                  expand: true,
                                  fontSize: 20,
                                  onPressed: p.buyRemoveAds,
                                )
                        else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Not available right now. Please try again later.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 15, color: Colors.white70),
                            ),
                          ),
                        if (p.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              p.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFFF9A9A)),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: p.busy ? null : p.restore,
                              child: const Text(
                                'Restore purchase',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Not now',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Image.asset(
                  'assets/icons/no_ads_big.png',
                  width: 120,
                  height: 120,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 22,
              color: muted ? Colors.white54 : const Color(0xFF5FE37A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: muted ? 14 : 16,
                fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
                color: muted ? Colors.white60 : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small Remove ads button for the game screen. Hidden once ads are
/// removed.
class RemoveAdsButton extends StatelessWidget {
  const RemoveAdsButton({super.key, required this.app});

  final AppServices app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.purchases,
      builder: (context, _) => app.purchases.adsRemoved
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Remove ads',
              onPressed: () => showRemoveAdsOffer(context, app),
              icon: const GameIcon('remove_ads', size: 34),
            ),
    );
  }
}
