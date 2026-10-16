import 'dart:math';

import '../../model/difficulty.dart';
import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../stage.dart';
import '../vehicle_spec.dart';
import 'road_layout.dart';
import 'traffic_system.dart';

/// Các bước của chặng tập lái, theo thứ tự. Mỗi bước kiểm tra bằng số liệu
/// thật của xe ([TutorialProbe]), không tin vào việc người chơi đã bấm nút.
enum TutorialStep {
  tapGas('Chạm Ga để lăn bánh', 'Mỗi lần chạm Ga thêm 5 km/h. Chạm vài lần tới 40 km/h.', 'Chạm Ga'),
  holdGas('Giữ Ga để tăng tốc', 'Giữ Ga tới 60 km/h rồi buông tay — xe tự giữ tốc độ.', 'Giữ Ga'),
  laneInner('Sang làn trong', '', 'Sang làn'),
  laneOuter('Về làn ngoài', '', 'Về làn'),
  tapBrake('Chạm Phanh hai lần', 'Mỗi lần chạm bớt 5 km/h — giảm 10 km/h.', 'Chạm Phanh'),
  horn('Bóp còi xin đường', 'Xe trước chậm thì bóp còi — xe to có khi không nhường.', 'Bóp còi'),
  headlights('Bật đèn pha', 'Trời sắp tối — bật đèn để thấy đường và người khác thấy mình.', 'Bật đèn'),
  redLight('Dừng trước đèn đỏ', 'Vào phố gặp đèn đỏ thì giữ Phanh, dừng hẳn trước vạch.', 'Đèn đỏ'),
  greenGo('Đèn xanh thì đi', 'Chờ đèn xanh rồi chạm Ga đi tiếp.', 'Đèn xanh');

  const TutorialStep(this.title, this._detail, this.short);

  final String title;
  final String _detail;

  /// Tên ngắn (bảng tổng kết cuối chặng tập).
  final String short;

  /// Lời chỉ dẫn; hai bước đổi làn tuỳ hướng gạt cần lái ([horizontal]: góc
  /// nhìn ghế lái, cần lái kéo ngang) và có bật hỗ trợ lái không ([assist]:
  /// thả tay là xe tự vào giữa làn).
  String detail({bool horizontal = false, bool assist = true}) {
    final inner = this == laneInner;
    if (!inner && this != laneOuter) return _detail;
    final way = inner ? (horizontal ? 'sang trái' : 'lên') : (horizontal ? 'sang phải' : 'xuống');
    final lane = inner ? 'làn trong' : 'làn sát lề';
    return assist
        ? 'Gạt cần lái $way rồi thả tay — xe tự ${inner ? 'vào giữa làn trong' : 'về làn sát lề'}.'
        : 'Gạt cần lái $way tới $lane rồi thả tay.';
  }
}

/// Bước đã xong thật hay người chơi bấm "Bỏ qua".
enum TutorialOutcome { done, skipped }

/// Đèn giao thông gần nhất phía trước (chưa qua vạch dừng).
class TutorialLight {
  const TutorialLight({required this.s, required this.color, required this.remaining, required this.distance});

  /// Tim ngã tư (định danh đèn).
  final double s;
  final LightColor color;

  /// Giây còn lại của màu đang sáng.
  final double remaining;

  /// Từ đầu xe tới vạch dừng (đơn vị đường), âm = đã chạm vạch.
  final double distance;

  bool get stopping => color != LightColor.green;
}

/// Ảnh chụp tình trạng xe mỗi khung hình để chấm bước tập.
class TutorialProbe {
  const TutorialProbe({
    required this.speedKmh,
    required this.cruiseKmh,
    this.throttle = false,
    this.brake = false,
    this.steer = 0,
    required this.d,
    this.lateral = 0,
    this.assist = true,
    this.honks = 0,
    this.headlights = false,
    this.driving = true,
    this.cityAheadKm,
    this.light,
    this.lightsLeft = 0,
  });

  final double speedKmh;

  /// Mức ga đang giữ (km/h).
  final double cruiseKmh;
  final bool throttle;
  final bool brake;
  final double steer;

  /// Lệch khỏi tim đường (dương = bên phải chiều đi).
  final double d;

  /// Tốc độ dạt ngang (đơn vị/giây): gần 0 là xe đã nằm yên trong làn.
  final double lateral;

  /// Hỗ trợ lái đang bật (thả cần lái xe tự vào giữa làn).
  final bool assist;

  /// Số lần bóp còi thành công từ đầu chặng.
  final int honks;
  final bool headlights;

  /// Đang lái (không ghé quán, chưa kết thúc).
  final bool driving;

