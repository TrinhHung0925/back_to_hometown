import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/collision.dart';
import 'package:back_to_hometown/game/logic/cross_traffic.dart';
import 'package:back_to_hometown/game/logic/road_layout.dart';
import 'package:back_to_hometown/game/logic/road_path.dart';
import 'package:back_to_hometown/game/logic/toll_gate.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sections = [
    StageSection(RoadKind.city, 3),
    StageSection(RoadKind.highway, 40),
    StageSection(RoadKind.expressway, 30),
    StageSection(RoadKind.highway, 10),
    StageSection(RoadKind.city, 3),
  ];

  RoadLayout layout({int tolls = 2, int seed = 1}) =>
      RoadLayout.build(sections: sections, startS: 400, tollBooths: tolls, random: Random(seed));

  group('RoadLayout', () {
    test('các đoạn nối liền nhau, đúng loại, đúng tổng chiều dài', () {
      final l = layout();
      expect(l.zones.map((z) => z.kind), [
        RoadKind.city,
        RoadKind.highway,
        RoadKind.expressway,
        RoadKind.highway,
        RoadKind.city,
      ]);
      for (var i = 1; i < l.zones.length; i++) {
        expect(l.zones[i].startS, l.zones[i - 1].endS);
      }
      expect(l.endS - l.startS, closeTo(86 * GameConfig.unitsPerKm, 1e-6));
      expect(l.kindAt(400 + 10 * GameConfig.unitsPerKm), RoadKind.highway);
    });

    test('ngã tư chỉ có ở đoạn phố, không sát điểm xuất phát', () {
      for (var seed = 0; seed < 10; seed++) {
        final l = layout(seed: seed);
        expect(l.lights, isNotEmpty);
        for (final light in l.lights) {
          expect(l.kindAt(light.s), RoadKind.city);
          expect(light.s, greaterThan(400 + GameConfig.firstLightAfterStart));
        }
      }
    });

    test('đủ số trạm thu phí, nằm ở quốc lộ/cao tốc, không chồng nhau', () {
      final l = layout(tolls: 3);
      expect(l.tolls.length, 3);
      for (final t in l.tolls) {
        expect(l.kindAt(t.plazaStart), isNot(RoadKind.city));
        expect(l.kindAt(t.plazaEnd), isNot(RoadKind.city));
      }
      for (var i = 1; i < l.tolls.length; i++) {
        expect(l.tolls[i].plazaStart, greaterThan(l.tolls[i - 1].plazaEnd));
      }
    });

    test('xe khách: có 2–6 điểm đón, không ở cao tốc, không sát ngã tư/trạm', () {
      for (var seed = 0; seed < 10; seed++) {
        final l = RoadLayout.build(sections: sections, startS: 400, tollBooths: 2, random: Random(seed), withBusStops: true);
        expect(l.busStops.length, inInclusiveRange(2, 6));
        for (final stop in l.busStops) {
          expect(l.kindAt(stop.s), isNot(RoadKind.expressway));
          expect(l.nearFeature(stop.s, margin: 100), isFalse);
          expect(stop.passengers, inInclusiveRange(2, 6));
        }
      }
      expect(layout().busStops, isEmpty);
    });

    test('dải phân cách chỉ có ở giữa đoạn cao tốc', () {
      final l = layout();
      final ex = l.zones.firstWhere((z) => z.kind == RoadKind.expressway);
      expect(l.hasMedian(ex.startS + 10), isFalse);
      expect(l.hasMedian((ex.startS + ex.endS) / 2), isTrue);
      expect(l.hasMedian(ex.endS - 10), isFalse);
      expect(l.hasMedian(l.zones.first.startS + 500), isFalse);
    });

    test('đường thẳng ở ngã tư / trạm thu phí, phố và cao tốc ít lệch hướng', () {
      for (var seed = 0; seed < 12; seed++) {
        final l = layout(tolls: 3, seed: seed);
        final road = RoadPath.winding(
          random: Random(seed * 3 + 5),
          styleAt: l.curveStyleAt,
          keepStraight: (a, b) => l.featureWithin(a, b, margin: 200),
        );
        road.ensureAhead(l.endS);
        for (final light in l.lights) {
          final a = road.at(light.s - 200).heading;
          final b = road.at(light.s + 200).heading;
          expect((a - b).abs(), lessThan(1e-6), reason: 'ngã tư ở ${light.s}');
        }
        for (final t in l.tolls) {
          expect((road.at(t.plazaStart).heading - road.at(t.plazaEnd).heading).abs(), lessThan(1e-6));
        }
        for (var s = 400.0; s < l.endS; s += 97) {
          final limit = switch (l.kindAt(s)) {
            RoadKind.city => GameConfig.maxHeadingCity,
            RoadKind.expressway => GameConfig.maxHeadingExpressway,
            RoadKind.highway => GameConfig.maxRoadHeading,
          };
          expect(road.at(s).heading.abs(), lessThanOrEqualTo(limit + 1e-9), reason: 'seed $seed, s $s, ${l.kindAt(s)}');
        }
        // Cua gắt chỉ có ở quốc lộ.
        for (final c in road.curvesBetween(400, l.endS).where((c) => c.sharp)) {
          expect(l.kindAt(c.startS), RoadKind.highway);
          expect(l.kindAt(c.endS), RoadKind.highway);
        }
      }
    });
  });

  group('TrafficLight', () {
    const light = TrafficLight(s: 1000, offset: 0);

    test('chu kỳ xanh → vàng → đỏ, đếm ngược đúng', () {
      expect(light.colorAt(0), LightColor.green);
      expect(light.remainingAt(0), TrafficLight.green);
      expect(light.colorAt(TrafficLight.green + 0.1), LightColor.yellow);
      expect(light.colorAt(TrafficLight.green + TrafficLight.yellow + 0.1), LightColor.red);
      expect(light.colorAt(TrafficLight.cycle + 0.1), LightColor.green);
    });

    test('đường ngang không bao giờ xanh khi chiều dọc xanh hoặc vàng', () {
      for (var t = 0.0; t < TrafficLight.cycle * 3; t += 0.05) {
        if (light.crossGreenAt(t)) expect(light.colorAt(t), LightColor.red);
      }
    });
  });

  group('CrossTraffic', () {
    test('xe đường ngang dừng trước vạch khi đèn đường ngang đỏ', () {
      const light = TrafficLight(s: 1000, offset: 0);
      final cross = CrossTraffic(Random(2));
      const far = RoadBox(s: -5000, d: 0, length: 60, width: 26);
      var t = TrafficLight.green + TrafficLight.yellow + 1.5; // đường ngang vừa xanh
      for (var i = 0; i < 60 * 30; i++) {
        cross.update(1 / 60, t, [light], far);
        t += 1 / 60;
        for (final v in cross.vehicles) {
          // Đèn đường ngang đỏ thì không xe nào vượt quá vạch mà chưa vào ngã tư.
          final inside = v.d.abs() < CrossTraffic.stopD;
          if (!light.crossGreenAt(t) && !inside) {
            final pastLine = v.down ? v.front > -CrossTraffic.stopD + 2 : v.front < CrossTraffic.stopD - 2;
            if (pastLine) expect(v.down ? v.d > 0 : v.d < 0, isTrue);
          }
        }
      }
    });

    test('không đâm vào người chơi đang đứng trong ngã tư', () {
      const light = TrafficLight(s: 1000, offset: 0);
      final cross = CrossTraffic(Random(4));
      final player = RoadBox(s: light.s, d: Lanes.center(0), length: 60, width: 26);
      var t = TrafficLight.green + TrafficLight.yellow + 1.2;
      for (var i = 0; i < 60 * 20; i++) {
        cross.update(1 / 60, t, [light], player);
        t += 1 / 60;
        expect(cross.hit(player), isNull);
      }
    });
  });

  group('TollGate', () {
    const plaza = TollPlaza(5000);

    double approach(TollGate gate, {required double d, required double speed, int lixi = 10, List<TollEvent>? events}) {
      var s = plaza.s - 400;
      var v = speed;
      for (var i = 0; i < 60 * 20; i++) {
        final front = s + 46;
        // Làn thường: phanh dừng ngay trước barrier.
        if (speed < GameConfig.tollStopSpeed && front > plaza.s - 30 && !gate.isOpen(TollLane.at(d) == TollLane.etc ? 0 : 1)) {
          v = 0;
        } else if (front < plaza.s - 30 || gate.passed || gate.isOpen(TollLane.at(d) == TollLane.etc ? 0 : 1) || TollLane.at(d) == TollLane.motorbike) {
          v = max(speed, 100);
        }
        final e = gate.updatePlayer(1 / 60, s: s, d: d, speed: v, length: 92, lixi: lixi);
        if (e != null) events?.add(e);
        gate.updateAi(1 / 60, const []);
        s += v / 60;
        if (gate.passed) break;
      }
      return s;
    }

    test('ô tô qua làn không dừng khi chạy chậm', () {
      final gate = TollGate(plaza, VehicleKind.car);
      final events = <TollEvent>[];
      approach(gate, d: TollGate.laneCenter(0), speed: GameConfig.etcMaxSpeed * 0.8, events: events);
      expect(gate.passed, isTrue);
      expect(events.single, isA<TollPaid>().having((e) => e.nonStop, 'nonStop', isTrue));
    });

    test('ô tô chạy nhanh vào làn không dừng thì barrier vẫn hạ (sẽ đâm)', () {
      final gate = TollGate(plaza, VehicleKind.car);
      final front = plaza.s - 10;
      gate.updatePlayer(1 / 60, s: front - 46, d: TollGate.laneCenter(0), speed: GameConfig.etcMaxSpeed * 1.5, length: 92, lixi: 10);
      expect(gate.isOpen(0), isFalse);
      expect(gate.obstacles().any((b) => b.length == 8 && b.d == TollGate.laneCenter(0)), isTrue);
    });

    test('làn thường: dừng hẳn thì trả phí, không đủ lì xì thì bị giữ', () {
      final gate = TollGate(plaza, VehicleKind.car);
      final events = <TollEvent>[];
      approach(gate, d: TollGate.laneCenter(1), speed: 0, lixi: 1, events: events);
      final paid = events.whereType<TollPaid>().single;
      expect(paid.broke, isTrue);
      expect(paid.fee, 1);
      expect(paid.nonStop, isFalse);
    });

    test('xe máy đi làn xe máy: miễn phí, không có barrier', () {
      final gate = TollGate(plaza, VehicleKind.motorbike);
      final events = <TollEvent>[];
      approach(gate, d: 148, speed: 200, events: events);
      expect(gate.passed, isTrue);
      expect(events.single, isA<TollFreeLane>());
    });

    test('xe AI dừng ở barrier một lúc thì được mở cho qua', () {
      final gate = TollGate(plaza, VehicleKind.car);
      final v = TrafficVehicle(id: 1, type: TrafficType.sedan, lane: 1, s: plaza.s - 44 - 2, cruiseSpeed: 0, variant: 0)..speed = 0;
      for (var i = 0; i < 90; i++) {
        gate.updateAi(1 / 60, [v]);
      }
      expect(gate.isOpen(1), isTrue);
      expect(gate.isOpen(0), isFalse);
    });
  });
}
