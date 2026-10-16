import 'dart:math';

import 'package:flutter/material.dart';

/// Bộ icon vẽ bằng code cho HUD và các nút tình huống (không dùng Material
/// Icons): nét tròn đầu, cùng khung 24×24.
enum RoadGlyph {
  cup,
  uTurn,
  pump,
  bottle,
  tire,
  tireFlat,
  wrench,
  phone,
  scooter,
  walker,
  tilt,
  raincoat,
  rain,
  drop,
  whistle,
  warning,

  /// Vô-lăng: chuyển sang góc nhìn ghế lái.
  steering,

  /// Bản đồ nhìn từ trên: chuyển về góc nhìn trên cao.
  aerial,

  /// Bông hoa đào năm cánh (cành đào buộc sau xe).
  blossom,

  /// Sương mù: mấy vệt ngang mờ.
  fog,

  /// Nhiệt kế (trời rét): ống thuỷ tinh, bầu thuỷ ngân, vạch chia.
  thermometer,

  /// Máy đo nồng độ cồn cầm tay: thân, màn hình, ống thổi, hơi thở.
  breathalyzer,

  /// Tắc đường: ba xe nối đuôi nhau (nhìn từ phía sau), đèn phanh đỏ.
  jam,
}

class RoadIcon extends StatelessWidget {
  const RoadIcon(this.glyph, {super.key, required this.size, required this.color, this.accent});

  final RoadGlyph glyph;
  final double size;
  final Color color;

  /// Màu phụ (chất lỏng trong chai, kính điện thoại…), mặc định nhạt hơn màu chính.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: RoadIconPainter(glyph, color, accent ?? color.withValues(alpha: 0.45))),
    );
  }
}

class RoadIconPainter extends CustomPainter {
  const RoadIconPainter(this.glyph, this.color, this.accent);

