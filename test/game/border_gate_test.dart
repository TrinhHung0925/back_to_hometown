import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/border_gate.dart';
import 'package:back_to_hometown/game/logic/provinces.dart';
import 'package:back_to_hometown/game/logic/road_layout.dart';
import 'package:back_to_hometown/game/logic/roadside.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:back_to_hometown/resource/vn_route_data.dart';
import 'package:back_to_hometown/service/route_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final routes = RouteService();

  group('Tỉnh và đặc sản', () {
    test('điểm nào trên bản đồ cũng thuộc một tỉnh có đặc sản', () {
      for (final p in VnRouteData.places) {
        final province = Provinces.byName(Provinces.of(p));
        expect(province, isNotNull, reason: p.name);
        expect(province!.specialties, isNotEmpty, reason: p.name);
      }
    });

    test('tên trạm nghỉ ra đúng tỉnh của điểm sắp tới', () {
      expect(Provinces.ofStop('Thanh Hoá'), 'Thanh Hoá');
      expect(Provinces.ofStop('Vinh'), 'Nghệ An');
      expect(Provinces.ofStop('Trạm nghỉ trên đường tới Vinh'), 'Nghệ An');
      expect(Provinces.ofStop('TP. Hồ Chí Minh'), 'TP. Hồ Chí Minh');
      expect(Provinces.ofStop('Chạy thử'), isNull);
    });

    test('đặc sản đúng kiểu quán: món no ở quán cơm, quà vặt quán nào cũng có', () {
      final hn = Provinces.at('Hà Nội', StallKind.com);
      expect(hn.map((s) => s.item.name), contains('Bún chả Hà Nội'));
      expect(Provinces.at('Hà Nội', StallKind.traDa).map((s) => s.item.name), ['Cốm làng Vòng']);
      expect(Provinces.at('Thanh Hoá', StallKind.traDa).first.item.name, 'Nem chua Thanh Hoá');
      expect(Provinces.at('Hà Tĩnh', StallKind.nuocMia).map((s) => s.item.name), contains('Kẹo cu đơ Hà Tĩnh'));
      expect(Provinces.at('Đắk Lắk', StallKind.caPheVong).single.item.name, 'Cà phê Buôn Ma Thuột');
      // Tiệm vá xe, cây xăng không bán đặc sản.
      expect(Provinces.at('Thanh Hoá', StallKind.vaXe), isEmpty);
      expect(Provinces.at('Thanh Hoá', StallKind.xang), isEmpty);
      expect(Provinces.at(null, StallKind.com), isEmpty);
      // Tối đa hai món mỗi quán.
      for (final p in Provinces.all) {
        for (final k in StallKind.values) {
          expect(Provinces.at(p.name, k, seed: 7).length, lessThanOrEqualTo(2));
        }
      }
    });

    test('đặc sản hồi tỉnh táo nhiều hơn món thường cùng loại', () {
      for (final p in Provinces.all) {
        for (final sp in p.specialties) {
          final floor = switch (sp.kind) {
            SpecialtyKind.meal => 35.0,
            SpecialtyKind.snack => 20.0,
            SpecialtyKind.drink => 28.0,
          };
          expect(sp.item.alert, greaterThan(floor), reason: sp.item.name);
          expect(sp.taste, isNotEmpty);
          expect(Provinces.specialtyOf(sp.item), same(sp));
          expect(Provinces.provinceOf(sp.item), same(p));
        }
      }
      expect(Provinces.specialtyOf(StallKind.traDa.menu.first), isNull);
    });

    test('tên trên cổng viết hoa đúng dấu', () {
      expect(Provinces.byName('Thanh Hoá')!.gateName, 'THANH HOÁ');
      expect(Provinces.byName('Hải Phòng')!.title, 'thành phố Hải Phòng');
      expect(Provinces.byName('Nghệ An')!.title, 'tỉnh Nghệ An');
      expect(Provinces.byName('TP. Hồ Chí Minh')!.title, 'TP. Hồ Chí Minh');
    });
  });

  group('Ranh giới tỉnh trên chặng', () {
    test('Thanh Hoá → Vinh: một ranh giới vào Nghệ An', () {
      final c = BorderCrossing.forStage('Thanh Hoá', 'Vinh', VehicleKind.car, routes: routes);
      expect(c, hasLength(1));
      expect(c.single.from, 'Thanh Hoá');
      expect(c.single.to, 'Nghệ An');
      expect(c.single.stretch, 0);
      expect(c.single.stretches, 1);
    });

    test('cùng một tỉnh thì không có cổng', () {
      expect(BorderCrossing.forStage('Hội An', 'Tam Kỳ', VehicleKind.car, routes: routes), isEmpty);
      expect(BorderCrossing.forStage('Trạm nghỉ trên đường tới Vinh', 'Vinh', VehicleKind.car, routes: routes), isEmpty);
      expect(BorderCrossing.forStage('Chạy thử', 'Chạy thử', VehicleKind.car, routes: routes), isEmpty);
    });

    test('chặng đi qua nhiều điểm: mỗi đoạn nối đổi tỉnh một cổng, theo thứ tự', () {
      for (final plan in [
        routes.plan('ha_noi', 'vinh', VehicleKind.motorbike)!,
        routes.plan('tp_hcm', 'can_tho', VehicleKind.car)!,
        routes.plan('hue', 'quy_nhon', VehicleKind.bus)!,
      ]) {
        for (final stage in plan.stages) {
          final c = BorderCrossing.forStage(stage.fromName, stage.toName, plan.vehicle, routes: routes);
          for (var i = 1; i < c.length; i++) {
            expect(c[i].from, c[i - 1].to);
            expect(c[i].stretch, greaterThan(c[i - 1].stretch));
          }
          for (final x in c) {
            expect(x.stretch, lessThan(x.stretches));
            expect(x.fraction, inExclusiveRange(0, 1));
            expect(x.from, isNot(x.to));
          }
        }
      }
    });

    test('chặng bắt đầu ở trạm nghỉ: cổng ở khúc sau khúc đầu', () {
      final c = BorderCrossing.forStage('Trạm nghỉ trên đường tới Thanh Hoá', 'Vinh', VehicleKind.car, routes: routes);
      expect(c.single.from, 'Thanh Hoá');
      expect(c.single.stretch, 1);
      expect(c.single.stretches, 2);
    });
  });

  group('Đặt cổng chào', () {
    const sections = [
      StageSection(RoadKind.city, 3),
      StageSection(RoadKind.highway, 40),
      StageSection(RoadKind.city, 3),
      StageSection(RoadKind.highway, 30),
      StageSection(RoadKind.city, 3),
    ];
    const crossings = [
      BorderCrossing(from: 'Hà Nội', to: 'Hà Nam', stretch: 0, stretches: 2, fraction: 0.3),
      BorderCrossing(from: 'Hà Nam', to: 'Ninh Bình', stretch: 1, stretches: 2, fraction: 0.7),
    ];

    test('mỗi ranh giới một cổng, nằm ở quốc lộ đúng khúc, đường giữ thẳng quanh cổng', () {
      for (var seed = 0; seed < 8; seed++) {
        final l = RoadLayout.build(sections: sections, startS: 400, tollBooths: 2, random: Random(seed), borders: crossings);
        expect(l.gates, hasLength(2));
        final cities = l.zones.where((z) => z.kind == RoadKind.city).toList();
        expect(l.gates[0].s, inExclusiveRange(cities[0].endS, cities[1].startS));
        expect(l.gates[1].s, inExclusiveRange(cities[1].endS, cities[2].startS));
        expect(l.gates.map((g) => g.to), ['Hà Nam', 'Ninh Bình']);
        for (final g in l.gates) {
          expect(l.kindAt(g.s), RoadKind.highway);
          expect(l.kindAt(g.s - BorderGate.keepBefore), RoadKind.highway);
          expect(l.nearFeature(g.s), isTrue);
          expect(l.featureWithin(g.s - BorderGate.keepBefore + 10, g.s - BorderGate.keepBefore + 20), isTrue);
          for (final t in l.tolls) {
            expect(g.s < t.plazaStart - 1000 || g.s > t.plazaEnd + 500, isTrue);
          }
          // Quán xá, chốt CSGT không đặt sát cổng.
          for (final st in l.stalls) {
            expect((st.s - g.s).abs(), greaterThan(BorderGate.reach + 200));
          }
          for (final c in l.checkpoints) {
            expect((c.s - g.s).abs(), greaterThan(BorderGate.reach + 200));
          }
        }
      }
    });

    test('số khúc không khớp thì đặt theo tỉ lệ chặng', () {
      final l = RoadLayout.build(
        sections: const [StageSection(RoadKind.city, 3), StageSection(RoadKind.highway, 70), StageSection(RoadKind.city, 6)],
        startS: 400,
        tollBooths: 0,
        random: Random(3),
        borders: const [
          BorderCrossing(from: 'Hà Nội', to: 'Hà Nam', stretch: 0, stretches: 4, fraction: 0.2),
          BorderCrossing(from: 'Hà Nam', to: 'Ninh Bình', stretch: 1, stretches: 4, fraction: 0.45),
          BorderCrossing(from: 'Ninh Bình', to: 'Thanh Hoá', stretch: 2, stretches: 4, fraction: 0.7),
        ],
      );
      expect(l.gates, hasLength(3));
      final len = l.endS - l.startS;
      expect(l.gates[0].s, closeTo(400 + len * 0.2, 1500));
      expect(l.gates[2].s, closeTo(400 + len * 0.7, 1500));
    });

    test('không có ranh giới thì không có cổng, bố cục giữ nguyên', () {
      final a = RoadLayout.build(sections: sections, startS: 400, tollBooths: 2, random: Random(5));
      final b = RoadLayout.build(sections: sections, startS: 400, tollBooths: 2, random: Random(5), borders: crossings);
      expect(a.gates, isEmpty);
      expect(a.tolls.map((t) => t.s), b.tolls.map((t) => t.s));
      expect(a.lights.map((t) => t.s), b.lights.map((t) => t.s));
    });

    test('cổng không sát điểm xuất phát / đích', () {
      final l = RoadLayout.build(
        sections: const [StageSection(RoadKind.highway, 12)],
        startS: 400,
        tollBooths: 0,
        random: Random(1),
        borders: const [BorderCrossing(from: 'Hà Nội', to: 'Hà Nam', stretch: 0, stretches: 1, fraction: 0.01)],
      );
      for (final g in l.gates) {
        expect(g.s, greaterThan(400 + 2000));
        expect(g.s, lessThan(400 + 12 * GameConfig.unitsPerKm - 1500));
      }
    });
  });
}
