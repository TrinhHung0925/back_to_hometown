part of 've_que_game.dart';

/// Đoạn đường phủ sương mù (theo quãng đường, dày dần rồi tan dần).
class _FogBank {
  const _FogBank(this.from, this.to, this.peak);

  final double from;
  final double to;
  final double peak;

  double at(double s) {
    if (s <= from || s >= to) return 0;
    return peak * (min(s - from, to - s) / GameConfig.fogFade).clamp(0.0, 1.0);
  }
}

/// Tắc đường cửa ngõ thành phố dịp cận Tết: xe xếp hàng từ [from] tới
/// [head] — đầu phố, chỗ CSGT đứng phân luồng cho đi từng đợt.
class _Jam {
  _Jam(this.from, this.head);

  final double from;
  final double head;
  bool filled = false;
  bool open = false;
  double cycle = 0;
  final Set<int> ids = {};
}

/// Đường cứu nạn bên phải đường đèo: dải sỏi rẽ ra khỏi đường cho xe mất
/// phanh lao vào. [s] là chỗ bắt đầu rẽ.
class _Ramp {
  _Ramp(this.s);

  final double s;
  bool rolled = false;
}

enum _HitchState { waiting, riding, done }

/// Người đứng ven đường vẫy xin đi nhờ một đoạn.
class _Hitch {
  _Hitch({required this.s, required this.dropS, required this.name, required this.who, required this.art, required this.tip});

  final double s;
  final double dropS;
  final String name;

  /// "Cậu sinh viên", "Cô bán hàng"… (tên hiện trên bong bóng lời).
  final String who;

  /// Ảnh người đứng vẫy (hitch_[art]_1/2).
  final int art;
  final int tip;
  _HitchState state = _HitchState.waiting;

  /// Chỗ đang đứng (lúc chờ: [s]; xuống xe rồi: chỗ xuống).
  late double standS = s;
  bool overshot = false;
  bool greeted = false;
}

/// Đang tự tấp vào lề vì việc gì (đón khách, trả khách, nghe điện thoại,
/// CSGT vẫy vào kiểm tra nồng độ cồn).
enum _PullKind { pickUp, dropOff, call, breath }

/// Cuộc gọi từ nhà.
class _Call {
  _Call(this.attempt);

  final int attempt;
  String get caller => attempt >= 3 ? 'Bố' : 'Mẹ';
  CallStage stage = CallStage.ringing;
  double t = 0;
  double ringIn = 0;
  bool driving = false;
  List<(String, bool)> lines = const [];
  int line = 0;
}

/// Chuyện dọc đường theo bản đồ và dịp Tết: sương mù đèo, gió biển giật và
/// cát bay, tắc đường cửa ngõ, xe tải mất phanh đổ dốc, mẹ gọi điện, khách
/// xin đi nhờ, cành đào buộc sau xe máy, xi-nhan của xe mình.
class _TetEvents {
  _TetEvents(this.g);

  final VeQueGame g;
  late final Random _r = Random(g.setup.seed * 53 + 11);

  double _between(double a, double b) => a + _r.nextDouble() * (b - a);

  // ------------------------------------------------------------ Lên lịch
  late final List<_FogBank> fogBanks = _planFog();
  late final _Jam? jam = _planJam();
  late final List<_Ramp> ramps = _planRamps();
  late final List<_Hitch> hitches = _planHitches();
  late final double _callAtS = _planCall();
  late final _Ferry? ferry = _planFerry();
  _FerryStep _ferryStep = _FerryStep.none;
  double _ferryT = 0;
  double _queueS = 0;

  List<RoadZone> _highways({double minLength = 3000}) => [
        for (final z in g.layout.zones)
          if (z.kind == RoadKind.highway && z.endS - z.startS > minLength) z,
      ];

  /// Đèo hay có sương mù; đồng bằng Bắc Bộ dịp Tết thỉnh thoảng cũng mù.
  List<_FogBank> _planFog() {
    if (!g.fatigue) return const [];
    final theme = g.setup.theme;
    final chance = theme == MapTheme.mountain ? 0.8 : (theme == MapTheme.delta && !g.setup.south ? 0.25 : 0.0);
    if (_r.nextDouble() >= chance) return const [];
    final zones = _highways();
    if (zones.isEmpty) return const [];
    final z = zones[_r.nextInt(zones.length)];
    final len = z.endS - z.startS;
    final span = min(len * 0.6, _between(8, 16) * GameConfig.unitsPerKm);
    final from = z.startS + _r.nextDouble() * (len - span);
    return [_FogBank(from, from + span, _between(0.7, 0.95))];
  }

