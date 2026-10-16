part of 've_que_game.dart';

/// Chốt CSGT kiểm tra nồng độ cồn dựng tối 30 Tết trên quốc lộ. [s] là chỗ
/// xe dừng kiểm tra (lề phải chiều về quê); biển báo, hàng cọc tiêu và người
/// vẫy gậy phát sáng đặt lùi về phía trước chốt. Đoạn đường quanh chốt được
/// giữ thẳng nên vẽ theo một khung toạ độ là đủ.
class _BreathPost {
  _BreathPost(this.s);

  final double s;

  /// Mình đã qua chốt (đã kiểm tra, hoặc đi qua khi chưa dựng).
  bool done = false;

  double get signS => s - 950;
  double get sign2S => s - 430;
  double get waveS => s - 300;
  double get conesFrom => s - 650;
  double get conesTo => s - 110;
}

/// Các bước ở chốt: xe tự tấp vào lề, lượn vào bãi, thổi, ra đường.
enum _BreathStep { none, pulling, parking, testing, leaving }

/// Đêm 30 Tết và trời rét miền Bắc: nhiệt độ theo giờ / vĩ độ / địa hình,
/// sương muối, tay cóng (găng tay), máy nguội khó nổ sau khi dừng lâu, chén
/// rượu mừng xuân ở quán và chốt kiểm tra nồng độ cồn tối giao thừa.
class _NightCold {
  _NightCold(this.g);

  final VeQueGame g;
  late final Random _r = Random(g.setup.seed * 977 + 23);

  /// Từ giờ này (ngày 30 Tết) CSGT lập chốt đo nồng độ cồn.
  static const double _nightFrom = 18 * 60;

  /// Không phải tối nào cũng gặp chốt.
  static const double _postChance = 0.75;

  /// Dựng chốt khi còn cách chừng này (khuất tầm nhìn cả ở ghế lái).
  static const double _activateAhead = 4700;

  /// Món quán mời ngày 29, 30 Tết.
  static const StallItem toast = StallItem('Chén rượu mừng xuân', price: 0, alert: 6, minutes: 3, art: 'ruou');

  /// Mỗi quán mời nhiều nhất bấy nhiêu chén.
  static const int toastsPerStall = 2;

  static const int glovesLixi = 1;

  // --------------------------------------------------------------- Rét
  late final ColdClimate climate = ColdClimate.forStage(
    fromName: g.setup.fromName,
    toName: g.setup.toName,
    south: g.setup.south,
    theme: g.setup.theme,
    offset: (Random(g.setup.seed * 61 + 5).nextDouble() - 0.5) * 3,
  );

  /// Nhiệt độ ngoài trời lúc này (°C) và mức rét, sương muối đang hiện (đã
  /// làm mượt cho cảnh đổi dần).
  double celsius = 20;
  double chillShown = 0;
  double frostShown = 0;
  bool _ready = false;

  /// Đã mua găng tay len (xe máy).
  bool gloves = false;

  bool get _moto => g.spec.kind == VehicleKind.motorbike;
  bool get cold => g.fatigue && celsius <= ColdClimate.coldBelow;

  /// Hơi sương sáng sớm (4–9 giờ dày nhất).
  double get mistLevel {
    final h = (g.clock.minutes % 1440) / 60;
    if (h >= 4 && h <= 9.5) return 1;
    if (h > 9.5 && h < 11) return 1 - (h - 9.5) / 1.5 * 0.65;
    return 0.35;
  }

  /// Hệ số mau mệt khi rét (xe máy, nhất là lúc ướt sũng).
  double get alertFactor => g.fatigue ? ColdEffects.alertFactor(celsius, exposed: _moto, soaked: g.soaked) : 1;

  // ------------------------------------------------------- Máy nguội
  bool _resting = false;
  double _restFrom = 0;
  bool _restCold = false;
  int kicksLeft = 0;
  bool _throttleWas = false;
  double _catchIn = -1;

  /// Vừa dừng lâu ngoài trời rét: lên đường thì máy khó nổ (tầng Flutter
  /// chưa bật tiếng máy, chờ game báo [GameSound.engineStart]).
  bool get engineCold => _restCold && g.clock.minutes - _restFrom >= 5 && !g.setup.tutorial;

  // ------------------------------------------------------------ Hơi men
  final AlcoholLevel alcohol = AlcoholLevel();
  final Map<int, int> _toasts = {};

  // -------------------------------------------------------- Chốt đo cồn
  late final List<double> spots = _planSpots();
  _BreathPost? post;
  _BreathStep stage = _BreathStep.none;
  double _t = 0;
  BreathReading? _reading;
  String _place = '';

  /// Đèn sáng của chốt trong góc nhìn ghế lái (vị trí màn hình, bán kính,
  /// màu) — dựng lúc xếp cảnh, vẽ sau lớp tối.
  final List<(Offset, double, Color)> driverGlows = [];

  Future<void> onLoad() async {
    try {
      await g.images.load(Img.texFrost);
    } catch (_) {
      // Thiếu vân sương muối thì bỏ qua lớp sương muối.
    }
    await g.world.addAll([_FrostLayer(g), _BreathPostLayer(g), _ColdHaze(g), _BreathGlow(g)]);
    await g.add(_NightColdTicker(g));
  }

  /// Đoạn đường quanh chỗ có thể dựng chốt giữ thẳng (thấy chốt từ xa).
  bool keepStraight(double a, double b) => spots.any((s) => s + 500 > a && s - 1350 < b);

  /// Chỗ có thể dựng chốt trên các đoạn quốc lộ: chỉ ở quãng mà người đi
  /// chậm (~19 km/h) tới nơi đã là tối 30 Tết; tránh quán, ngã tư, trạm thu
  /// phí, chốt bắn tốc độ, điểm đón khách, bãi đinh, đoạn tắc, sương mù…
  List<double> _planSpots() {
    final setup = g.setup;
    if (!g.fatigue || setup.tutorial) return const [];
    final r = Random(setup.seed * 389 + 71);
    if (r.nextDouble() > _postChance) return const [];
    final start = setup.startClockMinutes;
    if (start >= TripClock.midnight) return const [];
    final out = <double>[];
    for (final z in g.layout.zones) {
      if (z.kind != RoadKind.highway || z.endS - z.startS < 4500) continue;
      var s = z.startS + 2200 + r.nextDouble() * 1500;
      while (s < z.endS - 1600 && s < g.finishS - 3500 && out.length < 4) {
        final km = (s - VeQueGame._startS) / GameConfig.unitsPerKm;
        final slowArrival = start + km / 19 * 60 + 45;
        if (slowArrival >= _nightFrom && _clear(s)) {
          out.add(s);
          s += (7 + r.nextDouble() * 5) * GameConfig.unitsPerKm;
        } else {
          s += 500;
        }
      }
    }
    return out;
  }

