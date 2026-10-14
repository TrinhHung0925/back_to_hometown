import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, TextDirection;

import 'scenery_layer.dart';

/// Vẽ biển báo tròn (nhìn từ trên, mặt biển ngửa lên) dùng chung cho các lớp
/// cảnh: biển hạn chế tốc độ, cấm quay đầu, biển viết tay.
class RoadSigns {
  final Map<String, TextPainter> _text = {};

  static final Paint _shadow = Paint()..color = const Color(0x40000000);
  static final Paint _red = Paint()..color = const Color(0xffD62828);
  static final Paint _white = Paint()..color = const Color(0xffF6F6F4);
  static final Paint _ink = Paint()
    ..color = const Color(0xff1B1D22)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  static final Paint _slash = Paint()
    ..color = const Color(0xffD62828)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round;
  static final Paint _pole = Paint()..color = const Color(0xff7C8288);

  TextPainter label(String text, double size, Color color, {FontWeight weight = FontWeight.w800, String family = 'Manrope'}) =>
      _text.putIfAbsent(
        '$text|$size|${color.toARGB32()}|$family',
        () => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, color: color, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  /// Đĩa biển tròn viền đỏ, có bóng đổ và chân cột. [angle]: góc của hệ toạ
  /// độ đang vẽ (để bóng đổ đúng hướng nắng).
  void _disc(Canvas canvas, Offset center, double r, double angle) {
    canvas.drawCircle(center + toLocal(sunShadow * 1.3, angle), r, _shadow);
    canvas.drawCircle(center, r, _red);
    canvas.drawCircle(center, r * 0.76, _white);
    canvas.drawCircle(center + Offset(0, r + 3), 2.2, _pole);
  }

  /// Biển hạn chế tốc độ tối đa.
  void speedLimit(Canvas canvas, Offset center, int kmh, double angle, {double r = 13}) {
    _disc(canvas, center, r, angle);
    final t = label('$kmh', r * 0.86, const Color(0xff1B1D22));
    t.paint(canvas, center - Offset(t.width / 2, t.height / 2));
  }

  /// Biển cấm quay đầu: mũi tên chữ U đen, gạch chéo đỏ.
  void noUTurn(Canvas canvas, Offset center, double angle, {double r = 13}) {
    _disc(canvas, center, r, angle);
    final k = r / 13;
    final u = Path()
      ..moveTo(center.dx + 3.5 * k, center.dy + 6 * k)
      ..lineTo(center.dx + 3.5 * k, center.dy - 1 * k)
      ..arcToPoint(Offset(center.dx - 3.5 * k, center.dy - 1 * k), radius: Radius.circular(3.5 * k), clockwise: false)
      ..lineTo(center.dx - 3.5 * k, center.dy + 2 * k);
    canvas.drawPath(u, _ink..strokeWidth = 2.2 * k);
    canvas.drawPath(
      Path()
        ..addPolygon([
          Offset(center.dx - 6.5 * k, center.dy + 1 * k),
          Offset(center.dx - 0.5 * k, center.dy + 1 * k),
          Offset(center.dx - 3.5 * k, center.dy + 5.5 * k),
        ], true),
      Paint()..color = const Color(0xff1B1D22),
    );
    final d = r * 0.62;
    canvas.drawLine(center + Offset(-d * cos(pi / 4), -d * sin(pi / 4)), center + Offset(d * cos(pi / 4), d * sin(pi / 4)), _slash);
  }

  /// Tấm biển gỗ / bìa viết tay (người dân tự dựng): nền [paper], chữ đỏ.
  void handwritten(Canvas canvas, Offset center, String text, double angle, {Color paper = const Color(0xffEDE0C2)}) {
    final t = label(text, 8, const Color(0xffC62828), weight: FontWeight.w800);
    final board = Rect.fromCenter(center: center, width: t.width + 10, height: t.height + 8);
    canvas.drawRect(board.shift(toLocal(sunShadow * 1.1, angle)), _shadow);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.06);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawRect(board, Paint()..color = paper);
    canvas.drawRect(
      board.deflate(1),
      Paint()
        ..color = const Color(0x55704F2A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    t.paint(canvas, center - Offset(t.width / 2, t.height / 2));
    canvas.restore();
    canvas.drawCircle(center + Offset(-board.width / 2 + 3, board.height / 2 + 2), 1.8, _pole);
    canvas.drawCircle(center + Offset(board.width / 2 - 3, board.height / 2 + 2), 1.8, _pole);
  }

  void dispose() {
    for (final t in _text.values) {
      t.dispose();
    }
    _text.clear();
  }
}