  /// Cửa ngõ vào phố (sau một đoạn quốc lộ) hay tắc ngày cận Tết.
  _Jam? _planJam() {
    if (!g.fatigue) return null;
    final zones = g.layout.zones;
    for (var i = 1; i < zones.length; i++) {
      final z = zones[i];
      if (z.kind != RoadKind.city || zones[i - 1].kind != RoadKind.highway) continue;
      if (z.startS - GameConfig.jamLength - VeQueGame._startS < 2500) continue;
      if (_r.nextDouble() > GameConfig.jamChance) continue;
      return _Jam(z.startS - GameConfig.jamLength, z.startS - 30);
    }
    return null;
  }

  /// Đèo núi: vài đường cứu nạn bên phải, chỗ không vướng quán, ngã tư.
  List<_Ramp> _planRamps() {
    if (!g.fatigue || g.setup.theme != MapTheme.mountain) return const [];
    final out = <_Ramp>[];
    for (final z in _highways(minLength: 5000)) {
      var s = z.startS + 2600 + _r.nextDouble() * 1500;
      while (s < z.endS - 1400 && out.length < 2) {
        final clear = !g.layout.nearFeature(s, margin: 900) && g.layout.stallsBetween(s - 700, s + 900).isEmpty;
        if (clear) {
          out.add(_Ramp(s));
          s += _between(9, 14) * GameConfig.unitsPerKm;
        } else {
          s += 400;
        }
      }
    }
    return out;
  }

  static const List<(String, String, int)> _hitchPeople = [
    ('Minh', 'Cậu sinh viên', 1),
    ('Cô Hoa', 'Cô bán hàng', 2),
    ('Tuấn', 'Anh công nhân', 1),
    ('Chị Lan', 'Chị đi chợ Tết', 2),
  ];

  /// Người đứng vẫy xin đi nhờ ven quốc lộ (xe máy, ô tô).
  List<_Hitch> _planHitches() {
    // Xe máy chở cả nhà (vợ sau, con trước) thì hết chỗ cho người đi nhờ.
    if (!g.fatigue || g.spec.kind == VehicleKind.bus || (g.setup.family && g.spec.kind == VehicleKind.motorbike)) return const [];
    final out = <_Hitch>[];
    for (final z in _highways()) {
      var s = z.startS + _between(1500, 4000);
      while (s < z.endS - 800) {
        final clear = !g.layout.nearFeature(s, margin: 500) && g.layout.stallsBetween(s - 350, s + 350).isEmpty && !inRiver(s, margin: 2500);
        final drop = s + _between(5, 11) * GameConfig.unitsPerKm;
        if (clear && drop < g.finishS - 600 && _r.nextDouble() < 0.7) {
          final (name, who, art) = _hitchPeople[_r.nextInt(_hitchPeople.length)];
          out.add(_Hitch(s: s, dropS: drop, name: name, who: who, art: art, tip: 2 + _r.nextInt(3)));
          s = drop + _between(6, 12) * GameConfig.unitsPerKm;
        } else {
          s += _between(3, 6) * GameConfig.unitsPerKm;
        }
      }
    }
    return out;
  }

  /// Chặng nào cũng có thể mẹ gọi hỏi thăm (chặng đầu hay gọi hơn).
  double _planCall() {
    if (!g.fatigue) return double.infinity;
    final chance = g.setup.stageNumber == 1 ? 0.7 : 0.45;
    if (_r.nextDouble() >= chance) return double.infinity;
    return VeQueGame._startS + (g.finishS - VeQueGame._startS) * _between(0.25, 0.6);
  }

  // ------------------------------------------------------------- Trạng thái
  /// Sương mù chỗ xe đang chạy (0..1).
  double fog = 0;

  /// Gió biển đang giật (0..1) và lực đẩy ngang lên xe (u/s, dương = sang
  /// phải chiều đi).
  double gust = 0;
  double windPull = 0;

  /// Xe tải mất phanh đang tới (đếm ngược trước khi nó lọt vào khung hình).
  double truckWarn = 0;
  TrafficVehicle? truck;
  _Ramp? _truckRamp;
  double _hornIn = 0;

  _Hitch? riding;
  _Call? call;
  int _callAttempts = 0;
  double _callAgainIn = -1;

  _PullKind? pull;
  _Hitch? _pullHitch;
  double _holdT = 0;

  late double peach = g.spec.kind == VehicleKind.motorbike ? g.setup.startPeach : -1;

  /// Xi-nhan của xe mình theo chiều đi: -1 trái, 1 phải.
  int blinker = 0;
  double _blinkHold = 0;

  double _gustIn = 5;
  double _gustT = -1;
  double _sandIn = 4;
  double _fogDark = 0;
  bool _gustTold = false;

  bool get talkingWhileDriving => call?.stage == CallStage.talking && (call?.driving ?? false);

  /// Đang tự tấp vào / dừng giữ xe vì sự kiện (không cho tự lái).
  bool get holding =>
      pull != null || _holdT > 0 || ferryBusy || _ferryStep == _FerryStep.approach || (call?.stage == CallStage.talking && !(call?.driving ?? true));

