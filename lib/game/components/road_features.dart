import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../resource/app_colors.dart';
import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/road_path.dart';
import '../logic/toll_gate.dart';
import 'scenery_layer.dart';

const double _half = GameConfig.roadHalfWidth;

/// Lớp sát mặt đường của ngã tư / trạm thu phí: đảo phân làn, ca-bin thu
/// phí, barrier (nằm dưới xe).
class FeatureGroundLayer extends Component {
  FeatureGroundLayer({required this.road, required this.layout}) : super(priority: 3);

  final RoadPath road;
  final RoadLayout layout;
  double fromS = 0, toS = 0;
  List<TollGate> gates = const [];

  static final Paint _island = Paint()..color = const Color(0xffCFCBC2);
  static final Paint _islandEdge = Paint()
    ..color = const Color(0xff8D8980)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _yellow = Paint()..color = const Color(0xffF2C12E);
  static final Paint _dark = Paint()..color = AppColors.ff1B1D22;
  static final Paint _booth = Paint()..color = const Color(0xffF4F4F2);
  static final Paint _boothRoof = Paint()..color = const Color(0xff2D6CB5);
  static final Paint _glass = Paint()..color = const Color(0xff8FB8D8);
  static final Paint _shadow = Paint()..color = const Color(0x45000000);
  static final Paint _armRed = Paint()..color = const Color(0xffD62828);
  static final Paint _armWhite = Paint()..color = const Color(0xffF6F6F6);

  @override
  void render(Canvas canvas) {
    for (final gate in gates) {
      final t = gate.plaza;
      if (t.plazaEnd < fromS - 200 || t.plazaStart > toS + 200) continue;
      final p = road.at(t.s);
      final (x, y) = road.worldAt(t.s, 0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      _plaza(canvas, gate, forward: true);
      canvas.rotate(pi);
      _plaza(canvas, gate, forward: false);
      canvas.restore();
    }
  }

  /// Vẽ nửa trạm của một chiều trong hệ toạ độ riêng: x dọc chiều đi (0 =
  /// barrier), y lệch ngang sang phải chiều đi.
  void _plaza(Canvas canvas, TollGate gate, {required bool forward}) {
    final t = gate.plaza;
    final x0 = -(t.s - t.islandStart), x1 = t.islandEnd - t.s;
    for (final (from, to) in const [
      (GameConfig.tollIslandInnerFrom, GameConfig.tollIslandInnerTo),
      (GameConfig.tollIslandEdgeFrom, GameConfig.tollIslandEdgeTo),
    ]) {
      final r = Rect.fromLTRB(x0, from, x1, to);
      final rr = RRect.fromRectAndCorners(r, topLeft: const Radius.circular(6), bottomLeft: const Radius.circular(6));
      canvas.drawRRect(rr.shift(toLocal(sunShadow * 0.5, 0)), _shadow);
      canvas.drawRRect(rr, _island);
      // Mũi đảo sơn sọc vàng đen.
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(Rect.fromLTWH(x0 + i * 5, from, 5, to - from), i.isEven ? _yellow : _dark);
      }
      canvas.drawRRect(rr, _islandEdge);
      // Ca-bin thu phí trên đảo.
      final booth = Rect.fromLTRB(-58, from - 3, -24, to + 3);
      canvas.drawRect(booth.shift(const Offset(5, 6)), _shadow);
      canvas.drawRect(booth, _booth);
      canvas.drawRect(Rect.fromLTRB(booth.left, booth.top, booth.right, booth.top + 3), _boothRoof);
      canvas.drawRect(Rect.fromLTRB(booth.left + 4, booth.bottom - 4, booth.right - 4, booth.bottom - 1), _glass);
    }
    // Barrier: gốc trên đảo phía tim đường, cần sơn sọc đỏ trắng; nâng lên thì
    // nhìn từ trên thấy ngắn lại.
    for (var lane = 0; lane < 2; lane++) {
      final open = forward ? gate.arm[lane] : 1.0;
      final pivot = lane == 0 ? GameConfig.centerGap / 2 + 2 : GameConfig.tollIslandInnerTo + 1;
      final length = TollGate.laneWidthAtGate * (1 - open * 0.85);
      canvas.drawRect(Rect.fromLTWH(-3, pivot - 3, 6, 6), _dark);
      for (var k = 0.0; k < length; k += 8) {
        canvas.drawRect(Rect.fromLTWH(-2, pivot + k, 4, min(8, length - k)), (k ~/ 8).isEven ? _armRed : _armWhite);
      }
    }
  }
}

