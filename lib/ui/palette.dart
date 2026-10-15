import 'package:flutter/material.dart';

const Color kGameOverGrey = Color(0xFF6B7391);
const Color kGold = Color(0xFFFFD25A);

Color _lighten(Color c, double f) => Color.lerp(c, Colors.white, f)!;
Color _darken(Color c, double f) => Color.lerp(c, Colors.black, f)!;

/// Draws one bevelled block: a light rim on top, a dark lip at the bottom,
/// a flat face and a small shine.
void paintBlock(Canvas canvas, Rect cellRect, Color color, {double scale = 1}) {
  var rect = cellRect.deflate(cellRect.width * 0.03);
  if (scale != 1) {
    rect = Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
  }
  if (rect.width <= 0) return;
  final s = rect.width;
  final radius = Radius.circular(s * 0.16);
  final alpha = color.a;

  // Dark lip along the bottom edge.
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, radius),
    Paint()..color = _darken(color, 0.32).withValues(alpha: alpha),
  );
  // Light rim.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - s * 0.08),
      radius,
    ),
    Paint()..color = _lighten(color, 0.35).withValues(alpha: alpha),
  );
  // Face.
  final inset = s * 0.12;
  final face = Rect.fromLTRB(
    rect.left + inset,
    rect.top + inset,
    rect.right - inset,
    rect.bottom - inset * 1.25,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(face, Radius.circular(s * 0.1)),
    Paint()..color = color,
  );
  // Shine.
  final shine = Rect.fromLTRB(
    face.left + inset * 0.5,
    face.top + inset * 0.3,
    face.right - inset * 0.5,
    face.top + inset * 1.15,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(shine, Radius.circular(shine.height / 2)),
    Paint()..color = Colors.white.withValues(alpha: 0.3 * alpha),
  );
}

/// Draws one empty board square, slightly sunken.
void paintEmpty(Canvas canvas, Rect cellRect, Color color) {
  final rect = cellRect.deflate(cellRect.width * 0.03);
  final radius = Radius.circular(rect.width * 0.14);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, radius),
    Paint()..color = _darken(color, 0.25),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(
          rect.left, rect.top + rect.height * 0.06, rect.right, rect.bottom),
      radius,
    ),
    Paint()..color = color,
  );
}

/// Draws a faceted gem centred in [cellRect].
void paintGem(Canvas canvas, Rect cellRect,
    {double scale = 1, double alpha = 1}) {
  final s = cellRect.width * 0.62 * scale;
  final c = cellRect.center.translate(0, -cellRect.height * 0.03);
  final top = c.translate(0, -s * 0.5);
  final bottom = c.translate(0, s * 0.5);
  final left = c.translate(-s * 0.5, -s * 0.08);
  final right = c.translate(s * 0.5, -s * 0.08);
  final midL = c.translate(-s * 0.2, -s * 0.08);
  final midR = c.translate(s * 0.2, -s * 0.08);

  Paint fill(int argb) => Paint()..color = Color(argb).withValues(alpha: alpha);

  // Shadow, then the facets.
  canvas.drawPath(
    Path()
      ..moveTo(top.dx, top.dy + s * 0.08)
      ..lineTo(right.dx, right.dy + s * 0.08)
      ..lineTo(bottom.dx, bottom.dy + s * 0.08)
      ..lineTo(left.dx, left.dy + s * 0.08)
      ..close(),
    fill(0x55000000),
  );
  canvas.drawPath(
      Path()..addPolygon([left, midL, bottom], true), fill(0xFF1FA9D6));
  canvas.drawPath(
      Path()..addPolygon([midL, midR, bottom], true), fill(0xFF4FD8F5));
  canvas.drawPath(
      Path()..addPolygon([midR, right, bottom], true), fill(0xFF1789B8));
  canvas.drawPath(
      Path()..addPolygon([top, left, midL], true), fill(0xFFB8F3FF));
  canvas.drawPath(
      Path()..addPolygon([top, midL, midR], true), fill(0xFFFFFFFF));
  canvas.drawPath(
      Path()..addPolygon([top, midR, right], true), fill(0xFF8BE6FA));
}

/// Draws a sheet of ice over a block.
void paintIce(Canvas canvas, Rect cellRect, {double alpha = 1}) {
  final rect = cellRect.deflate(cellRect.width * 0.03);
  final s = rect.width;
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.16));
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFE8FAFF).withValues(alpha: 0.6 * alpha),
          const Color(0xFFA8DEFF).withValues(alpha: 0.35 * alpha),
        ],
      ).createShader(rect),
  );
  canvas.drawRRect(
    rrect.deflate(s * 0.04),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..color = Colors.white.withValues(alpha: 0.85 * alpha),
  );
  // Frost streaks.
  final streak = Paint()
    ..strokeWidth = s * 0.06
    ..strokeCap = StrokeCap.round
    ..color = Colors.white.withValues(alpha: 0.9 * alpha);
  canvas.drawLine(rect.topLeft + Offset(s * 0.22, s * 0.5),
      rect.topLeft + Offset(s * 0.5, s * 0.22), streak);
  canvas.drawLine(rect.topLeft + Offset(s * 0.4, s * 0.72),
      rect.topLeft + Offset(s * 0.72, s * 0.4), streak..strokeWidth = s * 0.04);
}

/// Draws one shard of broken ice, centred on the origin.
void paintIceShard(Canvas canvas, double size, double alpha) {
  canvas.drawPath(
    Path()
      ..moveTo(0, -size * 0.6)
      ..lineTo(size * 0.45, size * 0.4)
      ..lineTo(-size * 0.4, size * 0.3)
      ..close(),
    Paint()..color = const Color(0xFFDDF6FF).withValues(alpha: alpha),
  );
}