  // ------------------------------------------------------- Trước khi xe đi
  /// Gọi trước khi xe chạy một bước: gió đẩy ngang, đi lề lúc tắc đường,
  /// tự tấp vào lề, giữ xe đứng yên lúc đón trả khách / nghe điện thoại.
  void preMove(double dt) {
    final p = g.player;
    p.pull += windPull;
    p.distraction = talkingWhileDriving ? 1 : 0;
    // Xe máy luồn lên lề lúc tắc đường: lề gồ ghề, đi chậm.
    if (onShoulder) p.speedCap = min(p.speedCap ?? double.infinity, GameConfig.shoulderSpeed);
    // Bến phà: tự vào bến xếp hàng; lên phà rồi thì phà chở.
    _ferryApproach(dt);
    if (_ferryStep != _FerryStep.none) return;
    if (_holdT > 0) {
      _holdT -= dt;
      p
        ..throttle = false
        ..brake = true
        ..steer = 0;
      if (_holdT <= 0) {
        p.brake = false;
        _afterHold();
      }
      return;
    }
    final c = call;
    if (c != null && c.stage == CallStage.talking && !c.driving) {
      p
        ..stop()
        ..throttle = false
        ..steer = 0;
      return;
    }
    final k = pull;
    if (k == null) return;
    final target = switch (k) {
      _PullKind.pickUp => _pullHitch!.s - g.dir * 10,
      _PullKind.dropOff => _pullHitch!.overshot ? _stopSpot : _pullHitch!.dropS,
      _PullKind.call => _stopSpot,
      _PullKind.breath => g._nightCold.stopS,
    };
    if (g._pullInTo(target, dt)) _arrive(k);
  }

  /// Chỗ dừng gần nhất phía trước còn kịp phanh êm.
  late double _stopSpot = 0;

  void _arrive(_PullKind k) {
    pull = null;
    g.player
      ..stop()
      ..steer = 0;
    switch (k) {
      case _PullKind.pickUp:
        _holdT = 1.2;
      case _PullKind.dropOff:
        _holdT = 1.2;
      case _PullKind.call:
        final c = call;
        if (c != null) _startTalk(c, driving: false);
      case _PullKind.breath:
        g._nightCold.arrived();
    }
  }

  /// Đứng yên xong: khách lên xe / xuống xe.
  void _afterHold() {
    final h = _pullHitch;
    if (h == null) return;
    _pullHitch = null;
    if (h.state == _HitchState.waiting) {
      h.state = _HitchState.riding;
      riding = h;
      g.player.cargo += 1;
      final km = ((h.dropS - g.player.s) / GameConfig.unitsPerKm).round();
      g.onNotice(GameNotice('${h.name} lên xe: "Em cảm ơn! Cho em xuống cách đây chừng $km cây nhé."'));
      g.onSound(GameSound.gift);
    } else if (h.state == _HitchState.riding) {
      h
        ..state = _HitchState.done
        ..standS = g.player.s;
      riding = null;
      g.player.cargo = max(0, g.player.cargo - 1);
      final tip = max(1, h.tip - (h.overshot ? 1 : 0));
      g.lixi += tip;
      g._popAt(g.player.s, g.player.d + 20, '+$tip', const Color(0xffFFD166));
      g.onSound(GameSound.lixi);
      g.onNotice(GameNotice('${h.name}: "Cảm ơn nhiều nha, chúc năm mới an khang!" — biếu $tip lì xì', kind: NoticeKind.money));
    }
  }

  /// Xe máy đang chạy trên lề (chỉ lúc tắc đường cửa ngõ).
  bool get onShoulder =>
      g.spec.kind == VehicleKind.motorbike && shoulderOpen(g.player.s) && g.dir * g.player.d > GameConfig.roadHalfWidth - g.spec.width / 2 + 2;

  /// Lề phải mở cho xe máy luồn (đoạn tắc đường).
  bool shoulderOpen(double s) {
    final j = jam;
    return j != null && g.dir > 0 && g.spec.kind == VehicleKind.motorbike && s > j.from - 200 && s < j.head + 60;
  }

  // ----------------------------------------------------------- Mỗi khung
  void step(double dt) {
    if (g.player.scraping) damagePeach(18 * dt, 'Quệt lề mạnh quá, cành đào sau xe rụng mất mấy bông!');
    _stepBlinker(dt);
    _stepFog(dt);
    _stepWind(dt);
    _stepSand(dt);
    _stepJam(dt);
    _stepFerry(dt);
    _stepTruck(dt);
    _stepHitches();
    _stepCall(dt);
  }

  void _stepBlinker(double dt) {
    final p = g.player;
    if (pull != null || g._approach != null) {
      blinker = 1;
      _blinkHold = 0.6;
      return;
    }
    if (p.steer.abs() > 0.3 && p.speed > 20) {
      blinker = p.steer.sign.toInt();
      _blinkHold = 0.7;
    } else {
      _blinkHold -= dt;
      if (_blinkHold <= 0) blinker = 0;
    }
  }

