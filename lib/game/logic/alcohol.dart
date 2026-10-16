import 'dart:math';

/// Hơi men trong người, tính theo số đọc của máy đo (mg cồn / 1 lít khí thở).
/// Mỗi chén rượu mừng xuân cộng thêm [cupDose]; gan đào thải đều đặn
/// [eliminationPerHour] (không phụ thuộc uống nhiều hay ít) nên một chén
/// chừng 2 tiếng mới hết hẳn, hai chén chừng 4 tiếng.
class AlcoholLevel {
  AlcoholLevel();

  static const double cupDose = 0.12;
  static const double eliminationPerHour = 0.06;

  double _level = 0;
  double _at = 0;

  /// Mức hơi men lúc [minutes] (phút đồng hồ chuyến đi).
  double at(double minutes) => max(0.0, _level - eliminationPerHour * (minutes - _at) / 60);

  /// Uống [cups] chén lúc [minutes].
  void drink(double minutes, {int cups = 1}) {
    _level = at(minutes) + cupDose * cups;
    _at = minutes;
  }

  /// Còn bao nhiêu phút nữa mới hết hơi men.
  double minutesToSober(double minutes) => at(minutes) / eliminationPerHour * 60;

  /// Số hiện trên máy đo lúc [minutes] (làm tròn 0,01 mg/L).
  double readingAt(double minutes) => reading(at(minutes));

  static double reading(double level) => (level * 100).round() / 100;
}

/// Mức vi phạm nồng độ cồn theo số đo khí thở (như quy định xử phạt hiện
/// hành): mức 1 chưa vượt 0,25 mg/L, mức 2 tới 0,4 mg/L, mức 3 trên 0,4.
/// Luật cấm tuyệt đối: đã có cồn trong hơi thở là vi phạm.
enum AlcoholTier {
  none(0, 0, ''),
  level1(3, 15, 'chưa vượt quá 0,25 mg/1 lít khí thở'),
  level2(5, 25, 'vượt quá 0,25 đến 0,4 mg/1 lít khí thở'),
  level3(7, 35, 'vượt quá 0,4 mg/1 lít khí thở');

  const AlcoholTier(this.fineLixi, this.waitMinutes, this.band);

  /// Tiền phạt (lì xì) và số phút ngồi chờ hết hơi men mới được đi tiếp.
  final int fineLixi;
  final double waitMinutes;

  /// Khung nồng độ ghi trên biên bản.
  final String band;

  static AlcoholTier of(double reading) {
    if (reading <= 0) return none;
    if (reading <= 0.25) return level1;
    if (reading <= 0.4) return level2;
    return level3;
  }

  /// "Mức 1", "Mức 2"…
  String get title => 'Mức $index';
}

/// Kết quả một lần thổi ở chốt kiểm tra nồng độ cồn.
class BreathReading {
  const BreathReading({required this.value, required this.tier, required this.enoughLixi});

  /// Số đo (mg/L khí thở, làm tròn 0,01).
  final double value;
  final AlcoholTier tier;

  /// Đủ lì xì nộp phạt không.
  final bool enoughLixi;

  bool get positive => tier != AlcoholTier.none;

  /// Không đủ lì xì thì nộp hết, chờ thêm chừng này phút.
  static const double brokeExtraMinutes = 10;

  /// Phút bị giữ lại (cả lúc thổi): âm tính chỉ mất [testMinutes].
  static const double testMinutes = 3;
  double get minutes => testMinutes + tier.waitMinutes + (positive && !enoughLixi ? brokeExtraMinutes : 0);

  /// Số đọc kiểu máy đo: "0,18".
  String get display => value.toStringAsFixed(2).replaceAll('.', ',');
}
