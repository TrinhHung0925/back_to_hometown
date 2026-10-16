import 'dart:math';

import '../../model/map_theme.dart';
import '../../resource/vn_route_data.dart';

/// Khí hậu dịp Tết theo vĩ độ và địa hình: miền Bắc gặp gió mùa đông bắc rét
/// đậm, Bắc Trung Bộ se lạnh, từ Huế trở vào ấm dần, miền Nam nắng nóng. Đèo
/// núi rét hơn đồng bằng chừng 5–6 °C, ven biển dịu hơn một chút.
///
/// Trong ngày: thấp nhất lúc rạng sáng (~6 giờ), cao nhất đầu giờ chiều
/// (~14 giờ) — ấm dần 8 tiếng, lạnh dần 16 tiếng. Mưa phùn làm rét thêm.
class ColdClimate {
  const ColdClimate({required this.fromLat, required this.toLat, this.theme = MapTheme.delta, this.offset = 0});

  /// Khí hậu của chặng từ [fromName] tới [toName]: tìm vĩ độ theo tên điểm
  /// (đuôi tên chặng, ví dụ "Bến xe Giáp Bát, Hà Nội"); không thấy thì lấy
  /// theo miền ([south]: phía nam vĩ tuyến ~12,8°). [offset]: đợt rét năm
  /// nay đậm / nhạt hơn bình thường bao nhiêu độ.
  factory ColdClimate.forStage({
    required String fromName,
    required String toName,
    required bool south,
    MapTheme theme = MapTheme.delta,
    double offset = 0,
  }) {
    final fallback = south ? 10.8 : 21.0;
    return ColdClimate(
      fromLat: latitudeOf(fromName) ?? latitudeOf(toName) ?? fallback,
      toLat: latitudeOf(toName) ?? latitudeOf(fromName) ?? fallback,
      theme: theme,
      offset: offset,
    );
  }

  /// Vĩ độ (độ Bắc) điểm đầu / điểm cuối chặng.
  final double fromLat;
  final double toLat;
  final MapTheme theme;

  /// Đợt rét năm nay lệch bao nhiêu độ so với mốc (âm = rét hơn).
  final double offset;

  /// Từ mức này trở xuống là rét: tay cóng, máy nguội khó nổ, sương muối.
  static const double coldBelow = 12.5;

  /// Rét hại (rét buốt) từ mức này trở xuống.
  static const double severeBelow = 8.5;

  /// Vĩ độ của điểm có tên ở cuối [name] (null nếu không có trên bản đồ).
  static double? latitudeOf(String name) {
    for (final p in VnRouteData.places) {
      // Toạ độ bản đồ: y tăng về phía nam, 32 − y ≈ vĩ độ.
      if (name.endsWith(p.name)) return 32 - p.y;
    }
    return null;
  }

  /// Mốc nhiệt độ thấp nhất / cao nhất ngày Tết ở đồng bằng theo vĩ độ (gặp
  /// đợt gió mùa đông bắc): Cà Mau – Sài Gòn, Nha Trang, Đà Nẵng, Vinh, Hà
  /// Nội, Cao Bằng.
  static const List<(double, double, double)> _anchors = [
    (9.0, 23.0, 32.0),
    (12.8, 21.0, 30.0),
    (16.0, 17.5, 23.5),
    (18.7, 11.5, 17.0),
    (21.0, 8.5, 15.5),
    (22.8, 7.0, 14.5),
  ];

  /// Thấp nhất, cao nhất trong ngày ở vĩ độ [lat] (đồng bằng, chưa tính địa
  /// hình và đợt rét).
  static (double, double) dailyRange(double lat) {
    final first = _anchors.first, last = _anchors.last;
    if (lat <= first.$1) return (first.$2, first.$3);
    if (lat >= last.$1) return (last.$2, last.$3);
    for (var i = 1; i < _anchors.length; i++) {
      final (b, bLo, bHi) = _anchors[i];
      if (lat > b) continue;
      final (a, aLo, aHi) = _anchors[i - 1];
      final k = (lat - a) / (b - a);
      return (aLo + (bLo - aLo) * k, aHi + (bHi - aHi) * k);
    }
    return (last.$2, last.$3);
  }

  /// Đèo núi rét hơn hẳn, ven biển dịu hơn.
  double get terrain => switch (theme) {
        MapTheme.mountain => -5.5,
        MapTheme.coast => 1.2,
        _ => 0,
      };

  /// Độ ấm trong ngày theo giờ [hour] (0..24): 0 lúc thấp nhất (6 giờ), 1 lúc
  /// cao nhất (14 giờ).
  static double warmth(double hour) {
    final h = hour % 24;
    if (h >= 6 && h < 14) return (1 - cos(pi * (h - 6) / 8)) / 2;
    final t = (h >= 14 ? h - 14 : h + 10) / 16;
    return (1 + cos(pi * t)) / 2;
  }