  bool _clear(double s) {
    final l = g.layout;
    final ev = g._events;
    return s > VeQueGame._startS + 3500 &&
        !l.nearFeature(s, margin: 1300) &&
        l.stallsBetween(s - 750, s + 650).where((t) => t.side > 0).isEmpty &&
        l.stallsBetween(s - 320, s + 260).isEmpty &&
        !l.busStops.any((b) => (b.s - s).abs() < 900) &&
        l.nailsBetween(s - 900, s + 300).isEmpty &&
        !ev.inRiver(s, margin: 2000) &&
        !ev.keepStraight(s - 1500, s + 500) &&
        !ev.ramps.any((x) => (x.s - s).abs() < 1800) &&
        !ev.hitches.any((h) => (h.s - s).abs() < 1200 || (h.dropS - s).abs() < 900) &&
        !ev.fogBanks.any((b) => s > b.from - 800 && s < b.to + 800);
  }

  bool get _nightNow {
    final m = g.clock.minutes;
    return m >= _nightFrom - 15 && m < TripClock.midnight;
  }

  // ---------------------------------------------------------- Mỗi khung
  /// Gọi mỗi khung hình (sau bước game): nhiệt độ, báo trời rét, theo dõi
  /// dừng xe lâu ngoài trời rét.
  void frame(double dt) {
    if (!g.fatigue) return;
    final span = max(1.0, g.finishS - VeQueGame._startS);
    celsius = climate.temperatureAt(
      minutes: g.clock.minutes,
      progress: (g.player.s - VeQueGame._startS) / span,
      rain: g._rain,
    );
    final chill = ColdEffects.chill(celsius);
    final frost = ColdEffects.frost(celsius, mountain: g.setup.theme == MapTheme.mountain);
    if (!_ready) {
      _ready = true;
      chillShown = chill;
      frostShown = frost;
    } else {
      final k = 1 - exp(-0.6 * dt);
      chillShown += (chill - chillShown) * k;
      frostShown += (frost - frostShown) * k;
    }
    _coldNotices();
    _trackRest();
    if (_catchIn > 0) {
      _catchIn -= dt;
      if (_catchIn <= 0) g.onSound(GameSound.engineStart);
    }
  }

  void _coldNotices() {
    if (g.phase != GamePhase.driving || g.time < 1.5) return;
    if (cold) {
      final label = ColdEffects.label(celsius);
      g._notice(
        'cold',
        !_moto
            ? 'Ngoài trời ${label.toLowerCase()} — kính dễ mờ hơi nước, bật sưởi, đi chậm thôi'
            : gloves
                ? '$label — may có găng tay len, kéo khoá áo lên mà đi!'
                : '$label, gió bấc buốt tay — ghé quán mua găng tay len!',
        NoticeKind.warning,
      );
    }
    if (frostShown > 0.35) {
      g._notice(
        'frost',
        g.setup.theme == MapTheme.mountain
            ? 'Sương muối phủ trắng ruộng đồi — sáng sớm mặt đường trơn, đi chậm!'
            : 'Sương muối lấm tấm trên ruộng — rét hại rồi, giữ ấm nhé!',
        NoticeKind.info,
      );
    }
  }

  /// Dừng hẳn (ghé quán, chờ cứu hộ, ở chốt…) ngoài trời rét thì máy nguội;
  /// lên đường lại: xe máy phải đạp nổ, ô tô đề một lúc.
  void _trackRest() {
    if (g.phase == GamePhase.resting) {
      if (!_resting) {
        _resting = true;
        _restFrom = g.clock.minutes;
        _restCold = cold;
      }
      return;
    }
    if (!_resting) return;
    _resting = false;
    final coldStart = g.phase == GamePhase.driving && engineCold;
    _restCold = false;
    if (!coldStart) return;
    if (_moto && !g.pushing) {
      kicksLeft = ColdEffects.kicksNeeded(celsius, _r.nextDouble());
      _throttleWas = g.player.throttle;
      g.onNotice(const GameNotice('Trời rét, máy nguội không nổ — bấm Ga vài lần để đạp nổ máy!', kind: NoticeKind.warning));
    } else {
      g.onSound(GameSound.crank);
      _catchIn = 0.9;
    }
  }

  /// Trước khi xe đi một bước (lúc lái): tay cóng, máy nguội chưa nổ.
  void preMove(double dt) {
    final p = g.player;
    p.numb = g.fatigue ? ColdEffects.numb(celsius, exposed: _moto, gloves: gloves) : 0;
    if (kicksLeft > 0) {
      if (g.pushing || g.fuel.empty) {
        kicksLeft = 0;
      } else {
        p.engineOff = true;
        if (p.throttle && !_throttleWas) _kick();
      }
    }
    _throttleWas = p.throttle;
  }

  /// Một lần bấm Ga lúc máy nguội: khục khặc rồi tắt, đủ lần thì nổ.
  void _kick() {
    kicksLeft--;
    final pose = g._pose;
    final len = g.spec.length;
    final ex = pose.x - pose.fx * len * 0.5 + pose.rx * g.spec.width * 0.32;
    final ey = pose.y - pose.fy * len * 0.5 + pose.ry * g.spec.width * 0.32;
    g._shake = max(g._shake, 0.12);
    g.onHaptic?.call(GameHaptic.light);
    if (kicksLeft > 0) {
      g.onSound(GameSound.sputter);
      g._airFx.exhaust(g._random, ex, ey, -pose.fx * 30, -pose.fy * 30, strength: 0.7);
      return;
    }
    g.onSound(GameSound.engineStart);
    for (var i = 0; i < 4; i++) {
      g._airFx.exhaust(g._random, ex, ey, -pose.fx * 40, -pose.fy * 40, strength: 1.4);
    }
    g.onNotice(const GameNotice('Nổ máy rồi! Đi chầm chậm một lúc cho máy ấm', kind: NoticeKind.info));
  }

  /// Sau các chuyện dọc đường (lúc lái): chốt đo nồng độ cồn, khói pô trắng
  /// xoá trong sương lạnh.
  void step(double dt) {
    if (!g.fatigue) return;
    _stepPost();
    _stepVapor(dt);
  }

  double _vaporT = 0;
  double _breathT = 0;

  void _stepVapor(double dt) {
    final k = chillShown;
    if (k < 0.15) return;
    final pose = g._pose;
    final len = g.spec.length, wid = g.spec.width;
    _vaporT -= dt;
    if (_vaporT <= 0 && !g.player.engineOff && !g.pushing) {
      // Khói pô gặp lạnh ngưng thành hơi trắng, dày và lâu tan.
      _vaporT = 0.09;
      final side = g.spec.kind == VehicleKind.bus ? -0.34 : 0.3;
      final ex = pose.x - pose.fx * len * 0.5 + pose.rx * wid * side;
      final ey = pose.y - pose.fy * len * 0.5 + pose.ry * wid * side;
      final v = g.player.speed;
      g._airFx.exhaust(g._random, ex, ey, pose.fx * v * 0.1 - pose.fx * 22, pose.fy * v * 0.1 - pose.fy * 22, strength: 0.45 + 0.6 * k);
    }
    // Người đi xe máy thở ra khói (thấy rõ lúc đứng / đi chậm).
    _breathT -= dt;
    if (_moto && _breathT <= 0 && g.player.speed < 0.6 * GameConfig.normalSpeed) {
      _breathT = 2.6 + _r.nextDouble();
      g._airFx.dust(g._random, pose.x + pose.fx * len * 0.12, pose.y + pose.fy * len * 0.12, count: 1, size: 7, color: const Color(0xffF2F5F8));
    }
  }

