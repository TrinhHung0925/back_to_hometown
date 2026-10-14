import 'dart:math';

import '../game_config.dart';
import 'collision.dart';
import 'road_layout.dart';
import 'traffic_system.dart';

/// Xe chạy trên đường cắt ngang ở ngã tư (dọc theo trục d).
class CrossVehicle {
  CrossVehicle({
    required this.id,
    required this.type,
    required this.light,
    required this.down,
    required this.d,
    required this.cruiseSpeed,
    required this.variant,
  }) : speed = cruiseSpeed;

  final int id;
  final TrafficType type;
  final TrafficLight light;

  /// Chạy xuống dưới màn hình (d tăng). Việt Nam đi bên phải nên xe chạy
  /// xuống đi ở nửa trái đường ngang (s nhỏ hơn tim), xe chạy lên ở nửa phải.
  final bool down;
  final int variant;
  final double cruiseSpeed;
  double d;
  double speed;

  double get s => light.s + (down ? -1 : 1) * GameConfig.crossRoadWidth / 4;

  double get front => down ? d + type.length / 2 : d - type.length / 2;

  /// Hộp va chạm: thân xe nằm ngang đường chính.
  RoadBox get box => RoadBox(s: s, d: d, length: type.width, width: type.length);
}

/// Dòng xe đường ngang: chỉ chạy khi đèn đường ngang xanh, dừng trước vạch
/// khi đỏ, nhường xe người chơi nếu người chơi đang chắn trong ngã tư.
class CrossTraffic {
  CrossTraffic(this._random);

  final Random _random;
  final List<CrossVehicle> vehicles = [];
  final Map<double, double> _timers = {};
  int _nextId = 0;

  static const double _decel = 420;
  static const double _accel = 220;
  static double get spawnD => GameConfig.roadHalfWidth + GameConfig.sidewalkWidth + 270;
  static double get stopD => GameConfig.roadHalfWidth + GameConfig.crossStopGap;

  /// [lights]: các ngã tư gần người chơi; [t]: giây chơi kể từ đầu chặng.
  void update(double dt, double t, Iterable<TrafficLight> lights, RoadBox player) {
    final active = lights.toList();
    for (final light in active) {
      final timer = (_timers[light.s] ?? 0) - dt;
      _timers[light.s] = timer;
      if (timer > 0 || !light.crossGreenAt(t)) continue;
      _timers[light.s] = GameConfig.crossSpawnIntervalMin +
          _random.nextDouble() * (GameConfig.crossSpawnIntervalMax - GameConfig.crossSpawnIntervalMin);
      if (vehicles.where((v) => identical(v.light, light)).length >= GameConfig.crossVehiclesPerLight) continue;
      final down = _random.nextBool();
      final start = down ? -spawnD : spawnD;
      if (vehicles.any((v) => identical(v.light, light) && v.down == down && (v.d - start).abs() < 200)) continue;
      final type = _random.nextDouble() < 0.6 ? TrafficType.motorbike : TrafficType.sedan;
      vehicles.add(CrossVehicle(
        id: _nextId++,
        type: type,
        light: light,
        down: down,
        d: start,
        cruiseSpeed: (GameConfig.crossSpeedMin + _random.nextDouble() * (GameConfig.crossSpeedMax - GameConfig.crossSpeedMin)) *
            GameConfig.normalSpeed,
        variant: _random.nextInt(1 << 16),
      ));
    }

    for (final v in vehicles) {
      var desired = v.cruiseSpeed;
      final dir = v.down ? 1.0 : -1.0;
      // Vạch dừng của đường ngang.
      if (!v.light.crossGreenAt(t)) {
        final line = v.down ? -stopD : stopD;
        final ahead = (line - v.front) * dir;
        if (ahead > -2 && ahead > v.speed * v.speed / (2 * _decel * 1.6) - 4) {
          desired = min(desired, sqrt(2 * _decel * max(0, ahead - 3)));
        }
      }
      // Xe trước cùng hướng.
      for (final o in vehicles) {
        if (identical(o, v) || !identical(o.light, v.light) || o.down != v.down) continue;
        final gap = (o.d - v.d) * dir - (o.type.length + v.type.length) / 2;
        if (gap <= -1) continue;
        if (gap < GameConfig.trafficSafeGap * 0.5) {
          desired = 0;
        } else if (gap < GameConfig.trafficSafeGap * 2.5) {
          desired = min(desired, o.speed);
        }
      }
      // Người chơi đang chắn ngang lối đi: dừng lại, không đâm vào.
      if ((player.s - v.s).abs() < (player.length + v.type.width) / 2) {
        final gap = (player.d - v.d) * dir - (player.width + v.type.length) / 2;
        if (gap > -4 && gap < 90) desired = 0;
      }
      v.speed = desired < v.speed ? desired : min(desired, v.speed + _accel * dt);
      v.d += dir * v.speed * dt;
    }
    final keep = active.map((l) => l.s).toSet();
    vehicles.removeWhere((v) => v.d.abs() > spawnD + 40 || !keep.contains(v.light.s));
    _timers.removeWhere((s, _) => !keep.contains(s));
  }

  CrossVehicle? hit(RoadBox box) {
    for (final v in vehicles) {
      if (v.box.overlaps(box)) return v;
    }
    return null;
  }

  void remove(CrossVehicle v) => vehicles.remove(v);
}
