import 'dart:math';

import '../../model/trip.dart';
import '../game_config.dart';
import '../vehicle_spec.dart';

/// Nhiệm vụ phụ của một chặng (làm được thì tới nơi được thưởng thêm lì xì).
enum MissionKind {
  /// Không bị CSGT giữ lại, không dính phạt nguội.
  noFine,

  /// Không va quẹt xe nào, không đâm phải gà vịt chó.
  noCrash,

  /// Ghé quán ven đường gọi một món.
  restStop,

  /// Cho một người vẫy xe đi nhờ tới nơi.
  hitchhiker,

  /// Chạy hết chặng trong [Mission.target] phút (giờ trong game).
  onTime,

  /// Xe máy: cành đào còn đẹp ≥ [Mission.target]%.
  keepPeach,

  /// Xe khách: đón ≥ [Mission.target] khách.
  passengers,

  /// Nhặt ≥ [Mission.target] phong lì xì trên đường.
  collectLixi,
}

class Mission {
  const Mission(this.kind, {this.target = 0, required this.reward});

  final MissionKind kind;
  final int target;

  /// Lì xì thưởng khi tới nơi mà đã làm xong.
  final int reward;

  String get title => switch (kind) {
        MissionKind.noFine => 'Không bị phạt',
        MissionKind.noCrash => 'Không va chạm',
        MissionKind.restStop => 'Ghé quán nghỉ chân',
        MissionKind.hitchhiker => 'Cho 1 khách đi nhờ',
        MissionKind.onTime => 'Tới nơi trong ${durationLabel(target)}',
        MissionKind.keepPeach => 'Giữ cành đào đẹp ≥ $target%',
        MissionKind.passengers => 'Đón ≥ $target khách',
        MissionKind.collectLixi => 'Nhặt $target phong lì xì',
      };

  String get detail => switch (kind) {
        MissionKind.noFine => 'Không để CSGT giữ lại, không dính phạt nguội',
        MissionKind.noCrash => 'Không quệt xe, không đâm phải gà vịt',
        MissionKind.restStop => 'Vào quán ven đường gọi một món',
        MissionKind.hitchhiker => 'Đón người vẫy xe, chở tới nơi họ xuống',
        MissionKind.onTime => 'Đừng dừng lâu, đừng để bị phạt giữ xe',
        MissionKind.keepPeach => 'Tránh ổ gà, đừng quệt lề kẻo rụng hoa',
        MissionKind.passengers => 'Dừng sát lề ở các điểm đón khách',
        MissionKind.collectLixi => 'Lượn qua những phong lì xì trên đường',
      };

  /// "1 giờ 45 phút", "50 phút".
  static String durationLabel(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return '$m phút';
    return m == 0 ? '$h giờ' : '$h giờ $m phút';
  }

  @override
  bool operator ==(Object other) => other is Mission && other.kind == kind && other.target == target && other.reward == reward;

  @override
  int get hashCode => Object.hash(kind, target, reward);
}

/// Số liệu trong chặng để chấm nhiệm vụ (game cộng dồn khi có chuyện).
class MissionStats {
  /// Số lần bị CSGT giữ lại / dính phạt nguội.
  int incidents = 0;

  /// Số lần va chạm (xe, barrier, con vật).
  int bumps = 0;

  /// Số món đã gọi ở quán ăn uống.
  int meals = 0;

  /// Số khách đi nhờ đã chở tới nơi.
  int riders = 0;

  /// Số khách xe khách đã đón.
  int passengers = 0;

  /// Số phong lì xì nhặt trên đường.
  int lixiPicked = 0;
}

enum MissionState {
  /// Đang làm (chưa xong, chưa hỏng).
  active,
  done,
  failed,
}

/// Một nhiệm vụ đang tới đâu: trạng thái và dòng tiến độ ngắn.
class MissionCheck {
  const MissionCheck(this.mission, this.state, this.progress);

  final Mission mission;
  final MissionState state;
  final String progress;

  bool get done => state == MissionState.done;

  @override
  bool operator ==(Object other) =>
      other is MissionCheck && other.mission == mission && other.state == state && other.progress == progress;

  @override
  int get hashCode => Object.hash(mission, state, progress);
}

/// Chọn và chấm nhiệm vụ phụ.
abstract class Missions {
  /// Thưởng (lì xì) theo loại nhiệm vụ.
  static int rewardOf(MissionKind kind) => switch (kind) {
        MissionKind.noFine => 4,
        MissionKind.noCrash => 4,
        MissionKind.restStop => 2,
        MissionKind.hitchhiker => 3,
        MissionKind.onTime => 5,
        MissionKind.keepPeach => 4,
        MissionKind.passengers => 4,
        MissionKind.collectLixi => 3,
      };

