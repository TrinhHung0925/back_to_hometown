import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../../resource/app_resource.dart';
import '../game_config.dart';
import '../logic/cross_traffic.dart';
import '../logic/road_path.dart';
import '../logic/traffic_system.dart';
import 'vehicle_sprite.dart';

/// Đồng bộ hình xe với dòng xe AI (dọc đường và đường ngang ở ngã tư).
class TrafficLayer extends Component with HasGameReference<FlameGame> {
  TrafficLayer({required this.traffic, required this.cross, required this.road}) : super(priority: 4);

  final TrafficSystem traffic;
  final CrossTraffic cross;
  final RoadPath road;
  final Map<int, VehicleSprite> _sprites = {};
  final Map<int, VehicleSprite> _crossSprites = {};

  /// Ban đêm: xe AI bật đèn.
  bool lightsOn = false;

  /// Trời mưa: người đi xe máy trùm áo mưa.
  bool raining = false;

  final Map<String, Sprite> _cache = {};

  Sprite _sprite(String path) => _cache.putIfAbsent(path, () => Sprite(game.images.fromCache(path)));

  String _pathFor(TrafficType type, int variant) => raining && type == TrafficType.motorbike && variant % 3 != 0
      ? Img.scootersRaincoat[variant % Img.scootersRaincoat.length]
      : spritePath(type, variant);

  static String spritePath(TrafficType type, int variant) => switch (type) {
        TrafficType.motorbike => Img.scootersAi[variant % Img.scootersAi.length],
        TrafficType.sedan => Img.sedansAi[variant % Img.sedansAi.length],
        TrafficType.pickup => Img.pickups[variant % Img.pickups.length],
        TrafficType.bus => Img.buses[variant % Img.buses.length],
        TrafficType.truck => Img.trucks[variant % Img.trucks.length],
      };

  VehicleSprite _make(TrafficType type, int variant) => VehicleSprite(
        sprite: _sprite(_pathFor(type, variant)),
        shadow: Sprite(game.images.fromCache(Img.imgShadowBox)),
        width: type.width * (type == TrafficType.motorbike ? GameConfig.motorbikeVisualScale : 1),
        motorbike: type == TrafficType.motorbike,
      );

  void sync() {
    final alive = <int>{};
    for (final v in traffic.vehicles) {
      alive.add(v.id);
      final sprite = _sprites.putIfAbsent(v.id, () => _make(v.type, v.variant)..addToParent(this));
      sprite
        ..sprite = _sprite(_pathFor(v.type, v.variant))
        ..braking = v.braking
        ..lightsOn = lightsOn
        ..placeOn(road, v.s, v.d, facingBackward: v.oncoming, blinkerD: v.blinker);
    }
    _prune(_sprites, alive);

    final crossAlive = <int>{};
    for (final v in cross.vehicles) {
      crossAlive.add(v.id);
      final sprite = _crossSprites.putIfAbsent(v.id, () => _make(v.type, v.variant)..addToParent(this));
      sprite
        ..sprite = _sprite(_pathFor(v.type, v.variant))
        ..braking = v.speed < v.cruiseSpeed * 0.5
        ..lightsOn = lightsOn
        ..placeAcross(road, v.s, v.d, down: v.down);
    }
    _prune(_crossSprites, crossAlive);
  }

  void _prune(Map<int, VehicleSprite> sprites, Set<int> alive) {
    sprites.removeWhere((id, sprite) {
      if (alive.contains(id)) return false;
      sprite.removeFromParent();
      return true;
    });
  }
}