  /// Còn bao nhiêu km tới đoạn phố cuối (null khi đã vào phố).
  final double? cityAheadKm;

  /// Đèn phía trước trong đoạn phố cuối và còn mấy đèn chưa qua.
  final TutorialLight? light;
  final int lightsLeft;

  int? get lane => Lanes.at(d);
}

/// Chấm các bước tập lái. Thuần logic (không đụng game) để test được.
class TutorialTracker {
  static const double gasTarget = 40;
  static const double holdTarget = 60;
  static const double brakeDrop = 10;

  /// Giữ tốc độ (buông Ga) bao lâu thì tính là "xe tự giữ tốc độ".
  static const double cruiseHold = 1.5;

  /// Xe nằm yên giữa làn sau khi thả cần lái bao lâu.
  static const double laneHold = 0.5;

  /// Đứng yên trước đèn đỏ bao lâu.
  static const double stopHold = 0.8;

  /// Dừng cách vạch quá chừng này (đơn vị đường, chừng 3 thân xe) là còn xa.
  static const double stopReach = 300;

  final List<TutorialOutcome?> outcomes = List.filled(TutorialStep.values.length, null);
  int index = 0;

  /// Tiến độ bước hiện tại 0..1 và dòng nhắc ngắn (theo tình trạng xe).
  double progress = 0;
  String cue = '';

  double _held = 0;
  double _peak = 0;

  /// Bước đổi làn: xe đã rời khỏi làn đích lúc nào chưa (đang ở sẵn làn đích
  /// thì phải sang làn kia rồi về mới tính).
  bool _left = false;
  int? _honks0;
  double? _stoppedAt;

  TutorialStep? get step => index < TutorialStep.values.length ? TutorialStep.values[index] : null;
  bool get finished => step == null;
  int get doneCount => outcomes.where((o) => o == TutorialOutcome.done).length;
  int get skippedCount => outcomes.where((o) => o == TutorialOutcome.skipped).length;

  /// Ngã tư vừa dừng chờ đèn đỏ (bước "đèn xanh thì đi" theo dõi đèn này).
  double? get stoppedAt => _stoppedAt;

  /// Bỏ qua bước đang tập.
  void skip() {
    if (finished) return;
    outcomes[index] = TutorialOutcome.skipped;
    _advance();
  }

  void _advance() {
    index++;
    _held = 0;
    _peak = 0;
    _left = false;
    _honks0 = null;
    progress = 0;
    cue = '';
  }

  /// Chấm một khung hình; trả về bước vừa hoàn thành (null nếu chưa).
  TutorialStep? update(TutorialProbe p, double dt) {
    final step = this.step;
    if (step == null) return null;
    _honks0 ??= p.honks;
    if (!p.driving) {
      _held = 0;
      return null;
    }
    final (ok, need) = _check(step, p, _held + dt);
    _held = ok ? _held + dt : 0;
    if (!ok || _held + 1e-9 < need) return null;
    if (step == TutorialStep.redLight) _stoppedAt = p.light?.s;
    outcomes[index] = TutorialOutcome.done;
    _advance();
    return step;
  }

