import 'dart:math';

import '../game_config.dart';
import 'collision.dart';

/// Các làn: 0, 1 là chiều của mình (nửa dưới, 0 sát vạch giữa);
/// 2, 3 là chiều ngược lại (nửa trên, 2 sát vạch giữa).
abstract class Lanes {
  static const List<int> sameDirection = [0, 1];
  static const List<int> oncoming = [2, 3];

  static bool isOncoming(int lane) => lane >= 2;

  /// Lệch khỏi tim đường của tâm làn.
  static double center(int lane) {
    final inner = GameConfig.centerGap / 2 + GameConfig.laneWidth / 2;
    final index = lane % 2;
    final offset = inner + GameConfig.laneWidth * index;
    return isOncoming(lane) ? -offset : offset;
  }

  /// Làn đang chứa điểm lệch [d] (null nếu nằm ngoài mặt đường).
  static int? at(double d) {
    for (var lane = 0; lane < 4; lane++) {
      if ((d - center(lane)).abs() <= GameConfig.laneWidth / 2) return lane;
    }
    return null;
  }

  /// Làn bên cạnh cùng chiều.
  static int neighbour(int lane) => lane ^ 1;
}

enum TrafficType {
  sedan(length: 88, width: 44),
  pickup(length: 96, width: 46),
  motorbike(length: 56, width: 24),
  bus(length: 176, width: 54),
  truck(length: 150, width: 52);

  const TrafficType({required this.length, required this.width});

  final double length;
  final double width;

  bool get heavy => this == bus || this == truck;
}

/// Dòng xe theo loại đường (lấy ở chỗ sinh xe).
class TrafficProfile {
  const TrafficProfile({
    required this.maxVehicles,
    required this.oncomingChance,
    required this.motorbikeShare,
    required this.heavyShare,
    required this.sameDirSpeed,
    required this.oncomingSpeed,
    required this.laneChangeEvery,
  });

  final int maxVehicles;
  final double oncomingChance;
  final double motorbikeShare;
  final double heavyShare;

  /// (min, max) theo tỉ lệ [GameConfig.normalSpeed].
  final (double, double) sameDirSpeed;
  final (double, double) oncomingSpeed;

  /// Trung bình bao nhiêu giây một xe máy đổi làn (0 = không đổi làn).
  final double laneChangeEvery;

  static const highway = TrafficProfile(
    maxVehicles: GameConfig.maxTrafficVehicles,
    oncomingChance: GameConfig.oncomingChance,
    motorbikeShare: 0.4,
    heavyShare: 0.18,
    sameDirSpeed: (GameConfig.sameDirSpeedMin, GameConfig.sameDirSpeedMax),
    oncomingSpeed: (GameConfig.oncomingSpeedMin, GameConfig.oncomingSpeedMax),
    laneChangeEvery: 9,
  );

  static const city = TrafficProfile(
    maxVehicles: GameConfig.maxTrafficVehicles + 1,
    oncomingChance: 0.45,
    motorbikeShare: 0.68,
    heavyShare: 0.04,
    sameDirSpeed: (0.42, 0.66),
    oncomingSpeed: (0.5, 0.72),
    laneChangeEvery: 7,
  );

  static const expressway = TrafficProfile(
    maxVehicles: GameConfig.maxTrafficVehicles,
    oncomingChance: 0.4,
    motorbikeShare: 0,
    heavyShare: 0.25,
    sameDirSpeed: (0.75, 1.0),
    oncomingSpeed: (0.9, 1.15),
    laneChangeEvery: 0,
  );
}

class TrafficVehicle {
  TrafficVehicle({
    required this.id,
    required this.type,
    required this.lane,
    required this.s,
    required this.cruiseSpeed,
    required this.variant,
  })  : d = Lanes.center(lane),
        speed = cruiseSpeed;

  final int id;
  final TrafficType type;
  int lane;

  /// Làn đang chuyển sang (null = không đổi làn).
  int? targetLane;

  /// Xi-nhan: -1 về phía tim đường âm (lên trên), 1 về phía dương; 0 = tắt.
  int blinker = 0;

  /// Còn bao lâu nữa thì bắt đầu đánh lái sang làn mới (bật xi-nhan trước).
  double blinkTimer = 0;

  /// Đếm ngược tới lần tự đổi làn kế tiếp.
  double laneChangeTimer = 0;

  /// Chọn hình (màu, kiểu) cho xe — tầng vẽ tự hiểu.
  final int variant;

  double s;
  double d;

  /// Tốc độ muốn chạy và tốc độ hiện tại (luôn ≥ 0, chiều đi theo làn).
  final double cruiseSpeed;
  double speed;