  void _stepFog(double dt) {
    var level = 0.0;
    for (final b in fogBanks) {
      level = max(level, b.at(g.player.s));
    }
    fog = level;
    if (fog > 0.25) {
      g._notice('fog${fogBanks.first.from.round()}', 'Vào đoạn sương mù dày đặc — bật đèn, giảm tốc, nhìn kỹ xe phía trước!', NoticeKind.warning);
    }
    _fogDark = fog > 0.4 && !g.headlightsOn ? _fogDark + dt : 0;
    if (_fogDark > 4) {
      g._notice('fogLights${fogBanks.first.from.round()}', 'Sương mù mà không bật đèn — xe khác khó thấy mình lắm!', NoticeKind.warning);
    }
  }

  /// Tầm nhìn trong sương (đơn vị bản đồ); bật đèn thấy xa hơn một chút.
  double get visibility => (2600 + (330 - 2600) * fog) * (g.headlightsOn ? 1.12 : 1);

  void _stepWind(double dt) {
    final coast = g.setup.theme == MapTheme.coast && g.layout.kindAt(g.player.s) == RoadKind.highway && g.phase == GamePhase.driving;
    if (!coast) {
      gust = 0;
      windPull = 0;
      _gustT = -1;
      return;
    }
    if (_gustT < 0) {
      _gustIn -= dt;
      if (_gustIn > 0 || g.player.speed < 0.2 * GameConfig.normalSpeed) return;
      _gustT = 0;
      g.onSound(GameSound.windGust);
      if (!_gustTold) {
        _gustTold = true;
        g.onNotice(GameNotice(
          g.spec.kind == VehicleKind.motorbike ? 'Gió biển giật mạnh — giữ chặt tay lái, kẻo tạt sang làn bên!' : 'Gió biển giật mạnh — xe hơi lắc, giữ chặt vô-lăng!',
          kind: NoticeKind.warning,
        ));
      }
      return;
    }
    _gustT += dt;
    final k = _gustT / GameConfig.gustSeconds;
    if (k >= 1) {
      _gustT = -1;
      _gustIn = _between(6, 13);
      gust = 0;
      windPull = 0;
      return;
    }
    gust = sin(pi * k);
    final strength = switch (g.spec.kind) {
          VehicleKind.motorbike => 0.62,
          VehicleKind.car => 0.22,
          VehicleKind.bus => 0.4,
        } *
        g.spec.lateralSpeed;
    // Gió từ biển (phía d dương) thổi vào đất liền.
    windPull = -g.dir * strength * gust * (0.85 + 0.15 * sin(_gustT * 9));
    if (g.player.speed > 0.55 * GameConfig.normalSpeed) damagePeach(3.2 * gust * dt / GameConfig.gustSeconds * 2, null);
  }

  /// Ven biển: cát gió thổi tràn ra mặt đường từng doi.
  void _stepSand(double dt) {
    if (g.setup.theme != MapTheme.coast || g.layout.kindAt(g.player.s) != RoadKind.highway) return;
    _sandIn -= dt;
    if (_sandIn > 0) return;
    _sandIn = _between(3.5, 8);
    g._spawnSand();
  }

  // --------------------------------------------------------- Tắc đường
  /// Xe cuối hàng tắc (gồm cả xe vừa nối vào đuôi) và quãng trống từ đầu xe
  /// mình tới đó; null khi chưa tới gần hoặc đã ở trong hàng.
  TrafficVehicle? jamTail;
  double jamGap = 0;
  final Set<int> _jamLit = {};

  /// Quãng đường trước đuôi tắc giữ thẳng, khỏi khuất sau khúc cua.
  bool keepStraight(double a, double b) {
    final j = jam;
    return j != null && b > j.from - GameConfig.jamClearView && a < j.head;
  }

  void _stepJam(double dt) {
    final j = jam;
    if (j == null || g.dir < 0) return;
    final s = g.player.s;
    if (!j.filled && s > j.from - 2400 && s < j.from - 150) {
      j.filled = true;
      _fillJam(j);
    }
    _trackTail(j);
    final tail = jamTail;
    if (tail != null) {
      final v = g.player.speed;
      final moto = g.spec.kind == VehicleKind.motorbike;
      if (jamGap < GameConfig.jamWarnAhead) {
        g._notice(
          'jam${j.head.round()}',
          moto
              ? 'Phía trước tắc đường cửa ngõ ngày Tết! Xe máy đi sát lề phải luồn lên được — đi chậm thôi.'
              : 'Phía trước tắc đường cửa ngõ ngày Tết! Giảm tốc dần, CSGT đang phân luồng.',
          NoticeKind.warning,
        );
      }
      // Lao tới đuôi hàng xe mà chưa giảm tốc: báo nguy hiểm, kèm khoảng cách.
      if (v > 0.45 * GameConfig.normalSpeed && jamGap < _stopReach(v) + v * 0.5) {
        g._notice(
          'jamTail${j.head.round()}',
          moto ? 'Sắp đâm vào đuôi hàng xe tắc — phanh ngay, hoặc né sát lề phải!' : 'Sắp đâm vào đuôi hàng xe tắc — phanh ngay!',
          NoticeKind.danger,
        );
      }
    }
    // CSGT cho từng đợt xe đi qua.
    j.cycle += dt;
    if (j.cycle > (j.open ? 3.2 : 4.6)) {
      j
        ..open = !j.open
        ..cycle = 0;
    }
    // Qua khỏi chỗ phân luồng thì xe chạy lại bình thường.
    for (final v in g.traffic.vehicles) {
      if (j.ids.contains(v.id) && v.s > j.head + 40) {
        v.cruiseSpeed = max(v.cruiseSpeed, _between(0.45, 0.6) * GameConfig.normalSpeed);
        j.ids.remove(v.id);
      }
    }
  }

