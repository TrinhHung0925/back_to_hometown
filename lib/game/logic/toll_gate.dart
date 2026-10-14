import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';
import 'collision.dart';
import 'road_layout.dart';
import 'traffic_system.dart';

/// Các làn qua trạm (chiều mình), tính từ vạch giữa ra lề.
enum TollLane {
  /// Làn 0: thu phí không dừng — ô tô chạy chậm là barrier tự mở.
  etc,

  /// Làn 1: thu phí thường — dừng hẳn, trả lì xì, barrier mở.
  manual,

  /// Làn xe máy sát lề: không có barrier, không mất phí.
  motorbike;

  static TollLane at(double d) {
    if (d < (GameConfig.tollIslandInnerFrom + GameConfig.tollIslandInnerTo) / 2) return etc;
    if (d < (GameConfig.tollIslandEdgeFrom + GameConfig.tollIslandEdgeTo) / 2) return manual;
    return motorbike;
  }
}

/// Sự kiện ở trạm để báo lên HUD.
sealed class TollEvent {
  const TollEvent();
}

class TollPaid extends TollEvent {
  const TollPaid({required this.fee, required this.broke, required this.nonStop});

  final int fee;

  /// Không đủ lì xì: trả hết số đang có và bị giữ thêm.
  final bool broke;
  final bool nonStop;
}

class TollFreeLane extends TollEvent {
  const TollFreeLane();
}

/// Trạng thái một trạm thu phí: barrier từng làn, việc trả phí của người
/// chơi, và xe AI xếp hàng qua trạm.
class TollGate {
  TollGate(this.plaza, this.vehicle);

  final TollPlaza plaza;
  final VehicleKind vehicle;

  /// Giây còn mở của barrier làn 0 và 1 (do xe AI vừa trả phí).
  final List<double> _aiOpen = [0, 0];
  final List<double> _aiWait = [0, 0];

  /// Độ mở barrier để vẽ (0 = hạ, 1 = nâng hẳn).
  final List<double> arm = [0, 0];

  int? _playerLane;
  bool _paid = false;
  bool _freeReported = false;
  bool passed = false;
  double _stopTimer = 0;

  static double laneCenter(int lane) => lane == 0
      ? (GameConfig.centerGap / 2 + GameConfig.tollIslandInnerFrom) / 2
      : (GameConfig.tollIslandInnerTo + GameConfig.tollIslandEdgeFrom) / 2;

  static const double laneWidthAtGate = GameConfig.tollIslandInnerFrom - GameConfig.centerGap / 2;

  bool isOpen(int lane) => _aiOpen[lane] > 0 || (_paid && _playerLane == lane && !passed);

  /// Cập nhật cho người chơi. Trả về sự kiện mới (nếu có).
  TollEvent? updatePlayer(double dt, {required double s, required double d, required double speed, required double length, required int lixi}) {
    final front = s + length / 2;
    if (!passed && s - length / 2 > plaza.s + 20) passed = true;
    if (passed || front < plaza.s - 90) return null;

    final lane = TollLane.at(d);
    if (lane == TollLane.motorbike) {
      if (!_freeReported && front > plaza.s - 60) {
        _freeReported = true;
        return const TollFreeLane();
      }
      return null;
    }
    if (_paid) return null;
    final index = lane == TollLane.etc ? 0 : 1;
    final nearGate = front > plaza.s - 70 && front <= plaza.s + 2;
    if (!nearGate) {
      _stopTimer = 0;
      return null;
    }
    final fee = switch (vehicle) {
      VehicleKind.car => GameConfig.tollFeeCar,
      VehicleKind.bus => GameConfig.tollFeeBus,
      VehicleKind.motorbike => GameConfig.tollFeeMotorbike,
    };
    // Ô tô có thẻ thu phí tự động: làn không dừng chỉ cần chạy chậm.
    if (lane == TollLane.etc && vehicle.fourWheels && speed <= GameConfig.etcMaxSpeed) {
      return _pay(index, fee, lixi, nonStop: true);
    }
    if (speed < GameConfig.tollStopSpeed) {
      _stopTimer += dt;
      if (_stopTimer >= GameConfig.tollStopSeconds) return _pay(index, fee, lixi, nonStop: false);
    } else {
      _stopTimer = 0;
    }
    return null;
  }

  TollEvent _pay(int lane, int fee, int lixi, {required bool nonStop}) {
    _paid = true;
    _playerLane = lane;
    return TollPaid(fee: min(fee, lixi), broke: lixi < fee, nonStop: nonStop);
  }

  /// Xe AI dừng ở barrier một lúc thì barrier mở cho đi.
  void updateAi(double dt, List<TrafficVehicle> vehicles) {
    for (var lane = 0; lane < 2; lane++) {
      _aiOpen[lane] = max(0, _aiOpen[lane] - dt);
      final waiting = vehicles.any((v) =>
          !v.oncoming &&
          v.lane == lane &&
          v.speed < 6 &&
          (plaza.s - (v.s + v.type.length / 2)).abs() < 16);
      _aiWait[lane] = waiting ? _aiWait[lane] + dt : 0;
      if (_aiWait[lane] >= GameConfig.tollAiWait) {
        _aiWait[lane] = 0;
        _aiOpen[lane] = GameConfig.tollOpenSeconds;
      }
      final target = isOpen(lane) ? 1.0 : 0.0;
      arm[lane] += (target - arm[lane]).clamp(-dt * 2.5, dt * 2.5);
    }
  }

  /// Chỗ dừng cho xe AI: barrier các làn đang đóng.
  Iterable<StopPoint> stops() sync* {
    for (var lane = 0; lane < 2; lane++) {
      if (!isOpen(lane)) yield StopPoint(s: plaza.s - 2, forward: true, lanes: {lane});
    }
  }

  /// Vật cản cố định: đảo phân làn (cả hai chiều) và barrier đang hạ.
  Iterable<RoadBox> obstacles() sync* {
    final islandLength = plaza.islandEnd - plaza.islandStart;
    final mid = (plaza.islandStart + plaza.islandEnd) / 2;
    // Phía chiều ngược lại: đảo đối xứng qua barrier.
    final midOncoming = plaza.s + (plaza.s - mid);
    for (final (from, to) in const [
      (GameConfig.tollIslandInnerFrom, GameConfig.tollIslandInnerTo),
      (GameConfig.tollIslandEdgeFrom, GameConfig.tollIslandEdgeTo),
    ]) {
      yield RoadBox(s: mid, d: (from + to) / 2, length: islandLength, width: to - from);
      yield RoadBox(s: midOncoming, d: -(from + to) / 2, length: islandLength, width: to - from);
    }
    for (var lane = 0; lane < 2; lane++) {
      if (arm[lane] < 0.6) {
        yield RoadBox(s: plaza.s, d: laneCenter(lane), length: 8, width: laneWidthAtGate);
      }
    }
  }
}
