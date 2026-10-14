import 'dart:async';
import 'dart:math';

import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/toll_gate.dart';
import '../logic/traffic_system.dart';
import '../stage.dart';
import '../ve_que_game.dart';

/// Chỉ dùng khi phát triển: tự lái để chụp màn hình / kiểm tra trên
/// simulator (simulator không nhận thao tác chạm từ dòng lệnh).
///
/// Bật bằng:
///   flutter run --dart-define=VEQUE_AUTOPILOT=drive   (né xe, chạy tới đích)
///   flutter run --dart-define=VEQUE_AUTOPILOT=crash   (cố tình đâm để xem công an)
class Autopilot {
  Autopilot(this.game, {required this.mode});

  static const String modeFromEnv = String.fromEnvironment('VEQUE_AUTOPILOT');
  static bool get enabled => modeFromEnv.isNotEmpty;

  final VeQueGame game;
  final String mode;
  Timer? _timer;
  double _incidentWait = 0;

  void start() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick(0.05));
  }

  void stop() => _timer?.cancel();

  void _tick(double dt) {
    if (!game.isLoaded) return;
    switch (game.phase) {
      case GamePhase.incident:
        _incidentWait += dt;
        // Để bảng công an hiện vài giây cho chụp màn hình, rồi chọn chạy.
        if (_incidentWait > 3) {
          _incidentWait = 0;
          game.flee();
        }
        return;
      case GamePhase.finished:
      case GamePhase.resting:
        return;
      case GamePhase.driving:
      case GamePhase.chase:
        break;
    }

    final p = game.player;
    final crash = mode == 'crash';
    // Hết xăng, xẹp lốp: dừng lại gọi người tới giúp cho khỏi kẹt.
    if (game.phase == GamePhase.driving && p.speed < 8) {
      if (game.fuel.empty) {
        game.callFuel();
        return;
      }
      if (!game.tires.ok) {
        if (game.tires.spare) game.changeSpare();
        if (game.phase != GamePhase.resting) game.callMechanic();
        return;
      }
    }
    if ((game.fuel.empty || !game.tires.ok) && game.phase == GamePhase.driving) {
      game
        ..setThrottle(false)
        ..setBrake(true);
      return;
    }
    var targetSpeed = game.phase == GamePhase.chase ? p.spec.maxSpeed : 1.15 * GameConfig.normalSpeed;
    // Chốt CSGT phía trước: về dưới tốc độ cho phép.
    final limit = game.layout.checkpointsBetween(p.s - 200, p.s + 900).firstOrNull;
    if (limit != null) targetSpeed = min(targetSpeed, (limit.limitKmh - 5) / GameConfig.displayKmhPerUnitSpeed);
    // Cua gắt phía trước: giảm về tốc độ khuyên dùng.
    final curve = game.sharpCurveAhead;
    if (curve != null && curve.ahead < 500) targetSpeed = min(targetSpeed, curve.curve.adviseSpeed);
    game.setThrottle(p.speed < targetSpeed);

    // Tìm xe gần nhất phía trước trong làn của mình.
    final myLane = Lanes.at(p.d) ?? 1;
    TrafficVehicle? ahead;
    for (final v in game.traffic.vehicles) {
      if (v.lane != myLane) continue;
      final gap = v.s - p.s;
      if (gap <= 0 || gap > 520) continue;
      if (ahead == null || v.s < ahead.s) ahead = v;
    }

    var targetLane = myLane;
    if (crash && ahead != null && !ahead.oncoming) {
      targetLane = ahead.lane;
    } else if (ahead != null) {
      targetLane = myLane == 0 ? 1 : 0;
    } else if (Lanes.isOncoming(myLane)) {
      targetLane = 1;
    }
    if (crash) {
      // Không có xe trước mặt thì lượn sang làn có xe cùng chiều gần nhất.
      TrafficVehicle? nearest;
      for (final v in game.traffic.vehicles) {
        if (v.oncoming || v.s < p.s) continue;
        if (nearest == null || v.s < nearest.s) nearest = v;
      }
      if (nearest != null) targetLane = nearest.lane;
    }
    var targetD = Lanes.center(targetLane);
    var brake = !crash && ahead != null && ahead.oncoming == false && (ahead.s - p.s) < 140 && targetLane == myLane;

    // Ban đêm thì bật đèn.
    if (game.darkness > 0.3 && !game.headlightsOn) game.toggleHeadlights();

    // Đèn đỏ / vàng phía trước: dừng trước vạch (chế độ crash thì cứ vượt).
    final front = p.s + p.spec.length / 2;
    for (final l in game.layout.lightsBetween(front - 5, front + 260)) {
      if (crash || l.stopLine < front - 2) continue;
      if (l.colorAt(game.time) != LightColor.green) brake = true;
    }

    // Trạm thu phí: ô tô vào làn không dừng và chạy chậm; xe máy vào làn xe máy.
    final toll = game.layout.tollAt(p.s + 300);
    if (toll != null && p.s < toll.s + 40) {
      if (p.spec.kind.fourWheels) {
        targetD = TollGate.laneCenter(0);
        if (toll.s - front < 260 && p.speed > GameConfig.etcMaxSpeed * 0.8) brake = true;
      } else {
        targetD = (GameConfig.tollIslandEdgeTo + GameConfig.tollMotoLaneOuter) / 2;
      }
    }

    // Xe khách: tạt vào lề phải, dừng ở điểm đón.
    for (final stop in game.layout.busStops) {
      if (stop.served || stop.missed) continue;
      final ahead = stop.s - p.s;
      if (ahead < -40 || ahead > 700) continue;
      targetD = Lanes.center(1) + 8;
      if (ahead < 200 && p.speed > 6) brake = true;
      if (ahead < 40) brake = true;
    }

    if (p.speed > targetSpeed + 40) brake = true;

    // Bẻ lái bù lực văng khi vào cua, cộng thêm phần kéo về làn đích.
    final err = targetD - p.d;
    final counter = p.steerAuthority > 1 ? -p.curveDrift / p.steerAuthority : 0.0;
    game.setSteer((err / 30 + counter).clamp(-1.0, 1.0));
    game.setBrake(brake);
    if (brake) game.setThrottle(false);
  }
}
