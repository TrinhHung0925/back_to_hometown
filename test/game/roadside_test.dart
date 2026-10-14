import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/player_physics.dart';
import 'package:back_to_hometown/game/logic/road_layout.dart';
import 'package:back_to_hometown/game/logic/roadside.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/logic/u_turn.dart';
import 'package:back_to_hometown/game/logic/vehicle_condition.dart';
import 'package:back_to_hometown/game/logic/weather.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UTurn', () {
    test('ô tô từ làn phải quay nửa vòng sang làn ngoài chiều kia', () {
      final edge = VehicleSpec.car.width / 2 - GameConfig.roadHalfWidth;
      final r = UTurn.plan(d: Lanes.center(1), dir: 1, minRadius: UTurn.minRadius(VehicleKind.car), lo: edge, hi: -edge);
      expect(r, isNotNull);
      final u = UTurn(s0: 1000, d0: Lanes.center(1), dirFrom: 1, radius: r!, duration: 2.4);
      expect(u.endD, closeTo(Lanes.center(3), 1e-6));
      var maxS = u.s;
      while (!u.done) {
        u.update(1 / 60);
        maxS = max(maxS, u.s);
        expect(u.d, inInclusiveRange(edge - 1e-6, -edge + 1e-6));
      }
      expect(u.s, closeTo(1000, 1e-6));
      expect(u.d, closeTo(Lanes.center(3), 1e-6));
      expect(maxS, closeTo(1000 + r, 1));
      expect(u.theta, closeTo(pi, 1e-9));
    });

    test('ô tô đang ở làn trong thì không đủ chỗ, xe máy thì được', () {
      const edgeCar = GameConfig.roadHalfWidth - 23;
      expect(UTurn.plan(d: Lanes.center(0), dir: 1, minRadius: UTurn.minRadius(VehicleKind.car), lo: -edgeCar, hi: edgeCar), isNull);
      const edgeMoto = GameConfig.roadHalfWidth - 13;
      expect(UTurn.plan(d: Lanes.center(0), dir: 1, minRadius: UTurn.minRadius(VehicleKind.motorbike), lo: -edgeMoto, hi: edgeMoto), isNotNull);
    });

    test('đi ngược quay đầu về: cung quay sang phía d dương', () {
      final u = UTurn(s0: 500, d0: Lanes.center(3), dirFrom: -1, radius: 93, duration: 2);
      u.update(1);
      expect(u.s, lessThan(500));
      expect(u.endD, closeTo(Lanes.center(1), 1e-6));
    });
  });

  group('PlayerPhysics đi ngược', () {
    test('quay đầu rồi thì s giảm, kéo cần lái xuống vẫn là sang phải chiều đi', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, s: 5000, d: Lanes.center(3), speed: 200)
        ..dir = -1
        ..steer = 1;
      for (var i = 0; i < 30; i++) {
        p.update(1 / 60);
      }
      expect(p.s, lessThan(5000));
      // Bên phải khi đi ngược là phía d âm.
      expect(p.d, lessThan(Lanes.center(3)));
    });

    test('đi ngược qua cua phải của đường thì thành cua trái: văng sang phải chiều đi', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, s: 5000, d: Lanes.center(2), speed: 300)
        ..dir = -1
        ..curvature = 1 / 600;
      for (var i = 0; i < 60; i++) {
        p.speed = 300;
        p.update(1 / 60);
      }
      expect(p.d, lessThan(Lanes.center(2) - 20));
    });

    test('ngủ gật: tay lái không ăn, xe tự dạt', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(0), speed: 300)
        ..steer = -1
        ..asleep = true
        ..sleepDrift = GameConfig.microsleepDrift;
      for (var i = 0; i < 40; i++) {
        p.speed = 300;
        p.update(1 / 60);
      }
      expect(p.d, greaterThan(Lanes.center(0) + 20));
    });
  });

  group('Quán ven đường', () {
    const sections = [
      StageSection(RoadKind.city, 3),
      StageSection(RoadKind.highway, 40),
      StageSection(RoadKind.expressway, 20),
      StageSection(RoadKind.highway, 10),
    ];

    test('quán dày trên quốc lộ; cao tốc chỉ có cây xăng bên phải; tránh ngã tư / trạm / chốt / điểm đón', () {
      for (var seed = 0; seed < 8; seed++) {
        final l = RoadLayout.build(sections: sections, startS: 400, tollBooths: 2, random: Random(seed), withBusStops: seed.isEven);
        const highwayKm = 50.0;
        final food = l.stalls.where((t) => t.kind.food && l.kindAt(t.s) == RoadKind.highway).length;
        expect(food, greaterThan(highwayKm / GameConfig.stallGapHighwayKmMax * 0.6));
        for (final t in l.stalls) {
          if (l.kindAt(t.s) == RoadKind.expressway) {
            expect(t.kind, StallKind.xang);
            expect(t.side, 1);
          }
          expect(l.nearFeature(t.s, margin: 200), isFalse);
          for (final b in l.busStops) {
            expect((b.s - t.s).abs(), greaterThan(300));
          }
          expect(t.side == 1 || t.side == -1, isTrue);
        }
        // Các quán không chồng lên nhau.
        for (var i = 1; i < l.stalls.length; i++) {
          final a = l.stalls[i - 1], b = l.stalls[i];
          expect(b.s - a.s, greaterThan(min(a.halfLength, b.halfLength)));
        }
      }
    });

    test('cây xăng, tiệm vá xe, xăng lẻ đủ dày để đi tìm được', () {
      const long = [StageSection(RoadKind.highway, 100)];
      for (var seed = 0; seed < 6; seed++) {
        final l = RoadLayout.build(sections: long, startS: 400, tollBooths: 1, random: Random(seed));
        final gas = l.stalls.where((t) => t.kind == StallKind.xang).toList();
        final shops = l.stalls.where((t) => t.kind == StallKind.vaXe).toList();
        final bottles = l.stalls.where((t) => t.kind == StallKind.xangLe).toList();
        expect(gas.length, greaterThanOrEqualTo(5));
        expect(shops.length, greaterThanOrEqualTo(10));
        expect(bottles.length, greaterThanOrEqualTo(12));
        // Sau mỗi bãi đinh có tiệm vá xe "chặn đầu" bên phải.
        for (final n in l.nails) {
          expect(l.stalls.any((t) => t.gouging && t.side == 1 && t.s > n.s && t.s - n.s < 800), isTrue);
        }
      }
    });

    test('quán ngồi được có thực đơn, món nào cũng hồi tỉnh táo và tốn thời gian', () {
      for (final kind in StallKind.values.where((k) => k.canSit)) {
        for (final item in kind.menu) {
          expect(item.alert, greaterThan(0));
          expect(item.minutes, greaterThan(0));
          expect(item.price, greaterThanOrEqualTo(0));
        }
      }
      expect(StallKind.xang.canSit, isFalse);
      expect(StallKind.xang.sellsFuel, isTrue);
      expect(StallKind.vaXe.fixesTires, isTrue);
      expect(StallKind.vaXe.food, isFalse);
    });
  });

  group('Chốt CSGT', () {
    test('chốt ở quốc lộ, đoạn thẳng, cách xa trạm thu phí; vùng cấm quay đầu quanh chốt', () {
      const long = [StageSection(RoadKind.city, 3), StageSection(RoadKind.highway, 120)];
      var total = 0;
      for (var seed = 0; seed < 8; seed++) {
        final l = RoadLayout.build(sections: long, startS: 400, tollBooths: 1, random: Random(seed));
        total += l.checkpoints.length;
        for (final c in l.checkpoints) {
          expect(l.kindAt(c.s), RoadKind.highway);
          expect(c.limitKmh == 50 || c.limitKmh == 60, isTrue);
          for (final t in l.tolls) {
            expect((t.s - c.s).abs(), greaterThan(GameConfig.speedSignAhead));
          }
          expect(l.checkpointNear(c.s + 500), same(c));
          expect(l.checkpointNear(c.s + GameConfig.noUTurnReach + 50), isNot(same(c)));
          expect(c.radarS(1), lessThan(c.s));
          expect(c.radarS(-1), greaterThan(c.s));
        }
      }
      expect(total, greaterThanOrEqualTo(8));
    });
  });

  group('Xăng, lốp, mưa', () {
    test('xe máy đầy bình chạy được khoảng tầm xa đã định, chạy nhanh tốn hơn', () {
      final slow = FuelTank(VehicleKind.motorbike, level: 1);
      final fast = FuelTank(VehicleKind.motorbike, level: 1);
      for (var i = 0; i < 1000; i++) {
        slow.burn(GameConfig.unitsPerKm * 0.1, GameConfig.normalSpeed, 0);
        fast.burn(GameConfig.unitsPerKm * 0.1, GameConfig.normalSpeed * 1.5, 0);
      }
      // 100 km ở tốc độ thường: còn ~28% bình (140 km tầm xa).
      expect(slow.level, closeTo(1 - 100 / GameConfig.fuelRangeKmMotorbike, 0.01));
      expect(fast.level, lessThan(slow.level));
      expect(FuelTank(VehicleKind.car, level: 0.1).fullPrice, (0.9 / GameConfig.fuelPerLixiCar).ceil());
    });

    test('hết xăng thì giữ ga cũng không chạy; lốp xẹp thì không nhanh nổi và bị kéo lệch', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1), speed: 0)
        ..throttle = true
        ..engineOff = true;
      for (var i = 0; i < 60; i++) {
        p.update(1 / 60);
      }
      expect(p.speed, 0);
      final tires = Tires(VehicleKind.car)..puncture(Random(1));
      final q = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(0), speed: 0)
        ..throttle = true
        ..speedCap = tires.speedCap
        ..pull = tires.pull;
      for (var i = 0; i < 60 * 6; i++) {
        q.update(1 / 60);
      }
      expect(q.speed, closeTo(GameConfig.flatSpeedFactor * GameConfig.normalSpeed, 1));
      expect((q.d - Lanes.center(0)).sign, tires.pullSide.toDouble());
      // Chạy lốp xẹp xa quá thì nát săm.
      expect(tires.roll(GameConfig.unitsPerKm * (GameConfig.flatRuinKm + 0.1)), isTrue);
      expect(tires.state, TireState.ruined);
    });

    test('đường ướt phanh trượt dài hơn', () {
      double stopDistance(double grip) {
        final p = PlayerPhysics(spec: VehicleSpec.motorbike, d: Lanes.center(1), speed: 400)
          ..brake = true
          ..grip = grip;
        final s0 = p.s;
        while (p.speed > 0) {
          p.update(1 / 60);
        }
        return p.s - s0;
      }

      expect(stopDistance(GameConfig.wetGrip), greaterThan(stopDistance(1) * 1.25));
    });

    test('mưa to dần rồi ngớt; tạnh rồi đường còn ướt một lúc; miền Nam ít mưa hơn', () {
      const spell = RainSpell(kind: RainKind.shower, start: 100, end: 140, peak: 0.9);
      const w = Weather([spell]);
      expect(w.rainAt(99), 0);
      expect(w.rainAt(103), closeTo(0.45, 1e-9));
      expect(w.rainAt(120), 0.9);
      expect(w.rainAt(141), 0);
      expect(w.wetAt(141), greaterThan(0.5));
      expect(w.wetAt(140 + GameConfig.wetLingerMinutes + 1), 0);
      var north = 0, south = 0;
      for (var seed = 0; seed < 400; seed++) {
        if (Weather.forStage(random: Random(seed), south: false, startMinutes: 0, expectedMinutes: 100).spells.isNotEmpty) north++;
        if (Weather.forStage(random: Random(seed), south: true, startMinutes: 0, expectedMinutes: 100).spells.isNotEmpty) south++;
      }
      expect(north, greaterThan(south * 2));
    });
  });

  group('Xe AI khi mình đã quay đầu', () {
    test('xe cùng chiều mới (chạy ngược s) phía sau không tông đuôi mình đang phanh', () {
      final traffic = TrafficSystem(Random(1));
      final v = TrafficVehicle(id: 1, type: TrafficType.sedan, lane: 3, s: 5400, cruiseSpeed: 250, variant: 0)..speed = 250;
      traffic.vehicles.add(v);
      for (var i = 0; i < 60 * 4; i++) {
        traffic.update(
          1 / 60,
          PlayerSnapshot(s: 5000, d: Lanes.center(3), speed: 0, length: 92, width: 46, forward: false),
          spawnS: -99999,
          despawnBehindS: -1e9,
          despawnAheadS: 1e9,
        );
      }
      expect(v.s - v.type.length / 2, greaterThan(5000 + 46));
    });
  });
}
