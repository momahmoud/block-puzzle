import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_services.dart';
import 'dialogs.dart';
import 'remove_ads.dart';
import 'theme.dart';
import 'theme_picker.dart';
import 'widgets.dart';

/// The settings sheet. Opened from a game it is the pause menu, with
/// Resume, Restart and Home.
Future<void> showSettingsSheet(
  BuildContext context, {
  required AppServices app,
  VoidCallback? onRestart,
  VoidCallback? onHome,
}) {
  final inGame = onRestart != null || onHome != null;
  final settings = app.settings;
  final sfx = app.sfx;
  final purchases = app.purchases;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GameTheme.of(context).sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([settings, purchases]),
      builder: (context, _) {
        final theme = GameTheme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedText(inGame ? 'Paused' : 'Settings', size: 30),
                  const SizedBox(height: 16),
                  if (inGame) ...[
                    SizedBox(
                      width: 260,
                      child: ChunkyButton(
                        label: 'Resume',
                        leading: const GameIcon('play', size: 30),
                        expand: true,
                        onPressed: () {
                          sfx.tap();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                  ] else ...[
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          for (final (value, label) in [
                            (app.stats.gamesPlayed, 'GAMES'),
                            (app.stats.linesCleared, 'LINES'),
                            (app.stats.bestCombo, 'BEST COMBO'),
                          ])
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: StatTile(value: '$value', label: label),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Toggle(
                        label: 'Sound',
                        on: settings.sound,
                        accent: theme.accent,
                        icon: Icon(
                          settings.sound
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        onTap: () {
                          settings.sound = !settings.sound;
                          sfx.tap();
                        },
                      ),
                      _Toggle(
                        label: 'Music',
                        on: settings.music,
                        accent: theme.accent,
                        icon: const GameIcon('music', size: 36),
                        onTap: () {
                          settings.music = !settings.music;
                          sfx.tap();
                        },
                      ),
                      _Toggle(
                        label: 'Vibration',
                        on: settings.haptics,
                        accent: theme.accent,
                        icon: const Icon(Icons.vibration_rounded,
                            color: Colors.white, size: 32),
                        onTap: () {
                          settings.haptics = !settings.haptics;
                          sfx.tap();
                        },
                      ),
                    ],
                  ),
                  if (inGame) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (onRestart != null)
                            Expanded(
                              child: ChunkyButton(
                                label: 'Restart',
                                leading: const GameIcon('replay', size: 26),
                                fontSize: 18,
                                expand: true,
                                color:
                                    Color.lerp(theme.sheet, Colors.white, 0.2),
                                onPressed: () async {
                                  if (await _confirmRestart(context) &&
                                      context.mounted) {
                                    Navigator.pop(context);
                                    onRestart();
                                  }
                                },
                              ),
                            ),
                          if (onRestart != null && onHome != null)
                            const SizedBox(width: 12),
                          if (onHome != null)
                            Expanded(
                              child: ChunkyButton(
                                label: 'Home',
                                leading: const GameIcon('home', size: 26),
                                fontSize: 18,
                                expand: true,
                                color:
                                    Color.lerp(theme.sheet, Colors.white, 0.2),
                                onPressed: () {
                                  Navigator.pop(context);
                                  onHome();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    const SizedBox(height: 12),
                    _Row(
                      icon: Icons.palette_rounded,
                      label: 'Theme',
                      trailing: Text(
                        GameTheme.byId(settings.themeId).name,
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                      onTap: () => showThemePicker(context,
                          settings: settings, sfx: sfx),
                    ),
                    _Row(
                      icon: Icons.help_outline_rounded,
                      label: 'How to play',
                      onTap: () => showHowToPlay(context),
                    ),
                    if (!purchases.adsRemoved)
                      _Row(
                        icon: Icons.block_rounded,
                        label: 'Remove ads',
                        trailing: Text(
                          purchases.price ?? '',
                          style: TextStyle(
                              color: theme.accent, fontWeight: FontWeight.w900),
                        ),
                        onTap: () => showRemoveAdsOffer(context, app),
                      )
                    else
                      const _Row(
                        icon: Icons.verified_rounded,
                        label: 'Ads removed. Thank you!',
                        trailing: SizedBox.shrink(),
                        onTap: null,
                      ),
                    _Row(
                      icon: Icons.restore_rounded,
                      label: 'Restore purchases',
                      onTap: () async {
                        await purchases.restore();
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(SnackBar(
                          content: Text(purchases.error ??
                              (purchases.adsRemoved
                                  ? 'Ads are removed.'
                                  : 'No purchases to restore.')),
                        ));
                      },
                    ),
                    if (app.ads.privacyOptionsRequired)
                      _Row(
                        icon: Icons.manage_accounts_rounded,
                        label: 'Ad privacy choices',
                        onTap: app.ads.showPrivacyOptions,
                      ),
                    _Row(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy policy',
                      trailing: const Icon(Icons.open_in_new_rounded,
                          color: Colors.white54, size: 20),
                      onTap: () => launchUrl(
                        Uri.parse(AppConfig.privacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<bool> _confirmRestart(BuildContext context) => showConfirmDialog(
      context,
      icon: Icons.refresh_rounded,
      title: 'Restart?',
      message: 'Your current score will be lost.',
      confirmLabel: 'Restart',
      iconColor: const Color(0xFFFF8A00),
    );

/// Asks before throwing away a game in progress.
Future<bool> confirmNewGame(BuildContext context) => showConfirmDialog(
      context,
      icon: Icons.add_rounded,
      title: 'New game?',
      message: 'Your unfinished game will be lost.',
      confirmLabel: 'Start',
    );

class _Row extends StatelessWidget {
  const _Row(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.trailing});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _rowIcon(icon),
      title: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      onTap: onTap,
    );
  }
}

/// A round on/off button with a label, for sound, music and vibration.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.on,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool on;
  final Widget icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on
                    ? accent.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.25),
                border:
                    Border.all(color: on ? accent : Colors.white24, width: 2.5),
              ),
              child: Center(child: Opacity(opacity: on ? 1 : 0.4, child: icon)),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : Colors.white54,
              ),
            ),
            Text(
              on ? 'On' : 'Off',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? accent : Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

void showHowToPlay(BuildContext context) {
  final theme = GameTheme.of(context);
  Widget rule(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 15, height: 1.3))),
          ],
        ),
      );

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.sheet,
      title: const Text('How to play',
          style: TextStyle(fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            rule(Icons.pan_tool_alt_rounded,
                'Drag the pieces onto the 8×8 board.'),
            rule(Icons.grid_on_rounded,
                'Fill a whole row or column to clear it. Clearing several lines at once scores much more.'),
            rule(Icons.local_fire_department_rounded,
                'Keep clearing lines to build a combo. The dots show how many moves you have left to keep it going.'),
            rule(Icons.auto_awesome_rounded,
                'Empty the whole board for an All Clear bonus.'),
            rule(Icons.block_rounded,
                'Pieces in grey cannot fit anywhere. The game ends when none of your pieces fit.'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.button),
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

/// Illustrated icons for the rows that have one; Material icons otherwise.
final Map<IconData, String> _rowArt = {
  Icons.music_note_rounded: 'music',
  Icons.help_outline_rounded: 'info',
  Icons.block_rounded: 'remove_ads',
  Icons.refresh_rounded: 'replay',
  Icons.home_rounded: 'home',
};

Widget _rowIcon(IconData icon) {
  final art = _rowArt[icon];
  return art != null
      ? GameIcon(art, size: 30)
      : Icon(icon, color: Colors.white, size: 26);
}
