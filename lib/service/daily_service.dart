import 'dart:math';

import '../game/logic/trip_clock.dart';
import '../game/stage.dart';
import '../game/vehicle_spec.dart';
import '../model/difficulty.dart';
import '../model/map_theme.dart';
import '../model/trip.dart';
import 'local_service.dart';
import 'route_service.dart';

/// Một chặng lẻ trong danh sách thử thách: hai điểm kề nhau trên bản đồ
/// (50–90 km, đúng một chặng chơi), loại xe và cảnh đường.
class DailyRoute {
  const DailyRoute(this.fromId, this.toId, this.vehicle, this.theme, this.blurb);

  final String fromId;
  final String toId;
  final VehicleKind vehicle;
  final MapTheme theme;

  /// Một câu giới thiệu cung đường (hiện trên thẻ ở màn chính).
  final String blurb;
}

/// Thử thách của một ngày: cùng một chặng, cùng hạt giống, cùng trời và độ
/// khó cho mọi người chơi trong ngày đó.
class DailyChallenge {
  const DailyChallenge({
    required this.dateKey,
    required this.route,
    required this.seed,
    required this.sky,
    required this.difficulty,
    required this.startFuel,
  });

  /// Ngày dạng yyyy-mm-dd.
  final String dateKey;
  final DailyRoute route;
  final int seed;
  final SkyMode sky;
  final Difficulty difficulty;

  /// Xăng trong bình lúc xuất phát (0..1).
  final double startFuel;

  @override
  bool operator ==(Object other) =>
      other is DailyChallenge &&
      other.dateKey == dateKey &&
      identical(other.route, route) &&
      other.seed == seed &&
      other.sky == sky &&
      other.difficulty == difficulty &&
      other.startFuel == startFuel;

  @override
  int get hashCode => Object.hash(dateKey, route, seed, sky, difficulty, startFuel);
}

/// Điểm thử thách đã lưu: kỷ lục trong ngày [date], số lần chơi, chuỗi ngày
/// liên tiếp về tới nơi.
class DailyRecord {
  const DailyRecord({this.date = '', this.best = 0, this.plays = 0, this.streak = 0, this.streakDate = ''});

  final String date;
  final int best;
  final int plays;
  final int streak;

  /// Ngày gần nhất về tới nơi (tính chuỗi).
  final String streakDate;

  Map<String, dynamic> toJson() => {'date': date, 'best': best, 'plays': plays, 'streak': streak, 'streakDate': streakDate};

