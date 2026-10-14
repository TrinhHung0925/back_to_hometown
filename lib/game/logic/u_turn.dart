import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';

/// Quay đầu xe: một nửa vòng tròn trên mặt đường (toạ độ s, d). Đi bên phải
/// nên luôn quay về bên trái: từ lề phải chiều đang đi sang làn ngoài cùng
/// của chiều kia.
class UTurn {
  UTurn({required this.s0, required this.d0, required this.dirFrom, required this.radius, required this.duration});

  /// Điểm bắt đầu, chiều đang đi (1 về quê, -1 đi ngược), bán kính cung.
  final double s0;
  final double d0;
  final int dirFrom;
  final double radius;
  final double duration;

  double t = 0;

  bool get done => t >= duration;

  double get progress => (t / duration).clamp(0.0, 1.0);

  /// Góc đã quay (0 → π), tăng tốc rồi chậm dần ở cuối.
  double get theta {
    final k = progress;
    return pi * k * k * (3 - 2 * k);
  }

  double get s => s0 + dirFrom * radius * sin(theta);
  double get d => d0 - dirFrom * radius * (1 - cos(theta));
  double get endD => d0 - dirFrom * 2 * radius;

  /// Tốc độ dọc cung (u/s).
  double get speed {
    final k = progress;
    return pi * radius * 6 * k * (1 - k) / duration;
  }

  void update(double dt) => t = min(duration, t + dt);

  /// Hộp va chạm thẳng trục (dọc đường × ngang đường) bao thân xe đang xoay.
  (double, double) boxSize(double length, double width) {
    final c = cos(theta).abs(), sn = sin(theta).abs();
    return (c * length + sn * width, sn * length + c * width);
  }

  /// Bán kính nhỏ nhất xe quay đầu được (một lần lái, không lùi).
  static double minRadius(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => GameConfig.uTurnRadiusMotorbike,
        VehicleKind.car => GameConfig.uTurnRadiusCar,
        VehicleKind.bus => GameConfig.uTurnRadiusBus,
      };

  static double seconds(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => 1.6,
        VehicleKind.car => 2.4,
        VehicleKind.bus => 3.4,
      };

  /// Bán kính quay đầu từ chỗ [d] theo chiều [dir]: nhắm về làn ngoài cùng
  /// của chiều kia. Null nếu cung quay ra ngoài khoảng [lo]..[hi].
  static double? plan({required double d, required int dir, required double minRadius, required double lo, required double hi}) {
    const outerLane = GameConfig.centerGap / 2 + GameConfig.laneWidth * 1.5;
    final ideal = dir * (d + dir * outerLane) / 2;
    final radius = max(ideal, minRadius);
    final endD = d - dir * 2 * radius;
    if (endD < lo - 1e-6 || endD > hi + 1e-6) return null;
    return radius;
  }
}