  /// Quãng phanh hết cỡ từ tốc độ [v] (cộng chút phản xạ).
  double _stopReach(double v) => v * v / (2 * g.spec.brakeDecel) + v * 0.6 + 40;

  /// Dò đuôi hàng xe đứng / bò chậm từ chỗ phân luồng lùi về phía mình; xe
  /// ô tô cuối hàng mỗi làn bật đèn khẩn cấp như ngoài đời.
  void _trackTail(_Jam j) {
    final s = g.player.s;
    final front = s + g.spec.length / 2;
    jamTail = null;
    if (!j.filled || s > j.head || s < j.from - 3200) {
      _unlight();
      return;
    }
    final queue = [
      for (final v in g.traffic.vehicles)
        if (!v.oncoming && !v.runaway && v.s > s && v.s < j.head + 60 && v.speed < 0.4 * GameConfig.normalSpeed) v,
    ]..sort((a, b) => b.s.compareTo(a.s));
    var edge = j.head + 60;
    final chain = <TrafficVehicle>[];
    for (final v in queue) {
      if (edge - v.s > GameConfig.jamChainGap) break;
      chain.add(v);
      edge = v.s;
    }
    if (chain.isEmpty) {
      _unlight();
      return;
    }
    final tail = chain.last;
    final gap = tail.s - tail.type.length / 2 - front;
    // Đã nhập vào hàng (đứng ngay sau đuôi) hay đang luồn lề thì thôi báo.
    if (!onShoulder && (gap > 18 || g.player.speed > 0.3 * GameConfig.normalSpeed)) {
      jamTail = tail;
      jamGap = max(0.0, gap);
    }
    final lit = <int>{};
    for (final lane in Lanes.sameDirection) {
      final rear = chain.reversed.where((v) => v.lane == lane && v.type != TrafficType.motorbike).take(1);
      for (final v in rear) {
        v.hazardLights = true;
        lit.add(v.id);
      }
    }
    for (final v in g.traffic.vehicles) {
      if (_jamLit.contains(v.id) && !lit.contains(v.id)) v.hazardLights = false;
    }
    _jamLit
      ..clear()
      ..addAll(lit);
  }

  void _unlight() {
    if (_jamLit.isEmpty) return;
    for (final v in g.traffic.vehicles) {
      if (_jamLit.contains(v.id)) v.hazardLights = false;
    }
    _jamLit.clear();
  }

  /// Biển "Tắc …m" trên HUD; nền đỏ khi đang quá nhanh, phanh không kịp.
  JamHud? get jamHud {
    final tail = jamTail;
    if (tail == null || jamGap > GameConfig.jamWarnAhead) return null;
    final v = g.player.speed;
    return JamHud(meters: VeQueGame._meters(jamGap), tooFast: v > 0.3 * GameConfig.normalSpeed && _stopReach(v) + v * 0.5 > jamGap);
  }

  void _fillJam(_Jam j) {
    for (final lane in Lanes.sameDirection) {
      var s = j.head - 10 - _r.nextDouble() * 30;
      while (s > j.from) {
        final r = _r.nextDouble();
        final type = r < 0.42
            ? TrafficType.motorbike
            : r < 0.72
                ? TrafficType.sedan
                : r < 0.82
                    ? TrafficType.pickup
                    : r < 0.92
                        ? TrafficType.bus
                        : TrafficType.truck;
        s -= type.length / 2;
        if (g.traffic.isLaneClear(lane, s, type.length / 2 + 6, oncoming: false)) {
          final v = g.traffic.addVehicle(type, lane, s, _between(0.16, 0.26) * GameConfig.normalSpeed);
          j.ids.add(v.id);
        }
        s -= type.length / 2 + 14 + _r.nextDouble() * 18;
      }
    }
  }

  /// Chỗ dừng của dòng xe lúc CSGT chưa cho đi.
  List<StopPoint> stops() {
    final j = jam;
    if (j == null || j.open || !j.filled) return const [];
    return [StopPoint(s: j.head, forward: true)];
  }

