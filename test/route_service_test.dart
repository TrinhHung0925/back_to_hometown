import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
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