  // ------------------------------------------------------- Chốt đo cồn
  void _stepPost() {
    final p = g.player;
    if (post == null && g.dir > 0 && _nightNow) {
      for (final s in spots) {
        final ahead = s - p.s;
        if (ahead < _activateAhead - 900 || ahead > _activateAhead) continue;
        post = _BreathPost(s);
        break;
      }
    }
    final b = post;
    if (b == null || b.done) return;
    final ahead = b.s - p.s;
    if (stage == _BreathStep.none) {
      if (ahead < -80 || g.dir < 0) {
        b.done = ahead < -80;
        return;
      }
      if (ahead < 1700) {
        g._notice('breath${b.s.round()}', 'Chốt CSGT kiểm tra nồng độ cồn phía trước — mọi xe tấp vào lề phải dừng kiểm tra', NoticeKind.warning);
      }
      if (ahead < 950 && g.phase == GamePhase.driving && g._uTurn == null && !g._events.ferryBusy) {
        g._approach = null;
        if (g._events.pull != null) g._events.cancelPull();
        g._events.pull = _PullKind.breath;
        stage = _BreathStep.pulling;
        g.onSound(GameSound.whistle);
        g.onNotice(const GameNotice('Toét toét! CSGT vẫy gậy phát sáng — xe tự tấp vào lề, dừng kiểm tra nồng độ cồn', kind: NoticeKind.warning));
      }
    } else if (stage == _BreathStep.pulling && g._events.pull == null && !g._events.holding && g.phase == GamePhase.driving) {
      // Đang tấp vào thì bị việc khác chen ngang (nghe điện thoại…): tấp tiếp.
      g._events.pull = _PullKind.breath;
    }
  }

  /// Chỗ xe tự tấp vào dừng.
  double get stopS => post?.s ?? g.player.s;

  /// Đã dừng sát lề trước chốt: lượn vào bãi, CSGT tới cửa xe.
  void arrived() {
    final p = g.player;
    stage = _BreathStep.parking;
    _t = 0;
    _reading = null;
    _place = g._placeName();
    g.phase = GamePhase.resting;
    p
      ..stop()
      ..throttle = false
      ..brake = false
      ..steer = 0
      ..asleep = false;
    g._sleepLeft = 0;
    g._parkFrom = (p.s, p.d);
    g._parkTo = (p.s + g.dir * 45, g.dir * (GameConfig.roadHalfWidth + g.spec.width / 2 - 4));
    g.onPhaseChanged(g.phase);
  }

  /// Bước ở chốt lúc đang dừng (pha nghỉ); trả về false nếu không phải chuyện
  /// ở chốt.
  bool stepResting(double dt) {
    if (stage == _BreathStep.none || stage == _BreathStep.pulling) return false;
    final p = g.player;
    _t += dt;
    g._stepWorld(dt);
    switch (stage) {
      case _BreathStep.parking:
        final k = (_t / 1.1).clamp(0.0, 1.0);
        final (s, d, yaw) = g._parkPath(k);
        p
          ..s = s
          ..d = d;
        g._parkYaw = yaw;
        if (k >= 1) {
          g._parkYaw = 0;
          stage = _BreathStep.testing;
          _t = 0;
        }
      case _BreathStep.testing:
        break;
      case _BreathStep.leaving:
        final k = (_t / 1.0).clamp(0.0, 1.0);
        final (s, d, yaw) = g._parkPath(k);
        p
          ..s = s
          ..d = d
          ..speed = 30
          ..cruise = 30;
        g._parkYaw = yaw;
        if (k >= 1) {
          g._parkYaw = 0;
          stage = _BreathStep.none;
          post?.done = true;
          g.phase = GamePhase.driving;
          g.onPhaseChanged(g.phase);
          if (g.clock.isOver) g._end(StageEndReason.timeUp, delay: 0.4);
        }
      case _BreathStep.none:
      case _BreathStep.pulling:
        break;
    }
    return true;
  }

  /// Đang ở chốt (bảng thổi hiện lên), null khi không.
  BreathCheck? get check => stage == _BreathStep.parking || stage == _BreathStep.testing
      ? BreathCheck(place: _place, clock: g.clock.label, vehicle: g.spec.kind, cups: _toasts.values.fold(0, (a, b) => a + b))
      : null;

  /// Thổi xong: máy đo ra số.
  BreathReading blow() {
    final value = alcohol.readingAt(g.clock.minutes);
    final tier = AlcoholTier.of(value);
    return _reading = BreathReading(value: value, tier: tier, enoughLixi: g.lixi >= tier.fineLixi);
  }

  /// Xong kiểm tra: âm tính thì đi tiếp ngay; dương tính thì nộp phạt, ngồi
  /// chờ hết hơi men rồi mới được đi.
  void finish() {
    if (stage != _BreathStep.testing && stage != _BreathStep.parking) return;
    final r = _reading ?? blow();
    if (r.positive) {
      final fine = min(g.lixi, r.tier.fineLixi);
      g.lixi -= fine;
      if (fine > 0) g._popAt(g.player.s, g.player.d, '−$fine', const Color(0xffFF8A80));
      g.onSound(GameSound.toll);
      g.onNotice(GameNotice(
        'Nồng độ cồn ${r.tier.title.toLowerCase()} (${r.display} mg/L): ${fine > 0 ? '−$fine lì xì' : 'không đủ lì xì'} · ngồi chờ tỉnh rượu ${r.minutes.round()} phút',
        kind: NoticeKind.warning,
      ));
    } else {
      g.onNotice(const GameNotice('CSGT: "Chúc anh về quê ăn Tết an toàn!"', kind: NoticeKind.money));
    }
    g.clock.addPenalty(r.minutes);
    stage = _BreathStep.leaving;
    _t = 0;
    final p = g.player;
    g._parkFrom = (p.s, p.d);
    g._parkTo = (p.s + g.dir * 90, g.dir * min(Lanes.center(1), p.maxOffset));
  }

  // ---------------------------------------------------------- Ở quán
  /// Quán đang ngồi có mời chén rượu mừng xuân không (ngày 29, 30 Tết, quán
  /// ăn uống) và còn mời được mấy chén.
  int get toastsLeft {
    final stall = g._restStall;
    final day = g.clock.day;
    if (!g._served || stall == null || !stall.kind.food || day < 29 || day > 30) return 0;
    return max(0, toastsPerStall - (_toasts[stall.seed] ?? 0));
  }

