import 'package:back_to_hometown/dialog/place_picker_dialog.dart';
import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/place.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:back_to_hometown/resource/vn_route_data.dart';
import 'package:back_to_hometown/service/route_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final routes = RouteService();

  test('đi được từ Hà Nội tới mọi điểm trên bản đồ', () {
    for (final p in VnRouteData.places) {
      if (p.id == 'ha_noi') continue;
      expect(routes.plan('ha_noi', p.id, VehicleKind.motorbike), isNotNull, reason: p.name);
    }
  });

  for (final vehicle in VehicleKind.values) {
    test('${vehicle.name}: đi được giữa mọi cặp điểm, lộ trình đi đúng các đoạn nối', () {
      final linked = {for (final l in VnRouteData.links) ...['${l.a}|${l.b}', '${l.b}|${l.a}']};
      for (final a in VnRouteData.places) {
        for (final b in VnRouteData.places) {
          if (a.id == b.id) continue;
          final plan = routes.plan(a.id, b.id, vehicle);
          expect(plan, isNotNull, reason: '${a.name} → ${b.name}');
          expect(plan!.placeIds.first, a.id);
          expect(plan.placeIds.last, b.id);
          expect(plan.stages, isNotEmpty);
          for (var i = 0; i + 1 < plan.placeIds.length; i++) {
            expect(linked, contains('${plan.placeIds[i]}|${plan.placeIds[i + 1]}'));
          }
        }
      }
    });
  }

  test('dữ liệu điểm: id không trùng, đoạn nối hợp lệ, tỉnh cũ khác tên điểm', () {
    final ids = VnRouteData.places.map((p) => p.id).toSet();
    expect(ids.length, VnRouteData.places.length);
    expect(VnRouteData.places.length, greaterThanOrEqualTo(70));
    final pairs = <String>{};
    for (final l in VnRouteData.links) {
      expect(ids, containsAll([l.a, l.b]));
      expect(pairs.add(([l.a, l.b]..sort()).join('|')), isTrue, reason: 'trùng ${l.a}–${l.b}');
      expect(l.km, greaterThan(10));
      expect(l.expresswayKm, lessThanOrEqualTo(l.km));
      // Không có đoạn nào "bay": vận tốc trung bình ô tô hợp lý.
      expect(l.km / l.carHours, inInclusiveRange(25, 95), reason: '${l.a}–${l.b}');
    }
    for (final p in VnRouteData.places) {
      if (p.region != null) expect(p.region, isNot(p.name));
    }
    expect(VnRouteData.places.where((p) => p.zone == PlaceZone.highlands).map((p) => p.id),
        containsAll(['kon_tum', 'pleiku', 'buon_ma_thuot', 'da_lat']));
  });

  test('Hà Nội → Hà Giang đi QL2 qua Vĩnh Yên, Việt Trì, Tuyên Quang', () {
    final plan = routes.plan('ha_noi', 'ha_giang', VehicleKind.motorbike)!;
    expect(plan.placeIds, ['ha_noi', 'vinh_yen', 'viet_tri', 'tuyen_quang', 'ha_giang']);
    expect(plan.km, inInclusiveRange(290, 340));
  });

  test('TP.HCM → Hà Tiên khoảng 300–360 km, ô tô đi một phần cao tốc', () {
    final moto = routes.plan('tp_hcm', 'ha_tien', VehicleKind.motorbike)!;
    expect(moto.km, inInclusiveRange(300, 360));
    expect(moto.placeIds.last, 'ha_tien');
    final car = routes.plan('tp_hcm', 'ha_tien', VehicleKind.car)!;
    expect(car.expresswayKm, greaterThan(30));
  });

  test('Hà Nội → Điện Biên Phủ đi QL6 qua Hoà Bình, Mộc Châu, Sơn La', () {
    final plan = routes.plan('ha_noi', 'dien_bien', VehicleKind.motorbike)!;
    expect(plan.placeIds, ['ha_noi', 'hoa_binh', 'moc_chau', 'son_la', 'dien_bien']);
  });

  group('tìm điểm trong danh sách chọn', () {
    List<String> find(String q) => PlacePickerDialog.search(VnRouteData.places, q).map((p) => p.id).toList();

    test('tìm theo tên không dấu', () {
      expect(find('da nang').first, 'da_nang');
      expect(find('  Cần   thơ '), ['can_tho']);
    });

    test('tìm theo tên tỉnh cũ', () {
      expect(find('quang binh'), ['dong_hoi']);
      expect(find('phu tho'), ['viet_tri']);
      expect(find('kien giang'), unorderedEquals(['rach_gia', 'ha_tien']));
      expect(find('an giang'), unorderedEquals(['long_xuyen', 'chau_doc']));
      expect(find('quang'), containsAll(['ha_long', 'mong_cai', 'dong_hoi', 'dong_ha', 'hoi_an', 'tam_ky', 'quang_ngai']));
    });

    test('khớp tên đứng trước khớp tỉnh cũ', () {
      final result = find('quang');
      expect(result.indexOf('quang_ngai'), lessThan(result.indexOf('dong_hoi')));
      expect(result.indexOf('tuyen_quang'), lessThan(result.indexOf('ha_long')));
    });

    test('gõ chữ cái đầu', () {
      expect(find('hcm'), contains('tp_hcm'));
      expect(find('bmt'), contains('buon_ma_thuot'));
    });

    test('không có gì thì trả về rỗng, để trống thì đủ cả', () {
      expect(find('zzz'), isEmpty);
      expect(find('').length, VnRouteData.places.length);
    });
  });

  test('trùng điểm đi và điểm đến thì không có lộ trình', () {
    expect(routes.plan('vinh', 'vinh', VehicleKind.car), isNull);
  });

  test('Hà Nội → Vinh đi qua Phủ Lý, Ninh Bình, Thanh Hoá', () {
    final plan = routes.plan('ha_noi', 'vinh', VehicleKind.motorbike)!;
    expect(plan.placeIds, ['ha_noi', 'phu_ly', 'ninh_binh', 'thanh_hoa', 'vinh']);
    expect(plan.km, closeTo(305.2, 0.5));
  });

  for (final vehicle in VehicleKind.values) {
    test('${vehicle.name}: tổng km các chặng bằng km lộ trình, chặng không quá dài/ngắn', () {
      for (final to in ['vinh', 'da_nang', 'tp_hcm', 'ca_mau', 'phu_ly']) {
        final plan = routes.plan('ha_noi', to, vehicle)!;
        final sum = plan.stages.fold<double>(0, (s, st) => s + st.km);
        expect(sum, closeTo(plan.km, 0.01), reason: to);
        for (final st in plan.stages) {
          expect(st.km, lessThanOrEqualTo(GameConfig.stageMaxKm * 1.6), reason: '$to ${st.fromName}');
          if (plan.km >= GameConfig.stageMinKm) {
            expect(st.km, greaterThanOrEqualTo(GameConfig.stageMinKm / 2), reason: '$to ${st.fromName}');
          }
        }
      }
    });
  }

  test('xe máy không bao giờ đi cao tốc, ô tô thì có', () {
    final moto = routes.plan('ha_noi', 'tp_hcm', VehicleKind.motorbike)!;
    final car = routes.plan('ha_noi', 'tp_hcm', VehicleKind.car)!;
    bool hasExpressway(TripPlan p) => p.stages.any((s) => s.sections.any((x) => x.kind == RoadKind.expressway));
    expect(hasExpressway(moto), isFalse);
    expect(hasExpressway(car), isTrue);
    expect(car.realHours, lessThan(moto.realHours));
  });

  test('chặng đầu bắt đầu bằng đường phố của điểm xuất phát', () {
    final plan = routes.plan('ha_noi', 'thanh_hoa', VehicleKind.motorbike)!;
    expect(plan.stages.first.sections.first.kind, RoadKind.city);
    expect(plan.stages.last.sections.last.kind, RoadKind.city);
    expect(plan.stages.first.fromName, 'Hà Nội');
    expect(plan.stages.last.toName, 'Thanh Hoá');
  });

  test('lưu và đọc lại chuyến đi', () {
    final plan = routes.plan('hue', 'quy_nhon', VehicleKind.car)!;
    final progress = TripProgress(plan: plan, stageIndex: 1, clockMinutes: 900, lixi: 7, cargo: 2);
    final back = TripProgress.fromJson(progress.toJson());
    expect(back.plan.placeIds, plan.placeIds);
    expect(back.plan.stages.length, plan.stages.length);
    expect(back.plan.stages.first.sections.first.kind, plan.stages.first.sections.first.kind);
    expect(back.lixi, 7);
    expect(back.clockMinutes, 900);
  });
}
