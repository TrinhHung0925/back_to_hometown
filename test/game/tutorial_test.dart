import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/road_layout.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/logic/tutorial.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tình trạng xe mặc định: đang chạy đều ở làn ngoài, thả cần lái.
TutorialProbe probe({
  double speed = 0,
  double? cruise,
  bool throttle = false,
  bool brake = false,
  double steer = 0,
  double? d,
  double lateral = 0,
  bool assist = true,
  int honks = 0,
  bool headlights = false,
  double? cityAheadKm = 5,
  TutorialLight? light,
  int lightsLeft = 3,
}) =>
    TutorialProbe(
      speedKmh: speed,
      cruiseKmh: cruise ?? speed,
      throttle: throttle,
      brake: brake,
      steer: steer,
      d: d ?? Lanes.center(1),
      lateral: lateral,
      assist: assist,
      honks: honks,
      headlights: headlights,
      cityAheadKm: cityAheadKm,
      light: light,
      lightsLeft: lightsLeft,
    );

/// Chạy [seconds] giây với cùng một tình trạng xe; trả về các bước xong.
List<TutorialStep> run(TutorialTracker t, TutorialProbe p, [double seconds = 0.1]) {
  final done = <TutorialStep>[];
  for (var i = 0; i < (seconds * 30).ceil(); i++) {
    final s = t.update(p, 1 / 30);
    if (s != null) done.add(s);
  }
  return done;
}

