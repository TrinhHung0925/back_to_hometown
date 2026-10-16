import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/alcohol.dart';
import 'package:back_to_hometown/game/logic/cold_weather.dart';
import 'package:back_to_hometown/game/logic/player_physics.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/map_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hơi men', () {
    test('một chén rượu chừng 2 tiếng mới hết, đào thải đều', () {
      final a = AlcoholLevel()..drink(600);
      expect(a.readingAt(600), closeTo(AlcoholLevel.cupDose, 1e-9));
      expect(a.at(660), closeTo(AlcoholLevel.cupDose / 2, 1e-9));
      expect(a.at(719), greaterThan(0));
      expect(a.readingAt(720), 0);
      expect(a.at(900), 0);
      expect(a.minutesToSober(600), closeTo(120, 1e-6));
      expect(a.minutesToSober(690), closeTo(30, 1e-6));
    });

    test('uống thêm thì cộng dồn, lâu hết hơn', () {
      final a = AlcoholLevel()
        ..drink(0)
        ..drink(30);
      // Chén đầu đã bớt 0,03 sau nửa tiếng.
      expect(a.at(30), closeTo(2 * AlcoholLevel.cupDose - 0.03, 1e-9));
      expect(a.minutesToSober(30), closeTo(210, 1e-6));
      final b = AlcoholLevel()..drink(0, cups: 2);
      expect(b.minutesToSober(0), closeTo(240, 1e-6));
    });

    test('chưa uống thì máy đo 0,00; còn chút xíu cũng làm tròn như máy', () {
      expect(AlcoholLevel().readingAt(1000), 0);
      expect(AlcoholLevel.reading(0.004), 0);
      expect(AlcoholLevel.reading(0.116), 0.12);
    });

    test('mức vi phạm theo số đo khí thở', () {
      expect(AlcoholTier.of(0), AlcoholTier.none);
      expect(AlcoholTier.of(0.01), AlcoholTier.level1);
      expect(AlcoholTier.of(0.25), AlcoholTier.level1);
      expect(AlcoholTier.of(0.26), AlcoholTier.level2);
      expect(AlcoholTier.of(0.4), AlcoholTier.level2);
      expect(AlcoholTier.of(0.41), AlcoholTier.level3);
      // Càng nặng phạt càng cao, chờ càng lâu — nhưng vẫn vừa phải.
      for (final (lo, hi) in [(AlcoholTier.level1, AlcoholTier.level2), (AlcoholTier.level2, AlcoholTier.level3)]) {
        expect(hi.fineLixi, greaterThan(lo.fineLixi));
        expect(hi.waitMinutes, greaterThan(lo.waitMinutes));
      }
      expect(AlcoholTier.level3.fineLixi, lessThanOrEqualTo(8));
      expect(AlcoholTier.level3.waitMinutes, lessThanOrEqualTo(40));
    });

    test('âm tính chỉ mất vài phút; dương tính mà thiếu lì xì thì chờ thêm', () {
      const clean = BreathReading(value: 0, tier: AlcoholTier.none, enoughLixi: true);
      expect(clean.positive, isFalse);
      expect(clean.minutes, BreathReading.testMinutes);
      expect(clean.minutes, lessThanOrEqualTo(5));
      expect(clean.display, '0,00');
      const drunk = BreathReading(value: 0.18, tier: AlcoholTier.level1, enoughLixi: true);
      expect(drunk.minutes, BreathReading.testMinutes + AlcoholTier.level1.waitMinutes);
      expect(drunk.display, '0,18');
      const broke = BreathReading(value: 0.18, tier: AlcoholTier.level1, enoughLixi: false);
      expect(broke.minutes, drunk.minutes + BreathReading.brokeExtraMinutes);
    });
  });

  group('Khí hậu Tết', () {
    test('trong ngày lạnh nhất lúc 6 giờ, ấm nhất lúc 14 giờ', () {
      expect(ColdClimate.warmth(6), closeTo(0, 1e-9));
      expect(ColdClimate.warmth(14), closeTo(1, 1e-9));
      for (var h = 0.0; h < 24; h += 0.5) {
        final w = ColdClimate.warmth(h);
        expect(w, inInclusiveRange(0, 1));
      }
      // Ấm dần buổi sáng, lạnh dần về đêm.
      expect(ColdClimate.warmth(9), lessThan(ColdClimate.warmth(12)));
      expect(ColdClimate.warmth(20), greaterThan(ColdClimate.warmth(23)));
      expect(ColdClimate.warmth(2), greaterThan(ColdClimate.warmth(5)));
    });

    test('càng ra Bắc càng rét', () {
      var prev = double.infinity;
      for (var lat = 9.0; lat <= 23; lat += 0.5) {
        final (lo, hi) = ColdClimate.dailyRange(lat);
        expect(hi, greaterThan(lo));
        expect(lo, lessThanOrEqualTo(prev + 1e-9));
        prev = lo;
      }
    });

    test('tìm vĩ độ theo tên điểm trên bản đồ', () {
      expect(ColdClimate.latitudeOf('Hà Nội'), closeTo(21.0, 0.2));
      expect(ColdClimate.latitudeOf('Bến xe Giáp Bát, Hà Nội'), closeTo(21.0, 0.2));
      expect(ColdClimate.latitudeOf('Không có trên bản đồ'), isNull);
    });

    test('Hà Nội rạng sáng rét đậm, đầu giờ chiều hết rét; đêm khuya lại rét', () {
      final hn = ColdClimate.forStage(fromName: 'Hà Nội', toName: 'Hà Nội', south: false);
      final dawn = hn.temperatureAt(minutes: 6 * 60, progress: 0);
      final noon = hn.temperatureAt(minutes: 14 * 60, progress: 0);
      final late = hn.temperatureAt(minutes: 23.5 * 60, progress: 0);
      expect(dawn, inInclusiveRange(7, 10));
      expect(dawn, lessThanOrEqualTo(ColdClimate.coldBelow));
      expect(noon, greaterThan(ColdClimate.coldBelow));
      expect(late, lessThanOrEqualTo(ColdClimate.coldBelow));
      // Ngày trước giao thừa (phút âm) vẫn theo giờ trong ngày.
      expect(hn.temperatureAt(minutes: 6 * 60 - 1440, progress: 0), closeTo(dawn, 1e-9));
    });

    test('đèo núi rét hơn đồng bằng, mưa phùn rét thêm, ven biển dịu hơn', () {
      final delta = ColdClimate.forStage(fromName: 'Hà Nội', toName: 'Hà Nội', south: false);
      const mountain = ColdClimate(fromLat: 21, toLat: 21, theme: MapTheme.mountain);
      const coast = ColdClimate(fromLat: 21, toLat: 21, theme: MapTheme.coast);
      const flat = ColdClimate(fromLat: 21, toLat: 21);
      expect(mountain.temperatureAt(minutes: 360, progress: 0), closeTo(flat.temperatureAt(minutes: 360, progress: 0) - 5.5, 1e-9));
      expect(mountain.temperatureAt(minutes: 360, progress: 0), lessThan(5));
      expect(coast.temperatureAt(minutes: 360, progress: 0), greaterThan(flat.temperatureAt(minutes: 360, progress: 0)));
      expect(delta.temperatureAt(minutes: 360, progress: 0, rain: 1), lessThan(delta.temperatureAt(minutes: 360, progress: 0)));
    });

    test('miền Nam dịp Tết không bao giờ rét; Hà Nội → Vinh ấm dần về phía Nam', () {
      final south = ColdClimate.forStage(fromName: 'Chạy thử', toName: 'Đích', south: true);
      for (var m = 0.0; m < 1440; m += 30) {
        expect(south.temperatureAt(minutes: m, progress: 0.5), greaterThan(ColdClimate.coldBelow + 5));
      }
      final trip = ColdClimate.forStage(fromName: 'Hà Nội', toName: 'Vinh', south: false);
      expect(trip.temperatureAt(minutes: 360, progress: 1), greaterThan(trip.temperatureAt(minutes: 360, progress: 0)));
      // Không thấy tên điểm: miền Bắc lấy mốc Hà Nội.
      final unknown = ColdClimate.forStage(fromName: 'Chạy thử', toName: 'Đích', south: false);
      expect(unknown.temperatureAt(minutes: 360, progress: 0), lessThanOrEqualTo(ColdClimate.coldBelow));
    });
  });

  group('Rét ảnh hưởng người và xe', () {
    test('mức rét, sương muối', () {
      expect(ColdEffects.chill(15), 0);
      expect(ColdEffects.chill(ColdClimate.coldBelow), 0);
      expect(ColdEffects.chill(4), 1);
      expect(ColdEffects.chill(0), 1);
      expect(ColdEffects.chill(9), inExclusiveRange(0, 1));
      expect(ColdEffects.frost(14, mountain: true), 0);
      expect(ColdEffects.frost(3, mountain: true), 1);
      expect(ColdEffects.frost(5, mountain: true), greaterThan(ColdEffects.frost(5, mountain: false)));
      expect(ColdEffects.frost(2, mountain: false), lessThan(1));
    });

    test('tay cóng: xe máy không găng tay mất 15% sức lái; găng tay, ô tô thì không', () {
      expect(ColdEffects.numb(8, exposed: true, gloves: false), closeTo(0.15, 1e-9));
      expect(ColdEffects.numb(8, exposed: true, gloves: true), 0);
      expect(ColdEffects.numb(8, exposed: false, gloves: false), 0);
      expect(ColdEffects.numb(18, exposed: true, gloves: false), 0);
      final p = PlayerPhysics(spec: VehicleSpec.of(VehicleKind.motorbike), speed: GameConfig.normalSpeed);
      final full = p.steerAuthority;
      p.numb = ColdEffects.numb(8, exposed: true, gloves: false);
      expect(p.steerAuthority, closeTo(full * 0.85, 1e-9));
    });

    test('rét mau mệt hơn chút, rét mà ướt sũng thì mệt hẳn', () {
      expect(ColdEffects.alertFactor(18, exposed: true, soaked: 1), 1);
      expect(ColdEffects.alertFactor(6, exposed: false, soaked: 1), 1);
      final dry = ColdEffects.alertFactor(6, exposed: true, soaked: 0);
      final wet = ColdEffects.alertFactor(6, exposed: true, soaked: 1);
      expect(dry, greaterThan(1));
      expect(dry, lessThan(1.2));
      expect(wet, greaterThan(dry));
      expect(wet, lessThan(1.7));
    });

    test('máy nguội: bấm Ga 2 hoặc 3 lần mới nổ', () {
      for (var roll = 0.0; roll < 1; roll += 0.05) {
        expect(ColdEffects.kicksNeeded(9, roll), inInclusiveRange(2, 3));
      }
      expect(ColdEffects.kicksNeeded(3, 0.7), 3);
      expect(ColdEffects.kicksNeeded(12, 0.9), 2);
    });

    test('nhãn chip HUD', () {
      expect(ColdEffects.label(9.4), 'Rét đậm 9°C');
      expect(ColdEffects.label(8.4), 'Rét hại 8°C');
      expect(const NightColdHud(celsius: 6, severe: true).label, 'Rét hại 6°C');
      expect(const NightColdHud(alcohol: 12).label, isNull);
      expect(const NightColdHud(celsius: 9, numb: true), const NightColdHud(celsius: 9, numb: true));
      expect(const NightColdHud(celsius: 9), isNot(const NightColdHud(celsius: 9, kicksLeft: 2)));
    });
  });
}