  /// Chuyến đi có gặp rét không (để quán chào bán găng tay).
  bool get glovesOffer {
    if (!g.fatigue || !_moto || gloves || !g._served) return false;
    final (lo, _) = ColdClimate.dailyRange(max(climate.fromLat, climate.toLat));
    return lo + climate.terrain + climate.offset <= ColdClimate.coldBelow;
  }

  /// Vừa gọi món ở quán (gọi từ [VeQueGame.order]).
  void ordered(StallItem item) {
    if (item.art != toast.art) return;
    final stall = g._restStall;
    if (stall != null) _toasts[stall.seed] = (_toasts[stall.seed] ?? 0) + 1;
    alcohol.drink(g.clock.minutes);
    final hours = alcohol.minutesToSober(g.clock.minutes) / 60;
    g.onNotice(GameNotice(
      'Chén rượu ấm bụng — nhưng đã uống rượu bia thì không lái xe! Hơi men còn chừng ${hours.toStringAsFixed(1).replaceAll('.', ',')} tiếng',
      kind: NoticeKind.warning,
    ));
  }

  void buyGloves() {
    if (!glovesOffer) return;
    if (g.lixi < glovesLixi) {
      g.onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return;
    }
    g.lixi -= glovesLixi;
    gloves = true;
    g.clock.addPenalty(1);
    g.onSound(GameSound.gift);
    g.onNotice(const GameNotice('Đeo đôi găng tay len vào — hết cóng tay, lái chắc tay hẳn!', kind: NoticeKind.money));
  }

  /// Chuyện ở quán về rét, rượu, chốt đo cồn tối nay.
  List<String> chatter(Stall stall, String owner) {
    final lines = <String>[];
    final m = g.clock.minutes;
    if (stall.kind.food && g.clock.day >= 29 && g.clock.day <= 30) {
      lines.add('$owner: Tết nhất làm chén rượu mừng xuân cho ấm bụng không? Mà còn lái xe thì thôi nhé!');
    }
    if (m >= _nightFrom - 120 && m < TripClock.midnight && spots.any((s) => s > g.player.s)) {
      lines.add('Khách bàn bên: Tối nay CSGT lập chốt đo nồng độ cồn trên quốc lộ đấy, đã uống thì đừng cầm lái!');
    }
    if (cold && _moto && !gloves) {
      lines.add('$owner: Rét thế này mà không đeo găng tay à? Tay cóng là cầm lái không vững đâu.');
    } else if (cold) {
      lines.add('$owner: Rét quá, ngồi xích vào bếp than cho ấm rồi hẵng đi.');
    }
    return lines;
  }

  // ------------------------------------------------------------ HUD
  NightColdHud? get hud {
    if (!g.fatigue) return null;
    final m = g.clock.minutes;
    final a = alcohol.readingAt(m);
    final isCold = cold;
    if (!isCold && kicksLeft <= 0 && a <= 0) return null;
    return NightColdHud(
      celsius: isCold ? celsius.round() : null,
      severe: ColdEffects.severe(celsius),
      numb: isCold && g.player.numb > 0.01,
      kicksLeft: kicksLeft > 0 ? kicksLeft : null,
      alcohol: a > 0 ? (a * 100).round() : null,
      soberMinutes: a > 0 ? (alcohol.minutesToSober(m) / 10).ceil() * 10 : null,
    );
  }

  // ---------------------------------------------------------- Đèn đêm
  /// Đèn chiếu dã chiến của chốt soi sáng bãi kiểm tra.
  void nightLights(NightOverlay night) {
    final b = post;
    if (b == null || night.level <= 0.01) return;
    final (x, y) = g.road.worldAt(b.s + 30, GameConfig.roadHalfWidth + 30);
    night.lights.add(NightLight.round(Offset(x, y), 330, 0.95));
    final (wx, wy) = g.road.worldAt(b.waveS, GameConfig.roadHalfWidth - 14);
    night.lights.add(NightLight.round(Offset(wx, wy), 80, 0.6));
  }

  // ----------------------------------------------------- Sương muối
  Paint? _frostPaint;

  static Offset _point(RoadSample p, double d) => Offset(p.x - sin(p.heading) * d, p.y + cos(p.heading) * d);

  /// Phủ sương muối lên ruộng, bờ cỏ, rừng (không phủ mặt đường, phố xá,
  /// cát biển) từ [from] tới [to] qua [sink] — dùng chung cho bản đồ nhìn
  /// từ trên và góc nhìn ghế lái ([reach]: phủ xa tới đâu hai bên đường).
  void paintFrost(GroundSink sink, double from, double to, double alpha, {double reach = 760}) {
    if (alpha < 0.02 || !g.images.containsKey(Img.texFrost)) return;
    final paint = _frostPaint ??= g._paints.texture(Img.texFrost, 210);
    final a0 = min(from, to), b0 = max(from, to);
    const half = GameConfig.roadHalfWidth;
    final strong = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
    for (final zone in g.layout.zones) {
      final a = max(a0, zone.startS), b = min(b0, zone.endS);
      if (b <= a || zone.kind == RoadKind.city) continue;
      final samples = g.road.samplesBetween(a, b).toList(growable: false);
      if (samples.length < 2) continue;
      void band(double d1, double d2, [double k = 1]) {
        paint.color = strong.withValues(alpha: strong.a * k);
        sink.band([for (final p in samples) _point(p, d1)], [for (final p in samples) _point(p, d2)], paint);
      }

      if (zone.kind == RoadKind.expressway) {
        band(half + 32, reach);
        band(-reach, -half - 32);
        continue;
      }
      switch (g.setup.theme) {
        case MapTheme.mountain:
          // Vách taluy, rừng trên núi trắng sương; vực sâu phía kia ấm hơn.
          band(-reach, -half - 15);
          band(half + 64, max(reach, 1200), 0.55);
        case MapTheme.coast:
          band(-reach, -half - 36);
        case MapTheme.mekong:
          break;
        case MapTheme.delta:
        case MapTheme.auto:
          band(half + 26, reach);
          band(-reach, -half - 26);
      }
    }
  }
}

/// Đang dừng ở chốt kiểm tra nồng độ cồn (cho bảng thổi).
class BreathCheck {
  const BreathCheck({required this.place, required this.clock, required this.vehicle, required this.cups});

  /// Nơi kiểm tra (ghi biên bản), giờ lúc kiểm tra.
  final String place;
  final String clock;
  final VehicleKind vehicle;

  /// Đã uống mấy chén rượu trong chuyến (để CSGT nói cho đúng).
  final int cups;
}

/// Đêm 30 Tết, trời rét — tầng Flutter gọi vào (bảng thổi nồng độ cồn, quán).
extension TetNightGame on VeQueGame {
  /// Đang dừng ở chốt kiểm tra nồng độ cồn (null nếu không).
  BreathCheck? get breathCheck => _nightCold.check;

