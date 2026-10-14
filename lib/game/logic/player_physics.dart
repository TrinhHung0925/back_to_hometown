import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';

/// Chuyển động của xe người chơi trong toạ độ đường: [s] dọc đường,
/// [d] lệch khỏi tim đường (dương = bên phải hướng đi).
///
/// Giữ ga thì tăng tốc, nhả ga thì xe trôi chậm dần; giữ phanh thì giảm
/// tốc mạnh. Cần lái đổi tốc độ dạt ngang. Vào cua thì xe bị văng ra phía
/// ngoài (càng nhanh, cua càng gắt càng văng mạnh) — phải bẻ lái giữ làn,
/// chạy quá nhanh thì tì vào mép đường, quệt lề mất tốc độ.
class PlayerPhysics {
  PlayerPhysics({required this.spec, this.s = 0, this.d = 0, this.speed = 0});

  final VehicleSpec spec;

  double s;
  double d;
  double speed;

  /// Tốc độ dạt ngang hiện tại (u/s), dương là dạt sang phải hướng đi.
  double lateralVelocity = 0;

  /// Số món quà đang chở.
  int cargo = 0;

  // Đầu vào từ cần lái và cụm nút.
  bool throttle = false;
  bool brake = false;

  /// -1 (kéo hết lên) .. 1 (kéo hết xuống).
  double steer = 0;

  /// Độ cong của đường ở chỗ xe (game cập nhật mỗi khung hình), dương là
  /// cua phải.
  double curvature = 0;

  /// Đang bị văng tì vào mép đường / dải phân cách (quệt lề).
  bool scraping = false;

  /// Tốc độ dạt ngang do lực văng khi vào cua (âm = văng sang trái hướng đi).
  double get curveDrift => -curvature * speed * speed * GameConfig.curveDrift;

  /// Sức kéo ngang tối đa của cần lái ở tốc độ hiện tại.
  double get steerAuthority => spec.lateralSpeed * handling * (speed / (0.5 * GameConfig.normalSpeed)).clamp(0.0, 1.0);

  double get handling => spec.handlingFactor(cargo);

  /// Biên lệch ngang mặc định: không leo lên vỉa hè.
  double get maxOffset => GameConfig.roadHalfWidth - spec.width / 2;

  /// Biên lệch ngang hiện tại (game đổi theo chỗ: dải phân cách cao tốc,
  /// làn xe máy ở trạm thu phí…). Null = dùng [maxOffset] hai bên.
  double? minD;
  double? maxD;

  /// Góc lệch của thân xe so với hướng đường khi đang dạt ngang (radian).
  double get yawOffset => atan2(lateralVelocity, max(speed, 60)).clamp(-0.45, 0.45);

  void update(double dt) {
    final h = handling;

    if (brake) {
      // Chở nặng thì phanh ăn kém hơn.
      speed = max(0, speed - spec.brakeDecel * h * dt);
    } else if (throttle) {
      speed = min(spec.maxSpeed, speed + spec.accel * h * dt);
    } else {
      // Nhả ga: xe trôi chậm dần (phải giữ ga mới giữ được tốc độ).
      speed = max(0, speed - GameConfig.coastDecel * dt);
    }

    // Đứng yên thì không dạt ngang được; chạy càng nhanh dạt càng đủ lực.
    final drift = curveDrift;
    final target = steer.clamp(-1.0, 1.0) * steerAuthority + drift;
    final k = min(1.0, spec.steerResponse * h * dt);
    lateralVelocity += (target - lateralVelocity) * k;

    d += lateralVelocity * dt;
    final lo = minD ?? -maxOffset;
    final hi = maxD ?? maxOffset;
    scraping = false;
    if (d < lo || d > hi) {
      // Lực văng ép xe vào mép: quệt lề, tốc độ tụt nhanh.
      final side = d > hi ? 1.0 : -1.0;
      scraping = drift * side > GameConfig.scrapeMinDrift && target * side > 0;
      d = d.clamp(lo, hi);
      lateralVelocity = 0;
      if (scraping) speed = max(0, speed - GameConfig.scrapeDecel * dt);
    }

    s += speed * dt;
  }

  /// Qua ổ gà: xóc, mất một phần tốc độ.
  void bump() => speed *= GameConfig.potholeSpeedFactor;

  /// Va chạm: xe dừng hẳn.
  void stop() {
    speed = 0;
    lateralVelocity = 0;
  }
}
