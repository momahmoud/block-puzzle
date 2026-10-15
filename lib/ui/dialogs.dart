import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// A game-styled yes/no dialog: a round icon badge on top, a chunky title,
/// a short message and two chunky buttons. Pops in with a little bounce.
/// Completes with true if the player confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Color? iconColor,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, __) => _ConfirmDialog(
      icon: icon,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      iconColor: iconColor,
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.8, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
  return result == true;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    final badge = iconColor ?? theme.button;
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
                GameCard(
                  padding: const EdgeInsets.fromLTRB(22, 52, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedText(title, size: 28),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, height: 1.3, color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ChunkyButton(
                              label: cancelLabel,
                              fontSize: 18,
                              expand: true,
                              color: Color.lerp(theme.sheet, Colors.white, 0.2),
                              onPressed: () => Navigator.pop(context, false),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChunkyButton(
                              label: confirmLabel,
                              fontSize: 18,
                              expand: true,
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -34,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(badge, Colors.white, 0.2)!, badge],
                      ),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black38,
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 36),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