  /// Thổi đủ hơi: máy đo ra số.
  BreathReading blowBreath() => _nightCold.blow();

  /// Xong kiểm tra (nộp phạt nếu có), lên đường.
  void finishBreathTest() => _nightCold.finish();

  /// Vừa dừng lâu ngoài trời rét: chờ đạp / đề nổ máy rồi mới bật tiếng máy.
  bool get engineCold => _nightCold.engineCold;

  /// Quán đang ngồi còn mời mấy chén rượu mừng xuân (0 = không mời) — gọi
  /// [order] với [toastItem] để uống.
  int get toastsLeft => _nightCold.toastsLeft;
  StallItem get toastItem => _NightCold.toast;

  /// Quán có bán găng tay len (xe máy, chặng có rét, chưa có găng).
  bool get glovesOffer => _nightCold.glovesOffer;
  void buyGloves() => _nightCold.buyGloves();

  /// Chỗ có thể dựng chốt đo nồng độ cồn (để thử, chụp ảnh).
  List<double> get breathSpots => _nightCold.spots;

  /// Nhiệt độ ngoài trời lúc này (°C).
  double get celsius => _nightCold.celsius;

  /// Cho uống ngay một chén rượu (để thử chốt đo nồng độ cồn).
  void toastNow() => _nightCold.alcohol.drink(clock.minutes);
}

/// Gọi bước mỗi khung hình của phần rét / chốt đo cồn (sau bước game).
class _NightColdTicker extends Component {
  _NightColdTicker(this.game);

  final VeQueGame game;

  @override
  void update(double dt) => game._nightCold.frame(min(dt, 1 / 30));
}

// ================================================================ Bản đồ
/// Sương muối trên ruộng, bờ cỏ (nhìn từ trên): vẽ ngay sau mặt đất, dưới
/// cây cối nhà cửa.
class _FrostLayer extends Component {
  _FrostLayer(this.game) : super(priority: 0);

  final VeQueGame game;

  @override
  void render(Canvas canvas) {
    if (game._driverShown) return;
    final nc = game._nightCold;
    nc.paintFrost(FlatGroundSink(canvas), game._camLeftS - 700, game._camRightS + 700, nc.frostShown);
  }
}

/// Trời rét: hơi lạnh xanh xám phủ cảnh, sáng sớm thêm làn sương mờ dần ra xa.
class _ColdHaze extends Component {
  _ColdHaze(this.game) : super(priority: 13);

  final VeQueGame game;

  @override
  void render(Canvas canvas) {
    final nc = game._nightCold;
    final k = nc.chillShown;
    if (k < 0.02 || game._driverShown) return;
    final w = game._visibleWidth, h = game._visibleHeight;
    final c = cos(game._camAngle).abs(), sn = sin(game._camAngle).abs();
    final view = Rect.fromCenter(center: Offset(game._camX, game._camY), width: w * c + h * sn, height: w * sn + h * c).inflate(80);
    final night = game.nightLevel;
    final tone = Color.lerp(const Color(0xffB4C6DA), const Color(0xff4E6178), night)!;
    // Trời rét: màu cảnh nhạt đi, phủ hơi lạnh xanh xám.
    canvas.drawRect(view, Paint()
      ..color = const Color(0xff808080).withValues(alpha: 0.3 * k)
      ..blendMode = BlendMode.saturation);
    canvas.drawRect(view, Paint()..color = tone.withValues(alpha: (0.08 + 0.14 * k) * (1 - 0.5 * night)));
    final mist = k * nc.mistLevel * (1 - 0.6 * night);
    if (mist < 0.02) return;
    final (x, y) = game.road.worldAt(game.player.s + game.dir * 80, game.player.d);
    final center = Offset(x, y);
    final r = max(view.width, view.height) * 0.62;
    canvas.drawRect(
      view,
      Paint()
        ..shader = Gradient.radial(center, r, [
          tone.withValues(alpha: 0),
          tone.withValues(alpha: 0.16 * mist),
          tone.withValues(alpha: 0.42 * mist),
        ], const [
          0.22,
          0.62,
          1,
        ]),
    );
  }
}

/// Khung toạ độ của chốt: x dọc chiều về quê, y sang phải (lề có chốt).
void _postFrame(Canvas canvas, VeQueGame game, _BreathPost b) {
  final p = game.road.at(b.s);
  final (x, y) = game.road.worldAt(b.s, 0);
  canvas
    ..translate(x, y)
    ..rotate(p.heading);
}

/// Người CSGT vẫy gậy phát sáng: chỗ đứng và góc xoay (vung gậy theo nhịp).
(Offset, double) _waver(VeQueGame game, _BreathPost b) =>
    (Offset(b.waveS - b.s, GameConfig.roadHalfWidth - 14), -pi / 2 - 0.55 + sin(game._time * 5.5) * 0.4);

/// Chốt kiểm tra nồng độ cồn nhìn từ trên: biển báo, hàng cọc tiêu, bãi
/// đất, đèn chiếu dã chiến, bàn làm việc, xe máy CSGT, một xe đang bị kiểm
/// tra; CSGT vẫy gậy ở mép đường, CSGT cầm máy đo tới cửa xe mình.
class _BreathPostLayer extends Component {
  _BreathPostLayer(this.game) : super(priority: 5);

  final VeQueGame game;
  final RoadSigns _signs = RoadSigns();

