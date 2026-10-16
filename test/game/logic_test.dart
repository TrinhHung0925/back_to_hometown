import 'dart:math';

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/chase.dart';
import 'package:back_to_hometown/game/logic/collision.dart';
import 'package:back_to_hometown/game/logic/player_physics.dart';
import 'package:back_to_hometown/game/logic/road_path.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/logic/trip_clock.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/difficulty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoadPath', () {
    test('hướng đường luôn trong giới hạn và đường vẫn đi về bên phải', () {
      for (var seed = 0; seed < 20; seed++) {
        final road = RoadPath.winding(random: Random(seed));
        road.ensureAhead(60000);
        var prevX = double.negativeInfinity;
        for (final p in road.samplesBetween(0, 60000)) {
          expect(p.heading.abs(), lessThanOrEqualTo(GameConfig.maxRoadHeading + 1e-9));
          expect(p.x, greaterThan(prevX));
          prevX = p.x;
        }
      }
    });

    test('có khúc cua thật: cua trái, cua phải, cua gắt nhưng không gắt quá giới hạn', () {
      for (var seed = 0; seed < 10; seed++) {
        final road = RoadPath.winding(random: Random(seed));
        road.ensureAhead(40000);
        final curves = road.curvesBetween(0, 40000).toList();
        expect(curves.where((c) => c.right && c.turn.abs() > 0.6), isNotEmpty);
        expect(curves.where((c) => !c.right && c.turn.abs() > 0.6), isNotEmpty);
        expect(curves.where((c) => c.sharp), isNotEmpty);
        for (final c in curves) {
          expect(c.radius, greaterThanOrEqualTo(GameConfig.minCurveRadiusHighway - 1e-6));
        }
        // Độ cong ở từng mẫu khớp với hướng đổi giữa hai mẫu kề nhau.
        for (var s = 100.0; s < 40000; s += 211) {
          final a = road.at(s - 4), b = road.at(s + 4);
          expect(road.at(s).curvature, closeTo((b.heading - a.heading) / 8, 6e-5));
          expect(road.at(s).curvature.abs(), lessThanOrEqualTo(1 / GameConfig.minCurveRadiusHighway + 1e-6));
        }
      }
    });

    test('điểm lệch ngang luôn vuông góc với tim đường', () {
      final road = RoadPath.winding(random: Random(7));
      for (var s = 0.0; s < 20000; s += 137) {
        final (x1, y1) = road.worldAt(s, -90);
        final (x2, y2) = road.worldAt(s, 90);
        final dist = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
        expect(dist, closeTo(180, 1e-6));
      }
    });

    test('sAtX là nghịch đảo của x(s)', () {
      final road = RoadPath.winding(random: Random(11));
      for (var s = 50.0; s < 20000; s += 271) {
        expect(road.sAtX(road.at(s).x), closeTo(s, 1e-6));
      }
    });

    test('bỏ mẫu phía sau không làm sai vị trí phía trước', () {
      final a = RoadPath.winding(random: Random(3));
      final b = RoadPath.winding(random: Random(3));
      a.ensureAhead(30000);
      b.ensureAhead(30000);
      a.trimBefore(20000);
      for (var s = 20000.0; s < 30000; s += 333) {
        expect(a.at(s).x, closeTo(b.at(s).x, 1e-9));
        expect(a.at(s).y, closeTo(b.at(s).y, 1e-9));
      }
    });
  });

  group('PlayerPhysics', () {
    test('ga giữ mức: chạm Ga +5 km/h, giữ Ga tăng tốc, buông tay giữ tốc độ theo nấc, chạm Phanh −5 km/h', () {
      const step = PlayerPhysics.cruiseStep;
      final p = PlayerPhysics(spec: VehicleSpec.motorbike);
      void run(int frames) {
        for (var i = 0; i < frames; i++) {
          p.update(1 / 60);
        }
      }

      // Giữ Ga nửa giây rồi buông: mức ga làm tròn lên nấc 5 km/h, xe giữ đúng mức đó.
      p.throttle = true;
      run(30);
      final mid = p.speed;
      expect(mid, greaterThan(0));
      p.throttle = false;
      run(120);
      expect(p.cruise % step, closeTo(0, 1e-6));
      expect(p.cruise, greaterThanOrEqualTo(mid));
      expect(p.speed, closeTo(p.cruise, 1e-6));

      // Chạm Ga thêm một nấc, chạm Phanh bớt một nấc.
      final held = p.cruise;
      p.throttle = true;
      run(4);
      p.throttle = false;
      run(60);
      expect(p.cruise, closeTo(held + step, 1e-6));
      expect(p.speed, closeTo(held + step, 1e-6));
      p.brake = true;
      run(4);
      p.brake = false;
      run(90);
      expect(p.cruise, closeTo(held, 1e-6));
      expect(p.speed, closeTo(held, 1e-6));

      // Giữ Ga lâu: lên tới tốc độ tối đa và giữ ở đó.
      p.throttle = true;
      run(600);
      expect(p.speed, VehicleSpec.motorbike.maxSpeed);
      p.throttle = false;
      run(60);
      expect(p.speed, VehicleSpec.motorbike.maxSpeed);

      // Phanh ăn dần: chạm nhẹ chỉ bớt chút ít, giữ lâu thì dừng hẳn.
      p.brake = true;
      run(6);
      expect(p.speed, greaterThan(VehicleSpec.motorbike.maxSpeed - 40));
      run(120);
      p.brake = false;
      run(60);
      expect(p.speed, 0);
      expect(p.cruise, 0);
    });

    test('hỗ trợ lái: tự giảm tốc theo giới hạn, qua rồi chạy lại mức ga cũ', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, speed: 480)..cruise = 480;
      p.assistCap = 300;
      var braked = false;
      for (var i = 0; i < 90; i++) {
        p.update(1 / 60);
        braked |= p.assistBraking;
      }
      expect(braked, isTrue);
      expect(p.speed, closeTo(300, 1e-6));
      expect(p.cruise, 480);
      p.assistCap = null;
      for (var i = 0; i < 120; i++) {
        p.update(1 / 60);
      }
      expect(p.speed, 480);
    });

    test('giữ làn: thả cần lái thì về giữa làn gần nhất; gạt sang rồi thả thì vào làn bên', () {
      final lanes = [for (var lane = 0; lane < 4; lane++) Lanes.center(lane)];
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1) - 12, speed: 400)
        ..cruise = 400
        ..laneKeep = true
        ..laneTargets = lanes;
      void run(int frames) {
        for (var i = 0; i < frames; i++) {
          p.update(1 / 60);
        }
      }

      run(120);
      expect(p.d, closeTo(Lanes.center(1), 1.5));
      // Gạt cần lên chừng nửa giây rồi thả: xe sang hẳn làn trong.
      p.steer = -0.6;
      run(26);
      p.steer = 0;
      run(150);
      expect(p.d, closeTo(Lanes.center(0), 1.5));
    });

    test('giữ làn qua cua vừa tốc độ mà không cần bẻ lái', () {
      const curve = RoadCurve(startS: 0, length: 1.5 * 1.2 * GameConfig.minCurveRadiusHighway, turn: 1.2);
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1))
        ..curvature = 1 / curve.radius
        ..laneKeep = true
        ..laneTargets = [for (var lane = 0; lane < 4; lane++) Lanes.center(lane)];
      for (var i = 0; i < 180; i++) {
        p.speed = curve.adviseSpeed * 1.1;
        p.cruise = p.speed;
        p.update(1 / 60);
      }
      expect(p.d, closeTo(Lanes.center(1), 8));
      expect(p.scraping, isFalse);
    });

    test('ổ gà làm khựng xe rồi xe tự lấy lại tốc độ đang giữ', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, speed: 300)..cruise = 300;
      p.bump();
      expect(p.speed, lessThan(300));
      for (var i = 0; i < 120; i++) {
        p.update(1 / 60);
      }
      expect(p.speed, 300);
    });

    test('máy tắt (hết xăng / khục khặc) thì xe trôi chậm dần', () {
      final p = PlayerPhysics(spec: VehicleSpec.motorbike, speed: 200)
        ..cruise = 200
        ..engineOff = true;
      for (var i = 0; i < 60; i++) {
        p.update(1 / 60);
      }
      expect(p.speed, closeTo(200 - GameConfig.coastDecel, 1e-6));
    });

    test('đứng yên thì kéo cần lái cũng không dạt ngang', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: 40);
      p.steer = 1;
      for (var i = 0; i < 60; i++) {
        p.update(1 / 60);
      }
      expect(p.d, 40);
    });

    test('không leo lên vỉa hè', () {
      final p = PlayerPhysics(spec: VehicleSpec.motorbike, speed: 300);
      p.steer = 1;
      for (var i = 0; i < 600; i++) {
        p.update(1 / 60);
      }
      expect(p.d, closeTo(p.maxOffset, 1e-9));
    });

    test('vào cua vừa tốc độ thì xe tự ôm cua, không phải bẻ lái', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1), speed: 300)..curvature = 1 / 600;
      for (var i = 0; i < 60; i++) {
        p.speed = 300;
        p.update(1 / 60);
      }
      expect(p.d, closeTo(Lanes.center(1), 1e-9));
    });

    test('vào cua nhanh quá thì bị văng ra phía ngoài nếu không bẻ lái', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1), speed: 450)..curvature = 1 / 600;
      for (var i = 0; i < 60; i++) {
        p.speed = 450;
        p.update(1 / 60);
      }
      // Cua phải: văng sang trái hướng đi (về phía làn ngược chiều).
      expect(p.d, lessThan(Lanes.center(1) - 25));
    });

    test('chạy đúng tốc độ khuyên dùng thì bẻ lái giữ được làn qua cua gắt', () {
      const curve = RoadCurve(startS: 0, length: 1.5 * 1.2 * GameConfig.minCurveRadiusHighway, turn: 1.2);
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1))
        ..curvature = 1 / curve.radius
        ..steer = 1;
      for (var i = 0; i < 120; i++) {
        p.speed = curve.adviseSpeed;
        p.update(1 / 60);
      }
      expect(p.d, greaterThan(Lanes.center(1) - 5));
      expect(p.scraping, isFalse);
    });

    test('phóng hết tốc độ vào cua gắt: tì vào mép đường, quệt lề mất tốc độ', () {
      final p = PlayerPhysics(spec: VehicleSpec.car, d: Lanes.center(1), speed: VehicleSpec.car.maxSpeed)
        ..curvature = 1 / GameConfig.minCurveRadiusHighway
        ..steer = 1
        ..throttle = true;
      var scraped = false;
      var slowest = p.speed;
      for (var i = 0; i < 480; i++) {
        p.update(1 / 60);
        scraped |= p.scraping;
        slowest = min(slowest, p.speed);
      }
      expect(scraped, isTrue);
      expect(p.d, lessThan(-p.maxOffset + 30));
      expect(slowest, lessThan(VehicleSpec.car.maxSpeed - 50));
    });

    test('chở quà làm tăng tốc chậm hơn', () {
      double speedAfterOneSecond(int cargo) {
        final p = PlayerPhysics(spec: VehicleSpec.motorbike)
          ..cargo = cargo
          ..throttle = true;
        for (var i = 0; i < 60; i++) {
          p.update(1 / 60);
        }
        return p.speed;
      }

      expect(speedAfterOneSecond(5), lessThan(speedAfterOneSecond(0)));
    });
  });

  group('Va chạm', () {
    test('hộp va chạm', () {
      const a = RoadBox(s: 0, d: 0, length: 60, width: 26);
      expect(a.overlaps(const RoadBox(s: 40, d: 10, length: 88, width: 46)), isTrue);
      expect(a.overlaps(const RoadBox(s: 0, d: 60, length: 88, width: 46)), isFalse);
    });

    test('quẹt đuôi khi chạy thường là nhẹ, phóng nhanh đâm là tai nạn (chưa thua)', () {
      const slow = GameConfig.sameDirSpeedMin * GameConfig.normalSpeed;
      expect(classifyCollision(relativeImpactSpeed(GameConfig.normalSpeed, slow)), CollisionSeverity.minor);
      expect(classifyCollision(relativeImpactSpeed(VehicleSpec.motorbike.maxSpeed, slow)), CollisionSeverity.crash);
      expect(classifyCollision(relativeImpactSpeed(GameConfig.normalSpeed, 0)), CollisionSeverity.crash);
    });

    test('đâm trực diện xe ngược chiều ở tốc độ thường là thua ngay', () {
      const oncoming = -GameConfig.oncomingSpeedMin * GameConfig.normalSpeed;
      expect(classifyCollision(relativeImpactSpeed(GameConfig.normalSpeed, oncoming), headOn: true), CollisionSeverity.fatal);
      // Tông đuôi xe đang dừng ở tốc độ tối đa của xe máy: tai nạn nặng nhưng chưa thua.
      expect(classifyCollision(relativeImpactSpeed(VehicleSpec.motorbike.maxSpeed, 0)), CollisionSeverity.crash);
      expect(classifyCollision(relativeImpactSpeed(VehicleSpec.car.maxSpeed, 0)), CollisionSeverity.fatal);
    });
  });

  group('Chase', () {
    ChaseOutcome run(VehicleSpec spec, double Function(double t) playerSpeed) {
      final chase = Chase(spec);
      var t = 0.0;
      while (chase.outcome == ChaseOutcome.running) {
        chase.update(1 / 60, playerSpeed(t));
        t += 1 / 60;
      }
      return chase.outcome;
    }

    for (final spec in [VehicleSpec.motorbike, VehicleSpec.car]) {
      test('${spec.kind.name}: ga hết cỡ thì thoát', () {
        expect(run(spec, (t) => min(spec.maxSpeed, spec.accel * t)), ChaseOutcome.escaped);
      });

      test('${spec.kind.name}: chạy tốc độ thường thì bị bắt', () {
        expect(run(spec, (t) => min(GameConfig.normalSpeed, spec.accel * t)), ChaseOutcome.caught);
      });
    }
  });

  group('TripClock', () {
    test('quy đổi: 2,5 phút chơi ở tốc độ thường = 2 giờ trong game', () {
      final clock = TripClock(minutes: 20 * 60);
      clock.advance(150);
      expect(clock.minutes, closeTo(22 * 60, 1e-9));
      expect(clock.label, '22:00');
    });

    test('giờ xuất phát: chạy đều 20 km/h cộng 40 phút mỗi chặng vẫn kịp giao thừa', () {
      // 100 km một chặng: 5 giờ ở 20 km/h + 40 phút dừng nghỉ.
      expect(TripClock.allowedMinutes(100, 1, Difficulty.easy), greaterThan(TripClock.allowedMinutes(100, 1)));
      expect(TripClock.allowedMinutes(100, 1, Difficulty.hard), lessThan(TripClock.allowedMinutes(100, 1)));
      final allowed = TripClock.allowedMinutes(100, 1);
      expect(allowed, closeTo(5 * 60 + 40, 1e-9));
      expect(TripClock.departureFor(allowed), closeTo(24 * 60 - 340, 1e-9));
      // Đi đúng 20 km/h không dừng thì tới nơi còn dư đúng phần dừng nghỉ.
      final clock = TripClock(minutes: TripClock.departureFor(allowed));
      final playSeconds = 100 * GameConfig.unitsPerKm / (GameConfig.normalSpeed * 20 / 50);
      clock.advance(playSeconds);
      expect(clock.minutesLeft, closeTo(40, 1e-6));
    });

    test('nhãn giờ và ngày khi xuất phát từ mấy hôm trước', () {
      final clock = TripClock(minutes: -100);
      expect(clock.label, '22:20');
      expect(clock.dayLabel, '29 Tết');
      expect(TripClock(minutes: -3 * 1440 + 11 * 60).dayLabel, '27 Tết');
    });

    test('quá giao thừa là hết giờ', () {
      final clock = TripClock(minutes: 23 * 60 + 59);
      expect(clock.isOver, isFalse);
      clock.addPenalty(2);
      expect(clock.isOver, isTrue);
    });
  });

  group('TrafficSystem', () {
    test('xe AI cùng làn không bao giờ đè lên nhau', () {
      for (var seed = 0; seed < 10; seed++) {
        final traffic = TrafficSystem(Random(seed));
        var playerS = 0.0;
        for (var i = 0; i < 60 * 120; i++) {
          playerS += GameConfig.normalSpeed / 60;
          traffic.update(
            1 / 60,
            PlayerSnapshot(s: playerS, d: 300, speed: GameConfig.normalSpeed, length: 60, width: 26),
            spawnS: playerS + 900,
            despawnBehindS: playerS - 600,
            despawnAheadS: playerS + 3000,
          );
          for (final a in traffic.vehicles) {
            for (final b in traffic.vehicles) {
              if (identical(a, b) || a.lane != b.lane) continue;
              expect(a.box.overlaps(b.box, shrink: 1), isFalse, reason: 'seed $seed, frame $i');
            }
          }
        }
      }
    });

    test('xe cùng chiều phía sau không tông đuôi người chơi đang phanh', () {
      final traffic = TrafficSystem(Random(1));
      final lane = Lanes.sameDirection.first;
      final v = TrafficVehicle(
        id: 0,
        type: TrafficType.sedan,
        lane: lane,
        s: 0,
        cruiseSpeed: 0.7 * GameConfig.normalSpeed,
        variant: 0,
      );
      traffic.vehicles.add(v);
      final player = PlayerSnapshot(s: 400, d: Lanes.center(lane), speed: 0, length: 60, width: 26);
      for (var i = 0; i < 60 * 10; i++) {
        traffic.update(1 / 60, player, spawnS: 1e9, despawnBehindS: -1e9, despawnAheadS: 1e9);
        expect(
          v.box.overlaps(RoadBox(s: player.s, d: player.d, length: player.length, width: player.width), shrink: 1),
          isFalse,
        );
      }
    });

    test('không sinh xe chắn kín cả 2 làn chiều mình', () {
      for (var seed = 0; seed < 50; seed++) {
        final traffic = TrafficSystem(Random(seed));
        for (var i = 0; i < 40; i++) {
          traffic.trySpawn(1000.0 + i * 37, oncoming: false);
        }
        for (final a in traffic.vehicles.where((v) => v.lane == 0)) {
          for (final b in traffic.vehicles.where((v) => v.lane == 1)) {
            expect((a.s - b.s).abs(), greaterThanOrEqualTo(GameConfig.sideBySideBlockGap));
          }
        }
      }
    });

    test('tâm các làn', () {
      expect(Lanes.center(0), 33);
      expect(Lanes.center(1), 93);
      expect(Lanes.center(2), -33);
      expect(Lanes.center(3), -93);
      expect(Lanes.at(50), 0);
      expect(Lanes.at(-100), 3);
      expect(Lanes.at(200), isNull);
    });
  });
}
