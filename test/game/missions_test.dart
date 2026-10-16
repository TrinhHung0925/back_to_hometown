import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/missions.dart';
import 'package:back_to_hometown/game/stage.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sections = [StageSection(RoadKind.city, 6), StageSection(RoadKind.highway, 70), StageSection(RoadKind.city, 6)];
  const shortStage = [StageSection(RoadKind.city, 5), StageSection(RoadKind.highway, 25)];
  const expressway = [StageSection(RoadKind.city, 6), StageSection(RoadKind.expressway, 90), StageSection(RoadKind.city, 6)];

  group('Missions.forStage', () {
    test('cùng chặng, cùng xe thì luôn ra cùng nhiệm vụ', () {
      final seed = Missions.seedFor('Hà Nội', 'Phủ Lý', 1, VehicleKind.motorbike);
      expect(seed, Missions.seedFor('Hà Nội', 'Phủ Lý', 1, VehicleKind.motorbike));
      expect(seed, isNot(Missions.seedFor('Hà Nội', 'Phủ Lý', 1, VehicleKind.car)));
      final a = Missions.forStage(vehicle: VehicleKind.motorbike, sections: sections, seed: seed, startPeach: 100);
      final b = Missions.forStage(vehicle: VehicleKind.motorbike, sections: sections, seed: seed, startPeach: 100);
      expect(a, b);
    });

    test('chặng dài hai nhiệm vụ, chặng ngắn một; không giao cặp trùng ý', () {
      for (var seed = 0; seed < 200; seed++) {
        for (final v in VehicleKind.values) {
          final long = Missions.forStage(vehicle: v, sections: sections, seed: seed, startPeach: v == VehicleKind.motorbike ? 100 : -1);
          expect(long, hasLength(2));
          final kinds = {for (final m in long) m.kind};
          expect(kinds, hasLength(2));
          expect(kinds.containsAll({MissionKind.noFine, MissionKind.noCrash}), isFalse);
          expect(kinds.containsAll({MissionKind.onTime, MissionKind.restStop}), isFalse);
          expect(Missions.forStage(vehicle: v, sections: shortStage, seed: seed), hasLength(1));
        }
      }
    });

    test('nhiệm vụ hợp với loại xe và đường đi', () {
      final seen = <VehicleKind, Set<MissionKind>>{for (final v in VehicleKind.values) v: {}};
      for (var seed = 0; seed < 400; seed++) {
        for (final v in VehicleKind.values) {
          for (final m in Missions.forStage(vehicle: v, sections: sections, seed: seed, startPeach: v == VehicleKind.motorbike ? 100 : -1)) {
            seen[v]!.add(m.kind);
            expect(m.reward, greaterThan(0));
          }
        }
        // Toàn cao tốc thì không có khách vẫy xe đi nhờ (chỉ ven quốc lộ).
        for (final m in Missions.forStage(vehicle: VehicleKind.car, sections: expressway, seed: seed)) {
          expect(m.kind, isNot(MissionKind.hitchhiker));
        }
      }
      expect(seen[VehicleKind.motorbike], contains(MissionKind.keepPeach));
      expect(seen[VehicleKind.motorbike], contains(MissionKind.hitchhiker));
      expect(seen[VehicleKind.car], isNot(contains(MissionKind.keepPeach)));
      expect(seen[VehicleKind.car], isNot(contains(MissionKind.passengers)));
      expect(seen[VehicleKind.bus], contains(MissionKind.passengers));
      expect(seen[VehicleKind.bus], isNot(contains(MissionKind.hitchhiker)));
      expect(seen[VehicleKind.bus], isNot(contains(MissionKind.keepPeach)));
    });

    test('cành đào đã rụng nhiều thì hạ mức, rụng quá thì thôi giao', () {
      expect(Missions.peachTarget(100), 80);
      expect(Missions.peachTarget(80), 65);
      expect(Missions.peachTarget(-1), -1);
      for (var seed = 0; seed < 100; seed++) {
        final ms = Missions.forStage(vehicle: VehicleKind.motorbike, sections: sections, seed: seed, startPeach: 30);
        expect(ms.any((m) => m.kind == MissionKind.keepPeach), isFalse);
      }
    });

    test('hạn giờ bằng thời gian chạy thường, làm tròn lên 5 phút', () {
      final target = Missions.onTimeTarget(sections);
      final normal = Missions.normalMinutes(sections);
      expect(target % 5, 0);
      expect(target, greaterThanOrEqualTo(normal));
      expect(target - normal, lessThan(5));
    });

    test('số khách cần đón luôn đón đủ được nếu dừng hết các điểm', () {
      for (final km in [40.0, 72.0, 110.0, 180.0, 260.0]) {
        final s = [StageSection(RoadKind.highway, km)];
        final stops = Missions.busStopCount(s);
        // Mỗi điểm đón có ít nhất 2 khách.
        expect(Missions.passengerTarget(s), lessThanOrEqualTo(stops * 2));
        expect(Missions.passengerTarget(s), greaterThanOrEqualTo(2));
      }
    });
  });

  group('Missions.check', () {
    MissionCheck check(Mission m, MissionStats s, {double elapsed = 10, double peach = -1, bool arrived = false}) =>
        Missions.check(m, s, elapsed: elapsed, peach: peach, arrived: arrived);

    test('không bị phạt / không va chạm: hỏng ngay khi dính, tới nơi mới xong', () {
      const noFine = Mission(MissionKind.noFine, reward: 4);
      const noCrash = Mission(MissionKind.noCrash, reward: 4);
      final s = MissionStats();
      expect(check(noFine, s).state, MissionState.active);
      expect(check(noFine, s, arrived: true).state, MissionState.done);
      s.incidents = 1;
      expect(check(noFine, s).state, MissionState.failed);
      expect(check(noFine, s, arrived: true).state, MissionState.failed);
      expect(check(noCrash, s, arrived: true).state, MissionState.done);
      s.bumps = 1;
      expect(check(noCrash, s, arrived: true).state, MissionState.failed);
    });

    test('ghé quán, chở khách đi nhờ: xong ngay khi làm, tới nơi chưa làm thì hỏng', () {
      const rest = Mission(MissionKind.restStop, reward: 2);
      const hitch = Mission(MissionKind.hitchhiker, reward: 3);
      final s = MissionStats();
      expect(check(rest, s).state, MissionState.active);
      expect(check(rest, s, arrived: true).state, MissionState.failed);
      s.meals = 1;
      expect(check(rest, s).state, MissionState.done);
      expect(check(hitch, s, arrived: true).state, MissionState.failed);
      s.riders = 1;
      expect(check(hitch, s).state, MissionState.done);
    });

    test('đếm: lì xì nhặt, khách xe khách', () {
      const lixi = Mission(MissionKind.collectLixi, target: 12, reward: 3);
      const bus = Mission(MissionKind.passengers, target: 6, reward: 4);
      final s = MissionStats()
        ..lixiPicked = 11
        ..passengers = 6;
      expect(check(lixi, s).progress, '11/12 phong');
      expect(check(lixi, s).state, MissionState.active);
      expect(check(lixi, s, arrived: true).state, MissionState.failed);
      s.lixiPicked = 12;
      expect(check(lixi, s).state, MissionState.done);
      expect(check(bus, s).state, MissionState.done);
    });

    test('tới nơi đúng giờ: quá hạn là hỏng (kể cả phút bị giữ xe)', () {
      const onTime = Mission(MissionKind.onTime, target: 100, reward: 5);
      final s = MissionStats();
      expect(check(onTime, s, elapsed: 60).state, MissionState.active);
      expect(check(onTime, s, elapsed: 60).progress, 'Còn 40 phút');
      expect(check(onTime, s, elapsed: 99, arrived: true).state, MissionState.done);
      expect(check(onTime, s, elapsed: 101).state, MissionState.failed);
      expect(check(onTime, s, elapsed: 101, arrived: true).state, MissionState.failed);
    });

    test('cành đào: tụt dưới mức là hỏng', () {
      const peach = Mission(MissionKind.keepPeach, target: 80, reward: 4);
      final s = MissionStats();
      expect(check(peach, s, peach: 92).state, MissionState.active);
      expect(check(peach, s, peach: 81, arrived: true).state, MissionState.done);
      expect(check(peach, s, peach: 79).state, MissionState.failed);
    });

    test('thưởng chỉ tính nhiệm vụ đã xong', () {
      final s = MissionStats()..meals = 1;
      final checks = Missions.checkAll(
        const [Mission(MissionKind.restStop, reward: 2), Mission(MissionKind.hitchhiker, reward: 3), Mission(MissionKind.noFine, reward: 4)],
        s,
        elapsed: 50,
        arrived: true,
      );
      expect(Missions.rewardSum(checks), 2 + 4);
      final result = StageResult(reason: StageEndReason.arrived, lixi: 10, cargo: 0, clockMinutes: 900, minutesLeft: 500, missions: checks);
      expect(result.missionLixi, 6);
    });
  });

  test('MissionWatch báo một lần khi nhiệm vụ vừa đổi trạng thái', () {
    final watch = MissionWatch();
    const m = Mission(MissionKind.collectLixi, target: 2, reward: 3);
    final s = MissionStats();
    List<MissionCheck> run() => watch.changes(Missions.checkAll(const [m], s, elapsed: 1));
    expect(run(), isEmpty);
    s.lixiPicked = 2;
    expect(run().single.state, MissionState.done);
    expect(run(), isEmpty);
    watch.reset();
    expect(run(), hasLength(1));
  });

  test('StageSetup.copyWith giữ nguyên nâng cấp, nhiệm vụ, quà', () {
    final setup = StageSetup(
      vehicle: VehicleKind.car,
      fromName: 'A',
      toName: 'B',
      sections: sections,
      startClockMinutes: 600,
      missions: const [Mission(MissionKind.noFine, reward: 4)],
    );
    final copy = setup.withSeed(9);
    expect(copy.missions, setup.missions);
    expect(copy.seed, 9);
    expect(GameConfig.hornCooldown, greaterThan(0));
  });
}