  static const double _half = GameConfig.roadHalfWidth;
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _shadow = Paint()
    ..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn)
    ..filterQuality = FilterQuality.low;
  static final Paint _board = Paint()..color = const Color(0xff1F4E9C);
  static final Paint _boardHead = Paint()..color = const Color(0xffC62828);
  static final Paint _boardShadow = Paint()..color = const Color(0x40000000);
  static final Paint _leg = Paint()
    ..color = const Color(0xff4A4E54)
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;
  static final Paint _lamp = Paint()..color = const Color(0xffFFF6DC);
  static final Paint _lampBox = Paint()..color = const Color(0xff2C2F34);
  static final Paint _tentWhite = Paint()..color = const Color(0xffF2F4F6);

  @override
  void render(Canvas canvas) {
    final b = game._nightCold.post;
    if (b == null || game._driverShown) return;
    final from = game._camLeftS - 400, to = game._camRightS + 400;
    if (b.s + 450 < from || b.signS - 120 > to) return;
    final angle = game.road.at(b.s).heading;
    canvas.save();
    _postFrame(canvas, game, b);
    for (final s in [b.signS, b.sign2S]) {
      _sign(canvas, Offset(s - b.s, _half + 30), angle);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-170, _half + 2, 330, _half + 96), const Radius.circular(12)), game._paints.laterite);
    for (var x = b.conesFrom - b.s; x <= b.conesTo - b.s; x += 48) {
      _sprite(canvas, Img.imgTrafficCone, Offset(x, _half - 5), 15, 15, 0, angle);
    }
    for (var x = 340.0; x <= 440; x += 50) {
      _sprite(canvas, Img.imgTrafficCone, Offset(x, _half - 5), 15, 15, 0, angle);
    }
    // Bàn làm việc dưới lều bạt, cán bộ ngồi ghi biên bản; đèn chiếu dã chiến.
    _sprite(canvas, Img.imgPoliceTable, const Offset(-95, _half + 60), 46, 26, 0, angle);
    _sprite(canvas, Img.imgPoliceOfficer, const Offset(-92, _half + 78), 30, 30, -pi / 2, angle);
    _tent(canvas, const Rect.fromLTRB(-128, _half + 44, -60, _half + 92), angle);
    _flood(canvas, const Offset(-22, _half + 70), angle);
    // Xe máy CSGT dựng, một ô tô đang bị kiểm tra, chủ xe đứng thổi.
    _sprite(canvas, Img.imgScooterPoliceParked, const Offset(268, _half + 62), 26, 61, -pi / 2 + 0.25, angle);
    _sprite(canvas, Img.imgScooterPoliceParked, const Offset(300, _half + 66), 26, 61, -pi / 2 + 0.4, angle);
    final car = Img.sedansAi[(b.s.round() ~/ 7) % Img.sedansAi.length];
    _sprite(canvas, car, const Offset(185, _half + 28), TrafficType.sedan.width, TrafficType.sedan.length, 0, angle);
    _sprite(canvas, Img.people[(b.s.round() ~/ 11) % Img.people.length], const Offset(168, _half + 70), 24, 24, -pi / 2, angle);
    _sprite(canvas, Img.imgPoliceOfficerRadar, const Offset(196, _half + 82), 32, 32, pi * 0.85, angle);
    // CSGT vẫy gậy ở mép đường.
    final (at, rot) = _waver(game, b);
    _sprite(canvas, Img.imgPoliceOfficerWave, at, 46, 46, rot, angle);
    canvas.restore();
    _breathOfficer(canvas, b, angle);
  }

  /// CSGT cầm máy đo: đứng chờ trên bãi, mình tấp vào thì bước tới cửa xe.
  void _breathOfficer(Canvas canvas, _BreathPost b, double angle) {
    final nc = game._nightCold;
    final atCar = nc.stage == _BreathStep.testing || nc.stage == _BreathStep.parking;
    final k = nc.stage == _BreathStep.parking ? (nc._t / 1.1).clamp(0.0, 1.0) : (atCar ? 1.0 : 0.0);
    final p = game.player;
    final homeS = b.s + 60, homeD = _half + 46;
    final carS = p.s + game.dir * game.spec.length * 0.12, carD = p.d - game.dir * (game.spec.width / 2 + 13);
    final s = homeS + (carS - homeS) * k, d = homeD + (carD - homeD) * k;
    final (x, y) = game.road.worldAt(s, d);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    _sprite(canvas, Img.imgPoliceOfficerRadar, Offset.zero, 32, 32, k > 0.5 ? pi / 2 : -pi / 2, angle);
    canvas.restore();
  }

  /// Biển đứng "KIỂM TRA NỒNG ĐỘ CỒN" bên lề (bảng xanh, đầu đỏ, chữ vàng).
  void _sign(Canvas canvas, Offset at, double angle) {
    final rect = Rect.fromCenter(center: at, width: 62, height: 30);
    canvas.drawRect(rect.shift(toLocal(sunShadow * 1.4, angle)), _boardShadow);
    canvas.drawRect(rect, _board);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 8), _boardHead);
    final head = _signs.label('CSGT', 5.5, const Color(0xffFFFFFF));
    head.paint(canvas, Offset(rect.center.dx - head.width / 2, rect.top + 4 - head.height / 2));
    final l1 = _signs.label('KIỂM TRA', 6.5, const Color(0xffFFE046));
    final l2 = _signs.label('NỒNG ĐỘ CỒN', 6.5, const Color(0xffFFE046));
    l1.paint(canvas, Offset(rect.center.dx - l1.width / 2, rect.top + 13 - l1.height / 2));
    l2.paint(canvas, Offset(rect.center.dx - l2.width / 2, rect.top + 22.5 - l2.height / 2));
  }

  /// Đèn chiếu dã chiến nhìn từ trên: chân ba càng, thanh ngang hai pha
  /// LED chĩa về phía bãi kiểm tra.
  void _flood(Canvas canvas, Offset c, double angle) {
    for (var k = 0; k < 3; k++) {
      final a = k * 2 * pi / 3 + pi / 2;
      canvas.drawLine(c, c + Offset(cos(a), sin(a)) * 18, _leg);
    }
    final bar = Rect.fromCenter(center: c.translate(0, -3), width: 40, height: 6);
    canvas.drawRect(bar.shift(toLocal(sunShadow * 2.2, angle)), _boardShadow);
    canvas.drawRect(bar, _lampBox);
    for (final dx in [-11.0, 11.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(dx, -6), width: 16, height: 8), const Radius.circular(1.5)), _lampBox);
      canvas.drawRect(Rect.fromCenter(center: c.translate(dx, -9), width: 13, height: 2.2), _lamp);
    }
  }

  /// Lều bạt sọc xanh trắng che bàn làm việc của tổ kiểm tra.
  void _tent(Canvas canvas, Rect rect, double angle) {
    canvas.drawRect(rect.shift(toLocal(sunShadow * 1.8, angle)), _boardShadow);
    canvas.drawRect(rect, _tentWhite);
    for (var x = rect.left; x < rect.right; x += 17) {
      canvas.drawRect(Rect.fromLTWH(x, rect.top, 8.5, rect.height), _board);
    }
    canvas.drawRect(
      rect,
      Paint()..shader = Gradient.linear(rect.topCenter, rect.bottomCenter, const [Color(0x30FFFFFF), Color(0x00000000), Color(0x40000000)], const [0, 0.45, 1]),
    );
  }

  void _sprite(Canvas canvas, String path, Offset at, double w, double h, double rotation, double layerAngle) {
    if (!game.images.containsKey(path)) return;
    final img = game.images.fromCache(path);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotation + pi / 2);
    final dst = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawImageRect(img, src, dst.shift(toLocal(sunShadow * 0.35, layerAngle + rotation + pi / 2)), _shadow);
    canvas.drawImageRect(img, src, dst, _image);
    canvas.restore();
  }

  @override
  void onRemove() {
    _signs.dispose();
    super.onRemove();
  }
}

/// Ánh đèn của chốt trên lớp tối: gậy chỉ huy phát sáng đỏ, đèn xanh đỏ
/// nhấp nháy trên xe máy CSGT, hai đèn vàng trên biển, quầng đèn chiếu.
class _BreathGlow extends Component {
  _BreathGlow(this.game) : super(priority: 21);

  final VeQueGame game;

