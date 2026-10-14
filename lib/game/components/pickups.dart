import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../logic/road_path.dart';

enum PickupKind { lixi, pothole, gift, puddle }

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
      };
  double get width => switch (kind) {
        PickupKind.lixi => 18,
        PickupKind.pothole => 28,
        PickupKind.gift => 34,
        PickupKind.puddle => 34,
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