  // ------------------------------------------------- Xe tải mất phanh
  void _stepTruck(double dt) {
    if (g.dir > 0 && g.phase == GamePhase.driving && g._uTurn == null && truck == null && truckWarn <= 0) {
      for (final r in ramps) {
        final toRamp = r.s - g.player.s;
        if (r.rolled || toRamp > 2800 || toRamp < 1900) continue;
        r.rolled = true;
        if (_r.nextDouble() > GameConfig.runawayChance || g.player.speed < 0.35 * GameConfig.normalSpeed) continue;
        _truckRamp = r;
        truckWarn = GameConfig.runawayWarningSeconds;
        g.onSound(GameSound.truckHorn);
        g.onNotice(const GameNotice('Xe tải mất phanh lao tới phía sau! Tránh sang làn sát lề phải ngay!', kind: NoticeKind.danger));
      }
    }
    if (truckWarn > 0) {
      truckWarn -= dt;
      if (truckWarn <= 0) _spawnTruck();
      return;
    }
    final t = truck;
    final r = _truckRamp;
    if (t == null || r == null) return;
    if (!g.traffic.vehicles.contains(t)) {
      truck = null;
      return;
    }
    // Còi hơi liên hồi khi còn đang lao tới.
    if (t.speed > 40) {
      _hornIn -= dt;
      if (_hornIn <= 0 && (t.s - g.player.s).abs() < 1400) {
        _hornIn = 1.1;
        g.onSound(GameSound.truckHorn);
      }
      // Má phanh cháy khét: khói trắng sau bánh.
      final (x, y) = g.road.worldAt(t.s - t.type.length / 2, t.d);
      g._airFx.exhaust(g._random, x, y, 0, 0, strength: 1.4, diesel: true);
    }
    // Tới đường cứu nạn: tạt phải lao lên dải sỏi rồi dừng hẳn.
    if (t.s > r.s - 80) {
      final k = ((t.s - r.s) / GameConfig.rampLength).clamp(0.0, 1.0);
      final target = rampCenter(r, t.s);
      t
        ..lane = 1
        ..d += (target - t.d) * min(1.0, 5 * dt);
      if (k > 0) t.cruiseSpeed = max(0, t.cruiseSpeed - GameConfig.rampDecel * dt);
    }
  }

  /// Lệch ngang của tim đường cứu nạn ở quãng [s].
  double rampCenter(_Ramp r, double s) {
    final k = ((s - r.s) / GameConfig.rampLength).clamp(0.0, 1.0);
    return GameConfig.roadHalfWidth + 30 + 80 * k;
  }

  void _spawnTruck() {
    final s = g._camLeftS - 160;
    final speed = max(g.player.speed, GameConfig.normalSpeed) + GameConfig.runawayExtraSpeed * GameConfig.normalSpeed;
    // Xe làn trong tránh sang làn ngoài cho xe tải lao qua — chỉ khi làn
    // ngoài trống (không tạt vào xe mình, xe khác); xe khuất phía trước mà
    // không có chỗ tránh thì cho rẽ đi đường khác.
    final p = g.player;
    final gone = <TrafficVehicle>[];
    for (final v in g.traffic.vehicles) {
      if (v.oncoming || v.lane != 0 || v.targetLane != null) continue;
      final free = !g.traffic.vehicles.any((o) => !identical(o, v) && o.occupies(1) && (o.s - v.s).abs() < (o.type.length + v.type.length) / 2 + 40) &&
          !((p.d - Lanes.center(1)).abs() < (g.spec.width + v.type.width) / 2 + 4 && (p.s - v.s).abs() < (g.spec.length + v.type.length) / 2 + 120);
      final offscreen = v.s > g._camRightS + 200;
      if (!free) {
        if (offscreen) gone.add(v);
        continue;
      }
      if (offscreen) {
        v
          ..lane = 1
          ..d = Lanes.center(1);
      } else {
        v
          ..targetLane = 1
          ..blinker = 1
          ..blinkTimer = 0.3;
      }
    }
    gone.forEach(g.traffic.remove);
    truck = g.traffic.addVehicle(TrafficType.truck, 0, s, speed)..runaway = true;
    _hornIn = 0;
  }

  // ------------------------------------------------------ Khách đi nhờ
  /// Người vẫy xin đi nhờ phía trước còn kịp tấp vào.
  _Hitch? get hitchAhead {
    if (riding != null || pull != null || g.phase != GamePhase.driving || g.dir < 0 || g._approach != null) return null;
    final stopping = g.player.speed * g.player.speed / (2 * g._approachDecel);
    for (final h in hitches) {
      if (h.state != _HitchState.waiting) continue;
      final ahead = h.s - g.player.s;
      if (ahead > stopping + 20 && ahead < GameConfig.stallApproachReach) return h;
    }
    return null;
  }

