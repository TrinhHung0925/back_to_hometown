import 'dart:math';

import 'package:back_to_hometown/game/logic/family.dart';
import 'package:back_to_hometown/game/logic/roadside.dart';
import 'package:back_to_hometown/game/stage.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chạy [seconds] giây chơi với cùng một tình hình đường [input] (dt 1/30 s),
/// km tăng theo tốc độ.
double drive(FamilyRide ride, double seconds, {FamilyInput Function(double km)? input, double startKm = 0, double kmPerSecond = 0.67}) {
  const dt = 1 / 30;
  var km = startKm;
  for (var t = 0.0; t < seconds; t += dt) {
    km += kmPerSecond * dt;
    ride.step(input?.call(km) ?? FamilyInput(dt: dt, speedKmh: 50, km: km, kmLeft: 100 - km));
  }
  return km;
}

FamilyRide newRide({bool motorbike = true, double patience = 92, double stageKm = 0, int seed = 1}) =>
    FamilyRide(motorbike: motorbike, random: Random(seed), toName: 'Vinh', stageKm: stageKm, patience: patience);

  /// Chặng dài có lịch đòi đi vệ sinh (thử vài seed cho chắc có).
  FamilyRide rideWithBathroom({List<FamilyLine>? lines, double stopKm = 3}) {
    for (var seed = 0; seed < 50; seed++) {
      final r = newRide(stageKm: 100, seed: seed);
      if (lines != null) r.onLine = lines.add;
      for (var km = 0.0; km < 80; km += 0.02) {
        r.step(FamilyInput(dt: 1 / 30, speedKmh: 50, km: km, kmLeft: 100 - km, nextStopKm: stopKm));
        if (r.bathroomKm != null) return r;
      }
      lines?.clear();
    }
    throw StateError('không seed nào có đòi đi vệ sinh');
  }