/// Lớp trên cao: cột đèn giao thông có đồng hồ đếm ngược, mái che và biển
/// làn của trạm thu phí (vẽ trên xe).
class FeatureOverheadLayer extends Component {
  FeatureOverheadLayer({required this.road, required this.layout}) : super(priority: 8);

  final RoadPath road;
  final RoadLayout layout;
  double fromS = 0, toS = 0;

  /// Giây chơi kể từ đầu chặng (để tính màu đèn).
  double time = 0;

  final Map<String, TextPainter> _text = {};

  static final Paint _poleShadow = Paint()
    ..color = const Color(0x30000000)
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  static final Paint _pole = Paint()
    ..color = const Color(0xff4A4F55)
    ..strokeWidth = 4.5
    ..strokeCap = StrokeCap.round;
  static final Paint _head = Paint()..color = const Color(0xff16181B);
  static final Paint _headEdge = Paint()
    ..color = const Color(0xff3B4046)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _off = Paint()..color = const Color(0xff2E3236);
  static final Paint _canopy = Paint()..color = const Color(0x66F2F4F6);
  static final Paint _beam = Paint()
    ..color = const Color(0xaa8E959C)
    ..strokeWidth = 2.5;

  static const _red = Color(0xffFF3B30);
  static const _yellow = Color(0xffFFC800);
  static const _green = Color(0xff34E06A);