  final RoadGlyph glyph;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final fill = Paint()..color = color;
    final soft = Paint()..color = accent;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case RoadGlyph.cup:
        canvas.drawPath(
          Path()
            ..moveTo(3, 10)
            ..lineTo(17.5, 10)
            ..lineTo(15.5, 22)
            ..lineTo(5, 22)
            ..close(),
          fill,
        );
        canvas.drawArc(const Rect.fromLTWH(14.5, 11.5, 7, 6.5), -pi / 2, pi, false, stroke);
        for (final x in [7.5, 12.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 7.5)
              ..quadraticBezierTo(x - 2, 4.8, x, 1.5),
            stroke,
          );
        }
      case RoadGlyph.uTurn:
        canvas.drawPath(
          Path()
            ..moveTo(17, 22.5)
            ..lineTo(17, 10)
            ..arcToPoint(const Offset(7, 10), radius: const Radius.circular(5), clockwise: false)
            ..lineTo(7, 15),
          stroke..strokeWidth = 3,
        );
        canvas.drawPath(Path()..addPolygon(const [Offset(1.5, 13.5), Offset(12.5, 13.5), Offset(7, 22)], true), fill);
      case RoadGlyph.pump:
        canvas.drawRRect(RRect.fromLTRBR(3.5, 3, 14.5, 21.5, const Radius.circular(2.2)), fill);
        canvas.drawRRect(RRect.fromLTRBR(5.8, 5.4, 12.2, 10.2, const Radius.circular(1)), soft);
        canvas.drawLine(const Offset(2, 22), const Offset(16, 22), stroke..strokeWidth = 2);
        canvas.drawPath(
          Path()
            ..moveTo(14.5, 8)
            ..lineTo(17.5, 8)
            ..quadraticBezierTo(19.5, 8, 19.5, 10.5)
            ..lineTo(19.5, 16.5)
            ..quadraticBezierTo(19.5, 18.5, 21, 18.5)
            ..quadraticBezierTo(22.5, 18.5, 22.5, 16.5)
            ..lineTo(22.5, 6.5),
          stroke..strokeWidth = 1.8,
        );
        canvas.drawLine(const Offset(22.5, 6.5), const Offset(20.5, 3.5), stroke);
      case RoadGlyph.bottle:
        canvas.drawRRect(RRect.fromLTRBR(9.5, 1.5, 14.5, 5.5, const Radius.circular(1)), fill);
        final body = Path()
          ..moveTo(10, 5.5)
          ..lineTo(14, 5.5)
          ..lineTo(14, 8)
          ..quadraticBezierTo(18, 9.5, 18, 13)
          ..lineTo(18, 20.5)
          ..quadraticBezierTo(18, 22.5, 16, 22.5)
          ..lineTo(8, 22.5)
          ..quadraticBezierTo(6, 22.5, 6, 20.5)
          ..lineTo(6, 13)
          ..quadraticBezierTo(6, 9.5, 10, 8)
          ..close();
        canvas.drawPath(body, stroke..strokeWidth = 1.8);
        canvas.save();
        canvas.clipPath(body);
        canvas.drawRect(const Rect.fromLTRB(5, 13.5, 19, 23), fill);
        canvas.restore();
      case RoadGlyph.tire:
      case RoadGlyph.tireFlat:
        final flat = glyph == RoadGlyph.tireFlat;
        final outer = flat ? const Rect.fromLTRB(2, 4.5, 22, 22) : const Rect.fromLTRB(2.5, 2.5, 21.5, 21.5);
        final rim = RRect.fromRectAndCorners(
          outer,
          topLeft: const Radius.circular(10),
          topRight: const Radius.circular(10),
          bottomLeft: Radius.circular(flat ? 4 : 10),
          bottomRight: Radius.circular(flat ? 4 : 10),
        );
        canvas.drawRRect(rim, fill);
        canvas.drawCircle(Offset(12, flat ? 13.5 : 12), 5.2, soft);
        canvas.drawCircle(Offset(12, flat ? 13.5 : 12), 2.2, fill);
        if (flat) {
          canvas.drawLine(const Offset(5, 1.8), const Offset(8, 3.4), stroke..strokeWidth = 1.6);
          canvas.drawLine(const Offset(12, 0.8), const Offset(12, 3), stroke);
          canvas.drawLine(const Offset(19, 1.8), const Offset(16, 3.4), stroke);
        }
      case RoadGlyph.wrench:
        canvas.drawLine(const Offset(5, 19), const Offset(14.5, 9.5), stroke..strokeWidth = 3.6);
        // Đầu cờ lê: hình tròn khoét miệng ngàm.
        canvas.drawPath(
          Path.combine(
            PathOperation.difference,
            Path()..addOval(Rect.fromCircle(center: const Offset(16.5, 7.5), radius: 5.5)),
            Path()..addPolygon(const [Offset(16.5, 7.5), Offset(23, 1), Offset(24, 6.5)], true),
          ),
          fill,
        );
      case RoadGlyph.phone:
        canvas.drawRRect(RRect.fromLTRBR(6, 1.5, 18, 22.5, const Radius.circular(3)), fill);
        canvas.drawRRect(RRect.fromLTRBR(8, 4.5, 16, 17.5, const Radius.circular(1)), soft);
        canvas.drawCircle(const Offset(12, 20), 1.1, soft);
        for (final r in [3.5, 6.0]) {
          canvas.drawArc(Rect.fromCircle(center: const Offset(19, 5), radius: r), -pi / 2.2, pi / 2.6, false, stroke..strokeWidth = 1.5);
        }
      case RoadGlyph.scooter:
        _scooter(canvas, fill, stroke);
      case RoadGlyph.walker:
        canvas.save();
        canvas.translate(4, 2);
        canvas.scale(0.8);
        _scooter(canvas, fill, stroke);
        canvas.restore();
        canvas.drawCircle(const Offset(4.5, 4), 2.3, fill);
        canvas.drawLine(const Offset(4.5, 7), const Offset(5, 14), stroke..strokeWidth = 2.4);
        canvas.drawLine(const Offset(5, 14), const Offset(2.5, 21.5), stroke);
        canvas.drawLine(const Offset(5, 14), const Offset(8, 21.5), stroke);
        canvas.drawLine(const Offset(4.8, 9), const Offset(10, 9.5), stroke);
      case RoadGlyph.tilt:
        canvas.save();
        canvas.translate(12, 13);
        canvas.rotate(-0.42);
        canvas.translate(-12, -13);
        _scooter(canvas, fill, stroke);
        canvas.restore();
        canvas.drawPath(
          Path()
            ..moveTo(19.5, 2)
            ..quadraticBezierTo(23, 6.5, 19.5, 8.5)
            ..quadraticBezierTo(16, 6.5, 19.5, 2),
          soft..color = accent.withValues(alpha: 1),
        );
      case RoadGlyph.raincoat:
        canvas.drawCircle(const Offset(12, 5.5), 3.6, fill);
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 8)
            ..lineTo(16.5, 8)
            ..lineTo(22.5, 20.5)
            ..quadraticBezierTo(12, 23.5, 1.5, 20.5)
            ..close(),
          fill,
        );
        canvas.drawLine(const Offset(12, 10.5), const Offset(12, 20), stroke
          ..color = accent
          ..strokeWidth = 1.4);
      case RoadGlyph.rain:
        final cloud = Path()
          ..addOval(const Rect.fromLTWH(2, 6, 9, 9))
          ..addOval(const Rect.fromLTWH(6.5, 2, 11, 11))
          ..addOval(const Rect.fromLTWH(13, 6, 9, 9))
          ..addRRect(RRect.fromLTRBR(4, 10, 20, 15, const Radius.circular(2.5)));
        canvas.drawPath(cloud, fill);
        for (final x in [7.0, 12.0, 17.0]) {
          canvas.drawLine(Offset(x, 17.5), Offset(x - 1.6, 22), stroke
            ..color = accent.withValues(alpha: 1)
            ..strokeWidth = 1.8);
        }
      case RoadGlyph.drop:
        canvas.drawPath(
          Path()
            ..moveTo(12, 2)
            ..quadraticBezierTo(20, 11.5, 19, 15.5)
            ..arcToPoint(const Offset(5, 15.5), radius: const Radius.circular(7))
            ..quadraticBezierTo(4, 11.5, 12, 2),
          fill,
        );
        canvas.drawArc(const Rect.fromLTWH(7.5, 11, 6, 6), pi * 0.55, pi * 0.6, false, stroke
          ..color = accent
          ..strokeWidth = 1.5);
      case RoadGlyph.whistle:
        canvas.drawCircle(const Offset(9, 14.5), 6.5, fill);
        canvas.drawRRect(RRect.fromLTRBR(9, 8, 22.5, 13, const Radius.circular(1.5)), fill);
        canvas.drawCircle(const Offset(9, 14.5), 2.4, soft);
        canvas.drawLine(const Offset(14, 3), const Offset(15.5, 5.5), stroke..strokeWidth = 1.6);
        canvas.drawLine(const Offset(19, 2), const Offset(19, 5), stroke);
      case RoadGlyph.warning:
        canvas.drawPath(
          Path()
            ..moveTo(12, 2)
            ..lineTo(22.5, 21)
            ..lineTo(1.5, 21)
            ..close(),
          fill,
        );
        canvas.drawLine(const Offset(12, 8.5), const Offset(12, 14), stroke
          ..color = accent
          ..strokeWidth = 2.4);
        canvas.drawCircle(const Offset(12, 17.5), 1.3, soft);
      case RoadGlyph.jam:
        final glass = Paint()..color = const Color(0x991B1D22);
        for (final (l, t, r, b) in [(7.5, 2.0, 16.5, 7.5), (5.0, 8.0, 19.0, 14.5), (2.5, 15.0, 21.5, 23.0)]) {
          canvas.drawRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular((b - t) * 0.3)), fill);
          canvas.drawRRect(RRect.fromLTRBR(l + (r - l) * 0.18, t + (b - t) * 0.14, r - (r - l) * 0.18, t + (b - t) * 0.46, const Radius.circular(1)), glass);
        }
        canvas.drawCircle(const Offset(5.5, 19.5), 1.7, soft);
        canvas.drawCircle(const Offset(18.5, 19.5), 1.7, soft);
      case RoadGlyph.blossom:
        for (var i = 0; i < 5; i++) {
          final a = -pi / 2 + i * 2 * pi / 5;
          canvas.drawCircle(Offset(12 + cos(a) * 5.6, 12 + sin(a) * 5.6), 4.4, fill);
        }
        canvas.drawCircle(const Offset(12, 12), 2.6, soft);
      case RoadGlyph.fog:
        for (final (y, x0, x1) in [(6.0, 4.0, 18.0), (11.0, 2.0, 22.0), (16.0, 6.0, 20.0), (21.0, 3.0, 15.0)]) {
          canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke..strokeWidth = 2.4);
        }
      case RoadGlyph.thermometer:
        canvas.drawRRect(RRect.fromLTRBR(7.4, 1.6, 13.6, 16.5, const Radius.circular(3.1)), stroke..strokeWidth = 1.8);
        canvas.drawCircle(const Offset(10.5, 18.6), 4.4, fill);
        canvas.drawRRect(RRect.fromLTRBR(9.3, 8.5, 11.7, 18, const Radius.circular(1.2)), fill);
        canvas.drawCircle(const Offset(9.4, 17.6), 1.3, soft);
        for (final y in [4.5, 8.0, 11.5]) {
          canvas.drawLine(Offset(16.6, y), Offset(20, y), stroke..strokeWidth = 1.6);
        }
      case RoadGlyph.breathalyzer:
        canvas.drawRRect(RRect.fromLTRBR(8, 7.5, 18.5, 23, const Radius.circular(2.6)), fill);
        canvas.drawRRect(RRect.fromLTRBR(10, 10, 16.5, 14.8, const Radius.circular(1)), soft);
        canvas.drawCircle(const Offset(13.25, 19), 1.5, soft);
        canvas.drawLine(const Offset(13, 7.5), const Offset(9.8, 2.2), stroke..strokeWidth = 3);
        for (final (y, x) in [(4.0, 1.5), (7.5, 2.5)]) {
          canvas.drawLine(Offset(x, y + 1.2), Offset(x + 4.2, y), stroke..strokeWidth = 1.4);
        }
      case RoadGlyph.steering:
        canvas.drawCircle(const Offset(12, 12), 9.2, stroke..strokeWidth = 2.6);
        canvas.drawCircle(const Offset(12, 13), 2.6, fill);
        canvas.drawLine(const Offset(3.2, 11.5), const Offset(9.6, 12.4), stroke..strokeWidth = 2.4);
        canvas.drawLine(const Offset(20.8, 11.5), const Offset(14.4, 12.4), stroke);
        canvas.drawLine(const Offset(12, 15.4), const Offset(12, 21), stroke);
      case RoadGlyph.aerial:
        // Đoạn đường cong nhìn từ trên với vạch giữa và chiếc xe nhỏ.
        canvas.drawPath(
          Path()
            ..moveTo(7, 23)
            ..cubicTo(7, 14, 15, 11, 15, 1)
            ..lineTo(21, 1)
            ..cubicTo(21, 13, 13, 15, 13, 23)
            ..close(),
          soft,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10, 23)
            ..cubicTo(10, 14, 18, 12, 18, 1),
          stroke
            ..strokeWidth = 1.4
            ..color = color,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 7, 5, 8), const Radius.circular(1.5)), fill);
    }
  }

  /// Xe máy nhìn ngang: hai bánh, thân, yên, ghi-đông.
  void _scooter(Canvas canvas, Paint fill, Paint stroke) {
    final s = stroke..strokeWidth = 2;
    canvas.drawCircle(const Offset(5.5, 18), 3.3, s);
    canvas.drawCircle(const Offset(18.5, 18), 3.3, s);
    canvas.drawPath(
      Path()
        ..moveTo(2.5, 14.5)
        ..quadraticBezierTo(3, 10.5, 7.5, 10.5)
        ..lineTo(11, 10.5)
        ..lineTo(11.5, 15)
        ..lineTo(15.5, 15)
        ..lineTo(17, 8)
        ..lineTo(18.5, 8)
        ..lineTo(19.5, 14.5)
        ..lineTo(9, 16.5)
        ..lineTo(4, 16.5)
        ..close(),
      fill,
    );
    canvas.drawRRect(RRect.fromLTRBR(4, 8, 11, 10, const Radius.circular(1)), fill);
    canvas.drawLine(const Offset(17.5, 8), const Offset(16.5, 4.5), s);
    canvas.drawLine(const Offset(15, 4.5), const Offset(19, 4.5), s);
  }

  @override
  bool shouldRepaint(RoadIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color || oldDelegate.accent != accent;
}
