import 'game_config.dart';

enum VehicleKind {
  motorbike,
  car,

  /// Xe khách (chế độ "Đi xe khách": lái xe khách đón người về quê).
  bus;

  /// Ô tô và xe khách: được đi cao tốc, dùng làn thu phí không dừng.
  bool get fourWheels => this != motorbike;
}

/// Thông số xe của người chơi. Đơn vị theo [GameConfig].
class VehicleSpec {
  const VehicleSpec({
    required this.kind,
    required this.length,
    required this.width,
    required this.maxSpeed,
    required this.accel,
    required this.brakeDecel,
    required this.lateralSpeed,
    required this.steerResponse,
    required this.cargoCapacity,
    required this.cargoPenaltyPerItem,
  });

  final VehicleKind kind;

  /// Kích thước trên mặt đường (dọc theo đường × ngang đường).
  final double length;
  final double width;

  final double maxSpeed;

  /// Gia tốc khi giữ ga, giảm tốc khi giữ phanh (u/s²).
  final double accel;
  final double brakeDecel;

  /// Tốc độ dạt ngang tối đa khi kéo hết cần lái.
  final double lateralSpeed;

  /// Độ nhạy tay lái: tốc độ dạt ngang bám theo cần lái nhanh cỡ nào.
  final double steerResponse;

  /// Chở tối đa bao nhiêu món quà, mỗi món làm xe kém đi bao nhiêu phần.
  final int cargoCapacity;
  final double cargoPenaltyPerItem;

  static const motorbike = VehicleSpec(
    kind: VehicleKind.motorbike,
    length: 60,
    width: 26,
    maxSpeed: 1.8 * GameConfig.normalSpeed,
    accel: 250,
    brakeDecel: 520,
    lateralSpeed: 135,
    steerResponse: 8,
    cargoCapacity: 6,
    cargoPenaltyPerItem: 0.07,
  );

  static const car = VehicleSpec(
    kind: VehicleKind.car,
    length: 92,
    width: 46,
    maxSpeed: 2.2 * GameConfig.normalSpeed,
    accel: 195,
    brakeDecel: 460,
    lateralSpeed: 108,
    steerResponse: 5.5,
    cargoCapacity: 12,
    cargoPenaltyPerItem: 0.025,
  );

  static const bus = VehicleSpec(
    kind: VehicleKind.bus,
    length: 172,
    width: 54,
    maxSpeed: 1.8 * GameConfig.normalSpeed,
    accel: 135,
    brakeDecel: 380,
    lateralSpeed: 86,
    steerResponse: 4.2,
    cargoCapacity: 40,
    cargoPenaltyPerItem: 0,
  );

  static VehicleSpec of(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => motorbike,
        VehicleKind.car => car,
        VehicleKind.bus => bus,
      };

  /// Hệ số còn lại sau khi chở [cargo] món (không bao giờ dưới 0.5).
  double handlingFactor(int cargo) => (1 - cargoPenaltyPerItem * cargo).clamp(0.5, 1.0);
}