  TextPainter _label(String text, double size, Color color) => _text.putIfAbsent(
        '$text|$size|${color.toARGB32()}',
        () => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: 'Manrope', fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  @override
  void render(Canvas canvas) {
    for (final l in layout.lightsBetween(fromS - 160, toS + 160)) {
      _lightPost(canvas, l, forward: true);
      _lightPost(canvas, l, forward: false);
    }
    for (final t in layout.tollsBetween(fromS - 100, toS + 100)) {
      _canopyAt(canvas, t);
    }
    for (final c in road.curvesBetween(fromS - GameConfig.curveSignAhead - 100, toS + GameConfig.curveSignAhead + 100)) {
      if (!c.sharp) continue;
      _chevrons(canvas, c);
      _curveSign(canvas, c, forward: true);
      _curveSign(canvas, c, forward: false);
    }
  }

  static final Paint _signYellow = Paint()..color = const Color(0xffF6C700);
  static final Paint _signRed = Paint()..color = const Color(0xffD62828);
  static final Paint _signWhite = Paint()..color = const Color(0xffF6F6F4);
  static final Paint _signInk = Paint()
    ..color = AppColors.ff1B1D22
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _signShadow = Paint()..color = const Color(0x40000000);

  /// Biển "chỗ ngoặt nguy hiểm" (tam giác vàng viền đỏ, mũi tên cua) kèm biển
  /// tốc độ khuyên dùng, đặt lề phải trước khúc cua của mỗi chiều. Mặt biển
  /// đọc xuôi theo người lái chiều đó.
  void _curveSign(Canvas canvas, RoadCurve c, {required bool forward}) {
    final s = forward ? c.startS - GameConfig.curveSignAhead : c.endS + GameConfig.curveSignAhead;
    if (s < fromS - 100 || s > toS + 100) return;
    final p = road.at(s);
    final (x, y) = road.worldAt(s, 0);
    final angle = p.heading + (forward ? 0 : pi);
    // Chiều ngược lại đi theo hướng kia nên cua phải hoá cua trái.
    final right = forward == c.right;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    const center = Offset(0, _half + 22);
    final shadow = toLocal(sunShadow * 1.4, angle);
    final triangle = Path()
      ..addPolygon([center + const Offset(0, -17), center + const Offset(16, 11), center + const Offset(-16, 11)], true);
    canvas.drawPath(triangle.shift(shadow), _signShadow);
    canvas.drawPath(triangle, _signRed);
    final inner = Path()
      ..addPolygon([center + const Offset(0, -10), center + const Offset(10.5, 7.5), center + const Offset(-10.5, 7.5)], true);
    canvas.drawPath(inner, _signYellow);
    // Mũi tên: đi lên rồi bẻ sang phía cua.
    final k = right ? 1.0 : -1.0;
    final arrow = Path()
      ..moveTo(center.dx - 2 * k, center.dy + 6)
      ..lineTo(center.dx - 2 * k, center.dy)
      ..quadraticBezierTo(center.dx - 2 * k, center.dy - 4, center.dx + 3 * k, center.dy - 4);
    canvas.drawPath(arrow, _signInk);
    final head = Path()
      ..addPolygon([
        center + Offset(6 * k, -4),
        center + Offset(2 * k, -7.5),
        center + Offset(2 * k, -0.5),
      ], true);
    canvas.drawPath(head, Paint()..color = AppColors.ff1B1D22);
    // Biển tốc độ khuyên dùng đứng ngay trước biển cua (không lấn vào nhà ven đường).
    final disc = center + const Offset(-26, 2);
    canvas.drawCircle(disc + shadow, 11, _signShadow);
    canvas.drawCircle(disc, 11, _signRed);
    canvas.drawCircle(disc, 8.2, _signWhite);
    final label = _label('${c.adviseKmh}', 8.5, AppColors.ff1B1D22);
    label.paint(canvas, disc - Offset(label.width / 2, label.height / 2));
    canvas.restore();
  }

  /// Biển hướng cua (vạch vàng đen chỉ chiều cua) dọc mép ngoài khúc cua gắt.
  void _chevrons(Canvas canvas, RoadCurve c) {
    final outer = c.right ? -1.0 : 1.0;
    final from = max(c.startS + c.length * 0.18, fromS - 40);
    final to = min(c.endS - c.length * 0.18, toS + 40);
    for (var s = (from / 64).ceil() * 64.0; s < to; s += 64) {
      final p = road.at(s);
      final (x, y) = road.worldAt(s, outer * (_half + 16));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      const plate = Rect.fromLTWH(-8, -6, 16, 12);
      canvas.drawRect(plate.shift(toLocal(sunShadow * 0.8, p.heading)), _signShadow);
      canvas.drawRect(plate, _signYellow);
      // Mũi chevron chỉ vào phía trong khúc cua.
      final k = -outer;
      canvas.drawPath(
        Path()
          ..moveTo(-5, -2.5 * k)
          ..lineTo(0, 2.5 * k)
          ..lineTo(5, -2.5 * k),
        _signInk,
      );
      canvas.restore();
    }
  }

  void _lightPost(Canvas canvas, TrafficLight l, {required bool forward}) {
    final s = forward ? l.stopLine - 16 : l.oncomingStopLine + 16;
    final p = road.at(s);
    final (x, y) = road.worldAt(s, 0);
    canvas.save();
    canvas.translate(x, y);
    // Hệ toạ độ riêng: x dọc chiều đi, y sang phải chiều đi.
    canvas.rotate(p.heading + (forward ? 0 : pi));
    const base = Offset(0, _half + 20);
    const tip = Offset(0, 40);
    canvas.drawLine(base + toLocal(sunShadow * 2, p.heading), tip + toLocal(sunShadow * 2, p.heading), _poleShadow);
    canvas.drawLine(base, tip, _pole);
    canvas.drawCircle(base, 5, _head);

    final color = l.colorAt(time);
    final head = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 50), width: 56, height: 20), const Radius.circular(5));
    canvas.drawRRect(head, _head);
    canvas.drawRRect(head, _headEdge);
    const lamps = [(-18.0, _red, LightColor.red), (0.0, _yellow, LightColor.yellow), (18.0, _green, LightColor.green)];
    for (final (dx, c, which) in lamps) {
      final on = which == color;
      final center = Offset(dx, 50);
      if (on) {
        canvas.drawCircle(center, 13, Paint()
          ..color = c.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      }
      canvas.drawCircle(center, 7, on ? (Paint()..color = c) : _off);
    }
    // Đồng hồ đếm ngược bên cạnh.
    final secs = l.remainingAt(time).ceil();
    final digits = _label(secs.toString().padLeft(2, '0'), 15, color == LightColor.red ? _red : color == LightColor.yellow ? _yellow : _green);
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(46, 50), width: 30, height: 20), const Radius.circular(4));
    canvas.drawRRect(box, _head);
    canvas.drawRRect(box, _headEdge);
    // Chữ số đọc xuôi theo hướng nhìn của người lái chiều đó.
    digits.paint(canvas, Offset(46 - digits.width / 2, 50 - digits.height / 2));
    canvas.restore();
  }

  void _canopyAt(Canvas canvas, TollPlaza t) {
    final p = road.at(t.s);
    final (x, y) = road.worldAt(t.s - 25, 0);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(p.heading);
    const edge = GameConfig.tollMotoLaneOuter + 8;
    final roof = Rect.fromLTRB(-34, -edge, 34, edge);
    canvas.drawRect(roof, _canopy);
    for (var dx = -30.0; dx <= 30; dx += 15) {
      canvas.drawLine(Offset(dx, -edge), Offset(dx, edge), _beam);
    }
    canvas.drawLine(Offset(-34, -edge), Offset(34, -edge), _beam);
    canvas.drawLine(Offset(-34, edge), Offset(34, edge), _beam);
    // Biển làn phía chiều mình (nửa dưới) và phía chiều ngược (nửa trên, quay ngược).
    final signs = [
      ('KHÔNG DỪNG', const Color(0xff1E9C53), TollGate.laneCenter(0)),
      ('THU PHÍ', const Color(0xff2D6CB5), TollGate.laneCenter(1)),
      ('XE MÁY', const Color(0xffE9822E), (GameConfig.tollIslandEdgeTo + GameConfig.tollMotoLaneOuter) / 2),
    ];
    for (final (text, color, d) in signs) {
      for (final side in [1.0, -1.0]) {
        canvas.save();
        canvas.translate(0, side * d);
        canvas.rotate(side > 0 ? 0 : pi);
        final label = _label(text, 9, AppColors.ffFFFFFF);
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: label.width + 10, height: label.height + 6),
          const Radius.circular(3),
        );
        canvas.drawRRect(r, Paint()..color = color);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  void onRemove() {
    for (final t in _text.values) {
      t.dispose();
    }
    _text.clear();
    super.onRemove();
  }
}

