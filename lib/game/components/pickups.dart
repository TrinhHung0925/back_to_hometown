import 'dart:math';


import 'package:flame/components.dart';

import '../logic/road_path.dart';

enum PickupKind { lixi, pothole, gift }

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
      };
  double get width => switch (kind) {
        PickupKind.lixi => 18,
        PickupKind.pothole => 28,
        PickupKind.gift => 34,
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

/// Đặt một thành phần vẽ-bằng-code lên mặt đường theo (s, d).
void placeOnRoad(PositionComponent c, RoadPath road, double s, double d) {
  final (x, y) = road.worldAt(s, d);
  c.position.setValues(x, y);
  c.angle = road.at(s).heading + pi / 2;
}
