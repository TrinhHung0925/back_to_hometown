import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/missions.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/logic/vehicle_condition.dart';
import 'package:back_to_hometown/game/stage.dart';
import 'package:back_to_hometown/game/ve_que_game.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/shop.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:back_to_hometown/service/shop_service.dart';
import 'package:flutter_test/flutter_test.dart';

TripProgress _progress(VehicleKind vehicle, {int lixi = 50, double fuel = 0.5}) => TripProgress(
      plan: TripPlan(
        vehicle: vehicle,
        placeIds: const ['a', 'b'],
        stages: const [
          TripStage(fromName: 'A', toName: 'B', sections: [StageSection(RoadKind.highway, 80)], tollBooths: 1),
          TripStage(fromName: 'B', toName: 'C', sections: [StageSection(RoadKind.highway, 80)], tollBooths: 0),
        ],
        km: 160,
        expresswayKm: 0,
        realHours: 3,
        tollBooths: 1,
      ),
      stageIndex: 0,
      clockMinutes: 600,
      lixi: lixi,
      cargo: 0,
      fuel: fuel,
    );

void main() {
  final shop = ShopService.shared;

  group('Perks (tác dụng nâng cấp)', () {
    test('xe zin: mọi hệ số bằng 1', () {
      final p = Perks.of({});
      expect(p.wetGripLoss, 1);
      expect(p.puncture, 1);
      expect(p.fuelCapacity, 1);
      expect(p.headlightReach, 1);
      expect(p.led, isFalse);
      expect(p.hornReach, 1);
      expect(p.hornCooldown, 1);
      expect(p.drowsiness, 1);
    });

    test('mỗi nâng cấp chỉ đổi đúng phần của nó', () {
      final tires = Perks.of({Upgrade.tires});
      expect(tires.wetGripLoss, lessThan(1));
      expect(tires.puncture, lessThan(0.5));
      expect(tires.fuelCapacity, 1);
      final led = Perks.of({Upgrade.led});
      expect(led.led, isTrue);
      expect(led.headlightReach, greaterThan(1.3));
      final horn = Perks.of({Upgrade.airHorn});
      expect(horn.hornReach, greaterThan(1.3));
      expect(horn.hornCooldown, lessThan(1));
      expect(horn.heavyIgnoreHorn, lessThan(1));
      expect(Perks.of({Upgrade.cushion}).drowsiness, lessThan(1));
      expect(Perks.of({Upgrade.extraTank}).fuelCapacity, closeTo(1.4, 1e-9));
    });

    test('lốp tốt: đường ướt đẫm vẫn bám hơn hẳn', () {
      double grip(Set<Upgrade> u) => 1 - (1 - GameConfig.wetGrip) * 1.0 * Perks.of(u).wetGripLoss;
      expect(grip({Upgrade.tires}), greaterThan(grip({})));
      expect(1 - grip({Upgrade.tires}), closeTo((1 - grip({})) / 2, 1e-9));
    });

    test('StageSetup mang nâng cấp vào game (cả khi chơi lại với hạt giống mới)', () {
      final setup = StageSetup(
        vehicle: VehicleKind.car,
        fromName: 'A',
        toName: 'B',
        sections: const [StageSection(RoadKind.highway, 50)],
        startClockMinutes: 600,
        upgrades: const {Upgrade.led, Upgrade.airHorn},
        gifts: const [Gift.coTuong],
      );
      final again = setup.withSeed(42);
      expect(again.perks.led, isTrue);
      expect(again.perks.hornReach, Perks.hornReachAirHorn);
      expect(again.gifts, [Gift.coTuong]);
    });
  });

  group('VeQueGame dùng nâng cấp, nhiệm vụ từ StageSetup', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    VeQueGame make(Set<Upgrade> upgrades, {List<Mission> missions = const []}) => VeQueGame(
          setup: StageSetup(
            vehicle: VehicleKind.car,
            fromName: 'A',
            toName: 'B',
            sections: const [StageSection(RoadKind.highway, 60)],
            startClockMinutes: 600,
            startFuel: 0.5,
            upgrades: upgrades,
            missions: missions,
          ),
          onHud: (_) {},
          onPhaseChanged: (_) {},
          onChase: (_, _) {},
          onFinished: (_) {},
          onSound: (_) {},
          onNotice: (_) {},
        );

    test('bình xăng phụ, còi hơi', () {
      expect(make({Upgrade.extraTank}).fuel.kmLeft, closeTo(make({}).fuel.kmLeft * 1.4, 1e-6));
      expect(make({Upgrade.airHorn}).hornCooldownSeconds, closeTo(GameConfig.hornCooldown * Perks.hornCooldownAirHorn, 1e-9));
      expect(make({}).hornCooldownSeconds, GameConfig.hornCooldown);
      expect(make({Upgrade.led, Upgrade.cushion}).perks.drowsiness, Perks.drowsinessCushion);
    });

    test('có nhiệm vụ cho khách đi nhờ thì chặng nào cũng có người vẫy xe', () {
      var emptyWithout = 0;
      for (var seed = 0; seed < 60; seed++) {
        VeQueGame game(List<Mission> missions) => VeQueGame(
              setup: StageSetup(
                vehicle: VehicleKind.motorbike,
                fromName: 'A',
                toName: 'B',
                sections: const [StageSection(RoadKind.city, 4), StageSection(RoadKind.highway, 22), StageSection(RoadKind.city, 4)],
                startClockMinutes: 600,
                seed: seed,
                missions: missions,
              ),
              onHud: (_) {},
              onPhaseChanged: (_) {},
              onChase: (_, _) {},
              onFinished: (_) {},
              onSound: (_) {},
              onNotice: (_) {},
            );
        expect(game(const [Mission(MissionKind.hitchhiker, reward: 3)]).hitchSpots, isNotEmpty, reason: 'seed $seed');
        if (game(const []).hitchSpots.isEmpty) emptyWithout++;
      }
      // Không có nhiệm vụ thì vẫn có chặng không gặp ai (giữ nguyên ngẫu nhiên cũ).
      expect(emptyWithout, greaterThan(0));
    });

    test('chấm nhiệm vụ theo số liệu trong chặng', () {
      final g = make({}, missions: const [Mission(MissionKind.collectLixi, target: 3, reward: 3), Mission(MissionKind.noCrash, reward: 4)]);
      expect(g.missionChecks.map((c) => c.state), [MissionState.active, MissionState.active]);
      g.missionStats
        ..lixiPicked = 3
        ..bumps = 1;
      expect(g.missionChecks.map((c) => c.state), [MissionState.done, MissionState.failed]);
    });
  });

  group('Bình xăng phụ', () {
    test('chạy xa thêm 40%, đổ đầy cũng tốn hơn', () {
      for (final kind in VehicleKind.values) {
        final stock = FuelTank(kind, level: 0);
        final big = FuelTank(kind, level: 0, capacity: Perks.fuelCapacityExtraTank);
        expect(big.rangeKm, closeTo(stock.rangeKm * 1.4, 1e-6));
        expect(big.fullPrice, greaterThan(stock.fullPrice));
        // Cùng một lượng xăng (1 lì xì) thì chạy được cùng quãng đường.
        expect(big.perLixi * big.rangeKm, closeTo(stock.perLixi * stock.rangeKm, 1e-6));
      }
    });

    test('lắp can đầy sẵn: xăng cũ giữ nguyên, thêm đủ một can', () {
      final before = FuelTank(VehicleKind.car, level: 0.5);
      final level = ShopService.withExtraTank(0.5);
      final after = FuelTank(VehicleKind.car, level: level, capacity: Perks.fuelCapacityExtraTank);
      expect(after.kmLeft, closeTo(before.kmLeft + before.rangeKm * 0.4, 1e-6));
      expect(ShopService.withExtraTank(1), 1);
    });
  });

  group('ShopService (mua bằng lì xì)', () {
    test('mua nâng cấp: trừ đúng giá theo loại xe, không mua trùng, thiếu tiền thì thôi', () {
      final p = _progress(VehicleKind.car, lixi: 20);
      expect(shop.buyUpgrade(p, Upgrade.tires, save: false), isTrue);
      expect(p.lixi, 20 - Upgrade.tires.priceFor(VehicleKind.car));
      expect(p.upgrades, {Upgrade.tires});
      expect(shop.buyUpgrade(p, Upgrade.tires, save: false), isFalse);
      final before = p.lixi;
      expect(shop.buyUpgrade(p, Upgrade.led, save: false), before >= Upgrade.led.priceFor(VehicleKind.car));
      p.lixi = 0;
      expect(shop.buyUpgrade(p, Upgrade.cushion, save: false), isFalse);
      expect(p.upgrades.contains(Upgrade.cushion), isFalse);
    });

    test('đồ cho ô tô, xe khách không rẻ hơn xe máy', () {
      for (final u in Upgrade.values) {
        expect(u.priceFor(VehicleKind.car), greaterThanOrEqualTo(u.priceFor(VehicleKind.motorbike)));
        expect(u.priceFor(VehicleKind.bus), greaterThanOrEqualTo(u.priceFor(VehicleKind.car)));
      }
    });

    test('mua can xăng phụ thì bình đầy hơn', () {
      final p = _progress(VehicleKind.motorbike, fuel: 0.3);
      expect(shop.buyUpgrade(p, Upgrade.extraTank, save: false), isTrue);
      expect(p.fuel, closeTo((0.3 + 0.4) / 1.4, 1e-9));
    });

    test('quà: mỗi người một món', () {
      final p = _progress(VehicleKind.motorbike, lixi: 30);
      expect(shop.buyGift(p, Gift.khanLen, save: false), isTrue);
      expect(shop.buyGift(p, Gift.traSen, save: false), isFalse);
      expect(shop.giftFor(p, FamilyMember.grandma), Gift.khanLen);
      expect(shop.buyGift(p, Gift.coTuong, save: false), isTrue);
      expect(p.lixi, 30 - Gift.khanLen.price - Gift.coTuong.price);
      expect(shop.giftFor(p, FamilyMember.kid), isNull);
    });
  });

  group('Quà Tết', () {
    test('mỗi người 2–3 món, đúng một món ưng nhất', () {
      for (final m in FamilyMember.values) {
        final options = Gift.optionsFor(m);
        expect(options.length, inInclusiveRange(2, 3));
        expect(options.where((g) => g.favorite), hasLength(1));
        expect(m.greeting, isNotEmpty);
        for (final g in options) {
          expect(g.reaction, isNotEmpty);
        }
      }
    });

    test('quà đáng giá hơn lì xì giữ lại tới cuối chuyến; đủ cả nhà có thưởng thêm', () {
      for (final g in Gift.values) {
        // Một lì xì giữ tới cuối chuyến được 50 điểm (điểm chặng thì quà vẫn được tính như lì xì).
        expect(g.bonus, greaterThan(g.price * 150));
      }
      final all = [Gift.khanLen, Gift.coTuong, Gift.banhChung, Gift.butMau];
      final sum = all.fold(0, (s, g) => s + g.bonus);
      expect(Gift.bonusOf(all), sum + Gift.wholeFamilyBonus);
      expect(Gift.bonusOf(all.take(3)), sum - Gift.butMau.bonus);
      expect(Gift.bonusOf(const []), 0);
      expect(Gift.khanLen.bonus, greaterThan(Gift.mutTet.bonus * 1.2));
    });
  });

  test('quà chở theo xe tính điểm chặng như lì xì còn giữ', () {
    const kept = StageResult(reason: StageEndReason.arrived, lixi: 20, cargo: 0, clockMinutes: 900, minutesLeft: 300);
    final bought = StageResult(
      reason: StageEndReason.arrived,
      lixi: 20 - Gift.khanLen.price,
      cargo: 0,
      clockMinutes: 900,
      minutesLeft: 300,
      giftValue: Gift.khanLen.price,
    );
    expect(bought.score, kept.score);
  });

  group('TripProgress lưu / đọc', () {
    test('giữ nâng cấp, quà qua JSON', () {
      final p = _progress(VehicleKind.car)
        ..upgrades.addAll({Upgrade.led, Upgrade.tires})
        ..gifts.addAll([Gift.ruouNep, Gift.gauBong]);
      final back = TripProgress.fromJson(p.toJson());
      expect(back.upgrades, {Upgrade.led, Upgrade.tires});
      expect(back.gifts, [Gift.ruouNep, Gift.gauBong]);
    });

    test('chuyến lưu từ bản cũ (chưa có cửa hàng) vẫn đọc được', () {
      final json = _progress(VehicleKind.car).toJson()
        ..remove('upgrades')
        ..remove('gifts');
      final back = TripProgress.fromJson(json);
      expect(back.upgrades, isEmpty);
      expect(back.gifts, isEmpty);
      // Tên lạ (bản khác) bị bỏ qua, mỗi người giữ một món.
      json['upgrades'] = ['led', 'turbo'];
      json['gifts'] = ['khanLen', 'traSen', 'xe_dap'];
      final odd = TripProgress.fromJson(json);
      expect(odd.upgrades, {Upgrade.led});
      expect(odd.gifts, [Gift.khanLen]);
    });
  });

  group('Còi hơi', () {
    TrafficSystem withCarAhead(double gap) {
      final traffic = TrafficSystem(Random(1));
      traffic.vehicles.add(TrafficVehicle(id: 1, type: TrafficType.sedan, lane: 1, s: 1000 + gap, cruiseSpeed: GameConfig.normalSpeed, variant: 0));
      return traffic;
    }

    final player = PlayerSnapshot(s: 1000, d: Lanes.center(1), speed: GameConfig.normalSpeed, length: 88, width: 44);

    test('còi zin không tới xe xa; còi hơi vang xa thì xe trước nghe thấy, tránh sang', () {
      const gap = GameConfig.hornReach + 150;
      expect(withCarAhead(gap).requestYield(player), YieldResult.nobody);
      final reach = GameConfig.hornReach * Perks.hornReachAirHorn;
      expect(gap, lessThan(reach));
      expect(withCarAhead(gap).requestYield(player, reach: reach), YieldResult.yielded);
    });

    test('xe to ít lờ còi hơi hơn', () {
      var ignoredStock = 0, ignoredAir = 0;
      for (var seed = 0; seed < 400; seed++) {
        for (final air in [false, true]) {
          final traffic = TrafficSystem(Random(seed));
          traffic.vehicles.add(TrafficVehicle(id: 1, type: TrafficType.truck, lane: 1, s: 1200, cruiseSpeed: GameConfig.normalSpeed, variant: 0));
          final r = traffic.requestYield(player,
              ignoreChance: GameConfig.heavyIgnoreHornChance * (air ? Perks.heavyIgnoreAirHorn : 1));
          if (r == YieldResult.honkedBack) air ? ignoredAir++ : ignoredStock++;
        }
      }
      expect(ignoredAir, lessThan(ignoredStock * 0.6));
    });
  });
}
