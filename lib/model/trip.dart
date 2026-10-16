import '../game/game_config.dart';
import '../game/vehicle_spec.dart';
import 'difficulty.dart';
import 'shop.dart';

/// Loại đoạn đường trong một chặng.
enum RoadKind {
  /// Phố trong thành phố: chạy chậm, ngã tư đèn xanh đèn đỏ.
  city,

  /// Quốc lộ: 2 chiều, xe ngược chiều, ổ gà, trạm thu phí BOT.
  highway,

  /// Cao tốc (chỉ ô tô): gần như thẳng, không lấn sang chiều ngược.
  expressway,
}

/// Một đoạn liên tục cùng loại đường trong chặng.
class StageSection {
  const StageSection(this.kind, this.km);

  final RoadKind kind;
  final double km;

  /// Thời gian chơi ước tính (giây) ở tốc độ thường: phố chậm hơn (đèn đỏ,
  /// xe đông), cao tốc nhanh hơn.
  double get playSeconds =>
      km *
      GameConfig.playSecondsPerKm *
      switch (kind) {
        RoadKind.city => GameConfig.cityPaceFactor,
        RoadKind.highway => 1.0,
        RoadKind.expressway => GameConfig.expresswayPaceFactor,
      };

  Map<String, dynamic> toJson() => {'kind': kind.name, 'km': km};

  factory StageSection.fromJson(Map<String, dynamic> json) =>
      StageSection(RoadKind.values.byName(json['kind'] as String), (json['km'] as num).toDouble());
}

/// Một chặng chơi (khoảng 3–5 phút), nối hai điểm dừng.
class TripStage {
  const TripStage({
    required this.fromName,
    required this.toName,
    required this.sections,
    required this.tollBooths,
  });

  final String fromName;
  final String toName;
  final List<StageSection> sections;

  /// Số trạm thu phí trên chặng.
  final int tollBooths;

  double get km => sections.fold(0, (sum, s) => sum + s.km);

  Map<String, dynamic> toJson() => {
        'from': fromName,
        'to': toName,
        'sections': [for (final s in sections) s.toJson()],
        'tolls': tollBooths,
      };

  factory TripStage.fromJson(Map<String, dynamic> json) => TripStage(
        fromName: json['from'] as String,
        toName: json['to'] as String,
        sections: [for (final s in json['sections'] as List) StageSection.fromJson(Map<String, dynamic>.from(s as Map))],
        tollBooths: json['tolls'] as int,
      );
}

/// Lộ trình tìm được: dãy điểm đi qua và các chặng chơi.
class TripPlan {
  const TripPlan({
    required this.vehicle,
    required this.placeIds,
    required this.stages,
    required this.km,
    required this.expresswayKm,
    required this.realHours,
    required this.tollBooths,
  });

  final VehicleKind vehicle;

  /// Các điểm đi qua, từ điểm xuất phát tới điểm đến.
  final List<String> placeIds;
  final List<TripStage> stages;
  final double km;
  final double expresswayKm;

  /// Thời gian lái thực tế ước tính (giờ).
  final double realHours;
  final int tollBooths;

  Map<String, dynamic> toJson() => {
        'vehicle': vehicle.name,
        'places': placeIds,
        'stages': [for (final s in stages) s.toJson()],
        'km': km,
        'expresswayKm': expresswayKm,
        'realHours': realHours,
        'tolls': tollBooths,
      };

  factory TripPlan.fromJson(Map<String, dynamic> json) => TripPlan(
        vehicle: VehicleKind.values.byName(json['vehicle'] as String),
        placeIds: List<String>.from(json['places'] as List),
        stages: [for (final s in json['stages'] as List) TripStage.fromJson(Map<String, dynamic>.from(s as Map))],
        km: (json['km'] as num).toDouble(),
        expresswayKm: (json['expresswayKm'] as num).toDouble(),
        realHours: (json['realHours'] as num).toDouble(),
        tollBooths: json['tolls'] as int,
      );
}

