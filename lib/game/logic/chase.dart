import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';

enum ChaseOutcome { running, escaped, caught }

/// Rượt đuổi sau khi chọn "Chạy". Công an là "người đuổi ảo": chỉ cần biết
/// khoảng cách tới xe mình, không phải luồn lách giữa dòng xe.
class Chase {
  Chase(VehicleSpec spec)
      : policeMaxSpeed = spec.maxSpeed * GameConfig.policeMaxSpeedFactor,
        policeAccel = spec.accel * GameConfig.policeAccelFactor;

  final double policeMaxSpeed;
  final double policeAccel;

  /// Khoảng cách từ công an tới xe mình. Về 0 là bị bắt.
  double gap = GameConfig.chaseStartGap;
  double policeSpeed = 0;
  double elapsed = 0;

  ChaseOutcome outcome = ChaseOutcome.running;

  /// 0..1 — để vẽ thanh khoảng cách (1 = sắp thoát).
  double get progress => (gap / GameConfig.chaseEscapeGap).clamp(0.0, 1.0);

  double get timeLeft => max(0, GameConfig.chaseDuration - elapsed);

  void update(double dt, double playerSpeed) {
    if (outcome != ChaseOutcome.running) return;
    elapsed += dt;
    policeSpeed = min(policeMaxSpeed, policeSpeed + policeAccel * dt);
    gap += (playerSpeed - policeSpeed) * dt;
    if (gap <= 0) {
      gap = 0;
      outcome = ChaseOutcome.caught;
    } else if (gap >= GameConfig.chaseEscapeGap || elapsed >= GameConfig.chaseDuration) {
      outcome = ChaseOutcome.escaped;
    }
  }
}