  /// Đèn phanh: đang giảm tốc.
  bool braking = false;

  bool get oncoming => Lanes.isOncoming(lane);

  /// Vận tốc có dấu dọc chiều đi của người chơi.
  double get velocity => oncoming ? -speed : speed;

  bool occupies(int l) => lane == l || targetLane == l;

  RoadBox get box => RoadBox(s: s, d: d, length: type.length, width: type.width);
}

/// Thông tin xe người chơi mà xe AI cần biết để không tông từ phía sau.
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.s,
    required this.d,
    required this.speed,
    required this.length,
    required this.width,
    this.forward = true,
    this.maneuvering = false,
  });

  final double s;
  final double d;
  final double speed;
  final double length;
  final double width;

  /// Người chơi đang đi chiều về quê (s tăng) hay đã quay đầu.
  final bool forward;

  /// Đang quay đầu chắn ngang đường: xe hai chiều thấy thì phanh (nếu kịp).
  final bool maneuvering;

  /// Xe AI [v] đi cùng chiều với người chơi không.
  bool sameWay(TrafficVehicle v) => v.oncoming != forward;
}

/// Chỗ xe phải dừng (đèn đỏ, barrier trạm thu phí). [forward]: áp cho chiều
/// mình (true) hay chiều ngược (false). [lanes]: null = mọi làn của chiều đó.
class StopPoint {
  const StopPoint({required this.s, required this.forward, this.lanes});

  final double s;
  final bool forward;
  final Set<int>? lanes;
}

enum YieldResult {
  /// Xe phía trước bật xi-nhan rồi tránh sang làn bên.
  yielded,

  /// Xe tải/xe khách không nhường mà bóp còi lại.
  honkedBack,

  /// Làn bên đang có xe, không tránh được.
  noRoom,

  /// Không có xe nào ngay phía trước.
  nobody,
}

/// Quản lý dòng xe AI: sinh xe thưa, giữ khoảng cách, dừng đèn đỏ/barrier,
/// đổi làn có xi-nhan, nhường đường khi bị bóp còi.
class TrafficSystem {
  TrafficSystem(this._random) {
    _spawnTimer = _nextSpawnDelay();
  }

  final Random _random;
  final List<TrafficVehicle> vehicles = [];
  int _nextId = 0;
  late double _spawnTimer;

  static const double _accel = 220;
  static const double _stopDecel = 420;
  static const double _laneChangeSpeed = 75;

  double _nextSpawnDelay() =>
      GameConfig.trafficSpawnIntervalMin +
      _random.nextDouble() * (GameConfig.trafficSpawnIntervalMax - GameConfig.trafficSpawnIntervalMin);

