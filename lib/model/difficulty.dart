import '../game/game_config.dart';

/// Độ khó người chơi chọn trước chuyến đi: đổi quỹ giờ, độ đông xe, số chốt
/// CSGT và mức mau buồn ngủ. Hỗ trợ lái bật / tắt riêng ở menu tạm dừng.
enum Difficulty {
  easy(
    'Dễ',
    'Đường thoáng, ít chốt CSGT, dư nhiều giờ',
    guaranteedKmh: 15,
    stopAllowanceMinutes: 60,
    traffic: 0.7,
    checkpoints: 0.5,
    drowsiness: 0.75,
  ),
  normal(
    'Thường',
    'Như ngày cận Tết thật',
    guaranteedKmh: GameConfig.guaranteedKmh,
    stopAllowanceMinutes: GameConfig.stopAllowanceMinutes,
    traffic: 1,
    checkpoints: 1,
    drowsiness: 1,
  ),
  hard(
    'Khó',
    'Xe đông, chốt CSGT dày, ít giờ dư',
    guaranteedKmh: 28,
    stopAllowanceMinutes: 25,
    traffic: 1.35,
    checkpoints: 1.6,
    drowsiness: 1.25,
  );

  const Difficulty(
    this.title,
    this.subtitle, {
    required this.guaranteedKmh,
    required this.stopAllowanceMinutes,
    required this.traffic,
    required this.checkpoints,
    required this.drowsiness,
  });

  final String title;
  final String subtitle;

  /// Chạy đều tốc độ này (km/h) vẫn về kịp giao thừa, cộng thêm
  /// [stopAllowanceMinutes] mỗi chặng cho ghé quán, đổ xăng, bị phạt.
  final double guaranteedKmh;
  final double stopAllowanceMinutes;

  /// Hệ số độ đông xe, số chốt CSGT, độ mau buồn ngủ (so với mức thường).
  final double traffic;
  final double checkpoints;
  final double drowsiness;
}