void main() {
  group('TutorialTracker', () {
    test('đi đủ các bước theo đúng thứ tự khi lái đúng', () {
      final t = TutorialTracker();
      final done = <TutorialStep>[];
      // Chạm Ga từng nấc 5 km/h tới 40.
      for (var kmh = 5.0; kmh <= 40; kmh += 5) {
        done.addAll(run(t, probe(speed: kmh - 5, cruise: kmh, throttle: true), 0.1));
        done.addAll(run(t, probe(speed: kmh, cruise: kmh), 0.3));
      }
      expect(done, [TutorialStep.tapGas]);
      // Giữ Ga lên 60 rồi buông: xe tự giữ tốc độ.
      done.addAll(run(t, probe(speed: 55, cruise: 61, throttle: true), 1.0));
      expect(t.step, TutorialStep.holdGas, reason: 'còn đang giữ Ga thì chưa xong');
      done.addAll(run(t, probe(speed: 60, cruise: 60), 1.7));
      // Sang làn trong rồi thả tay; về lại làn ngoài.
      done.addAll(run(t, probe(speed: 60, steer: -0.5, d: (Lanes.center(0) + Lanes.center(1)) / 2), 0.3));
      done.addAll(run(t, probe(speed: 60, d: Lanes.center(0)), 0.7));
      done.addAll(run(t, probe(speed: 60, steer: 0.5, d: (Lanes.center(0) + Lanes.center(1)) / 2), 0.3));
      done.addAll(run(t, probe(speed: 60, d: Lanes.center(1)), 0.7));
      // Chạm Phanh hai lần: 60 → 50.
      done.addAll(run(t, probe(speed: 60, cruise: 55, brake: true), 0.1));
      done.addAll(run(t, probe(speed: 56, cruise: 55), 0.3));
      done.addAll(run(t, probe(speed: 55, cruise: 50, brake: true), 0.1));
      done.addAll(run(t, probe(speed: 51, cruise: 50), 0.3));
      // Còi, đèn.
      done.addAll(run(t, probe(speed: 50, honks: 0), 0.2));
      done.addAll(run(t, probe(speed: 50, honks: 1), 0.1));
      done.addAll(run(t, probe(speed: 50, honks: 1, headlights: true), 0.1));
      expect(t.step, TutorialStep.redLight);
      // Vào phố: đèn đỏ phía trước, phanh dừng hẳn trước vạch.
      const red = TutorialLight(s: 20000, color: LightColor.red, remaining: 3, distance: 120);
      done.addAll(run(t, probe(speed: 20, cityAheadKm: null, light: red), 0.5));
      done.addAll(run(t, probe(speed: 0, cityAheadKm: null, light: red), 1.0));
      expect(t.stoppedAt, 20000);
      // Đèn xanh: chạm Ga đi tiếp.
      const green = TutorialLight(s: 20000, color: LightColor.green, remaining: 7, distance: 110);
      done.addAll(run(t, probe(speed: 15, cityAheadKm: null, light: green), 0.5));
      expect(done, TutorialStep.values);
      expect(t.finished, isTrue);
      expect(t.doneCount, TutorialStep.values.length);
      expect(t.skippedCount, 0);
    });

    test('chạm Ga: đủ 40 km/h mà còn giữ Ga thì chưa tính', () {
      final t = TutorialTracker();
      expect(run(t, probe(speed: 40, cruise: 40, throttle: true), 1), isEmpty);
      expect(t.cue, contains('buông'));
      expect(run(t, probe(speed: 40, cruise: 40), 0.3), [TutorialStep.tapGas]);
    });

    test('giữ tốc độ: phanh giữa chừng thì đếm lại từ đầu', () {
      final t = TutorialTracker()..index = TutorialStep.holdGas.index;
      run(t, probe(speed: 60, cruise: 60), 1.0);
      run(t, probe(speed: 60, cruise: 60, brake: true), 0.1);
      expect(run(t, probe(speed: 60, cruise: 60), 1.0), isEmpty);
      expect(run(t, probe(speed: 60, cruise: 60), 0.6), [TutorialStep.holdGas]);
    });

    test('đổi làn: còn giữ cần lái hoặc chưa vào giữa làn thì chưa xong', () {
      final t = TutorialTracker()..index = TutorialStep.laneInner.index;
      expect(run(t, probe(speed: 60), 0.5), isEmpty, reason: 'chưa gạt cần lái');
      expect(run(t, probe(speed: 60, steer: -0.3, d: Lanes.center(0)), 1), isEmpty);
      expect(t.cue, contains('Thả tay'));
      expect(run(t, probe(speed: 60, d: Lanes.center(0) + 20, lateral: -40), 1), isEmpty, reason: 'xe còn đang dạt sang');
      expect(run(t, probe(speed: 60, d: Lanes.center(0)), 0.6), [TutorialStep.laneInner]);
      // Về làn ngoài: hỗ trợ lái cho xe nằm sát lề cũng được.
      run(t, probe(speed: 60, d: Lanes.center(0)), 0.1);
      expect(run(t, probe(speed: 60, d: Lanes.center(1) + 18), 0.6), [TutorialStep.laneOuter]);
      // Tắt hỗ trợ lái: chỉ cần nằm trong làn và thả tay.
      final off = TutorialTracker()..index = TutorialStep.laneInner.index;
      run(off, probe(speed: 60, assist: false), 0.1);
      expect(run(off, probe(speed: 60, d: Lanes.center(0) - 20, lateral: -30, assist: false), 0.6), [TutorialStep.laneInner]);
    });

    test('chạm Phanh: giảm đúng 10 km/h so với mức cao nhất', () {
      final t = TutorialTracker()..index = TutorialStep.tapBrake.index;
      run(t, probe(speed: 70, cruise: 70), 0.2);
      expect(run(t, probe(speed: 66, cruise: 65), 0.5), isEmpty);
      expect(t.cue, contains('70 → 60'));
      expect(run(t, probe(speed: 61, cruise: 60), 0.3), [TutorialStep.tapBrake]);
    });

    test('còi tính từ lúc bắt đầu bước, không tính lần bóp trước đó', () {
      final t = TutorialTracker()..index = TutorialStep.horn.index;
      expect(run(t, probe(speed: 50, honks: 3), 0.5), isEmpty);
      expect(run(t, probe(speed: 50, honks: 4), 0.1), [TutorialStep.horn]);
    });

    test('đèn đỏ: đèn xanh, dừng quá xa vạch hay chưa dừng hẳn đều chưa tính', () {
      final t = TutorialTracker()..index = TutorialStep.redLight.index;
      expect(run(t, probe(speed: 30, cityAheadKm: 3), 1), isEmpty);
      expect(t.cue, contains('tới phố'));
      const green = TutorialLight(s: 1, color: LightColor.green, remaining: 4, distance: 100);
      expect(run(t, probe(speed: 0, cityAheadKm: null, light: green), 2), isEmpty);
      const far = TutorialLight(s: 1, color: LightColor.red, remaining: 4, distance: 900);
      expect(run(t, probe(speed: 0, cityAheadKm: null, light: far), 2), isEmpty);
      const short = TutorialLight(s: 1, color: LightColor.red, remaining: 4, distance: 420);
      expect(run(t, probe(speed: 0, cityAheadKm: null, light: short), 2), isEmpty);
      expect(t.cue, contains('nhích lên'));
      const near = TutorialLight(s: 1, color: LightColor.red, remaining: 4, distance: 80);
      expect(run(t, probe(speed: 3, cityAheadKm: null, light: near), 2), isEmpty);
      expect(run(t, probe(speed: 0, cityAheadKm: null, light: near), 1), [TutorialStep.redLight]);
    });

    test('đèn đỏ: hết đèn phía trước thì chỉ cần dừng hẳn', () {
      final t = TutorialTracker()..index = TutorialStep.redLight.index;
      expect(run(t, probe(speed: 30, cityAheadKm: null, lightsLeft: 0), 1), isEmpty);
      expect(run(t, probe(speed: 0, cityAheadKm: null, lightsLeft: 0), 1), [TutorialStep.redLight]);
    });

    test('đèn xanh thì đi: còn đỏ thì chờ, xanh rồi mới tính', () {
      final t = TutorialTracker()..index = TutorialStep.redLight.index;
      const red = TutorialLight(s: 5, color: LightColor.red, remaining: 2, distance: 60);
      run(t, probe(speed: 0, cityAheadKm: null, light: red), 1);
      expect(t.step, TutorialStep.greenGo);
      expect(run(t, probe(speed: 20, cityAheadKm: null, light: red), 1), isEmpty, reason: 'vượt đèn đỏ không tính');
      expect(t.cue, contains('Chờ đèn xanh'));
      const green = TutorialLight(s: 5, color: LightColor.green, remaining: 7, distance: 40);
      expect(run(t, probe(speed: 20, cityAheadKm: null, light: green), 0.5), [TutorialStep.greenGo]);
    });

    test('đổi làn: đang ở sẵn làn đích thì phải sang làn kia rồi về mới tính', () {
      final t = TutorialTracker()..index = TutorialStep.laneOuter.index;
      expect(run(t, probe(speed: 60, d: Lanes.center(1)), 1), isEmpty);
      expect(t.cue, contains('Sang làn trong'));
      run(t, probe(speed: 60, d: Lanes.center(0)), 0.5);
      expect(run(t, probe(speed: 60, d: Lanes.center(1)), 0.6), [TutorialStep.laneOuter]);
    });

    test('bỏ qua: đánh dấu bỏ qua và sang bước sau', () {
      final t = TutorialTracker();
      t.skip();
      expect(t.outcomes.first, TutorialOutcome.skipped);
      expect(t.step, TutorialStep.holdGas);
      for (var i = 0; i < 20; i++) {
        t.skip();
      }
      expect(t.finished, isTrue);
      expect(t.skippedCount, TutorialStep.values.length);
    });

    test('đang ghé quán / đã kết thúc thì không chấm', () {
      final t = TutorialTracker();
      final p = TutorialProbe(speedKmh: 40, cruiseKmh: 40, d: Lanes.center(1), driving: false);
      expect(run(t, p, 1), isEmpty);
    });
  });

  group('TutorialLights', () {
    test('lệch pha cho ra đúng màu đèn mong muốn', () {
      for (final time in [0.0, 3.3, 47.9, 1234.5]) {
        final red = TrafficLight(s: 0, offset: TutorialLights.offsetFor(time, TutorialLights.phaseRedLeft(2.2)));
        expect(red.colorAt(time), LightColor.red);
        expect(red.remainingAt(time), closeTo(2.2, 1e-6));
        final soon = TrafficLight(s: 0, offset: TutorialLights.offsetFor(time, TutorialLights.phaseRedIn(5)));
        expect(soon.colorAt(time), LightColor.green);
        expect(soon.colorAt(time + 5.01), LightColor.red);
      }
    });

    test('sắp xếp đèn: chỉ khi vừa tầm, đỏ đúng lúc xe tới, giữ đỏ tới khi dừng, dừng xong thì nhả', () {
      double? plan({bool armed = false, bool stopped = false, LightColor color = LightColor.green, double remaining = 5, double distance = 1500, double speed = 300}) =>
          TutorialLights.plan(armed: armed, stopped: stopped, color: color, remaining: remaining, distance: distance, speed: speed);
      expect(plan(distance: 4000), isNull, reason: 'còn xa');
      expect(plan(distance: 200), isNull, reason: 'gần quá không kịp');
      final phase = plan(distance: 1500, speed: 300)!;
      // Tới vạch sau 5 giây: đèn đỏ trước đó chừng redLead giây.
      final light = TrafficLight(s: 0, offset: TutorialLights.offsetFor(0, phase));
      expect(light.colorAt(5 - TutorialLights.redLead - 0.1), isNot(LightColor.red));
      expect(light.colorAt(5), LightColor.red);
      // Đi quá chậm, còn xa: chờ tới gần hơn.
      expect(plan(distance: 2000, speed: 60), isNull);
      // Đã đỏ, sắp hết đỏ mà xe chưa dừng: giữ đỏ.
      expect(plan(armed: true, color: LightColor.red, remaining: 1, distance: 300), TutorialLights.phaseRedLeft(TutorialLights.holdLeft));
      expect(plan(armed: true, color: LightColor.red, remaining: 4, distance: 300), isNull);
      // Dừng xong: đỏ còn lâu thì rút ngắn.
      expect(plan(armed: true, stopped: true, color: LightColor.red, remaining: 5, distance: 50), TutorialLights.phaseRedLeft(TutorialLights.releaseLeft));
      expect(plan(armed: true, stopped: true, color: LightColor.red, remaining: 1, distance: 50), isNull);
    });
  });

  group('TutorialPlan', () {
    test('phố ngắn không đèn → quốc lộ → phố có nhiều ngã tư đèn', () {
      final setup = TutorialPlan.setup();
      expect(setup.tutorial, isTrue);
      expect(setup.daily, isFalse);
      expect(setup.tollBooths, 0);
      expect([for (final s in setup.sections) s.kind], [RoadKind.city, RoadKind.highway, RoadKind.city]);
      for (var seed = 0; seed < 30; seed++) {
        final layout = RoadLayout.build(sections: setup.sections, startS: 400, tollBooths: 0, random: Random(seed * 104729 + 3));
        final city = layout.zones.last;
        expect(layout.lights.where((l) => l.s < layout.zones.first.endS), isEmpty, reason: 'phố đầu không có đèn');
        expect(layout.lights.where((l) => l.s >= city.startS).length, greaterThanOrEqualTo(3));
        expect(layout.checkpoints, isEmpty);
      }
      // Tốc độ chặng tập: đủ dài để tập hết các bước trên quốc lộ.
      expect(setup.sections[1].km * GameConfig.unitsPerKm / (60 / GameConfig.displayKmhPerUnitSpeed), greaterThan(25));
    });
  });
}