  factory DailyRecord.fromJson(Map<String, dynamic> json) => DailyRecord(
        date: json['date'] as String? ?? '',
        best: (json['best'] as num?)?.toInt() ?? 0,
        plays: (json['plays'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        streakDate: json['streakDate'] as String? ?? '',
      );

  /// Kỷ lục hôm nay (null nếu hôm nay chưa về tới nơi lần nào).
  int? bestOn(String today) => date == today && best > 0 ? best : null;

  /// Chuỗi còn giữ được tới hôm nay (hôm qua có chơi xong thì vẫn còn).
  int streakOn(String today, String yesterday) => streakDate == today || streakDate == yesterday ? streak : 0;

  /// Ghi một lần chơi xong thử thách [today] được [score] điểm.
  DailyRecord played({required String today, required String yesterday, required int score, required bool won}) {
    final sameDay = date == today;
    final best = max(sameDay ? this.best : 0, won ? score : 0);
    var streak = this.streak, streakDate = this.streakDate;
    if (won && streakDate != today) {
      streak = streakDate == yesterday ? streak + 1 : 1;
      streakDate = today;
    }
    return DailyRecord(date: today, best: best, plays: (sameDay ? plays : 0) + 1, streak: streak, streakDate: streakDate);
  }
}

/// Kết quả lần chơi vừa xong (bảng kết quả hiện "Kỷ lục hôm nay").
class DailyResult {
  const DailyResult({required this.score, required this.best, required this.previousBest, required this.streak});

  final int score;
  final int best;

  /// Kỷ lục hôm nay trước lần chơi này (null = lần đầu về tới nơi hôm nay).
  final int? previousBest;
  final int streak;

  bool get newBest => score > 0 && (previousBest == null || score > previousBest!);
}

/// Thử thách hôm nay: chọn chặng theo ngày (ai chơi cùng ngày cũng gặp cùng
/// một chặng), dựng chặng, lưu kỷ lục trong ngày và chuỗi ngày liên tiếp.
class DailyService {
  static final DailyService shared = DailyService._internal();

  factory DailyService() => shared;

  DailyService._internal();

  /// Các chặng lẻ hay nhất, đủ cả đồng bằng, ven biển, đèo núi, sông nước.
  static const List<DailyRoute> routes = [
    DailyRoute('ha_noi', 'phu_ly', VehicleKind.motorbike, MapTheme.delta, 'Quốc lộ 1 xuôi về Hà Nam, đồng lúa hai bên'),
    DailyRoute('hung_yen', 'thai_binh', VehicleKind.motorbike, MapTheme.delta, 'Đường làng quê lúa, lũy tre, mái ngói đỏ'),
    DailyRoute('ninh_binh', 'thanh_hoa', VehicleKind.car, MapTheme.delta, 'Cao tốc men núi đá vôi Tam Điệp'),
    DailyRoute('ha_noi', 'thai_nguyen', VehicleKind.car, MapTheme.delta, 'Cao tốc lên xứ chè Thái Nguyên'),
    DailyRoute('vinh', 'ha_tinh', VehicleKind.motorbike, MapTheme.delta, 'Qua cầu Bến Thuỷ về đất Hà Tĩnh'),
    DailyRoute('hai_phong', 'ha_long', VehicleKind.car, MapTheme.coast, 'Qua cầu Bạch Đằng ra vịnh Hạ Long'),
    DailyRoute('dong_ha', 'hue', VehicleKind.motorbike, MapTheme.coast, 'Cát trắng, phi lao dọc dải đất Quảng Trị'),
    DailyRoute('da_nang', 'tam_ky', VehicleKind.motorbike, MapTheme.coast, 'Ven biển Quảng Nam, gió chướng cuối năm'),
    DailyRoute('tam_ky', 'quang_ngai', VehicleKind.car, MapTheme.coast, 'Quốc lộ 1 nắng gió miền Trung'),
    DailyRoute('tp_hcm', 'vung_tau', VehicleKind.car, MapTheme.coast, 'Ra biển Vũng Tàu đón gió Tết'),
    DailyRoute('ha_noi', 'hoa_binh', VehicleKind.car, MapTheme.mountain, 'Đại lộ Thăng Long lên dốc Cun, đèo Hoà Bình'),
    DailyRoute('sa_pa', 'lai_chau', VehicleKind.motorbike, MapTheme.mountain, 'Đèo Ô Quy Hồ mây phủ, cua tay áo'),
    DailyRoute('thai_nguyen', 'bac_kan', VehicleKind.motorbike, MapTheme.mountain, 'Quốc lộ 3 vượt đèo lên Bắc Kạn'),
    DailyRoute('viet_tri', 'yen_bai', VehicleKind.car, MapTheme.mountain, 'Men đồi chè, rừng quế lên Yên Bái'),
    DailyRoute('tp_hcm', 'my_tho', VehicleKind.car, MapTheme.mekong, 'Cao tốc Trung Lương về miền Tây'),
    DailyRoute('can_tho', 'soc_trang', VehicleKind.motorbike, MapTheme.mekong, 'Kênh rạch, vườn dừa, chùa Khmer'),
    DailyRoute('vinh_long', 'tra_vinh', VehicleKind.motorbike, MapTheme.mekong, 'Vườn dừa, cầu khỉ đất Trà Vinh'),
    DailyRoute('long_xuyen', 'rach_gia', VehicleKind.car, MapTheme.mekong, 'Dọc kênh xáng, lúa chín vàng'),
    DailyRoute('bac_lieu', 'ca_mau', VehicleKind.motorbike, MapTheme.mekong, 'Về Đất Mũi, cánh đồng muối, rừng đước'),
  ];

  /// Ngày gốc để đánh số ngày (lịch dương, không phụ thuộc múi giờ).
  static final DateTime _epoch = DateTime.utc(2026, 1, 1);

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static int dayIndex(DateTime date) => DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

  /// Thử thách của ngày [date] (chỉ lấy ngày, bỏ giờ). Mỗi vòng
  /// [routes].length ngày đi qua đủ các chặng, thứ tự xáo theo vòng.
  static DailyChallenge challengeFor(DateTime date) {
    final day = dayIndex(date);
    final n = routes.length;
    final cycle = (day / n).floor();
    final order = List<int>.generate(n, (i) => i);
    final shuffle = _Lcg(cycle * 7919 + 104729);
    for (var i = n - 1; i > 0; i--) {
      final j = shuffle.nextInt(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    final rng = _Lcg(day * 2654435 + 97);
    final sky = _pick(rng, const [(SkyMode.day, 45), (SkyMode.clock, 35), (SkyMode.night, 20)]);
    final difficulty = _pick(rng, const [(Difficulty.easy, 25), (Difficulty.normal, 50), (Difficulty.hard, 25)]);
    return DailyChallenge(
      dateKey: dateKey(date),
      route: routes[order[day - cycle * n]],
      seed: rng.nextInt(1 << 20),
      sky: sky,
      difficulty: difficulty,
      startFuel: ((0.45 + 0.25 * rng.nextDouble()) * 100).round() / 100,
    );
  }

  static T _pick<T>(_Lcg rng, List<(T, int)> weighted) {
    final total = weighted.fold(0, (sum, w) => sum + w.$2);
    var r = rng.nextInt(total);
    for (final (value, weight) in weighted) {
      if (r < weight) return value;
      r -= weight;
    }
    return weighted.last.$1;
  }

  /// Chặng chơi của thử thách (lộ trình thật trên bản đồ).
  static TripStage stageOf(DailyRoute route, [VehicleKind? vehicle]) =>
      RouteService.shared.plan(route.fromId, route.toId, vehicle ?? route.vehicle)!.stages.first;

  /// Dựng chặng cho thử thách: giờ xuất phát tính như chuyến một chặng ở độ
  /// khó của ngày, chở cành đào nếu đi xe máy.
  /// [vehicle]: xe máy hay ô tô do người chơi chọn ở màn lộ trình (mặc định
  /// theo thử thách).
  static StageSetup setupFor(DailyChallenge challenge, {VehicleKind? vehicle}) {
    final route = challenge.route;
    final kind = vehicle ?? route.vehicle;
    final stage = stageOf(route, kind);
    final to = RouteService.shared.place(route.toId);
    return StageSetup(
      vehicle: kind,
      fromName: stage.fromName,
      toName: stage.toName,
      sections: stage.sections,
      tollBooths: stage.tollBooths,
      startClockMinutes: TripClock.departureFor(TripClock.allowedMinutes(stage.km, 1, challenge.difficulty)),
      startLixi: 10,
      startFuel: challenge.startFuel,
      startPeach: kind == VehicleKind.motorbike ? 100 : -1,
      seed: challenge.seed,
      // Từ Nha Trang trở vào (vĩ tuyến ~12,8°): lúa chín vàng dịp Tết.
      south: 32 - to.y < 12.8,
      theme: route.theme,
      sky: challenge.sky,
      difficulty: challenge.difficulty,
      daily: true,
    );
  }

  DateTime Function() clock = DateTime.now;

  DailyChallenge get today => challengeFor(clock());

  String get _today => dateKey(clock());
  String get _yesterday => dateKey(clock().subtract(const Duration(days: 1)));

  DailyRecord get record {
    final json = LocalService.shared.getDaily();
    if (json == null) return const DailyRecord();
    try {
      return DailyRecord.fromJson(json);
    } catch (_) {
      return const DailyRecord();
    }
  }

  /// Kỷ lục hôm nay (null nếu chưa về tới nơi lần nào).
  int? get bestToday => record.bestOn(_today);

  int get streak => record.streakOn(_today, _yesterday);

  /// Chơi xong thử thách: lưu kỷ lục hôm nay, cập nhật chuỗi ngày.
  DailyResult submit(StageResult result) {
    final old = record;
    final previous = old.bestOn(_today);
    final next = old.played(today: _today, yesterday: _yesterday, score: result.score, won: result.won);
    LocalService.shared.saveDaily(next.toJson());
    return DailyResult(score: result.score, best: next.best, previousBest: previous, streak: next.streakOn(_today, _yesterday));
  }
}

/// Bộ sinh số giả ngẫu nhiên Park–Miller: cùng hạt giống thì cùng dãy số trên
/// mọi máy (Random của Dart không hứa điều này giữa các nền tảng).
class _Lcg {
  _Lcg(int seed) : _state = 1 + (seed.abs() % 2147483646);

  int _state;

  int next() => _state = (_state * 48271) % 2147483647;

  int nextInt(int max) => next() % max;

  double nextDouble() => (next() - 1) / 2147483646;
}
