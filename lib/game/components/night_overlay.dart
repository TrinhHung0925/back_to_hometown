import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../game_config.dart';
import '../logic/road_path.dart';

/// Một nguồn sáng trong đêm (toạ độ thế giới).
class NightLight {
  const NightLight.cone(this.position, this.direction, this.length, this.spread, this.strength) : radius = 0;
  const NightLight.round(this.position, this.radius, this.strength)
      : direction = 0,
        length = 0,
        spread = 0;

  final Offset position;

  /// Hướng chiếu (radian) và tầm chiếu của đèn pha; [spread] nửa góc mở.
  final double direction;
  final double length;
  final double spread;

  /// Bán kính quầng sáng tròn (đèn đường, quầng quanh xe).
  final double radius;
  final double strength;
}

/// Lớp tối phủ lên cảnh khi trời tối dần theo giờ của chuyến đi. Các nguồn
/// sáng "khoét" lớp tối: đèn pha xe mình (bật đèn mới nhìn xa được), đèn xe
/// khác, đèn đường ở phố.
class NightOverlay extends Component {
  NightOverlay() : super(priority: 20);

  /// 0 = ban ngày, 1 = tối hẳn.
  double level = 0;

  /// Vùng thế giới đang nhìn thấy.
  Rect view = Rect.zero;
  final List<NightLight> lights = [];

  static final Paint _layer = Paint();
  static final Paint _cut = Paint()..blendMode = BlendMode.dstOut;
  static final Paint _warm = Paint()
    ..blendMode = BlendMode.plus
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

  @override
  void render(Canvas canvas) {
    if (level <= 0.01 || view.isEmpty) return;
    final area = view.inflate(80);
    canvas.saveLayer(area, _layer);
    canvas.drawRect(area, Paint()..color = Color.fromRGBO(6, 10, 26, GameConfig.nightDarkness * level));
    for (final l in lights) {
      if (l.radius > 0) {
        _cut.shader = Gradient.radial(l.position, l.radius, [
          Color.fromRGBO(0, 0, 0, l.strength),
          const Color(0x00000000),
        ]);
        canvas.drawCircle(l.position, l.radius, _cut);
      } else {
        _cone(canvas, l);
      }
    }
    canvas.restore();
    // Ánh vàng ấm của đèn pha trên mặt đường.
    for (final l in lights) {
      if (l.radius > 0 || l.strength < 0.6) continue;
      final end = l.position + Offset(cos(l.direction), sin(l.direction)) * l.length * 0.55;
      _warm.color = Color.fromRGBO(255, 214, 140, 0.10 * level);
      canvas.drawLine(l.position, end, _warm..strokeWidth = 40);
    }
  }

  void _cone(Canvas canvas, NightLight l) {
    final a = l.direction;
    final p = l.position;
    final left = p + Offset(cos(a - l.spread), sin(a - l.spread)) * l.length;
    final right = p + Offset(cos(a + l.spread), sin(a + l.spread)) * l.length;
    final tip = p + Offset(cos(a), sin(a)) * l.length;
    _cut.shader = Gradient.linear(p, tip, [
      Color.fromRGBO(0, 0, 0, l.strength),
      Color.fromRGBO(0, 0, 0, l.strength * 0.75),
      const Color(0x00000000),
    ], [0, 0.55, 1]);
    final path = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(left.dx, left.dy)
      ..quadraticBezierTo(tip.dx + (tip.dx - p.dx) * 0.08, tip.dy + (tip.dy - p.dy) * 0.08, right.dx, right.dy)
      ..close();
    canvas.drawPath(path, _cut);
  }
}

/// Mũi tên nhấp nháy ở mép trái làn có xe sắp vượt lên từ phía sau.
class OvertakeWarning extends PositionComponent {
  OvertakeWarning() : super(priority: 12, anchor: Anchor.center, size: Vector2(46, 34));

  double _t = 0;
  bool active = false;

  static final Paint _fill = Paint()..color = const Color(0xffFF3B30);
  static final Paint _edge = Paint()
    ..color = const Color(0xffFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  @override
  void update(double dt) => _t += dt;

  void placeOn(RoadPath road, double s, double d) {
    final (x, y) = road.worldAt(s, d);
    position.setValues(x, y);
    angle = road.at(s).heading;
  }

  @override
  void render(Canvas canvas) {
    if (!active || (_t * 5).floor().isOdd) return;
    for (final dx in [0.0, 16.0]) {
      final path = Path()
        ..moveTo(dx + 4, 4)
        ..lineTo(dx + 22, 17)
        ..lineTo(dx + 4, 30)
        ..lineTo(dx + 10, 17)
        ..close();
      canvas.drawPath(path, _fill);
      canvas.drawPath(path, _edge);
    }
  }
}