  /// Điều kiện đạt chưa và phải giữ bao lâu; đồng thời đặt [progress], [cue]
  /// ([held]: tính cả khung hình này nếu điều kiện vẫn đạt).
  (bool, double) _check(TutorialStep step, TutorialProbe p, double held) {
    final cruise = p.cruiseKmh, speed = p.speedKmh;
    switch (step) {
      case TutorialStep.tapGas:
        progress = (cruise / gasTarget).clamp(0.0, 1.0);
        final taps = ((gasTarget - cruise) / 5).ceil();
        cue = cruise >= gasTarget - 0.5
            ? (p.throttle ? 'Đủ rồi, buông Ga ra' : 'Xe đang lên ${gasTarget.round()} km/h…')
            : '${cruise.round()} km/h · chạm thêm $taps lần';
        return (cruise >= gasTarget - 0.5 && speed >= gasTarget - 3 && !p.throttle, 0.15);
      case TutorialStep.holdGas:
        final reached = cruise >= holdTarget - 0.5;
        final steady = reached && !p.throttle && !p.brake && speed >= holdTarget - 12;
        if (!reached) {
          progress = ((cruise - gasTarget) / (holdTarget - gasTarget)).clamp(0.0, 1.0) * 0.6;
          cue = p.throttle ? 'Giữ tiếp… ${cruise.round()} km/h' : 'Giữ chặt nút Ga';
        } else if (p.throttle) {
          progress = 0.6;
          cue = 'Đủ ${holdTarget.round()} rồi — buông Ga!';
        } else {
          progress = 0.6 + 0.4 * (held / cruiseHold).clamp(0.0, 1.0);
          cue = 'Xe tự giữ ${cruise.round()} km/h';
        }
        return (steady, cruiseHold);
      case TutorialStep.laneInner:
      case TutorialStep.laneOuter:
        final inner = step == TutorialStep.laneInner;
        final want = inner ? 0 : 1;
        final from = Lanes.center(inner ? 1 : 0), to = Lanes.center(want);
        final released = p.steer.abs() <= 0.05;
        final inLane = p.lane == want;
        if (!inLane) _left = true;
        // Hỗ trợ lái đưa xe vào giữa làn (hoặc sát lề): chờ xe nằm yên hẳn.
        final settled = !p.assist || p.lateral.abs() < 6;
        final ok = inLane && released && settled && _left;
        if (!ok) progress = _left ? ((p.d - from) / (to - from)).clamp(0.0, 1.0) * 0.8 : 0;
        cue = speed < 15
            ? 'Chạm Ga cho xe chạy đã'
            : !_left
            ? (inner ? 'Gạt nhẹ cần lái rồi thả' : 'Sang làn trong rồi về lại đây')
            : !released
            ? (inLane ? 'Thả tay — xe tự vào làn' : 'Gạt thêm chút nữa…')
            : inLane
            ? 'Vào làn rồi!'
            : (inner ? 'Gạt nhẹ cần lái rồi thả' : 'Gạt cần lái về làn ngoài');
        if (ok) progress = 0.8 + 0.2 * (held / laneHold).clamp(0.0, 1.0);
        return (ok, laneHold);
      case TutorialStep.tapBrake:
        if (!p.brake) _peak = max(_peak, cruise);
        final target = _peak - brakeDrop;
        if (_peak < 15) {
          progress = 0;
          cue = 'Chạm Ga lên tốc độ đã';
          return (false, 0);
        }
        progress = ((_peak - cruise) / brakeDrop).clamp(0.0, 1.0);
        final left = ((cruise - target) / 5).ceil();
        cue = cruise <= target + 0.5
            ? (p.brake ? 'Buông Phanh' : 'Giữ ${cruise.round()} km/h')
            : '${_peak.round()} → ${target.round()} km/h · chạm thêm $left lần';
        return (cruise <= target + 0.5 && !p.brake, 0.1);
      case TutorialStep.horn:
        progress = 0;
        cue = 'Bấm nút Còi';
        return (p.honks > (_honks0 ?? p.honks), 0);
      case TutorialStep.headlights:
        progress = 0;
        cue = 'Bấm nút Đèn';
        return (p.headlights, 0);
      case TutorialStep.redLight:
        return _checkRedLight(p, held);
      case TutorialStep.greenGo:
        final light = p.light;
        final at = _stoppedAt;
        final same = light != null && at != null && (light.s - at).abs() < 1;
        final waiting = light != null && same && light.stopping;
        progress = waiting ? 0.2 : (speed / 12).clamp(0.0, 1.0);
        cue = light != null && waiting
            ? 'Chờ đèn xanh… ${light.remaining.ceil()} giây'
            : same
            ? 'Đèn xanh rồi — chạm Ga đi tiếp'
            : 'Chạm Ga đi tiếp';
        return (!waiting && speed >= 12, 0.3);
    }
  }

  (bool, double) _checkRedLight(TutorialProbe p, double held) {
    final speed = p.speedKmh;
    final light = p.light;
    final ahead = p.cityAheadKm;
    // Không còn đèn nào phía trước: chỉ cần phanh dừng hẳn.
    if (light == null && p.lightsLeft == 0 && ahead == null) {
      progress = speed < 1 ? 0.6 + 0.4 * (held / stopHold).clamp(0.0, 1.0) : (1 - speed / 50).clamp(0.0, 0.6);
      cue = speed < 1 ? 'Dừng tốt rồi' : 'Giữ Phanh — dừng hẳn xe lại';
      return (speed < 1, stopHold);
    }
    if (light == null || light.distance > 1800) {
      progress = 0;
      cue = ahead != null && ahead >= 0.3 ? 'Còn ${ahead.toStringAsFixed(1).replaceAll('.', ',')} km tới phố' : 'Sắp tới ngã tư — để ý đèn';
      return (false, stopHold);
    }
    if (!light.stopping) {
      progress = 0;
      cue = 'Sắp tới ngã tư — đi chậm lại';
      return (false, stopHold);
    }
    final near = light.distance >= -2 && light.distance <= stopReach;
    if (!near) {
      progress = 0.1;
      cue = speed < 1 ? 'Còn xa vạch — nhích lên chút' : 'Đèn đỏ — giảm tốc từ từ';
      return (false, stopHold);
    }
    final stopped = speed < 1;
    progress = stopped ? 0.6 + 0.4 * (held / stopHold).clamp(0.0, 1.0) : 0.1 + 0.5 * (1 - speed / 50).clamp(0.0, 1.0);
    cue = stopped ? 'Dừng tốt rồi' : 'Giữ Phanh — dừng trước vạch';
    return (stopped, stopHold);
  }
}

