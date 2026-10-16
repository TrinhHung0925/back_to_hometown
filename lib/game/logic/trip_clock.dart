import '../../model/difficulty.dart';
import '../game_config.dart';

/// Đồng hồ trong game, tính bằng phút kể từ 00:00 ngày xuất phát.
/// Giao thừa là phút thứ 24 × 60 của ngày 30 Tết.
class TripClock {
  TripClock({required this.minutes, this.deadline = midnight});

  static const double midnight = 24 * 60;

  double minutes;
  final double deadline;

  bool get isOver => minutes >= deadline;

  double get minutesLeft => deadline - minutes;

  void advance(double playSeconds) {
    minutes += playSeconds * GameConfig.gameSecondsPerPlaySecond / 60;
  }

  void addPenalty(double gameMinutes) => minutes += gameMinutes;

  /// Giờ:phút để hiện trên HUD, ví dụ "22:05". Quá nửa đêm vẫn hiện tiếp
  /// ("00:12") vì lúc đó đã thua.
  String get label {
    final total = minutes.floor();
    final hours = (total / 60).floor();
    final h = hours % 24;
    final m = total - hours * 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Ngày cuối năm âm lịch: phút 0..1439 là ngày 30 Tết, âm là mấy ngày trước.
  int get day => 30 + (minutes / 1440).floor();
  String get dayLabel => '$day Tết';

  /// Giờ xuất phát tính ngược từ giao thừa khi cho phép [allowedMinutes] phút.
  static double departureFor(double allowedMinutes) => midnight - allowedMinutes;

  /// Phút cho phép đi hết [km] km chia [stages] chặng: chạy đều
  /// [Difficulty.guaranteedKmh] vẫn kịp, mỗi chặng dư thêm chút cho ghé quán.
  static double allowedMinutes(double km, int stages, [Difficulty difficulty = Difficulty.normal]) =>
      km / difficulty.guaranteedKmh * 60 + stages * difficulty.stopAllowanceMinutes;
}
