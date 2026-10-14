import 'dart:math';

import '../game_config.dart';

enum RainKind {
  /// Mưa phùn: hạt nhỏ li ti, trời mù mù (miền Bắc dịp Tết).
  drizzle,

  /// Mưa rào: hạt to, nặng hạt, đường đọng vũng.
  shower,
}

/// Một cơn mưa theo giờ trong game: mưa nặng hạt dần, rồi ngớt dần.
class RainSpell {
  const RainSpell({required this.kind, required this.start, required this.end, required this.peak});

  final RainKind kind;

  /// Phút trong game (cùng mốc với đồng hồ chuyến đi).
  final double start;
  final double end;

  /// Độ nặng hạt lúc to nhất (0..1).
  final double peak;

  /// Bao nhiêu phút để mưa to dần / ngớt dần.
  static const double fade = 6;

  double levelAt(double minutes) {
    if (minutes <= start || minutes >= end) return 0;
    final k = min(minutes - start, end - minutes) / fade;
    return peak * k.clamp(0.0, 1.0);
  }
}

/// Thời tiết của một chặng: các cơn mưa theo giờ trong game.
class Weather {
  const Weather(this.spells);

  static const clear = Weather([]);

  /// Miền Bắc hay mưa phùn (thỉnh thoảng mưa rào), miền Nam dịp Tết là mùa
  /// khô, hiếm khi có cơn mưa trái mùa.
  factory Weather.forStage({
    required Random random,
    required bool south,
    required double startMinutes,
    required double expectedMinutes,
  }) {
    final chance = south ? GameConfig.rainChanceSouth : GameConfig.rainChanceNorth;
    if (random.nextDouble() >= chance) return clear;
    final shower = south || random.nextDouble() < 0.3;
    final spells = <RainSpell>[];
    var at = startMinutes + expectedMinutes * (0.08 + random.nextDouble() * 0.45);
    final count = shower ? 1 : 1 + (random.nextDouble() < 0.3 ? 1 : 0);
    for (var i = 0; i < count; i++) {
      final length = shower ? 18 + random.nextDouble() * 22 : 40 + random.nextDouble() * 50;
      spells.add(RainSpell(
        kind: shower ? RainKind.shower : RainKind.drizzle,
        start: at,
        end: at + length,
        peak: shower ? 0.8 + random.nextDouble() * 0.2 : 0.35 + random.nextDouble() * 0.2,
      ));
      at += length + 25 + random.nextDouble() * 30;
    }
    return Weather(spells);
  }

  final List<RainSpell> spells;

  /// Độ nặng hạt lúc [minutes] (0 = tạnh).
  double rainAt(double minutes) => spells.fold(0.0, (a, s) => max(a, s.levelAt(minutes)));

  /// Mặt đường ướt (0..1): đang mưa, hoặc vừa tạnh chưa khô.
  double wetAt(double minutes) {
    var wet = 0.0;
    for (final s in spells) {
      if (minutes > s.start && minutes < s.end) {
        wet = max(wet, max(s.levelAt(minutes), min(1, (minutes - s.start) / RainSpell.fade) * s.peak));
      } else if (minutes >= s.end && minutes < s.end + GameConfig.wetLingerMinutes) {
        wet = max(wet, s.peak * (1 - (minutes - s.end) / GameConfig.wetLingerMinutes));
      }
    }
    return wet.clamp(0.0, 1.0);
  }

  /// Cơn mưa đang rơi lúc [minutes] (null nếu tạnh).
  RainSpell? spellAt(double minutes) {
    for (final s in spells) {
      if (minutes > s.start && minutes < s.end) return s;
    }
    return null;
  }
}
