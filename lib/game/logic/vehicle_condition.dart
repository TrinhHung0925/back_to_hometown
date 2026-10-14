import 'dart:math';

import '../game_config.dart';
import '../vehicle_spec.dart';

/// Bình xăng (0..1). Tốn theo quãng đường: chạy nhanh và chở nặng thì tốn
/// hơn, đứng yên nổ máy tốn rất ít.
class FuelTank {
  FuelTank(this.kind, {required double level}) : level = level.clamp(0.0, 1.0);

  final VehicleKind kind;
  double level;

  double get rangeKm => switch (kind) {
        VehicleKind.motorbike => GameConfig.fuelRangeKmMotorbike,
        VehicleKind.car => GameConfig.fuelRangeKmCar,
        VehicleKind.bus => GameConfig.fuelRangeKmBus,
      };

  /// Một lì xì đổ được bao nhiêu phần bình ở cây xăng.
  double get perLixi => switch (kind) {
        VehicleKind.motorbike => GameConfig.fuelPerLixiMotorbike,
        VehicleKind.car => GameConfig.fuelPerLixiCar,
        VehicleKind.bus => GameConfig.fuelPerLixiBus,
      };

  bool get empty => level <= 0;
  bool get low => level < GameConfig.fuelLow;
  bool get sputtering => level < GameConfig.fuelSputter;

  /// Còn chạy được chừng bao nhiêu km ở tốc độ thường.
  double get kmLeft => level * rangeKm;

  /// Đi thêm [units] ở tốc độ [speed], chở [cargo] món.
  void burn(double units, double speed, int cargo) {
    if (units <= 0) return;
    final pace = speed / GameConfig.normalSpeed;
    final rate = (0.6 + 0.4 * pace * pace) * (1 + 0.03 * cargo);
    level = max(0, level - units / GameConfig.unitsPerKm / rangeKm * rate);
  }

  /// Số lì xì để đổ đầy bình.
  int get fullPrice => ((1 - level) / perLixi - 1e-6).ceil().clamp(0, 99);

  /// Đổ thêm [amount] phần bình (không tràn).
  double add(double amount) {
    final before = level;
    level = min(1, level + amount);
    return level - before;
  }
}

enum TireState {
  ok,

  /// Xì lốp: chạy chậm, xe bị kéo lệch.
  flat,

  /// Chạy lốp xẹp quá xa: nát săm, chỉ còn cách thay.
  ruined,
}

/// Lốp xe: xì vì đinh tặc / sập ổ gà, chạy lốp xẹp lâu thì nát săm.
class Tires {
  Tires(this.kind);

  final VehicleKind kind;
  TireState state = TireState.ok;

  /// Lốp xẹp kéo xe về bên nào (theo chiều đi: 1 phải, -1 trái).
  int pullSide = 1;

  /// Đã chạy bao nhiêu km trên lốp xẹp.
  double flatKm = 0;

  /// Ô tô, xe khách: còn lốp dự phòng không.
  bool spare = true;

  bool get ok => state == TireState.ok;

  double get flatChanceOnNails => switch (kind) {
        VehicleKind.motorbike => GameConfig.nailFlatChanceMotorbike,
        VehicleKind.car => GameConfig.nailFlatChanceCar,
        VehicleKind.bus => GameConfig.nailFlatChanceBus,
      };

  /// Tốc độ tối đa khi lốp hỏng (null nếu lốp lành).
  double? get speedCap => switch (state) {
        TireState.ok => null,
        TireState.flat => GameConfig.flatSpeedFactor * GameConfig.normalSpeed,
        TireState.ruined => GameConfig.ruinedSpeedFactor * GameConfig.normalSpeed,
      };

  /// Lực kéo lệch ngang (u/s, dương = sang phải chiều đi).
  double get pull => switch (state) {
        TireState.ok => 0,
        TireState.flat => pullSide * GameConfig.flatPull,
        TireState.ruined => pullSide * GameConfig.flatPull * 1.4,
      };

  void puncture(Random random) {
    if (!ok) return;
    state = TireState.flat;
    pullSide = random.nextBool() ? 1 : -1;
    flatKm = 0;
  }

  /// Chạy tiếp trên lốp xẹp. Trả về true lúc vừa nát săm.
  bool roll(double units) {
    if (state != TireState.flat) return false;
    flatKm += units / GameConfig.unitsPerKm;
    if (flatKm < GameConfig.flatRuinKm) return false;
    state = TireState.ruined;
    return true;
  }

  void fix() {
    state = TireState.ok;
    flatKm = 0;
  }
}

/// Một cách sửa lốp ở tiệm vá xe / bên lề: giá, phút, có làm được với lốp
/// đã nát không.
class RepairOption {
  const RepairOption(this.name, {required this.detail, required this.price, required this.minutes, required this.art, this.forRuined = true});

  final String name;
  final String detail;
  final int price;
  final double minutes;
  final bool forRuined;

  /// Tên hình minh hoạ (assets/images/img_item_[art].png).
  final String art;

  /// Các cách sửa ở tiệm vá xe theo loại xe. Tiệm "chặn đầu" sau bãi đinh
  /// lấy giá gấp đôi.
  static List<RepairOption> shopOptions(VehicleKind kind, {bool gouging = false}) {
    final k = gouging ? 2 : 1;
    return kind == VehicleKind.motorbike
        ? [
            RepairOption('Vá săm', detail: 'Miếng vá dán nóng, bơm căng', price: 1 * k, minutes: 12, art: 'va_sam', forRuined: false),
            RepairOption('Thay săm mới', detail: 'Săm mới, chắc chắn', price: 2 * k, minutes: 8, art: 'thay_sam'),
          ]
        : [
            RepairOption('Vá lốp', detail: 'Rút đinh, nút lốp không săm', price: 2 * k, minutes: 15, art: 'va_lop', forRuined: false),
            RepairOption('Thay lốp mới', detail: 'Lốp mới, cân bằng động', price: 5 * k, minutes: 12, art: 'thay_lop'),
          ];
  }
}