/// Chuyến đi đang chơi dở: lộ trình + tiến độ, lưu lại ở trạm dừng nghỉ.
class TripProgress {
  TripProgress({
    required this.plan,
    required this.stageIndex,
    required this.clockMinutes,
    required this.lixi,
    required this.cargo,
    this.fuel = 0.6,
    this.score = 0,
    this.budget = GameConfig.timeBudgetFactor,
    this.peach = -1,
    this.difficulty = Difficulty.normal,
    Set<Upgrade>? upgrades,
    List<Gift>? gifts,
  })  : upgrades = upgrades ?? {},
        gifts = gifts ?? [];

  final TripPlan plan;

  /// Độ khó chọn lúc lên đường (giữ nguyên cả chuyến).
  final Difficulty difficulty;

  /// Chặng sắp chơi (hoặc đang chơi).
  int stageIndex;

  /// Giờ trong game lúc bắt đầu chặng [stageIndex].
  double clockMinutes;
  int lixi;
  int cargo;

  /// Xăng trong bình (0..1) mang sang chặng sau.
  double fuel;

  /// Tổng điểm các chặng đã xong.
  int score;

  /// Hệ số thời gian cho phép lúc tính giờ xuất phát (bản cũ là 1,25).
  double budget;

  /// Cành đào buộc sau xe máy còn đẹp bao nhiêu (0..100); âm = không chở.
  double peach;

  /// Nâng cấp xe đã mua ở cửa hàng trạm dừng nghỉ (giữ cả chuyến).
  final Set<Upgrade> upgrades;

  /// Quà Tết đã mua cho người nhà (mỗi người một món).
  final List<Gift> gifts;

  bool get finished => stageIndex >= plan.stages.length;

  Map<String, dynamic> toJson() => {
        'plan': plan.toJson(),
        'stage': stageIndex,
        'clock': clockMinutes,
        'lixi': lixi,
        'cargo': cargo,
        'fuel': fuel,
        'score': score,
        'budget': budget,
        'peach': peach,
        'difficulty': difficulty.name,
        'upgrades': [for (final u in upgrades) u.name],
        'gifts': [for (final g in gifts) g.name],
      };

  factory TripProgress.fromJson(Map<String, dynamic> json) => TripProgress(
        plan: TripPlan.fromJson(Map<String, dynamic>.from(json['plan'] as Map)),
        stageIndex: json['stage'] as int,
        clockMinutes: (json['clock'] as num).toDouble(),
        lixi: json['lixi'] as int,
        cargo: json['cargo'] as int,
        fuel: (json['fuel'] as num?)?.toDouble() ?? 0.6,
        score: (json['score'] as int?) ?? 0,
        budget: (json['budget'] as num?)?.toDouble() ?? 1.25,
        peach: (json['peach'] as num?)?.toDouble() ?? -1,
        difficulty: Difficulty.values.asNameMap()[json['difficulty']] ?? Difficulty.normal,
        upgrades: Upgrade.parse(json['upgrades']),
        gifts: Gift.parse(json['gifts']),
      );
}

/// Kỷ lục của một tuyến (điểm đi → điểm đến, loại xe).
class TripRecord {
  const TripRecord({
    required this.fromName,
    required this.toName,
    required this.vehicle,
    required this.score,
    required this.km,
    required this.arrivedMinutes,
  });

  final String fromName;
  final String toName;
  final VehicleKind vehicle;
  final int score;
  final double km;

  /// Giờ về tới nhà (phút trong ngày giao thừa).
  final double arrivedMinutes;

  String get key => '$fromName|$toName|${vehicle.name}';

  Map<String, dynamic> toJson() => {
        'from': fromName,
        'to': toName,
        'vehicle': vehicle.name,
        'score': score,
        'km': km,
        'arrived': arrivedMinutes,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) => TripRecord(
        fromName: json['from'] as String,
        toName: json['to'] as String,
        vehicle: VehicleKind.values.byName(json['vehicle'] as String),
        score: json['score'] as int,
        km: (json['km'] as num).toDouble(),
        arrivedMinutes: (json['arrived'] as num).toDouble(),
      );
}

/// Tổng kết khi về tới nhà.
class TripSummary {
  const TripSummary({required this.record, required this.newRecord, this.previousBest, this.giftBonus = 0});

  final TripRecord record;
  final bool newRecord;
  final int? previousBest;

  /// Điểm thưởng quà Tết mang về biếu cả nhà (đã cộng vào [record]).
  final int giftBonus;
}