void main() {
  group('Kiên nhẫn của bé', () {
    test('tụt dần khi ngồi xe, nhanh hơn lúc tắc đường, mưa, đêm', () {
      // 15 giây: chưa đủ lâu để bé ngủ gật ban đêm.
      final calm = newRide()..patience = 90;
      drive(calm, 15);
      final jam = newRide()..patience = 90;
      drive(jam, 15, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 5, km: km, kmLeft: 100, jam: true));
      final rain = newRide()..patience = 90;
      drive(rain, 15, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 50, km: km, kmLeft: 100, rain: 1));
      final night = newRide()..patience = 90;
      drive(night, 15, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 50, km: km, kmLeft: 100, night: 1));
      expect(calm.patience, lessThan(90));
      expect(calm.patience, greaterThan(85));
      expect(jam.patience, lessThan(calm.patience));
      expect(rain.patience, lessThan(calm.patience));
      expect(night.patience, lessThan(calm.patience));
    });

    test('xe máy có áo mưa thì bé đỡ khổ hơn khi trời mưa; ô tô gần như không sao', () {
      FamilyRide wet({required bool motorbike, bool raincoat = false}) {
        final r = newRide(motorbike: motorbike)..patience = 90;
        drive(r, 30, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 50, km: km, kmLeft: 100, rain: 1, raincoat: raincoat));
        return r;
      }

      final soaked = wet(motorbike: true);
      final coated = wet(motorbike: true, raincoat: true);
      final car = wet(motorbike: false);
      expect(coated.patience, greaterThan(soaked.patience));
      expect(car.patience, greaterThan(coated.patience));
    });

    test('ổ gà, phanh gấp, va chạm làm bé tụt kiên nhẫn ngay', () {
      final r = newRide()..patience = 80;
      r.bump();
      expect(r.patience, closeTo(80 - FamilyRide.bumpHit, 1e-9));
      r.hardBrake();
      expect(r.patience, closeTo(80 - FamilyRide.bumpHit - FamilyRide.brakeHit, 1e-9));
      final before = r.patience;
      r.crash();
      expect(r.patience, closeTo(before - FamilyRide.crashHit, 1e-9));
    });

    test('ghé quán, ngồi nghỉ, mua bim bim / hộp sữa thì bé vui lại', () {
      final r = newRide()..patience = 30;
      r.stopAt();
      expect(r.patience, closeTo(30 + FamilyRide.stopBoost, 1e-9));
      r.rest(5);
      expect(r.patience, closeTo(30 + FamilyRide.stopBoost + 5 * FamilyRide.restPerSecond, 1e-9));
      final before = r.patience;
      r.eat(FamilySnack.bimBim);
      expect(r.patience, closeTo(min(100, before + FamilySnack.bimBim.patience), 1e-9));
      r.eat(FamilySnack.hopSua);
      expect(r.patience, lessThanOrEqualTo(100));
    });

    test('không bao giờ ra ngoài 0..100', () {
      final r = newRide()..patience = 3;
      for (var i = 0; i < 10; i++) {
        r.crash();
      }
      expect(r.patience, 0);
      for (var i = 0; i < 10; i++) {
        r.eat(FamilySnack.bimBim);
      }
      expect(r.patience, 100);
    });

    test('quán ăn uống bán đồ cho bé; cây xăng, tiệm vá xe, xăng lẻ thì không', () {
      expect(FamilySnack.menuFor(StallKind.traDa), [FamilySnack.bimBim, FamilySnack.hopSua]);
      expect(FamilySnack.menuFor(StallKind.com), isNotEmpty);
      expect(FamilySnack.menuFor(StallKind.xang), isEmpty);
      expect(FamilySnack.menuFor(StallKind.vaXe), isEmpty);
      expect(FamilySnack.menuFor(StallKind.xangLe), isEmpty);
    });
  });

  group('Bé khóc', () {
    test('cạn kiên nhẫn thì khóc: phân tâm tay lái, mau mệt, trừ điểm', () {
      final r = newRide()..patience = FamilyRide.cryBelow + 1;
      drive(r, 10, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 5, km: km, kmLeft: 100, jam: true));
      expect(r.crying, isTrue);
      expect(r.mood, KidMood.crying);
      expect(r.distraction, greaterThan(0));
      expect(r.alertFactor, greaterThan(1));
      expect(r.score, -FamilyRide.cryPenalty);
    });

    test('dỗ được bằng bim bim; không dỗ thì khóc mệt rồi ngủ thiếp đi', () {
      final soothed = newRide()..patience = 5;
      drive(soothed, 1);
      expect(soothed.crying, isTrue);
      soothed.eat(FamilySnack.bimBim);
      expect(soothed.crying, isFalse);
      expect(soothed.distraction, 0);

      final tired = newRide()..patience = 5;
      drive(tired, FamilyRide.crySeconds + 2);
      expect(tired.crying, isFalse);
      expect(tired.asleep, isTrue);
      expect(tired.mood, KidMood.asleep);
      expect(tired.patience, greaterThanOrEqualTo(25));
    });

    test('đang ngủ thì kiên nhẫn hồi lại; sập ổ gà làm bé giật mình thức dậy', () {
      final r = newRide()..patience = 5;
      drive(r, FamilyRide.crySeconds + 2);
      expect(r.asleep, isTrue);
      final before = r.patience;
      drive(r, 10);
      expect(r.patience, greaterThan(before));
      r.bump();
      expect(r.asleep, isFalse);
    });
  });

  group('Đi vệ sinh', () {

    test('bé đòi đi vệ sinh khi phía trước có chỗ dừng; hạn = quán gần nhất + dư', () {
      final r = rideWithBathroom();
      expect(r.bathroomKm, lessThanOrEqualTo(3 + FamilyRide.bathroomSpareKm + 0.01));
      expect(r.hud.bathroomKm, isNotNull);
    });

    test('phía trước không có chỗ dừng thì bé chưa đòi', () {
      for (var seed = 0; seed < 20; seed++) {
        final r = newRide(stageKm: 100, seed: seed);
        drive(r, 140, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 50, km: km, kmLeft: 100 - km));
        expect(r.bathroomKm, isNull);
      }
    });

    test('ghé quán kịp thì xong, không bị trừ điểm', () {
      final r = rideWithBathroom();
      final score = r.score;
      r.stopAt();
      expect(r.bathroomKm, isNull);
      expect(r.score, score);
    });

    test('quá hạn mà chưa dừng: bé tè dầm, buồn, trừ điểm nhẹ', () {
      final r = rideWithBathroom();
      final before = r.patience;
      final score = r.score;
      drive(r, 20, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 50, km: 80 + km, kmLeft: 20, nextStopKm: 3));
      expect(r.bathroomKm, isNull);
      expect(r.score, lessThanOrEqualTo(score - FamilyRide.bathroomPenalty));
      expect(r.patience, lessThan(before));
    });
  });

  group('Chuyện trò trên xe', () {
    test('bé, vợ thỉnh thoảng nói chuyện; câu hỏi "sắp tới chưa" có số km thật', () {
      final r = newRide()..patience = 50;
      final lines = <FamilyLine>[];
      r.onLine = lines.add;
      drive(r, 200, input: (km) => const FamilyInput(dt: 1 / 30, speedKmh: 50, km: 1, kmLeft: 42));
      expect(lines, isNotEmpty);
      expect(lines.map((l) => l.speaker).toSet(), containsAll([FamilySpeaker.kid]));
      for (final l in lines.where((l) => l.text.contains('cây nữa'))) {
        expect(l.text, contains('42'));
      }
    });

    test('chạy quá nhanh thì vợ nhắc đi chậm lại (không nhắc liên tục)', () {
      final r = newRide();
      final lines = <FamilyLine>[];
      r.onLine = lines.add;
      drive(r, 20, input: (km) => FamilyInput(dt: 1 / 30, speedKmh: 90, km: km, kmLeft: 100, speeding: true));
      final warns = lines.where((l) => l.speaker == FamilySpeaker.spouse && (l.text.contains('chậm') || l.text.contains('Nhanh') || l.text.contains('vội')));
      expect(warns.length, 1);
    });

    test('bé buồn tè: câu đòi và câu mình trả lời nói nối nhau', () {
      final lines = <FamilyLine>[];
      final r = rideWithBathroom(lines: lines, stopKm: 2);
      drive(r, 8, input: (_) => const FamilyInput(dt: 1 / 30, speedKmh: 50, kmLeft: 30, nextStopKm: 2), kmPerSecond: 0);
      final i = lines.indexWhere((l) => l.text.contains('tè') && l.speaker == FamilySpeaker.kid);
      expect(i, greaterThanOrEqualTo(0));
      expect(lines[i + 1].speaker, FamilySpeaker.me);
    });

    test('về tới nơi bé còn vui thì được thưởng', () {
      expect((newRide()..patience = 80).arrivalBonus, greaterThan((newRide()..patience = 40).arrivalBonus));
      expect((newRide()..patience = 10).arrivalBonus, 0);
    });
  });

  group('Lưu chuyến, dựng chặng', () {
    TripProgress progress({bool family = false}) => TripProgress(
          plan: const TripPlan(
            vehicle: VehicleKind.motorbike,
            placeIds: ['ha_noi', 'vinh'],
            stages: [
              TripStage(fromName: 'Hà Nội', toName: 'Vinh', sections: [StageSection(RoadKind.highway, 80)], tollBooths: 0),
            ],
            km: 80,
            expresswayKm: 0,
            realHours: 2,
            tollBooths: 0,
          ),
          stageIndex: 0,
          clockMinutes: 600,
          lixi: 3,
          cargo: 0,
          family: family,
        );

    test('chuyến chở cả nhà lưu và đọc lại được; bản lưu cũ (không có trường) là đi một mình', () {
      final json = progress(family: true).toJson();
      expect(TripProgress.fromJson(json).family, isTrue);
      final old = Map<String, dynamic>.from(progress().toJson())..remove('family');
      expect(TripProgress.fromJson(old).family, isFalse);
    });

    test('copyWith giữ chế độ chở cả nhà; điểm chặng cộng điểm cả nhà', () {
      const setup = StageSetup(vehicle: VehicleKind.car, fromName: 'A', toName: 'B', sections: [], startClockMinutes: 0, family: true);
      expect(setup.copyWith(seed: 5).family, isTrue);
      expect(setup.withSeed(9).family, isTrue);
      const base = StageResult(reason: StageEndReason.arrived, lixi: 1, cargo: 0, clockMinutes: 0, minutesLeft: 10);
      const happy = StageResult(reason: StageEndReason.arrived, lixi: 1, cargo: 0, clockMinutes: 0, minutesLeft: 10, familyScore: 200);
      expect(happy.score - base.score, 200);
      const lost = StageResult(reason: StageEndReason.timeUp, lixi: 1, cargo: 0, clockMinutes: 0, minutesLeft: 0, familyScore: 200);
      expect(lost.score, 0);
    });

    test('HUD so sánh cả ô kiên nhẫn của bé', () {
      HudData hud(FamilyHud? f) =>
          HudData(kmDone: 1, kmTotal: 2, speedKmh: 3, clockLabel: '', minutesLeft: 4, lixi: 0, cargo: 0, danger: false, family: f);
      expect(hud(const FamilyHud(patience: 50, mood: KidMood.ok)), hud(const FamilyHud(patience: 50, mood: KidMood.ok)));
      expect(hud(const FamilyHud(patience: 50, mood: KidMood.ok)) == hud(const FamilyHud(patience: 49, mood: KidMood.ok)), isFalse);
      expect(hud(null) == hud(const FamilyHud(patience: 50, mood: KidMood.ok)), isFalse);
    });
  });
}
