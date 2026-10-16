import 'package:back_to_hometown/game/logic/trip_clock.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/map_theme.dart';
import 'package:back_to_hometown/service/daily_service.dart';
import 'package:back_to_hometown/service/route_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyService.challengeFor', () {
    test('cùng một ngày thì cùng thử thách, giờ nào trong ngày cũng vậy', () {
      final a = DailyService.challengeFor(DateTime(2026, 10, 16, 0, 5));
      final b = DailyService.challengeFor(DateTime(2026, 10, 16, 23, 59));
      expect(a, b);
      expect(a.dateKey, '2026-10-16');
      expect(DailyService.challengeFor(DateTime(2026, 10, 16)).seed, a.seed);
    });

    test('giá trị cố định (không đổi giữa các bản build, các máy)', () {
      final c = DailyService.challengeFor(DateTime(2026, 10, 16));
      final again = DailyService.challengeFor(DateTime.utc(2026, 10, 16, 12));
      expect(again.route, same(c.route));
      expect(again.seed, c.seed);
      expect(again.sky, c.sky);
      expect(again.difficulty, c.difficulty);
      expect(c.seed, inInclusiveRange(0, (1 << 20) - 1));
      expect(c.startFuel, inInclusiveRange(0.45, 0.7));
    });

    test('mỗi vòng đi qua đủ các chặng, không ngày nào trùng chặng trong vòng', () {
      final n = DailyService.routes.length;
      final start = DateTime(2026, 1, 1).add(Duration(days: n * 3));
      final seen = <DailyRoute>{};
      for (var i = 0; i < n; i++) {
        seen.add(DailyService.challengeFor(start.add(Duration(days: i))).route);
      }
      expect(seen.length, n);
    });

    test('ngày khác nhau thì hạt giống, trời, độ khó đổi đi', () {
      final days = [for (var i = 0; i < 60; i++) DailyService.challengeFor(DateTime(2026, 11, 1).add(Duration(days: i)))];
      expect(days.map((d) => d.seed).toSet().length, greaterThan(55));
      expect(days.map((d) => d.sky).toSet().length, 3);
      expect(days.map((d) => d.difficulty).toSet().length, 3);
      // Trước mốc 2026 vẫn chọn được (chỉ số ngày âm).
      expect(() => DailyService.challengeFor(DateTime(2025, 3, 2)), returnsNormally);
    });
  });

  group('DailyService.routes', () {
    test('mỗi chặng là đúng một chặng chơi 50–90 km, đủ loại cảnh và xe', () {
      for (final r in DailyService.routes) {
        final plan = RouteService.shared.plan(r.fromId, r.toId, r.vehicle);
        expect(plan, isNotNull, reason: '${r.fromId} → ${r.toId}');
        expect(plan!.stages.length, 1, reason: '${r.fromId} → ${r.toId}');
        expect(plan.stages.first.km, inInclusiveRange(50, 90), reason: '${r.fromId} → ${r.toId}');
      }
      expect(DailyService.routes.length, inInclusiveRange(12, 20));
      expect(DailyService.routes.map((r) => r.theme).toSet(), containsAll([MapTheme.delta, MapTheme.coast, MapTheme.mountain, MapTheme.mekong]));
      expect(DailyService.routes.map((r) => r.vehicle).toSet(), {VehicleKind.motorbike, VehicleKind.car});
    });

    test('dựng chặng: đánh dấu thử thách, giữ đúng hạt giống, cảnh, trời, độ khó', () {
      final c = DailyService.challengeFor(DateTime(2026, 10, 16));
      final setup = DailyService.setupFor(c);
      expect(setup.daily, isTrue);
      expect(setup.tutorial, isFalse);
      expect(setup.seed, c.seed);
      expect(setup.theme, c.route.theme);
      expect(setup.sky, c.sky);
      expect(setup.difficulty, c.difficulty);
      expect(setup.vehicle, c.route.vehicle);
      expect(setup.stageNumber, setup.stageCount);
      expect(setup.startClockMinutes, lessThan(TripClock.midnight - 60));
      expect(setup.withSeed(1).daily, isTrue, reason: 'copyWith giữ cờ thử thách');
      expect(setup.startPeach, c.route.vehicle == VehicleKind.motorbike ? 100 : -1);
    });
  });

  group('DailyRecord', () {
    test('kỷ lục trong ngày: giữ điểm cao nhất, sang ngày mới thì tính lại', () {
      var r = const DailyRecord();
      r = r.played(today: '2026-10-16', yesterday: '2026-10-15', score: 900, won: true);
      r = r.played(today: '2026-10-16', yesterday: '2026-10-15', score: 700, won: true);
      expect(r.bestOn('2026-10-16'), 900);
      expect(r.plays, 2);
      r = r.played(today: '2026-10-16', yesterday: '2026-10-15', score: 0, won: false);
      expect(r.bestOn('2026-10-16'), 900);
      expect(r.bestOn('2026-10-17'), isNull);
      r = r.played(today: '2026-10-17', yesterday: '2026-10-16', score: 500, won: true);
      expect(r.bestOn('2026-10-17'), 500);
      expect(r.plays, 1);
      expect(DailyRecord.fromJson(r.toJson()).toJson(), r.toJson());
    });

    test('chuỗi ngày: liên tiếp thì cộng, cách quãng thì về 1, thua không tính', () {
      var r = const DailyRecord();
      r = r.played(today: '2026-10-14', yesterday: '2026-10-13', score: 100, won: true);
      r = r.played(today: '2026-10-15', yesterday: '2026-10-14', score: 100, won: true);
      r = r.played(today: '2026-10-15', yesterday: '2026-10-14', score: 300, won: true);
      expect(r.streak, 2);
      r = r.played(today: '2026-10-16', yesterday: '2026-10-15', score: 0, won: false);
      expect(r.streak, 2);
      expect(r.streakOn('2026-10-16', '2026-10-15'), 2, reason: 'hôm qua có chơi xong, chuỗi vẫn còn');
      expect(r.streakOn('2026-10-17', '2026-10-16'), 0, reason: 'bỏ một ngày là mất chuỗi');
      r = r.played(today: '2026-10-18', yesterday: '2026-10-17', score: 100, won: true);
      expect(r.streak, 1);
    });

    test('kết quả: kỷ lục mới khi hơn điểm cũ', () {
      expect(const DailyResult(score: 900, best: 900, previousBest: null, streak: 1).newBest, isTrue);
      expect(const DailyResult(score: 900, best: 1200, previousBest: 1200, streak: 1).newBest, isFalse);
      expect(const DailyResult(score: 0, best: 0, previousBest: null, streak: 0).newBest, isFalse);
    });
  });
}