  /// Khách đang chở sắp tới chỗ xuống (hoặc đã quá chỗ, xuống đâu cũng được).
  bool get canDropOff {
    final h = riding;
    if (h == null || pull != null || g.phase != GamePhase.driving || g.dir < 0) return false;
    if (h.overshot) return true;
    final stopping = g.player.speed * g.player.speed / (2 * g._approachDecel);
    final ahead = h.dropS - g.player.s;
    return ahead > stopping + 20 && ahead < GameConfig.stallApproachReach;
  }

  void pickUp() {
    final h = hitchAhead;
    if (h == null) return;
    _pullHitch = h;
    pull = _PullKind.pickUp;
    g.onNotice(GameNotice('Tấp vào cho ${h.name} đi nhờ — vặn Ga hoặc đánh lái mạnh để thôi'));
  }

  void dropOff() {
    final h = riding;
    if (!canDropOff || h == null) return;
    _pullHitch = h;
    pull = _PullKind.dropOff;
    _stopSpot = g.player.s + g.dir * (g.player.speed * g.player.speed / (2 * g._approachDecel) + 40);
  }

  /// Thôi tấp vào (vặn ga, đánh lái mạnh, bấm "Thôi").
  bool cancelPull() {
    final k = pull;
    // CSGT vẫy vào kiểm tra nồng độ cồn thì không thôi được.
    if (k == null || k == _PullKind.breath) return false;
    pull = null;
    if (k == _PullKind.call) {
      final c = call;
      if (c != null) _startTalk(c, driving: true);
    } else {
      _pullHitch = null;
    }
    return true;
  }

  void _stepHitches() {
    for (final h in hitches) {
      if (h.state == _HitchState.waiting && !h.greeted && h.s - g.player.s < 900 && h.s > g.player.s && g.dir > 0) {
        h.greeted = true;
        if (riding == null) g._speech.say('hitch${h.s.round()}', () => g.road.worldAt(h.s, h.side), '"Cho đi nhờ một đoạn với ơi!"', name: h.who, seconds: 4);
      }
    }
    final h = riding;
    if (h == null || h.overshot || pull != null) return;
    if (g.player.s > h.dropS + 350) {
      h.overshot = true;
      g.onNotice(GameNotice('${h.name}: "Ơ quá chỗ em rồi! Cho em xuống đây cũng được."', kind: NoticeKind.warning));
    }
  }

  // ------------------------------------------------------- Điện thoại
  void _stepCall(double dt) {
    final c = call;
    if (c == null) {
      if (_callAgainIn > 0) {
        _callAgainIn -= dt;
        if (_callAgainIn <= 0) _ring();
      } else if (_callAttempts == 0 && g.player.s >= _callAtS && g.phase == GamePhase.driving) {
        _ring();
      }
      return;
    }
    c.t += dt;
    switch (c.stage) {
      case CallStage.ringing:
        c.ringIn -= dt;
        if (c.ringIn <= 0) {
          c.ringIn = 2.4;
          g.onSound(GameSound.phoneRing);
        }
        if (c.t > GameConfig.callRingSeconds || g.phase != GamePhase.driving) _missed();
      case CallStage.pullingOver:
        if (g.phase != GamePhase.driving) _hangUp();
      case CallStage.talking:
        if (g.phase == GamePhase.incident || g.phase == GamePhase.finished) {
          _hangUp();
          return;
        }
        final i = (c.t / GameConfig.callLineSeconds).floor();
        if (i != c.line) {
          c.line = i;
          if (i >= c.lines.length) {
            _endTalk(c);
            return;
          }
          _report();
        }
    }
  }

  void _ring() {
    if (g.phase != GamePhase.driving) {
      _callAgainIn = 20;
      return;
    }
    _callAttempts++;
    call = _Call(_callAttempts)..ringIn = 0;
    _report();
  }

  void _missed() {
    call = null;
    g.onCall?.call(null);
    if (_callAttempts >= 3) {
      g.onNotice(const GameNotice('Mẹ nhắn tin: "Sao con không nghe máy? Cả nhà lo lắm, đến nơi gọi về ngay nhé!"'));
      return;
    }
    _callAgainIn = _between(40, 70);
    g.onNotice(GameNotice(_callAttempts == 1 ? 'Lỡ cuộc gọi của mẹ — lát nữa mẹ gọi lại.' : 'Lại lỡ máy rồi, mẹ sốt ruột lắm đấy!'));
  }

  /// Bắt máy luôn (vừa lái vừa nghe) hoặc tự tấp vào lề rồi nghe.
  void answer({required bool pullOver}) {
    final c = call;
    if (c == null || c.stage != CallStage.ringing) return;
    if (!pullOver || g.player.speed < GameConfig.stallStopSpeed) {
      if (pullOver) g.player.stop();
      _startTalk(c, driving: !pullOver);
      return;
    }
    g._approach = null;
    pull = _PullKind.call;
    _stopSpot = g.player.s + g.dir * (g.player.speed * g.player.speed / (2 * g._approachDecel) + 40);
    c.stage = CallStage.pullingOver;
    _report();
  }

