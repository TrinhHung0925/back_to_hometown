import 'dart:math';

import 'package:flutter/material.dart';

import '../game/logic/missions.dart';
import '../resource/app_colors.dart';
import '../screen/game/road_icons.dart';
import 'lixi_icon.dart';

/// Icon vẽ bằng code cho cửa hàng và nhiệm vụ phụ (cùng khung 24×24, nét
/// tròn đầu như RoadGlyph).
enum ShopGlyph {
  /// Sạp hàng có mái hiên sọc (nút Cửa hàng).
  stall,

  /// Hộp quà thắt nơ.
  gift,

  /// Đồng hồ (nhiệm vụ tới nơi đúng giờ).
  clock,

  /// Hai xe húc nhau, tia va chạm.
  bump,

  /// Hai người (khách xe khách).
  people,

  /// Dấu tích / dấu gạch chéo (xong / hỏng).
  check,
  cross,

  /// Trái tim (món người nhà ưng nhất).
  heart,

  /// Cờ đích (nhiệm vụ phụ).
  flag,
}

class ShopIcon extends StatelessWidget {
  const ShopIcon(this.glyph, {super.key, required this.size, required this.color, this.accent});

  final ShopGlyph glyph;
  final double size;
  final Color color;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShopGlyphPainter(glyph, color, accent ?? color.withValues(alpha: 0.45))),
    );
  }
}

class _ShopGlyphPainter extends CustomPainter {
  const _ShopGlyphPainter(this.glyph, this.color, this.accent);

