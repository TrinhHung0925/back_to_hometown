import 'dart:math';

import '../game/game_config.dart';
import '../game/logic/trip_clock.dart';
import '../game/logic/vehicle_condition.dart';
import '../game/stage.dart';
import '../game/vehicle_spec.dart';
import '../model/difficulty.dart';
import '../model/map_theme.dart';
import '../model/place.dart';
import '../model/trip.dart';
import 'local_service.dart';
import 'route_service.dart';

/// Chuyến đi đang chơi: tạo từ lộ trình, dựng chặng, lưu/đọc tiến độ.
class TripService {
  static final TripService shared = TripService._internal();

  factory TripService() => shared;

  TripService._internal();

  final _random = Random();

  TripProgress? _current;

  /// Chuyến đi đang dở (đọc từ máy nếu app vừa mở lại).
  TripProgress? get current {
    if (_current != null) return _current;
    final json = LocalService.shared.getTrip();
    if (json == null) return null;
    try {
      _current = TripProgress.fromJson(json);
    } catch (_) {
      // Dữ liệu cũ không đọc được thì bỏ.
      LocalService.shared.clearTrip();
    }
    final progress = _current;
    if (progress != null && !progress.finished && progress.budget < GameConfig.timeBudgetFactor) {
      // Chuyến lưu từ bản cũ (ít thời gian dư hơn): lùi đồng hồ cho phần
      // đường còn lại được dư như chuyến mới.
      final stages = progress.plan.stages.skip(progress.stageIndex);
      final old = progress.budget * stages.fold(0.0, (sum, s) => sum + stageGameMinutes(s));
      final now = TripClock.allowedMinutes(stages.fold(0.0, (sum, s) => sum + s.km), stages.length, progress.difficulty);
      progress
        ..clockMinutes -= max(0.0, now - old)
        ..budget = GameConfig.timeBudgetFactor;
      _save(progress);
    }
    return _current;
  }

  bool get hasTrip => current != null && !current!.finished;

  /// Giờ xuất phát: tính ngược từ giao thừa theo thời gian chơi ước tính.
  static double departureFor(TripPlan plan, [Difficulty difficulty = Difficulty.normal]) =>
      TripClock.departureFor(TripClock.allowedMinutes(plan.stages.fold(0.0, (sum, s) => sum + s.km), plan.stages.length, difficulty));

  TripProgress start(TripPlan plan) {
    final difficulty = LocalService.shared.getDifficulty();
    final progress = TripProgress(
      plan: plan,
      difficulty: difficulty,
      stageIndex: 0,
      clockMinutes: departureFor(plan, difficulty),
      lixi: 0,
      cargo: 0,
      // Đi vội, bình còn chừng nửa (chưa kịp đổ đầy).
      fuel: GameConfig.fuelTripStartMin + _random.nextDouble() * (GameConfig.fuelTripStartMax - GameConfig.fuelTripStartMin),
      // Đi xe máy thì buộc cành đào sau yên mang về cắm Tết.
      peach: plan.vehicle == VehicleKind.motorbike ? 100 : -1,
    );
    _save(progress);
    return progress;
  }

  StageSetup stageSetup(TripProgress progress) {
    final stage = progress.plan.stages[progress.stageIndex];
    return StageSetup(
      vehicle: progress.plan.vehicle,
      fromName: stage.fromName,
      toName: stage.toName,
      sections: stage.sections,
      tollBooths: stage.tollBooths,
      startClockMinutes: progress.clockMinutes,
      startLixi: progress.lixi,
      startCargo: progress.cargo,
      startFuel: progress.fuel,
      startPeach: progress.peach,
      stageNumber: progress.stageIndex + 1,
      stageCount: progress.plan.stages.length,
      seed: _random.nextInt(1 << 20),
      south: _isSouth(progress.plan, progress.stageIndex),
      laterMinutes: progress.plan.stages.skip(progress.stageIndex + 1).fold(0.0, (sum, s) => sum + stageGameMinutes(s)),
      theme: themeFor(stage.fromName, stage.toName),
      sky: LocalService.shared.getSkyMode(),
      difficulty: progress.difficulty,
    );
  }