/// Đèn đỏ "đến đúng lúc" cho bước dừng đèn đỏ: đổi pha đèn ngã tư phía trước
/// để người tập chắc chắn gặp đèn đỏ (và đèn chờ tới khi xe dừng hẳn).
abstract class TutorialLights {
  /// Bắt đầu sắp xếp đèn khi vạch dừng còn cách chừng này.
  static const double armReach = 2400;

  /// Gần quá thì không kịp sắp xếp (để ngã tư sau).
  static const double armMin = 320;

  /// Đèn chuyển đỏ trước lúc xe tới vạch chừng này giây (tính theo tốc độ
  /// lúc sắp xếp), và chưa tới lúc thì tối thiểu chừng này giây đỏ còn lại.
  static const double redLead = 2.4;
  static const double holdLeft = 2.2;

  /// Dừng xong thì chờ thêm chừng này giây là đèn xanh.
  static const double releaseLeft = 2.5;

  static double get _green => TrafficLight.green;
  static double get _yellow => TrafficLight.yellow;
  static double get _cycle => TrafficLight.cycle;

  /// Lệch pha để lúc [time] đèn đang ở giây thứ [phase] của chu kỳ.
  static double offsetFor(double time, double phase) {
    final o = (phase - time) % _cycle;
    return o < 0 ? o + _cycle : o;
  }

  /// Giây trong chu kỳ để đèn chuyển đỏ sau [redIn] giây nữa (còn xanh hoặc
  /// đang vàng tới lúc đó).
  static double phaseRedIn(double redIn) => _green + _yellow - redIn.clamp(0.0, _green + _yellow);

  /// Giây trong chu kỳ để đèn đang đỏ, còn [left] giây nữa thì xanh.
  static double phaseRedLeft(double left) => _cycle - left.clamp(0.05, TrafficLight.red);

  /// Nên đặt đèn sắp gặp ở pha nào lúc này (null = để nguyên).
  ///
  /// [armed]: đèn này đã được sắp xếp chưa; [stopped]: người tập đã dừng xong
  /// bước đèn đỏ; [distance]: đầu xe tới vạch dừng; [speed]: đơn vị/giây.
  static double? plan({
    required bool armed,
    required bool stopped,
    required LightColor color,
    required double remaining,
    required double distance,
    required double speed,
  }) {
    if (stopped) {
      return color == LightColor.red && remaining > releaseLeft + 0.05 ? phaseRedLeft(releaseLeft) : null;
    }
    if (!armed) {
      if (distance > armReach || distance < armMin) return null;
      final eta = distance / max(speed, 1);
      // Đi chậm quá thì đợi tới gần hơn mới sắp xếp (khỏi đỏ rồi lại xanh).
      if (eta > _green + _yellow + redLead && distance > 900) return null;
      return phaseRedIn(max(0.6, eta - redLead));
    }
    // Đã đỏ mà xe chưa dừng xong: giữ đèn đỏ thêm.
    if (color == LightColor.red && remaining < holdLeft && distance > -6 && distance < 1500) return phaseRedLeft(holdLeft);
    return null;
  }
}

/// Dựng chặng tập lái: phố ngắn → quốc lộ thoáng → phố có đèn giao thông.
abstract class TutorialPlan {
  static const List<StageSection> sections = [
    StageSection(RoadKind.city, 2),
    StageSection(RoadKind.highway, 24),
    StageSection(RoadKind.city, 10),
  ];

  /// Xe trên đường thưa hơn mức "Dễ".
  static const double trafficDensity = 0.45;

  static StageSetup setup({int seed = 2027}) => StageSetup(
    vehicle: VehicleKind.motorbike,
    fromName: 'Bãi tập lái',
    toName: 'Thị trấn',
    sections: sections,
    // Chiều muộn: vào phố lúc chạng vạng, bật đèn là thấy ngay.
    startClockMinutes: 16 * 60 + 50,
    startFuel: 1,
    seed: seed,
    theme: MapTheme.delta,
    sky: SkyMode.clock,
    difficulty: Difficulty.easy,
    tutorial: true,
  );
}