  final ShopGlyph glyph;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final fill = Paint()..color = color;
    final soft = Paint()..color = accent;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case ShopGlyph.stall:
        // Mái hiên sọc lượn vỏ sò, quầy hàng, hai cột.
        final awning = Path()..moveTo(2, 8.5);
        for (var i = 0; i < 4; i++) {
          awning.arcToPoint(Offset(2 + (i + 1) * 5, 8.5), radius: const Radius.circular(2.6), clockwise: false);
        }
        awning
          ..lineTo(20, 4)
          ..lineTo(4, 4)
          ..close();
        canvas.drawPath(awning, fill);
        for (var i = 0; i < 2; i++) {
          canvas.drawRect(Rect.fromLTWH(6.5 + i * 7, 4, 3.4, 4.6), soft);
        }
        canvas.drawLine(const Offset(4.5, 10.5), const Offset(4.5, 21), stroke..strokeWidth = 1.8);
        canvas.drawLine(const Offset(19.5, 10.5), const Offset(19.5, 21), stroke);
        canvas.drawRRect(RRect.fromLTRBR(3, 14.5, 21, 21, const Radius.circular(1.6)), fill);
        canvas.drawRRect(RRect.fromLTRBR(6.5, 16.5, 11, 19, const Radius.circular(0.8)), soft);
        canvas.drawRRect(RRect.fromLTRBR(13, 16.5, 17.5, 19, const Radius.circular(0.8)), soft);
      case ShopGlyph.gift:
        canvas.drawRRect(RRect.fromLTRBR(3, 10, 21, 22, const Radius.circular(2)), fill);
        canvas.drawRRect(RRect.fromLTRBR(2, 7, 22, 11.5, const Radius.circular(1.6)), fill);
        canvas.drawRect(const Rect.fromLTWH(10.5, 7, 3, 15), soft);
        canvas.drawPath(
          Path()
            ..moveTo(12, 7)
            ..cubicTo(8, 1, 3.5, 4, 7, 7)
            ..moveTo(12, 7)
            ..cubicTo(16, 1, 20.5, 4, 17, 7),
          stroke..strokeWidth = 1.9,
        );
      case ShopGlyph.clock:
        canvas.drawCircle(const Offset(12, 13), 9.5, fill);
        canvas.drawCircle(const Offset(12, 13), 7.4, soft);
        canvas.drawLine(const Offset(12, 13), const Offset(12, 8), stroke..strokeWidth = 2);
        canvas.drawLine(const Offset(12, 13), const Offset(15.5, 14.5), stroke);
        canvas.drawLine(const Offset(9.5, 2), const Offset(14.5, 2), stroke..strokeWidth = 2.4);
      case ShopGlyph.bump:
        // Hai xe nhìn từ trên húc nhau, tia sáng ở chỗ va.
        canvas.save();
        canvas.translate(6.5, 15);
        canvas.rotate(0.5);
        canvas.drawRRect(RRect.fromLTRBR(-4.5, -3, 4.5, 3, const Radius.circular(1.6)), fill);
        canvas.restore();
        canvas.save();
        canvas.translate(17.5, 15);
        canvas.rotate(-0.5);
        canvas.drawRRect(RRect.fromLTRBR(-4.5, -3, 4.5, 3, const Radius.circular(1.6)), fill);
        canvas.restore();
        for (var i = 0; i < 5; i++) {
          final a = -pi / 2 + (i - 2) * 0.55;
          canvas.drawLine(Offset(12 + cos(a) * 3, 9 + sin(a) * 3), Offset(12 + cos(a) * 6.5, 9 + sin(a) * 6.5), stroke
            ..color = accent.withValues(alpha: 1)
            ..strokeWidth = 1.7);
        }
      case ShopGlyph.people:
        canvas.drawCircle(const Offset(8, 7), 3.4, fill);
        canvas.drawPath(Path()..addRRect(RRect.fromLTRBR(2, 12, 14, 22, const Radius.circular(5))), fill);
        canvas.drawCircle(const Offset(16.5, 8.5), 3, soft);
        canvas.drawPath(Path()..addRRect(RRect.fromLTRBR(12, 13, 22, 22, const Radius.circular(4.5))), soft);
      case ShopGlyph.check:
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 12.5)
            ..lineTo(10, 18)
            ..lineTo(19.5, 6.5),
          stroke..strokeWidth = 3.2,
        );
      case ShopGlyph.cross:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), stroke..strokeWidth = 3.2);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), stroke);
      case ShopGlyph.heart:
        canvas.drawPath(
          Path()
            ..moveTo(12, 21)
            ..cubicTo(2, 14, 1.5, 8, 4.5, 5.2)
            ..cubicTo(7.5, 2.6, 11, 4.4, 12, 7)
            ..cubicTo(13, 4.4, 16.5, 2.6, 19.5, 5.2)
            ..cubicTo(22.5, 8, 22, 14, 12, 21),
          fill,
        );
        canvas.drawCircle(const Offset(7.6, 8.4), 1.6, soft);
      case ShopGlyph.flag:
        canvas.drawLine(const Offset(5, 3), const Offset(5, 22), stroke..strokeWidth = 2.2);
        final cell = Paint()..color = accent;
        canvas.drawRect(const Rect.fromLTWH(5, 3, 15, 10), fill);
        for (var r = 0; r < 2; r++) {
          for (var c = 0; c < 3; c++) {
            if ((r + c).isEven) canvas.drawRect(Rect.fromLTWH(5 + c * 5, 3 + r * 5, 5, 5), cell);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_ShopGlyphPainter old) => old.glyph != glyph || old.color != color || old.accent != accent;
}

/// Icon của một loại nhiệm vụ phụ.
class MissionIcon extends StatelessWidget {
  const MissionIcon(this.kind, {super.key, required this.size, this.color = AppColors.ff1B1D22});

  final MissionKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      MissionKind.noFine => RoadIcon(RoadGlyph.whistle, size: size, color: color, accent: AppColors.ffFFFFFF),
      MissionKind.noCrash => ShopIcon(ShopGlyph.bump, size: size, color: color, accent: AppColors.ffEE9B2F),
      MissionKind.restStop => RoadIcon(RoadGlyph.cup, size: size, color: color, accent: AppColors.ffEE9B2F),
      MissionKind.hitchhiker => RoadIcon(RoadGlyph.walker, size: size, color: color),
      MissionKind.onTime => ShopIcon(ShopGlyph.clock, size: size, color: color, accent: AppColors.ffFFFFFF),
      MissionKind.keepPeach => RoadIcon(RoadGlyph.blossom, size: size, color: AppColors.ffE8768F, accent: AppColors.ffFFD166),
      MissionKind.passengers => ShopIcon(ShopGlyph.people, size: size, color: color, accent: color.withValues(alpha: 0.5)),
      MissionKind.collectLixi => SizedBox(width: size, height: size, child: Center(child: LixiIcon(height: size * 0.92))),
    };
  }
}