  /// Bản đồ đang chọn (tự động thì theo vùng) cho chặng từ [from] tới [to].
  static MapTheme themeFor(String from, String to) => LocalService.shared.getMapTheme().resolve(_place(from), _place(to));

  /// Điểm trên bản đồ có tên ở cuối tên điểm dừng của chặng.
  static Place? _place(String name) {
    for (final p in RouteService.shared.places) {
      if (name.endsWith(p.name)) return p;
    }
    return null;
  }

  /// Chặng ở phía nam vĩ tuyến ~12,8° (từ Nha Trang trở vào): ruộng lúa
  /// chín vàng dịp Tết.
  static bool _isSouth(TripPlan plan, int stageIndex) {
    final places = RouteService.shared.places;
    final name = plan.stages[stageIndex].toName;
    final match = places.where((p) => name.endsWith(p.name));
    final y = match.isNotEmpty ? match.first.y : places.firstWhere((p) => p.id == plan.placeIds.last).y;
    return 32 - y < 12.8;
  }

  /// Đổ đầy bình ở trạm dừng nghỉ (giá như cây xăng, mất vài phút). Trả về
  /// false nếu bình đã đầy hoặc không đủ lì xì.
  bool refuelAtRestStop(TripProgress progress) {
    final tank = FuelTank(progress.plan.vehicle, level: progress.fuel);
    final price = tank.fullPrice;
    if (price <= 0 || progress.lixi < price) return false;
    progress
      ..lixi -= price
      ..fuel = 1
      ..clockMinutes += 5;
    _save(progress);
    return true;
  }

  /// Về tới cuối chặng: sang chặng sau, lưu lại (đây là "trạm dừng nghỉ").
  /// Chặng cuối thì trả về tổng kết cả chuyến (và lưu kỷ lục nếu cao hơn).
  TripSummary? completeStage(StageResult result) {
    final progress = current;
    if (progress == null) return null;
    progress
      ..stageIndex += 1
      ..clockMinutes = result.clockMinutes
      ..lixi = result.lixi
      ..cargo = result.cargo
      ..fuel = result.fuel
      ..peach = result.peach
      ..score += result.score;
    if (!progress.finished) {
      _save(progress);
      return null;
    }
    clear();
    final plan = progress.plan;
    final record = TripRecord(
      fromName: plan.stages.first.fromName,
      toName: plan.stages.last.toName,
      vehicle: plan.vehicle,
      // Điểm cuối chuyến: tổng các chặng + thưởng lì xì, quà còn mang về.
      score: progress.score + progress.lixi * 50 + progress.cargo * 200,
      km: plan.km,
      arrivedMinutes: result.clockMinutes,
    );
    final records = this.records;
    final old = records.where((r) => r.key == record.key).firstOrNull;
    final better = old == null || record.score > old.score;
    if (better) {
      records
        ..removeWhere((r) => r.key == record.key)
        ..add(record);
      LocalService.shared.saveRecords([for (final r in records) r.toJson()]);
    }
    return TripSummary(record: record, newRecord: better, previousBest: old?.score);
  }

  /// Các kỷ lục đã lưu, điểm cao trước.
  List<TripRecord> get records {
    final list = [for (final json in LocalService.shared.getRecords()) TripRecord.fromJson(json)];
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  void clear() {
    _current = null;
    LocalService.shared.clearTrip();
  }

  void _save(TripProgress progress) {
    _current = progress;
    LocalService.shared.saveTrip(progress.toJson());
  }

  /// Quãng đường đã đi (km) tới đầu chặng hiện tại.
  static double kmDone(TripProgress progress) =>
      progress.plan.stages.take(progress.stageIndex).fold(0, (sum, s) => sum + s.km);

  /// Phút còn lại tới giao thừa.
  static double minutesLeft(TripProgress progress) => TripClock.midnight - progress.clockMinutes;

  /// Thời gian chơi còn lại ước tính (giây).
  static double playSecondsLeft(TripProgress progress) => progress.plan.stages
      .skip(progress.stageIndex)
      .fold(0, (sum, s) => sum + RouteService.stagePlaySeconds(s));

  /// Phút cho một chặng ở tốc độ thường (để hiển thị).
  static double stageGameMinutes(TripStage stage) =>
      RouteService.stagePlaySeconds(stage) * GameConfig.gameSecondsPerPlaySecond / 60;
}