/// Điểm đón khách (chế độ xe khách): nhà chờ mái xanh ở lề phải, người đứng
/// đợi kèm hành lý; khách lên xe thì biến mất.
class BusStopLayer extends Component {
  BusStopLayer({required this.road, required this.layout, required this.people}) : super(priority: 3);

  final RoadPath road;
  final RoadLayout layout;
  final List<Sprite> people;
  double fromS = 0, toS = 0;

  /// Điểm đang đón (khách đang bước lên xe) và tiến độ 0..1.
  BusStop? boarding;
  double boardProgress = 0;

  /// Vị trí cửa xe để khách bước tới (toạ độ đường).
  double doorS = 0, doorD = 0;

  final Map<String, TextPainter> _text = {};

  static final Paint _roof = Paint()..color = const Color(0xff2D6CB5);
  static final Paint _roofEdge = Paint()
    ..color = const Color(0xffE9EEF4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _shadow = Paint()..color = const Color(0x40000000);
  static final Paint _sign = Paint()..color = const Color(0xffF2C12E);

  TextPainter get _label => _text.putIfAbsent(
        'stop',
        () => TextPainter(
          text: const TextSpan(
            text: 'ĐIỂM ĐÓN',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xff1B1D22)),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  @override
  void render(Canvas canvas) {
    for (final stop in layout.busStops) {
      if (stop.s < fromS - 120 || stop.s > toS + 120) continue;
      final p = road.at(stop.s);
      final (x, y) = road.worldAt(stop.s, _half + 30);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      // Nhà chờ: mái che + biển vàng.
      const roof = Rect.fromLTRB(-42, -6, 42, 16);
      canvas.drawRect(roof.shift(const Offset(6, 8)), _shadow);
      canvas.drawRect(roof, _roof);
      canvas.drawRect(roof, _roofEdge);
      final label = _label;
      final sign = Rect.fromCenter(center: const Offset(0, 5), width: label.width + 8, height: label.height + 4);
      canvas.drawRect(sign, _sign);
      label.paint(canvas, Offset(-label.width / 2, 5 - label.height / 2));
      canvas.restore();

      if (stop.served) continue;
      final r = Random(stop.seed);
      final t = identical(stop, boarding) ? boardProgress : 0.0;
      for (var i = 0; i < stop.passengers; i++) {
        final ps = stop.s - 36 + i * (72 / max(1, stop.passengers - 1)) + r.nextDouble() * 6;
        final pd = _half + 10 + r.nextDouble() * 8;
        // Đang lên xe: bước dần về phía cửa xe.
        final s = ps + (doorS - ps) * t;
        final d = pd + (doorD - pd) * t;
        final (px, py) = road.worldAt(s, d);
        final sprite = people[(stop.seed + i) % people.length];
        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(road.at(s).heading + pi + (r.nextDouble() - 0.5) * 0.6);
        sprite.render(canvas, position: Vector2(-12, -12), size: Vector2.all(24));
        canvas.restore();
      }
    }
  }

  @override
  void onRemove() {
    for (final t in _text.values) {
      t.dispose();
    }
    super.onRemove();
  }
}
