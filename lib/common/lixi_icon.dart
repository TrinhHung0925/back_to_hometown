import 'package:flutter/material.dart';

import '../resource/app_colors.dart';

/// Phong bao lì xì vẽ bằng code (cùng kiểu với lì xì trong game).
class LixiIcon extends StatelessWidget {
  const LixiIcon({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(height * 0.7, height), painter: _LixiPainter());
  }
}

class _LixiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()..color = AppColors.ff1B1D22;
    final red = Paint()..color = AppColors.ffD62828;
    final gold = Paint()..color = AppColors.ffFFD166;
    final r = Rect.fromLTWH(w * 0.08, h * 0.06, w * 0.84, h * 0.88);
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(w * 0.08), Radius.circular(w * 0.22)), outline);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(w * 0.16)), red);
    canvas.drawRect(Rect.fromLTWH(r.left + w * 0.1, r.top + h * 0.2, r.width - w * 0.2, h * 0.09), gold);
    canvas.drawCircle(Offset(w / 2, h * 0.6), w * 0.22, gold);
    canvas.drawCircle(Offset(w / 2, h * 0.6), w * 0.1, red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