  void decline() {
    if (call?.stage != CallStage.ringing) return;
    _missed();
  }

  void _startTalk(_Call c, {required bool driving}) {
    c
      ..stage = CallStage.talking
      ..driving = driving
      ..t = 0
      ..line = 0
      ..lines = _callLines(c, driving: driving);
    _report();
  }

  void _endTalk(_Call c) {
    call = null;
    g.onCall?.call(null);
    _callAttempts = 3;
    if (c.driving) {
      g.alert = min(100, g.alert + 4);
      g.onNotice(const GameNotice('Cúp máy. Vừa lái vừa nghe điện thoại nguy hiểm lắm, may mà không sao!'));
    } else {
      g.alert = min(100, g.alert + 10);
      g.clock.addPenalty(GameConfig.callStopMinutes);
      g.onNotice(GameNotice('Nghe giọng mẹ thấy ấm lòng hẳn · tỉnh táo +10 · ${GameConfig.callStopMinutes.round()} phút'));
    }
  }

  void _hangUp() {
    call = null;
    pull = pull == _PullKind.call ? null : pull;
    g.onCall?.call(null);
  }

  void _report() {
    final c = call;
    if (c == null) {
      g.onCall?.call(null);
      return;
    }
    final talking = c.stage == CallStage.talking && c.line < c.lines.length;
    g.onCall?.call(PhoneCallState(
      caller: c.caller,
      stage: c.stage,
      line: talking ? c.lines[c.line].$1 : null,
      mine: talking && c.lines[c.line].$2,
      driving: c.driving,
      attempt: c.attempt,
    ));
  }

  List<(String, bool)> _callLines(_Call c, {required bool driving}) {
    final mom = c.caller == 'Mẹ';
    final me = mom ? 'mẹ' : 'bố';
    final km = max(1, ((g.finishS - g.player.s) / GameConfig.unitsPerKm).round());
    final String context;
    if (g.nightLevel > 0.5) {
      context = 'Tối rồi đấy, bật đèn lên mà đi chậm thôi con.';
    } else if (g._rain > 0.3) {
      context = 'Ngoài đấy mưa à? Mặc áo mưa vào kẻo ướt lạnh ốm ra đấy.';
    } else if (g.alert < 45) {
      context = 'Nghe giọng mệt thế, buồn ngủ thì tấp vào uống cốc trà đá đã rồi đi.';
    } else if (g.spareMinutes < 20) {
      context = 'Không kịp giao thừa cũng không sao, an toàn là chính, nghe chưa?';
    } else if (peach >= 0) {
      context = 'Cành đào có còn nguyên không con? Mẹ để sẵn lọ cắm ở bàn thờ rồi.';
    } else if (g.spec.kind == VehicleKind.bus) {
      context = 'Xe khách đông không? Giữ ví với điện thoại cẩn thận nhé.';
    } else {
      context = const [
        'Nhà gói bánh chưng xong rồi, bố đang canh nồi bánh ngoài sân.',
        'Ông bà mong lắm, cứ hỏi mãi "thằng cả về chưa".',
        'Mẹ làm sẵn nồi thịt đông với vại dưa hành rồi, về là có ăn.',
      ][_r.nextInt(3)];
    }
    return [
      (
        c.attempt > 1
            ? (mom ? 'Alo! Sao mẹ gọi mãi không nghe máy thế con?' : 'Alo, bố đây. Mẹ gọi mãi không được, lo quá!')
            : (mom ? 'Alo, con đến đâu rồi?' : 'Alo, bố đây. Đến đâu rồi con?'),
        false,
      ),
      ('${driving ? 'Con đang lái xe' : 'Con tấp vào lề rồi'} $me ạ, còn chừng $km cây nữa là tới ${g.setup.toName}.', true),
      (context, false),
      (driving ? 'Vâng vâng, con biết rồi, con đang lái…' : 'Vâng, con nhớ rồi ạ.', true),
      (driving ? 'Thôi cúp máy đi, đang lái xe đừng có nghe điện thoại!' : 'Ừ, về đến nơi gọi cho $me nhé. Đi cẩn thận!', false),
    ];
  }

  // -------------------------------------------------------------- Cành đào
  void damagePeach(double amount, String? why) {
    if (peach < 0 || amount <= 0) return;
    final before = peach;
    peach = max(0, peach - amount);
    if (before > 0 && peach == 0) {
      g.onNotice(const GameNotice('Gãy cành đào rồi! Về nhà biết ăn nói sao với mẹ đây…', kind: NoticeKind.warning));
    } else if (before >= 60 && peach < 60) {
      g.onNotice(GameNotice(why ?? 'Cành đào buộc sau xe rụng mất mấy bông rồi!', kind: NoticeKind.warning));
    }
  }
}

extension on _Hitch {
  /// Đứng sát mép đường bên phải chiều về.
  double get side => GameConfig.roadHalfWidth + 22;
}
