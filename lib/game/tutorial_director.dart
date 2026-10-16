import 'package:flame/components.dart';

import '../model/trip.dart';
import 'game_config.dart';
import 'logic/cross_traffic.dart';
import 'logic/road_layout.dart';
import 'logic/tutorial.dart';
import 'stage.dart';
import 've_que_game.dart';

/// Gắn vào chặng tập lái: mỗi khung hình chụp tình trạng xe cho
/// [TutorialTracker] chấm bước, và tới bước dừng đèn đỏ thì sắp xếp đèn ngã
/// tư phía trước để chắc chắn gặp đèn đỏ (xem [TutorialLights]).
class TutorialDirector extends Component {
  TutorialDirector({
    required this.game,
    required this.tracker,
    required this.honks,
    required this.onStep,
    required this.onTick,
  });

  final VeQueGame game;
  final TutorialTracker tracker;

  /// Số lần bóp còi thành công (đếm ở tầng Flutter).
  final int Function() honks;

  /// Một bước vừa xong.
  final void Function(TutorialStep step) onStep;

  /// Sau mỗi khung hình chấm bước (giao diện đọc [TutorialTracker.progress]).
  final void Function() onTick;

  /// Ngã tư đã sắp xếp đèn (theo tim ngã tư).
  final Set<double> _armed = {};

  /// Ảnh chụp gần nhất.
  TutorialProbe? probe;

  @override
  void update(double dt) {
    super.update(dt);
    final p = _probe();
    probe = p;
    _planLight(p);
    final done = tracker.update(p, dt);
    if (done != null) onStep(done);
    onTick();
  }

  /// Đoạn phố cuối chặng (có đèn giao thông), null nếu chặng không kết thúc
  /// bằng phố.
  RoadZone? get _finalCity {
    final last = game.layout.zones.last;
    return last.kind == RoadKind.city ? last : null;
  }

  TutorialProbe _probe() {
    final player = game.player;
    const k = GameConfig.displayKmhPerUnitSpeed;
    final front = player.s + game.spec.length / 2;
    final city = _finalCity;
    TutorialLight? light;
    var left = 0;
    if (city != null) {
      for (final l in game.layout.lights) {
        if (l.s < city.startS) continue;
        final distance = l.stopLine - front;
        if (distance < -2) continue;
        left++;
        light ??= TutorialLight(s: l.s, color: l.colorAt(game.time), remaining: l.remainingAt(game.time), distance: distance);
      }
    }
    return TutorialProbe(
      speedKmh: player.speed * k,
      cruiseKmh: player.cruise * k,
      throttle: player.throttle,
      brake: player.brake,
      steer: player.steer,
      d: player.d,
      lateral: player.lateralVelocity,
      assist: game.driveAssist,
      honks: honks(),
      headlights: game.headlightsOn,
      driving: game.phase == GamePhase.driving,
      cityAheadKm: city == null || player.s >= city.startS ? null : (city.startS - player.s) / GameConfig.unitsPerKm,
      light: light,
      lightsLeft: left,
    );
  }

  /// Bước dừng đèn đỏ: đèn phía trước chuyển đỏ vừa lúc xe tới, giữ đỏ tới
  /// khi xe dừng hẳn; dừng xong thì vài giây sau đèn xanh.
  void _planLight(TutorialProbe p) {
    final light = p.light;
    if (light == null) return;
    final step = tracker.step;
    final stopped = step == TutorialStep.greenGo && tracker.stoppedAt == light.s;
    if (step != TutorialStep.redLight && !stopped) return;
    final armed = _armed.contains(light.s);
    if (stopped && !armed) return;
    final phase = TutorialLights.plan(
      armed: armed,
      stopped: stopped,
      color: light.color,
      remaining: light.remaining,
      distance: light.distance,
      speed: game.player.speed,
    );
    if (phase == null) return;
    _armed.add(light.s);
    _retime(light.s, phase);
  }

  /// Thay đèn ngã tư [s] bằng đèn cùng chỗ, lệch pha mới; xe đường ngang
  /// đang ở ngã tư đó chuyển sang theo đèn mới.
  void _retime(double s, double phase) {
    final lights = game.layout.lights;
    final i = lights.indexWhere((l) => l.s == s);
    if (i < 0) return;
    final old = lights[i];
    final fresh = TrafficLight(s: old.s, offset: TutorialLights.offsetFor(game.time, phase), noUTurn: old.noUTurn);
    lights[i] = fresh;
    final cross = game.cross.vehicles;
    for (var j = 0; j < cross.length; j++) {
      final v = cross[j];
      if (!identical(v.light, old)) continue;
      cross[j] = CrossVehicle(
        id: v.id,
        type: v.type,
        light: fresh,
        down: v.down,
        d: v.d,
        cruiseSpeed: v.cruiseSpeed,
        variant: v.variant,
      )..speed = v.speed;
    }
  }
}
