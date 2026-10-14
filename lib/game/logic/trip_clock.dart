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
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Giờ xuất phát tính ngược từ giao thừa: thời gian cho phép = thời gian
  /// ước tính × [GameConfig.timeBudgetFactor].
  static double departureFor(double estimatedPlaySeconds) {
    final estimatedGameMinutes = estimatedPlaySeconds * GameConfig.gameSecondsPerPlaySecond / 60;
    return midnight - estimatedGameMinutes * GameConfig.timeBudgetFactor;
  }
}
