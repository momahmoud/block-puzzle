import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/settings.dart';
import '../services/sfx.dart';
import 'theme.dart';
import 'theme_picker.dart';
import 'widgets.dart';

/// The settings sheet. Opened from a game it is the pause menu, with
/// Resume, Restart and Home.
Future<void> showSettingsSheet(
  BuildContext context, {
  required Settings settings,
  required Sfx sfx,
  VoidCallback? onRestart,
  VoidCallback? onHome,
}) {
  final inGame = onRestart != null || onHome != null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GameTheme.of(context).sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => ListenableBuilder(
      listenable: settings,
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
                  const SizedBox(height: 12),
                  if (inGame) ...[
                    ChunkyButton(
                      label: 'Resume',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () {
                        sfx.tap();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  _SwitchRow(
                    icon: Icons.volume_up_rounded,
                    label: 'Sound',
                    value: settings.sound,
                    accent: theme.accent,
                    onChanged: (v) => settings.sound = v,
                  ),
                  _SwitchRow(
                    icon: Icons.vibration_rounded,
                    label: 'Vibration',
                    value: settings.haptics,
                    accent: theme.accent,
                    onChanged: (v) {
                      settings.haptics = v;
                      sfx.tap();
                    },
                  ),
                  _Row(
                    icon: Icons.palette_rounded,
                    label: 'Theme',
                    trailing: Text(
                      GameTheme.byId(settings.themeId).name,
                      style: const TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w700),
                    ),
                    onTap: () =>
                        showThemePicker(context, settings: settings, sfx: sfx),
                  ),
                  _Row(
                    icon: Icons.help_outline_rounded,
                    label: 'How to play',
                    onTap: () => showHowToPlay(context),
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
                  if (onRestart != null)
                    _Row(
                      icon: Icons.refresh_rounded,
                      label: 'Restart game',
                      onTap: () async {
                        if (await _confirmRestart(context) && context.mounted) {
                          Navigator.pop(context);
                          onRestart();
                        }
                      },
                    ),
                  if (onHome != null)
                    _Row(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      onTap: () {
                        Navigator.pop(context);
                        onHome();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<bool> _confirmRestart(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GameTheme.of(context).sheet,
      title:
          const Text('Restart?', style: TextStyle(fontWeight: FontWeight.w900)),
      content: const Text('Your current score will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: GameTheme.of(context).button),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restart', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Asks before throwing away a game in progress.
Future<bool> confirmNewGame(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GameTheme.of(context).sheet,
      title: const Text('Start a new game?',
          style: TextStyle(fontWeight: FontWeight.w900)),
      content: const Text('Your unfinished game will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: GameTheme.of(context).button),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('New game', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  return ok == true;
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.trailing});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      onTap: onTap,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white),
      title: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: accent,
      onChanged: onChanged,
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
