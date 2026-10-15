import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';

/// Chuyển động của xe người chơi trong toạ độ đường: [s] dọc đường,
/// [d] lệch khỏi tim đường (dương = bên phải hướng đi).
///
/// Ga kiểu "giữ mức" (như vặn tay ga rồi giữ yên): giữ nút Ga thì vặn thêm
/// ga, xe tăng tốc; buông tay thì xe giữ nguyên tốc độ đang chạy. Giữ Phanh
/// thì giảm tốc, buông ra xe giữ tốc độ mới. Cần lái đổi tốc độ dạt ngang.
/// Vào cua đúng tốc độ thì xe tự ôm cua (người lái nghiêng theo cua); chạy
/// nhanh quá thì xe bị văng ra phía ngoài — phải bẻ lái giữ làn, quá nữa thì
/// tì vào mép đường, quệt lề mất tốc độ.
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

  /// Mức ga đang giữ: tốc độ xe tự giữ khi buông tay. Giữ Ga thì mức này
  /// tăng dần, giữ Phanh thì hạ theo tốc độ; xe dừng hẳn / va chạm thì về 0.
  double cruise = 0;

  /// -1 (kéo hết lên) .. 1 (kéo hết xuống).
  double steer = 0;

  /// Chiều đi: 1 về quê (s tăng), -1 sau khi quay đầu (s giảm). Cần lái và
  /// tốc độ dạt ngang luôn tính theo chiều đang đi (dương = bên phải).
  int dir = 1;

  /// Đang ngủ gật: tay lái không ăn, xe tự dạt ngang với tốc độ này.
  bool asleep = false;
  double sleepDrift = 0;

  /// Trượt nước (lao qua vũng nước nhanh): tay lái không ăn, xe dạt ngang.
  bool slipping = false;
  double slipDrift = 0;

  /// Hết xăng / máy khục khặc: giữ ga cũng không ăn.
  bool engineOff = false;

  /// Tốc độ tối đa tạm thời (lốp xẹp, dắt bộ); null = theo xe.
  double? speedCap;

  /// Lực kéo lệch ngang (u/s) của lốp xẹp, dương = sang phải chiều đi.
  double pull = 0;

  /// Độ bám đường: 1 khô ráo, nhỏ hơn khi đường ướt (phanh kém, văng mạnh).
  double grip = 1;

  /// Độ cong của đường ở chỗ xe (game cập nhật mỗi khung hình), dương là
  /// cua phải.
  double curvature = 0;

  /// Đang mải nghe điện thoại (0..1): tay lái kém nhạy hẳn đi.
  double distraction = 0;

  /// Đang bị văng tì vào mép đường / dải phân cách (quệt lề).
  bool scraping = false;

  /// Tốc độ dạt ngang do lực văng khi vào cua (âm = văng sang trái hướng đi).
  /// Đi ngược chiều thì cua phải của đường thành cua trái của mình. Phần lực
  /// văng trong sức bám của lốp ([GameConfig.curveHoldDrift], kém đi khi
  /// đường ướt) xe tự ôm cua được — chỉ phần vượt quá mới đẩy xe ra ngoài.
  double get curveDrift {
    final raw = -dir * curvature * speed * speed * GameConfig.curveDrift / grip;
    final hold = GameConfig.curveHoldDrift * grip;
    return raw.sign * max(0.0, raw.abs() - hold);
  }

  /// Sức kéo ngang tối đa của cần lái ở tốc độ hiện tại.
  double get steerAuthority =>
      spec.lateralSpeed * handling * (1 - 0.45 * distraction) * (speed / (0.5 * GameConfig.normalSpeed)).clamp(0.0, 1.0);

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

    final top = min(spec.maxSpeed, speedCap ?? double.infinity);
    if (brake) {
      // Chở nặng thì phanh ăn kém hơn; đường ướt phanh trượt dài hơn. Buông
      // phanh thì xe giữ tốc độ vừa giảm tới.
      speed = max(0, speed - spec.brakeDecel * h * grip * dt);
      cruise = min(cruise, speed);
    } else if (throttle) {
      // Vặn thêm ga: mức ga tăng theo sức kéo của xe.
      cruise = max(cruise, speed) + spec.accel * h * dt;
    }
    // Lốp xẹp, dắt bộ: vặn ga cỡ nào cũng không quá được mức này.
    cruise = min(cruise, top);
    if (!brake) {
      if (!engineOff && speed < cruise) {
        speed = min(cruise, speed + spec.accel * h * dt);
      } else if (engineOff || speed > cruise) {
        // Máy tắt / khục khặc: xe trôi chậm dần.
        speed = max(engineOff ? 0 : cruise, speed - GameConfig.coastDecel * dt);
      }
    }
    // Lốp xẹp: không chạy nhanh nổi, đang nhanh thì bị ghì lại.
    if (speed > top) speed = max(top, speed - 3 * GameConfig.coastDecel * dt);

    // Đứng yên thì không dạt ngang được; chạy càng nhanh dạt càng đủ lực.
    final drift = curveDrift;
    final hands = asleep
        ? sleepDrift
        : slipping
            ? slipDrift
            : steer.clamp(-1.0, 1.0) * steerAuthority;
    final rolling = (speed / (0.3 * GameConfig.normalSpeed)).clamp(0.0, 1.0);
    final target = hands + drift + pull * rolling;
    final k = min(1.0, spec.steerResponse * h * dt);
    lateralVelocity += (target - lateralVelocity) * k;

    d += dir * lateralVelocity * dt;
    final lo = minD ?? -maxOffset;
    final hi = maxD ?? maxOffset;
    scraping = false;
    if (d < lo || d > hi) {
      // Lực văng ép xe vào mép: quệt lề, tốc độ tụt nhanh.
      final side = (d > hi ? 1.0 : -1.0) * dir;
      scraping = drift * side > GameConfig.scrapeMinDrift && target * side > 0;
      d = d.clamp(lo, hi);
      lateralVelocity = 0;
      if (scraping) {
        // Quệt lề thì giật mình nhả bớt ga.
        speed = max(0, speed - GameConfig.scrapeDecel * dt);
        cruise = min(cruise, speed);
      }
    }

    s += dir * speed * dt;
  }

  /// Qua ổ gà: xóc, mất một phần tốc độ.
  void bump() => speed *= GameConfig.potholeSpeedFactor;

  /// Va chạm, dừng hẳn: xe đứng yên, trả hết ga.
  void stop() {
    speed = 0;
    cruise = 0;
    lateralVelocity = 0;
  }
}