  /// [spawnS]: ngay ngoài mép phải màn hình; [despawnBehindS]: đã khuất
  /// sau mép trái; [despawnAheadS]: xe chạy quá xa phía trước.
  void update(
    double dt,
    PlayerSnapshot player, {
    required double spawnS,
    required double despawnBehindS,
    required double despawnAheadS,
    List<StopPoint> stops = const [],
    TrafficProfile Function(double s)? profileAt,
    bool Function(double s)? canSpawnAt,
  }) {
    _laneChanges(dt, player, profileAt);
    _followLeaders(dt, player, stops);
    for (final v in vehicles) {
      v.s += v.velocity * dt;
    }
    vehicles.removeWhere((v) => v.s < despawnBehindS || v.s > despawnAheadS);

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = _nextSpawnDelay();
      final profile = profileAt?.call(spawnS) ?? TrafficProfile.highway;
      if (vehicles.length < profile.maxVehicles && (canSpawnAt?.call(spawnS) ?? true)) {
        // Đã quay đầu thì "xe cùng chiều" với mình là xe chạy ngược s.
        final chance = player.forward ? profile.oncomingChance : 1 - profile.oncomingChance;
        trySpawn(spawnS, oncoming: _random.nextDouble() < chance, profile: profile);
      }
    }
  }

  void _laneChanges(double dt, PlayerSnapshot player, TrafficProfile Function(double s)? profileAt) {
    for (final v in vehicles) {
      final target = v.targetLane;
      if (target != null) {
        if (v.blinkTimer > 0) {
          v.blinkTimer -= dt;
          continue;
        }
        final goal = Lanes.center(target);
        final step = _laneChangeSpeed * dt;
        if ((goal - v.d).abs() <= step) {
          v.d = goal;
          v.lane = target;
          v.targetLane = null;
          v.blinker = 0;
        } else {
          v.d += step * (goal - v.d).sign;
        }
        continue;
      }
      // Xe máy thỉnh thoảng tự đổi làn (có xi-nhan báo trước).
      final every = profileAt?.call(v.s).laneChangeEvery ?? TrafficProfile.highway.laneChangeEvery;
      if (v.type != TrafficType.motorbike || every <= 0) continue;
      v.laneChangeTimer -= dt;
      if (v.laneChangeTimer > 0) continue;
      v.laneChangeTimer = every * (0.6 + _random.nextDouble() * 0.8);
      _startLaneChange(v, Lanes.neighbour(v.lane), player);
    }
  }

  /// Bắt đầu đổi làn nếu làn kia trống; trả về true nếu bắt đầu được.
  bool _startLaneChange(TrafficVehicle v, int target, PlayerSnapshot player) {
    final window = v.type.length + 160;
    for (final o in vehicles) {
      if (identical(o, v) || !o.occupies(target)) continue;
      if ((o.s - v.s).abs() < window) return false;
    }
    // Không tạt đầu người chơi đang ở làn kia.
    if (Lanes.at(player.d) == target && (player.s - v.s).abs() < window + 60) return false;
    v.targetLane = target;
    v.blinker = (Lanes.center(target) - v.d).sign.toInt();
    v.blinkTimer = GameConfig.blinkerSeconds;
    return true;
  }

  /// Mỗi xe nhìn xe ngay trước mặt cùng làn (theo chiều đi của nó), chỗ phải
  /// dừng phía trước, và người chơi; giảm tốc mượt, tăng tốc từ từ.
  void _followLeaders(double dt, PlayerSnapshot player, List<StopPoint> stops) {
    for (final v in vehicles) {
      var desired = v.cruiseSpeed;
      double? gap;
      double leaderSpeed = 0;

      void consider(double g, double speed) {
        if (gap == null || g < gap!) {
          gap = g;
          leaderSpeed = speed;
        }
      }

      for (final other in vehicles) {
        if (identical(other, v)) continue;
        if (!(other.occupies(v.lane) || (v.targetLane != null && other.occupies(v.targetLane!)))) continue;
        if (other.oncoming != v.oncoming) continue;
        final ahead = v.oncoming ? v.s - other.s : other.s - v.s;
        if (ahead <= 0) continue;
        consider(ahead - (v.type.length + other.type.length) / 2, other.speed);
      }

      // Xe cùng chiều phía sau người chơi thì coi người chơi là xe trước —
      // phanh gấp không bao giờ bị tông đuôi oan. Người chơi đang quay đầu
      // chắn ngang thì xe hai chiều đều phanh, nếu còn kịp.
      if ((player.d - v.d).abs() < (player.width + v.type.width) / 2) {
        final ahead = v.oncoming ? v.s - player.s : player.s - v.s;
        final g = ahead - (v.type.length + player.length) / 2;
        if (ahead > 0 && player.sameWay(v)) {
          consider(g, player.speed);
        } else if (ahead > 0 && player.maneuvering && g >= v.speed * v.speed / (2 * _stopDecel * 1.6) - 4) {
          consider(g, 0);
        }
      }

      // Đèn đỏ / barrier: chỉ dừng nếu còn kịp phanh êm; không kịp thì đi luôn.
      for (final stop in stops) {
        if (stop.forward == v.oncoming) continue;
        if (stop.lanes != null && !stop.lanes!.contains(v.lane)) continue;
        final front = v.oncoming ? v.s - v.type.length / 2 : v.s + v.type.length / 2;
        final ahead = v.oncoming ? front - stop.s : stop.s - front;
        if (ahead < -2) continue;
        final brakeNeed = v.speed * v.speed / (2 * _stopDecel * 1.6);
        if (ahead < brakeNeed - 4) continue;
        desired = min(desired, sqrt(2 * _stopDecel * max(0, ahead - 3)));
      }

      final g = gap;
      if (g != null) {
        if (g < GameConfig.trafficSafeGap * 0.5) {
          desired = 0;
        } else if (g < GameConfig.trafficSafeGap * 3) {
          desired = min(desired, leaderSpeed);
        }
      }
      v.braking = desired < v.speed - 1;
      v.speed = desired < v.speed ? desired : min(desired, v.speed + _accel * dt);
    }
  }

  /// Thử sinh một xe ở quãng [spawnS]. Trả về xe mới, hoặc null nếu chỗ đó
  /// không hợp lệ (đè lên xe khác, hoặc chắn kín cả 2 làn chiều mình).
  TrafficVehicle? trySpawn(double spawnS, {bool? oncoming, TrafficProfile profile = TrafficProfile.highway}) {
    final isOncoming = oncoming ?? _random.nextDouble() < profile.oncomingChance;
    final lanes = isOncoming ? Lanes.oncoming : Lanes.sameDirection;
    final lane = lanes[_random.nextInt(lanes.length)];
    final type = _randomType(profile);

    if (!isLaneClear(lane, spawnS, type.length + GameConfig.trafficSafeGap * 3)) return null;
    // Không cho 2 xe cùng chiều chắn kín cả hai làn của chiều đó.
    if (!isLaneClear(Lanes.neighbour(lane), spawnS, GameConfig.sideBySideBlockGap, oncoming: isOncoming)) {
      return null;
    }

    final (minF, maxF) = isOncoming ? profile.oncomingSpeed : profile.sameDirSpeed;
    // Xe nặng chạy chậm hơn một chút.
    final heavy = type.heavy ? 0.85 : 1.0;
    final speed = (minF + _random.nextDouble() * (maxF - minF)) * GameConfig.normalSpeed * heavy;

    final vehicle = TrafficVehicle(
      id: _nextId++,
      type: type,
      lane: lane,
      s: spawnS,
      cruiseSpeed: speed,
      variant: _random.nextInt(1 << 16),
    )..laneChangeTimer = profile.laneChangeEvery * (0.5 + _random.nextDouble());
    vehicles.add(vehicle);
    return vehicle;
  }

  /// Xe chạy nhanh vượt lên từ phía sau (người chơi đã được báo trước).
  TrafficVehicle? spawnOvertaker(double s, int lane, double speed, {TrafficProfile profile = TrafficProfile.highway}) {
    if (!isLaneClear(lane, s, 260)) return null;
    final r = _random.nextDouble();
    final type = profile.motorbikeShare > 0 && r < 0.3
        ? TrafficType.motorbike
        : r < 0.55
            ? TrafficType.bus
            : TrafficType.sedan;
    final vehicle = TrafficVehicle(
      id: _nextId++,
      type: type,
      lane: lane,
      s: s,
      cruiseSpeed: speed,
      variant: _random.nextInt(1 << 16),
    );
    vehicles.add(vehicle);
    return vehicle;
  }

  TrafficType _randomType(TrafficProfile profile) {
    final r = _random.nextDouble();
    if (r < profile.motorbikeShare) return TrafficType.motorbike;
    if (r < profile.motorbikeShare + profile.heavyShare) {
      return _random.nextBool() ? TrafficType.bus : TrafficType.truck;
    }
    return _random.nextDouble() < 0.78 ? TrafficType.sedan : TrafficType.pickup;
  }

  /// Bóp còi: xe cùng chiều ngay phía trước mũi xe người chơi tránh sang
  /// làn bên (xe tải, xe khách có khi không nhường mà bóp còi lại).
  YieldResult requestYield(PlayerSnapshot player) {
    TrafficVehicle? target;
    var best = double.infinity;
    for (final v in vehicles) {
      if (!player.sameWay(v) || v.targetLane != null) continue;
      if ((v.d - player.d).abs() > (v.type.width + player.width) / 2 + 6) continue;
      final ahead = player.forward ? v.s - player.s : player.s - v.s;
      if (ahead <= 0 || ahead > GameConfig.hornReach) continue;
      if (ahead < best) {
        best = ahead;
        target = v;
      }
    }
    final v = target;
    if (v == null) return YieldResult.nobody;
    if (v.type.heavy && _random.nextDouble() < GameConfig.heavyIgnoreHornChance) return YieldResult.honkedBack;
    // Tránh sang làn bên cùng chiều (nếu làn đó trống).
    return _startLaneChange(v, Lanes.neighbour(v.lane), player) ? YieldResult.yielded : YieldResult.noRoom;
  }

  /// Làn [lane] có trống trong khoảng ±[halfRange] quanh [s] không.
  /// [oncoming]: chỉ xét xe của chiều đó (null = mọi xe).
  bool isLaneClear(int lane, double s, double halfRange, {bool? oncoming}) {
    for (final v in vehicles) {
      if (!v.occupies(lane)) continue;
      if (oncoming != null && v.oncoming != oncoming) continue;
      if ((v.s - s).abs() < halfRange) return false;
    }
    return true;
  }

  /// Xe đầu tiên đang chạm hộp [box] (nếu có).
  TrafficVehicle? hit(RoadBox box) {
    for (final v in vehicles) {
      if (v.box.overlaps(box)) return v;
    }
    return null;
  }

  void remove(TrafficVehicle vehicle) => vehicles.remove(vehicle);
}
