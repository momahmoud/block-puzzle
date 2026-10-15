import 'package:flutter/material.dart';

import '../services/settings.dart';
import '../services/sfx.dart';
import 'palette.dart';
import 'theme.dart';

/// A sheet listing every theme with a small preview.
Future<void> showThemePicker(BuildContext context,
    {required Settings settings, required Sfx sfx}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameTheme.of(context).sheet,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Themes',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
                children: [
                  for (final theme in GameTheme.all)
                    _ThemeCard(
                      theme: theme,
                      selected: theme.id == settings.themeId,
                      onTap: () {
                        sfx.tap();
                        settings.themeId = theme.id;
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(
      {required this.theme, required this.selected, required this.onTap});

  final GameTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.name} theme',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: theme.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 3 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: theme.accent.withValues(alpha: 0.5),
                        blurRadius: 14)
                  ]
                : const [],
          ),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(painter: _PreviewPainter(theme)),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 15),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      theme.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 4x4 mini board showing the theme's blocks.
class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.theme);

  final GameTheme theme;

  static const _layout = [
    [1, 1, 0, 5],
    [0, 3, 3, 5],
    [7, 0, 4, 4],
    [7, 6, 6, 2],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          (Offset.zero & size).inflate(3), const Radius.circular(10)),
      Paint()..color = theme.board,
    );
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        final id = _layout[r][c];
        id == 0
            ? paintEmpty(canvas, rect, theme.emptyCell)
            : paintBlock(canvas, rect, theme.block(id));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => old.theme != theme;
}