  static const double _half = GameConfig.roadHalfWidth;
  static final Paint _glow = Paint()..blendMode = BlendMode.plus;
  static final Paint _stick = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  void _dot(Canvas canvas, Offset c, double r, Color color, double alpha) {
    if (alpha <= 0.01) return;
    _glow.shader = Gradient.radial(c, r, [color.withValues(alpha: alpha), color.withValues(alpha: 0)]);
    canvas.drawCircle(c, r, _glow);
  }

  @override
  void render(Canvas canvas) {
    final b = game._nightCold.post;
    if (b == null || game._driverShown) return;
    final from = game._camLeftS - 400, to = game._camRightS + 400;
    if (b.s + 450 < from || b.signS - 120 > to) return;
    final dark = game.darkness;
    final t = game._time;
    canvas.save();
    _postFrame(canvas, game, b);
    // Quầng đèn chiếu dã chiến trên bãi.
    _dot(canvas, const Offset(10, _half + 50), 170, const Color(0xffFFF3D6), 0.18 * dark);
    _dot(canvas, const Offset(-11, _half + 61), 24, const Color(0xffFFFFFF), 0.75 * dark);
    _dot(canvas, const Offset(-33, _half + 61), 24, const Color(0xffFFFFFF), 0.75 * dark);
    // Đèn xanh đỏ nhấp nháy trên hai xe máy CSGT.
    final redOn = (t * 5).floor().isEven;
    for (final at in const [Offset(254, _half + 58), Offset(284, _half + 60)]) {
      _dot(canvas, at, redOn ? 26 : 16, const Color(0xffFF3B30), (redOn ? 0.75 : 0.35) * (0.35 + 0.65 * dark));
      _dot(canvas, at + const Offset(0, 8), redOn ? 16 : 26, const Color(0xff2F6BFF), (redOn ? 0.35 : 0.75) * (0.35 + 0.65 * dark));
    }
    // Hai đèn vàng nhấp nháy trên mỗi biển.
    final amber = (t * 2.2).floor().isEven ? 1.0 : 0.25;
    for (final s in [b.signS, b.sign2S]) {
      for (final dx in [-28.0, 28.0]) {
        _dot(canvas, Offset(s - b.s + dx, _half + 15), 14, const Color(0xffFFB020), amber * (0.4 + 0.5 * dark));
      }
    }
    // Gậy chỉ huy phát sáng trên tay người vẫy.
    final (at, rot) = _waver(game, b);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rot + pi / 2);
    const k = 46 / 64;
    const a = Offset(9 * k, -3 * k), tip = Offset(33 * k, -27 * k);
    final pulse = 0.75 + 0.25 * sin(t * 12);
    _stick
      ..color = const Color(0xffFF4A2E).withValues(alpha: (0.45 + 0.5 * dark) * pulse)
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawLine(a, tip, _stick);
    _stick
      ..color = const Color(0xffFFB09A).withValues(alpha: (0.3 + 0.6 * dark) * pulse)
      ..strokeWidth = 2.6
      ..maskFilter = null;
    canvas.drawLine(a, tip, _stick);
    canvas.restore();
    canvas.restore();
  }
}

// =========================================================== Ghế lái
extension _TetNightDriver on _DriverView {
  static const double _h = GameConfig.roadHalfWidth;

  /// Sương muối trên ruộng hai bên đường (phối cảnh).
  void _coldGround(PerspectiveGroundSink ground) {
    final nc = game._nightCold;
    if (nc.frostShown < 0.02) return;
    final camS = game.player.s;
    nc.paintFrost(ground, camS - game.dir * 400, camS + game.dir * cam.far, nc.frostShown * 0.9, reach: 2400);
  }

  /// Ảnh đứng [key] tại (s, d) kèm việc vẽ thêm sau ảnh (đèn sáng…).
  void _propAfter(List<_Drawn> items, DriverArt a, String key, double s, double d,
      {required double fallbackH, Color fallback = const Color(0xff7C6A55), void Function(Canvas c, Rect rect, double fade)? after}) {
    final art = a.prop(key);
    final h = (art?.heightM ?? fallbackH) * _DriverView._u;
    final w = art == null ? h * 0.45 : h * art.aspect;
    final o = _at(s, d);
    _board(items, o.dx, o.dy, w, h, art?.image, fallback: fallback, after: after);
  }

