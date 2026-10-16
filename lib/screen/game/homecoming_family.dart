import 'dart:math';

import 'package:flutter/animation.dart';

import '../../game/vehicle_spec.dart';

/// Chở cả nhà về quê: vợ và bé cùng về trên xe, xe dừng thì xuống xe — vợ
/// xách túi quà đi vào cổng chào bố mẹ, bé chạy ùa tới ôm bà.
///
/// Toạ độ trong khung cảnh nhà 2200 × 1000 (như homecoming_overlay.dart): xe
/// dừng ở x = 1092, mép đất của xe y = 950; cả nhà đứng chờ quanh cổng
/// (x 1218–1500, y 788–818) rồi bước ra ngõ (y 870–890).
abstract final class HomecomingFamily {
  /// Xe máy chở cả nhà nhìn ngang (vợ ngồi sau, bé ngồi trước), cùng cỡ ảnh
  /// với player_moto_side.
  static const String scooterSide = 'player_moto_family_side';

  /// Vợ con xuống xe sau khi xe dừng chừng này giây.
  static const double getOffAt = 0.55;

  /// Ảnh xe lúc [since] giây sau khi dừng (âm: còn đang chạy vào): xe máy còn
  /// chở cả nhà thì dùng ảnh có vợ con, xuống xe rồi thì ảnh thường (null).
  static String? vehicleArt(VehicleKind vehicle, double? since) =>
      vehicle == VehicleKind.motorbike && (since == null || since < getOffAt) ? scooterSide : null;

  /// Vợ và bé lúc [t] (giây của cảnh), [since] giây sau khi xe dừng (null:
  /// chưa dừng). Trả về (ảnh, cao m, x, y, lật ngang) — xa vẽ trước.
  static List<(String, double, double, double, bool)> people(VehicleKind vehicle, double? since, double t) {
    if (since == null || since < getOffAt) return const [];
    final moto = vehicle == VehicleKind.motorbike;
    final k = since - getOffAt;
    // Xe máy: vợ xuống phía đuôi xe (bên trái ảnh), bé được bế xuống phía đầu
    // xe; ô tô: hai mẹ con mở cửa bước ra giữa thân xe (khuất sau xe).
    final wifeFrom = moto ? 965.0 : 1050.0, kidFrom = moto ? 1205.0 : 1130.0;
    final w = Curves.easeInOut.transform((k / 2.2).clamp(0.0, 1.0));
    final r = Curves.easeOut.transform(((k - 0.25) / 1.3).clamp(0.0, 1.0));
    final wifeWalking = w > 0 && w < 1;
    final kidRunning = r > 0 && r < 1;
    final wifeX = wifeFrom + (1330 - wifeFrom) * w;
    final wifeY = 936 + (906 - 936) * w - (wifeWalking ? sin(t * 9).abs() * 4 : 0);
    final kidX = kidFrom + (1532 - kidFrom) * r;
    final kidY = 940 + (900 - 940) * r;
    // Bé chạy thì nhún nhảy nhanh, tới nơi rồi thì nhảy cẫng lên mừng bà.
    final kidFrame = (t * (kidRunning ? 6 : 2.6)).floor().isEven ? 1 : 2;
    final wifeFrame = (t * 2.2 + 0.3).floor().isEven ? 1 : 2;
    return [
      ('family_wife_$wifeFrame', wifeFrame == 1 ? 1.667 : 1.677, wifeX, wifeY, false),
      ('family_son_$kidFrame', kidFrame == 1 ? 1.053 : 1.123, kidX, kidY, false),
    ];
  }
}