  /// Nhiệt độ (°C) lúc [minutes] (phút đồng hồ chuyến đi) khi đã đi được
  /// [progress] (0..1) chặng; [rain] 0..1 độ nặng hạt.
  double temperatureAt({required double minutes, required double progress, double rain = 0}) {
    final lat = fromLat + (toLat - fromLat) * progress.clamp(0.0, 1.0);
    final (lo, hi) = dailyRange(lat);
    final k = warmth((minutes % 1440) / 60);
    return lo + (hi - lo) * k + terrain + offset - 1.5 * rain.clamp(0.0, 1.0);
  }
}

/// Rét ảnh hưởng tới người và xe thế nào (hàm thuần, dễ thử).
abstract class ColdEffects {
  /// Mức rét 0..1: 0 từ [ColdClimate.coldBelow] trở lên, 1 khi xuống 4 °C.
  static double chill(double celsius) => ((ColdClimate.coldBelow - celsius) / (ColdClimate.coldBelow - 4)).clamp(0.0, 1.0);

  /// Sương muối phủ ruộng, bờ cỏ (0..1): đèo núi xuống dưới 9 °C là trắng
  /// dần, 4 °C thì phủ kín; đồng bằng chỉ phủ mỏng lúc rét hại.
  static double frost(double celsius, {required bool mountain}) {
    final k = mountain ? (9 - celsius) / 5 : (11 - celsius) / 5.5;
    final s = k.clamp(0.0, 1.0);
    return s * s * (3 - 2 * s) * (mountain ? 1 : 0.6);
  }

  /// Tay cóng: phần sức lái mất đi (tối đa 15%). Chỉ người đi xe máy không
  /// đeo găng tay mới bị; ngồi trong ô tô có sưởi thì không.
  static double numb(double celsius, {required bool exposed, required bool gloves}) {
    if (!exposed || gloves) return 0;
    return 0.15 * ((ColdClimate.coldBelow + 0.5 - celsius) / 2).clamp(0.0, 1.0);
  }

  /// Hệ số mau mệt khi rét (nhân vào tốc độ tụt tỉnh táo): rét thì mỏi hơn
  /// chút, rét mà ướt sũng thì mệt hẳn.
  static double alertFactor(double celsius, {required bool exposed, required double soaked}) {
    if (!exposed) return 1;
    final k = chill(celsius);
    return 1 + 0.15 * k + 0.4 * k * soaked.clamp(0.0, 1.0);
  }

  /// Số lần bấm Ga (đạp nổ) mới nổ máy xe máy để nguội ngoài trời rét: 2
  /// hoặc 3 ([roll] 0..1 ngẫu nhiên; càng rét càng hay phải 3 lần).
  static int kicksNeeded(double celsius, double roll) => roll < 0.3 + 0.45 * chill(celsius) ? 3 : 2;

  /// Nhãn chip HUD: "Rét đậm 9°C", "Rét hại 6°C".
  static String label(double celsius) => '${severe(celsius) ? 'Rét hại' : 'Rét đậm'} ${celsius.round()}°C';

  /// Rét hại: nhiệt độ (làm tròn như trên HUD) không quá [ColdClimate.severeBelow].
  static bool severe(double celsius) => celsius.round() <= ColdClimate.severeBelow;
}

/// Rét và hơi men hiện trên HUD.
class NightColdHud {
  const NightColdHud({this.celsius, this.severe = false, this.numb = false, this.kicksLeft, this.alcohol, this.soberMinutes});

  /// Đang rét: nhiệt độ (°C, làm tròn); null khi không rét.
  final int? celsius;
  final bool severe;

  /// Tay cóng vì chưa có găng tay.
  final bool numb;

  /// Máy nguội: còn phải bấm Ga mấy lần nữa mới nổ (null = máy đang chạy).
  final int? kicksLeft;

  /// Hơi men (phần trăm mg/L khí thở, ví dụ 12 = 0,12 mg/L) và còn chừng
  /// bao nhiêu phút mới hết; null khi tỉnh.
  final int? alcohol;
  final int? soberMinutes;

  String? get label => celsius == null ? null : '${severe ? 'Rét hại' : 'Rét đậm'} $celsius°C';

  @override
  bool operator ==(Object other) =>
      other is NightColdHud &&
      other.celsius == celsius &&
      other.severe == severe &&
      other.numb == numb &&
      other.kicksLeft == kicksLeft &&
      other.alcohol == alcohol &&
      other.soberMinutes == soberMinutes;

  @override
  int get hashCode => Object.hash(celsius, severe, numb, kicksLeft, alcohol, soberMinutes);
}