  /// Chốt kiểm tra nồng độ cồn dựng đứng: biển, cọc tiêu, người vẫy gậy
  /// phát sáng, đèn chiếu, lều, CSGT cầm máy đo, xe đang bị kiểm tra.
  void _tetNightProps(List<_Drawn> items, DriverArt a, double camS) {
    final nc = game._nightCold;
    nc.driverGlows.clear();
    final b = nc.post;
    if (b == null) return;
    final dir = game.dir;
    bool inView(double s) => (s - camS) * dir > -300 && (s - camS) * dir < cam.far;
    if (!inView(b.signS) && !inView(b.s) && !inView(b.s + 300)) return;
    final dark = game.darkness;
    final t = game._time;
    final amber = (t * 2.2).floor().isEven ? 1.0 : 0.25;
    for (final s in [b.signS, b.sign2S]) {
      if (!inView(s)) continue;
      _propAfter(items, a, 'police_sign_alcohol', s, _h + 36, fallbackH: 1.56, fallback: const Color(0xff1F4E9C), after: (c, rect, fade) {
        for (final u in const [0.09, 0.91]) {
          nc.driverGlows.add((Offset(rect.left + rect.width * u, rect.top + rect.height * 0.05), rect.width * 0.22, const Color(0xffFFB020).withValues(alpha: amber * (0.25 + 0.55 * dark) * fade)));
        }
      });
    }
    for (var s = b.conesFrom; s <= b.conesTo; s += 50) {
      if (inView(s)) _prop(items, a, 'traffic_cone', s, _h + 2, fallbackH: 0.7, fallback: const Color(0xffF26B1D));
    }
    if (inView(b.waveS)) {
      final pulse = 0.75 + 0.25 * sin(t * 12);
      _propAfter(items, a, 'police_officer_baton', b.waveS, _h - 6, fallbackH: 2.4, fallback: const Color(0xffC4D23E), after: (c, rect, fade) {
        for (final k in const [0.0, 0.33, 0.66, 1.0]) {
          final p = Offset(rect.left + rect.width * (0.30 - 0.23 * k), rect.top + rect.height * (0.29 - 0.26 * k));
          nc.driverGlows.add((p, rect.width * 0.16, const Color(0xffFF4A2E).withValues(alpha: (0.25 + 0.6 * dark) * pulse * fade)));
        }
      });
    }
    if (inView(b.s)) {
      _propAfter(items, a, 'flood_light', b.s - 30, _h + 96, fallbackH: 2.55, fallback: const Color(0xff4A4E54), after: (c, rect, fade) {
        for (final u in const [0.27, 0.73]) {
          nc.driverGlows.add((Offset(rect.left + rect.width * u, rect.top + rect.height * 0.07), rect.width * 0.45, const Color(0xffFFF6E0).withValues(alpha: 0.9 * dark * fade)));
        }
        // Quầng sáng đèn chiếu trên bãi kiểm tra.
        nc.driverGlows.add((Offset(rect.center.dx + rect.width * 0.6, rect.bottom), rect.height * 1.25, const Color(0xffFFF0D0).withValues(alpha: 0.32 * dark * fade)));
      });
      _prop(items, a, 'police_tent', b.s - 130, _h + 160, fallbackH: 2.7, fallback: const Color(0xff2F6FB5));
      _prop(items, a, 'police_officer_breath', b.s + 60, _h + 46, fallbackH: 1.74, fallback: const Color(0xffC4D23E));
    }
    if (inView(b.s + 185)) {
      final car = a.vehicle(Img.sedansAi[(b.s.round() ~/ 7) % Img.sedansAi.length], 'rear');
      final o = _at(b.s + 185 - dir * TrafficType.sedan.length / 2, _h + 28);
      final cw = car == null ? TrafficType.sedan.width : car.width / DriverArt.vehiclePixelsPerMeter * _DriverView._u;
      final ch = car == null ? TrafficType.sedan.width * 0.8 : car.height / DriverArt.vehiclePixelsPerMeter * _DriverView._u;
      final hazard = (t * 1.6).floor().isEven;
      _board(items, o.dx, o.dy, cw, ch, car, fallback: const Color(0xff4B5563), after: (c, rect, fade) {
        if (!hazard) return;
        for (final u in const [0.13, 0.87]) {
          nc.driverGlows.add((Offset(rect.left + rect.width * u, rect.top + rect.height * 0.55), rect.width * 0.12, const Color(0xffFFA01E).withValues(alpha: 0.85 * fade)));
        }
      });
      _prop(items, a, 'person_2', b.s + 150, _h + 66, fallbackH: 1.66, fallback: const Color(0xff8E44AD));
      _prop(items, a, 'police_officer_breath', b.s + 200, _h + 78, fallbackH: 1.74, fallback: const Color(0xffC4D23E));
      final police = a.vehicle(Img.imgScooterPolice, 'side');
      if (police != null) {
        final po = _at(b.s + 280, _h + 70);
        final redOn = (t * 5).floor().isEven;
        _board(items, po.dx, po.dy, police.width / DriverArt.vehiclePixelsPerMeter * _DriverView._u,
            police.height / DriverArt.vehiclePixelsPerMeter * _DriverView._u, police, after: (c, rect, fade) {
          final p = Offset(rect.center.dx, rect.top + rect.height * 0.12);
          nc.driverGlows.add((p, rect.width * 0.18, (redOn ? const Color(0xffFF3B30) : const Color(0xff2F6BFF)).withValues(alpha: (0.45 + 0.5 * dark) * fade)));
        });
      }
    }
  }

  /// Sau lớp tối: hơi lạnh xanh xám phủ cảnh (dày về phía chân trời), đèn
  /// của chốt, kính ô tô mờ hơi nước ở mép dưới.
  void _coldScene(Canvas canvas, Size size) {
    final nc = game._nightCold;
    final k = nc.chillShown;
    if (k > 0.02) {
      final hy = cam.horizonY;
      final night = game.darkness;
      final tone = Color.lerp(const Color(0xffCAD8E6), const Color(0xff3E5068), night)!;
      final mist = nc.mistLevel;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = const Color(0xff808080).withValues(alpha: 0.32 * k)
          ..blendMode = BlendMode.saturation,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = Gradient.linear(Offset(0, hy - size.height * 0.35), Offset(0, size.height), [
            tone.withValues(alpha: (0.08 + 0.12 * k) * (1 - 0.4 * night)),
            tone.withValues(alpha: (0.16 + 0.36 * k * mist) * (1 - 0.5 * night)),
            tone.withValues(alpha: (0.06 + 0.10 * k) * (1 - 0.4 * night)),
          ], [
            0,
            ((hy + size.height * 0.04 - (hy - size.height * 0.35)) / (size.height * 1.35 - hy)).clamp(0.05, 0.95),
            1,
          ]),
      );
    }
    for (final (p, r, c) in nc.driverGlows) {
      if (c.a <= 0.01 || r <= 0.5) continue;
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = Gradient.radial(p, r, [c, c.withValues(alpha: 0)]),
      );
    }
    // Ô tô, xe khách: kính chắn gió mờ hơi nước ở mép dưới và hai góc (sau
    // khung xe vẽ đè nên chỉ thấy trên mặt kính).
    if (k > 0.15 && game.spec.kind != VehicleKind.motorbike) {
      final fogAlpha = (0.10 + 0.22 * k) * (1 - 0.65 * game.darkness);
      final band = Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.4);
      canvas.drawRect(
        band,
        Paint()
          ..shader = Gradient.linear(band.topCenter, band.bottomCenter, [
            const Color(0x00F2F6FA),
            const Color(0xffF2F6FA).withValues(alpha: fogAlpha),
          ]),
      );
      for (final x in [size.width * 0.04, size.width * 0.96]) {
        final c = Offset(x, size.height * 0.55);
        canvas.drawCircle(
          c,
          size.width * 0.22,
          Paint()..shader = Gradient.radial(c, size.width * 0.22, [const Color(0xffF2F6FA).withValues(alpha: fogAlpha * 0.9), const Color(0x00F2F6FA)]),
        );
      }
    }
  }

  /// Xe máy: hơi thở người lái phả ra thành làn khói trắng trước mặt (rõ lúc
  /// đứng / đi chậm, chạy nhanh thì gió thổi tạt ngay).
  void _coldBreath(Canvas canvas, Size size) {
    final nc = game._nightCold;
    final k = nc.chillShown;
    if (k < 0.08 || game.spec.kind != VehicleKind.motorbike) return;
    final speed = (game.player.speed / game.spec.maxSpeed).clamp(0.0, 1.0);
    const period = 3.6;
    final ph = (game._time % period) / period;
    if (ph > 0.42) return;
    final life = ph / 0.42;
    final strength = (0.35 + 0.65 * k) * (1 - 0.8 * speed) * sin(pi * life);
    if (strength < 0.01) return;
    final night = game.darkness;
    final color = Color.lerp(const Color(0xffF4F7FA), const Color(0xffB8C4D2), night)!;
    final drift = speed * 0.25;
    final base = Offset(size.width * (0.5 + 0.03 * sin(game._time * 0.7)), size.height * (0.70 - 0.16 * life + drift * life));
    for (var i = 0; i < 4; i++) {
      final c = base + Offset((i - 1.5) * size.width * 0.035 * (0.6 + life), -i * size.height * 0.025 * life);
      final r = size.width * (0.05 + 0.09 * life) * (0.8 + 0.12 * i);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5)
          ..color = color.withValues(alpha: 0.3 * strength * (1 - 0.15 * i)),
      );
    }
  }
}
