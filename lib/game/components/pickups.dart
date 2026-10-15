import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../logic/road_path.dart';

enum PickupKind {
  lixi,
  pothole,
  gift,
  puddle,

  /// Cát biển gió thổi tràn ra mặt đường (bản đồ ven biển): trơn trượt.
  sand,
}

/// Lì xì, quà Tết hoặc ổ gà nằm yên trên đường.
class Pickup {
  Pickup({required this.kind, required this.s, required this.d});

  final PickupKind kind;
  final double s;
  final double d;
  bool consumed = false;

  double get length => switch (kind) {
        PickupKind.lixi => 26,
        PickupKind.pothole => 34,
        PickupKind.gift => 34,
        PickupKind.puddle => 64,
        PickupKind.sand => 80,
      };
  double get width => switch (kind) {
        PickupKind.lixi => 18,
        PickupKind.pothole => 28,
        PickupKind.gift => 34,
        PickupKind.puddle => 34,
        PickupKind.sand => 42,
      };
}

/// Phong bao lì xì đỏ in hoa mai vàng, lắc nhẹ cho dễ thấy.
class LixiComponent extends SpriteComponent {
  LixiComponent(Sprite sprite) : super(sprite: sprite, size: Vector2(20, 28), anchor: Anchor.center, priority: 3);

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    scale.setAll(1 + sin(_t * 6) * 0.06);
  }
}

/// Quà Tết (cành đào, cây quất, thùng quà) nằm chờ trên đường, nảy nhẹ.
class GiftComponent extends SpriteComponent {
  GiftComponent(Sprite sprite) : super(sprite: sprite, size: Vector2.all(38), anchor: Anchor.center, priority: 3);

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    scale.setAll(1 + sin(_t * 5) * 0.07);
  }
}

/// Ổ gà: ảnh vết lõm có đá dăm, nước đọng (vẽ trong build_world_art.py).
class PotholeComponent extends SpriteComponent {
  PotholeComponent(Sprite sprite) : super(sprite: sprite, size: Vector2(44, 40), anchor: Anchor.center, priority: 2);
}

/// Vũng nước đọng trên mặt đường lúc mưa: mép loang lổ, mặt nước phản chiếu
/// trời xám, hạt mưa rơi xuống toé vòng tròn. Lao qua nhanh thì trượt nước.
class PuddleComponent extends PositionComponent {
  PuddleComponent(int seed) : super(size: Vector2(80, 46), anchor: Anchor.center, priority: 2) {
    final r = Random(seed);
    final points = <Offset>[];
    for (var i = 0; i < 14; i++) {
      final a = i * 2 * pi / 14;
      final k = 0.72 + r.nextDouble() * 0.3;
      points.add(Offset(40 + cos(a) * 38 * k, 23 + sin(a) * 21 * k));
    }
    _shape = Path()..addPolygon(points, true);
    _phase = r.nextDouble() * 5;
  }

  late final Path _shape;
  late final double _phase;
  double _t = 0;

  /// Độ nặng hạt mưa đang rơi (vòng toé trên mặt vũng).
  static double rain = 0;

  static final Paint _rim = Paint()
    ..color = const Color(0x55262B30)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_shape, _rim);
    canvas.drawPath(
      _shape,
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          Offset(size.x, size.y),
          const [Color(0xcc8B9AAA), Color(0xcc4E5C6B), Color(0xcc3A4552)],
          const [0, 0.55, 1],
        ),
    );
    // Vệt trời sáng phản chiếu.
    canvas.save();
    canvas.clipPath(_shape);
    canvas.drawLine(const Offset(14, 30), const Offset(52, 8), Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round);
    if (rain > 0.05) {
      for (var i = 0; i < 4; i++) {
        final k = (_t * 1.6 + _phase + i * 0.27) % 1;
        final c = Offset(14 + ((i * 37 + (_t * 1.6 + _phase + i * 0.27).floor() * 23) % 52), 10 + ((i * 17) % 26));
        _ring.color = Color.fromRGBO(230, 238, 245, 0.7 * (1 - k) * min(1, rain * 1.5));
        canvas.drawOval(Rect.fromCenter(center: c, width: 3 + 12 * k, height: 2 + 8 * k), _ring);
      }
    }
    canvas.restore();
  }
}

/// Đặt một thành phần vẽ-bằng-code lên mặt đường theo (s, d).
void placeOnRoad(PositionComponent c, RoadPath road, double s, double d) {
  final (x, y) = road.worldAt(s, d);
  c.position.setValues(x, y);
  c.angle = road.at(s).heading + pi / 2;
}

/// Doi cát gió biển thổi tràn ra mặt đường: vệt cát loang theo chiều gió,
/// gợn sóng nhỏ.
class SandPatchComponent extends PositionComponent {
  SandPatchComponent(int seed) : super(size: Vector2(96, 54), anchor: Anchor.center, priority: 2) {
    final r = Random(seed);
    final points = <Offset>[];
    for (var i = 0; i < 16; i++) {
      final a = i * 2 * pi / 16;
      final k = 0.62 + r.nextDouble() * 0.38;
      points.add(Offset(48 + cos(a) * 46 * k, 27 + sin(a) * 25 * k));
    }
    _shape = Path()..addPolygon(points, true);
    _ripples = [for (var i = 0; i < 5; i++) 10 + i * 8 + r.nextDouble() * 4];
  }

  late final Path _shape;
  late final List<double> _ripples;

  static final Paint _fill = Paint()
    ..shader = Gradient.radial(const Offset(48, 27), 50, const [Color(0xd9E3D2A6), Color(0x99D7C394), Color(0x00D7C394)], const [0, 0.7, 1]);
  static final Paint _ripple = Paint()
    ..color = const Color(0x40A88F5E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_shape, _fill);
    canvas.save();
    canvas.clipPath(_shape);
    for (final y in _ripples) {
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(24, y - 4, 48, y)
          ..quadraticBezierTo(72, y + 4, 96, y),
        _ripple,
      );
    }
    canvas.restore();
  }
}
