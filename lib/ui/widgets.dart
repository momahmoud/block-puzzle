import 'package:flutter/material.dart';

import 'palette.dart';
import 'theme.dart';

/// Chunky game text: a gradient fill with a dark outline.
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    required this.size,
    this.colors = const [Colors.white, Colors.white],
    this.outline,
  });

  final String text;
  final double size;
  final List<Color> colors;

  /// Defaults to the theme's outline colour.
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final outline = this.outline ?? GameTheme.of(context).outline;
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
      letterSpacing: 0.5,
    );
    return Stack(
      children: [
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
            shadows: [
              Shadow(
                  color: Colors.black38,
                  offset: Offset(0, size * 0.08),
                  blurRadius: size * 0.1)
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(bounds),
          child: Text(text, style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// A small gold crown, used next to the best score.
class CrownIcon extends StatelessWidget {
  const CrownIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.8), painter: _CrownPainter());
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.88)
      ..lineTo(0, h * 0.25)
      ..lineTo(w * 0.3, h * 0.5)
      ..lineTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.7, h * 0.5)
      ..lineTo(w, h * 0.25)
      ..lineTo(w * 0.92, h * 0.88)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE0A21C));
    canvas.drawPath(
      path.shift(Offset(0, -h * 0.06)),
      Paint()..color = kGold,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.8, w * 0.84, h * 0.16),
        Radius.circular(h * 0.05),
      ),
      Paint()..color = const Color(0xFFE0A21C),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A big rounded button with a darker lip, matching the blocks.
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
    this.subtitle,
    this.fontSize = 22,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// Fill the available width (content stays centred).
  final bool expand;

  /// Defaults to the theme's button colour.
  final Color? color;
  final IconData? icon;
  final String? subtitle;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? GameTheme.of(context).button;
    return Material(
      color: Color.lerp(color, Colors.black, 0.3),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: expand ? double.infinity : null,
          alignment: expand ? Alignment.center : null,
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: fontSize * 1.2),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round translucent icon button with a label underneath.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small number with a caption, for stats.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: Colors.white60),
        ),
      ],
    );
  }
}

/// The card used by dialogs and end-of-game screens.
class GameCard extends StatelessWidget {
  const GameCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(22)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(theme.sheet, Colors.white, 0.1)!, theme.sheet],
        ),
        borderRadius: BorderRadius.circular(30),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))
        ],
      ),
      child: child,
    );
  }
}

/// A banner title that sits across the top edge of a [GameCard].
class Ribbon extends StatelessWidget {
  const Ribbon(this.text, {super.key, required this.colors});

  final String text;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))
        ],
      ),
      child: OutlinedText(text, size: 28),
    );
  }
}

/// A small rounded stat, like "Lines 22".
class StatPill extends StatelessWidget {
  const StatPill(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}