  /// Cặp nhiệm vụ không giao cùng nhau (trùng ý hoặc ngược nhau).
  static bool _clash(MissionKind a, MissionKind b) {
    bool pair(MissionKind x, MissionKind y) => (a == x && b == y) || (a == y && b == x);
    return pair(MissionKind.noFine, MissionKind.noCrash) || pair(MissionKind.onTime, MissionKind.restStop);
  }

  /// Hạt giống ổn định theo chặng (FNV-1a): cùng chặng, cùng xe thì cùng
  /// nhiệm vụ — ở trạm dừng nghỉ, trong game hay lúc chơi lại đều như nhau.
  static int seedFor(String fromName, String toName, int stageNumber, VehicleKind vehicle) {
    var h = 0x811c9dc5;
    for (final c in '$fromName|$toName|$stageNumber|${vehicle.name}'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Phút trong game để chạy hết các đoạn [sections] ở tốc độ thường.
  static double normalMinutes(List<StageSection> sections) =>
      sections.fold(0.0, (sum, s) => sum + s.playSeconds) * GameConfig.gameSecondsPerPlaySecond / 60;

  /// Số điểm đón khách của xe khách (cùng cách tính với RoadLayout).
  static int busStopCount(List<StageSection> sections) {
    final km = sections.where((s) => s.kind != RoadKind.expressway).fold(0.0, (sum, s) => sum + s.km);
    return (km / GameConfig.busStopEveryKm).round().clamp(2, 6);
  }

  /// 1–2 nhiệm vụ cho một chặng, chọn theo [seed] trong các nhiệm vụ hợp
  /// với loại xe và đường đi. Chặng ngắn (< 40 km) chỉ một nhiệm vụ.
  static List<Mission> forStage({
    required VehicleKind vehicle,
    required List<StageSection> sections,
    required int seed,
    double startPeach = -1,

    /// Xe máy chở cả nhà: hết chỗ cho người đi nhờ.
    bool family = false,
  }) {
    final km = sections.fold(0.0, (sum, s) => sum + s.km);
    if (km <= 0) return const [];
    final highwayKm = sections.where((s) => s.kind == RoadKind.highway).fold(0.0, (sum, s) => sum + s.km);
    final slowKm = sections.where((s) => s.kind != RoadKind.expressway).fold(0.0, (sum, s) => sum + s.km);
    final pool = <Mission>[
      Mission(MissionKind.noFine, reward: rewardOf(MissionKind.noFine)),
      Mission(MissionKind.noCrash, reward: rewardOf(MissionKind.noCrash)),
      if (slowKm >= 10) Mission(MissionKind.restStop, reward: rewardOf(MissionKind.restStop)),
      if (vehicle != VehicleKind.bus && !(family && vehicle == VehicleKind.motorbike) && highwayKm >= 20) Mission(MissionKind.hitchhiker, reward: rewardOf(MissionKind.hitchhiker)),
      Mission(MissionKind.onTime, target: onTimeTarget(sections), reward: rewardOf(MissionKind.onTime)),
      if (vehicle == VehicleKind.motorbike && peachTarget(startPeach) >= 40)
        Mission(MissionKind.keepPeach, target: peachTarget(startPeach), reward: rewardOf(MissionKind.keepPeach)),
      if (vehicle == VehicleKind.bus) Mission(MissionKind.passengers, target: passengerTarget(sections), reward: rewardOf(MissionKind.passengers)),
      Mission(MissionKind.collectLixi, target: lixiTarget(sections), reward: rewardOf(MissionKind.collectLixi)),
    ];
    final r = Random(seed);
    // Nhiệm vụ riêng của loại xe (cành đào, đón khách) hay được giao hơn.
    final weighted = [
      for (final m in pool) (m, r.nextDouble() * (m.kind == MissionKind.keepPeach || m.kind == MissionKind.passengers ? 2.2 : 1)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final count = km < 40 ? 1 : 2;
    final out = <Mission>[];
    for (final (m, _) in weighted) {
      if (out.length >= count) break;
      if (out.any((o) => _clash(o.kind, m.kind))) continue;
      out.add(m);
    }
    return out;
  }

  /// Hạn giờ: bằng thời gian chạy thường, làm tròn lên 5 phút (chạy nhanh
  /// hơn thường, ghé ít, không bị giữ xe mới kịp).
  static int onTimeTarget(List<StageSection> sections) => (normalMinutes(sections) / 5).ceil() * 5;

  /// Cành đào: giữ được tới 80%, thấp hơn nếu đã rụng bớt từ chặng trước.
  static int peachTarget(double startPeach) => startPeach < 0 ? -1 : min(80, ((startPeach - 12) / 5).floor() * 5);

  /// Số khách cần đón: đủ đón hết các điểm (ít nhất 2 khách mỗi điểm) là kịp.
  static int passengerTarget(List<StageSection> sections) {
    final stops = busStopCount(sections);
    return min(stops * 2, max(2, (stops - 1) * 3));
  }

  /// Lì xì cần nhặt: theo thời gian chơi ước tính (lì xì rơi đều theo thời gian).
  static int lixiTarget(List<StageSection> sections) =>
      (sections.fold(0.0, (sum, s) => sum + s.playSeconds) * 0.15).round().clamp(8, 30);

  /// Chấm một nhiệm vụ lúc này. [elapsed] phút trong game từ đầu chặng (gồm
  /// phút bị giữ xe, ngồi quán); [peach] cành đào còn bao nhiêu (âm = không
  /// chở); [arrived] đã về tới cuối chặng.
  static MissionCheck check(Mission m, MissionStats s, {required double elapsed, double peach = -1, bool arrived = false}) {
    MissionCheck at(MissionState state, String progress) => MissionCheck(m, state, progress);
    MissionCheck count(int have, String unit) =>
        have >= m.target ? at(MissionState.done, '$have/${m.target} $unit') : at(arrived ? MissionState.failed : MissionState.active, '$have/${m.target} $unit');
    switch (m.kind) {
      case MissionKind.noFine:
        if (s.incidents > 0) return at(MissionState.failed, 'Đã bị phạt');
        return at(arrived ? MissionState.done : MissionState.active, 'Chưa bị phạt lần nào');
      case MissionKind.noCrash:
        if (s.bumps > 0) return at(MissionState.failed, 'Đã va chạm');
        return at(arrived ? MissionState.done : MissionState.active, 'Chưa va quẹt lần nào');
      case MissionKind.restStop:
        if (s.meals > 0) return at(MissionState.done, 'Đã ghé quán');
        return at(arrived ? MissionState.failed : MissionState.active, 'Chưa ghé quán');
      case MissionKind.hitchhiker:
        if (s.riders > 0) return at(MissionState.done, 'Đã chở khách tới nơi');
        return at(arrived ? MissionState.failed : MissionState.active, 'Chưa chở ai');
      case MissionKind.onTime:
        final left = (m.target - elapsed).floor();
        if (left < 0) return at(MissionState.failed, 'Quá giờ rồi');
        return at(arrived ? MissionState.done : MissionState.active, arrived ? 'Kịp, dư $left phút' : 'Còn ${Mission.durationLabel(left)}');
      case MissionKind.keepPeach:
        final now = max(0, peach).round();
        if (peach < m.target) return at(MissionState.failed, 'Cành đào còn $now%');
        return at(arrived ? MissionState.done : MissionState.active, 'Cành đào còn $now%');
      case MissionKind.passengers:
        return count(s.passengers, 'khách');
      case MissionKind.collectLixi:
        return count(s.lixiPicked, 'phong');
    }
  }

  static List<MissionCheck> checkAll(List<Mission> missions, MissionStats s, {required double elapsed, double peach = -1, bool arrived = false}) =>
      [for (final m in missions) check(m, s, elapsed: elapsed, peach: peach, arrived: arrived)];

  /// Lì xì thưởng của các nhiệm vụ đã xong.
  static int rewardSum(Iterable<MissionCheck> checks) => checks.fold(0, (sum, c) => sum + (c.done ? c.mission.reward : 0));
}

/// Theo dõi nhiệm vụ giữa chặng: báo ra khi một nhiệm vụ vừa xong / vừa hỏng
/// (để hiện thông báo một lần).
class MissionWatch {
  final Map<MissionKind, MissionState> _last = {};

  /// Các nhiệm vụ vừa đổi trạng thái so với lần trước.
  List<MissionCheck> changes(List<MissionCheck> checks) {
    final out = <MissionCheck>[];
    for (final c in checks) {
      final before = _last[c.mission.kind] ?? MissionState.active;
      if (before != c.state) out.add(c);
      _last[c.mission.kind] = c.state;
    }
    return out;
  }

  void reset() => _last.clear();
}
