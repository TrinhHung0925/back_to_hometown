import '../game_config.dart';

/// Hộp va chạm trong toạ độ đường: tâm ([s], [d]), dài [length] dọc đường,
/// rộng [width] ngang đường. Mọi xe đều chạy dọc đường nên so hộp thẳng
/// trong toạ độ này là đủ chính xác, kể cả ở khúc cong.
class RoadBox {
  const RoadBox({required this.s, required this.d, required this.length, required this.width});

  final double s;
  final double d;
  final double length;
  final double width;

  bool overlaps(RoadBox other, {double shrink = GameConfig.hitboxShrink}) {
    final ds = (s - other.s).abs();
    final dd = (d - other.d).abs();
    return ds < (length + other.length) / 2 * shrink && dd < (width + other.width) / 2 * shrink;
  }
}

enum CollisionSeverity {
  /// Quẹt nhẹ: dừng lại giải quyết, công an tới.
  minor,

  /// Đâm mạnh: tai nạn, thua ngay.
  accident,
}

/// Chênh lệch tốc độ lúc đâm. [playerSpeed] luôn dọc chiều đi;
/// [otherVelocity] có dấu: dương là xe cùng chiều, âm là xe ngược chiều.
double relativeImpactSpeed(double playerSpeed, double otherVelocity) => (playerSpeed - otherVelocity).abs();

CollisionSeverity classifyCollision(double relativeSpeed) =>
    relativeSpeed >= GameConfig.accidentRelativeSpeed ? CollisionSeverity.accident : CollisionSeverity.minor;

/// Tốc độ "nguy hiểm" để tô đỏ vòng tốc độ quanh nút ga: đâm vào một xe
/// cùng chiều chạy chậm nhất ở tốc độ này là thành tai nạn.
const double dangerSpeed = GameConfig.accidentRelativeSpeed + GameConfig.sameDirSpeedMin * GameConfig.normalSpeed;
