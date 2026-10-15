part of 've_que_game.dart';

/// Phà qua sông (bản đồ sông nước): đường quốc lộ cắt ngang một nhánh sông,
/// từ bờ [a] tới bờ [b]. Phà con thoi qua lại; xe tới bến thì xếp hàng, mua
/// vé, chờ phà cập bến rồi lái lên, phà chở qua sông, xuống phà đi tiếp.
class _Ferry {
  _Ferry(this.a, this.b) : center = a + _length / 2 - 10;

  final double a;
  final double b;

  /// Tâm phà (theo s) và đang làm gì.
  double center;
  _FerryState state = _FerryState.dockedA;
  double t = 0;

  /// Xe đang đậu trên boong (đi cùng chuyến với mình).
  final List<_DeckCar> deck = [];

  /// Phà dài 30 m (ảnh img_ferry.png, 47 điểm ảnh mỗi mét), rộng 10 m.
  static const double _length = 1420 / 47 * DriverArt.unitsPerMeter;
  static const double width = 482 / 47 * DriverArt.unitsPerMeter;
  static double get length => _length;

  double get dockA => a + _length / 2 - 10;
  double get dockB => b - _length / 2 + 10;

  bool get moving => state == _FerryState.toA || state == _FerryState.toB;
}

enum _FerryState { dockedA, toB, dockedB, toA }

/// Xe AI đang lên / đậu trên phà: chạy từ chỗ xếp hàng tới chỗ đậu.
class _DeckCar {
  _DeckCar(this.type, this.variant, this.fromS, this.fromD, this.slotS, this.slotD);

  final TrafficType type;
  final int variant;
  final double fromS;
  final double fromD;

  /// Chỗ đậu so với tâm phà.
  final double slotS;
  final double slotD;
}

/// Mình đang tới đâu ở bến phà.
enum _FerryStep { none, approach, ticket, waiting, boarding, crossing, landing }

extension _FerryEvents on _TetEvents {
  _Ferry? _planFerry() {
    if (!g.fatigue || g.setup.theme != MapTheme.mekong) return null;
    final zones = _highways(minLength: 7000);
    if (zones.isEmpty) return null;
    final z = zones[_r.nextInt(zones.length)];
    final len = z.endS - z.startS;
    for (var k = 0; k < 12; k++) {
      final a = z.startS + len * (0.3 + 0.35 * k / 12);
      final b = a + GameConfig.riverWidth;
      final clear = !g.layout.nearFeature(a, margin: 1400) && !g.layout.nearFeature(b, margin: 1400) && b < z.endS - 900;
      if (!clear) continue;
      // Quán xá không mở giữa bến phà.
      g.layout.stalls.removeWhere((t) => t.s > a - 600 && t.s < b + 400);
      return _Ferry(a, b);
    }
    return null;
  }

  /// Chỗ [s] nằm trên sông (cộng thêm [margin] hai bên bờ).
  bool inRiver(double s, {double margin = 0}) {
    final f = ferry;
    return f != null && s > f.a - margin && s < f.b + margin;
  }

  /// Đang ở bến / trên phà: không tự lái, nhìn từ trên.
  bool get ferryBusy => _ferryStep.index >= _FerryStep.ticket.index;

  /// Phà con thoi qua lại; chở mình thì theo nhịp của mình.
  void _stepFerry(double dt) {
    final f = ferry;
    if (f == null) return;
    f.t += dt;
    // Có xe đang chờ ở bến thì phà về nhanh (đỡ phải ngồi chờ lâu).
    final waiting = _ferryStep == _FerryStep.waiting || _ferryStep == _FerryStep.ticket;
    final speed = GameConfig.ferrySpeed * (waiting ? 3 : 1);
    final dock = waiting ? 0.4 : GameConfig.ferryDockSeconds;
    switch (f.state) {
      case _FerryState.dockedA:
        // Đang chờ mình lên phà thì chưa rời bến.
        final holding = _ferryStep == _FerryStep.waiting || _ferryStep == _FerryStep.boarding;
        if (!holding && f.t > GameConfig.ferryDockSeconds && !waiting) _depart(f, _FerryState.toB);
      case _FerryState.toB:
        f.center = min(f.dockB, f.center + speed * dt);
        if (f.center >= f.dockB) _dock(f, _FerryState.dockedB);
      case _FerryState.dockedB:
        if (_ferryStep != _FerryStep.landing && f.t > dock) _depart(f, _FerryState.toA);
      case _FerryState.toA:
        f.center = max(f.dockA, f.center - speed * dt);
        if (f.center <= f.dockA) _dock(f, _FerryState.dockedA);
    }
    _stepFerryTrip(f, dt);
  }

  void _depart(_Ferry f, _FerryState to) {
    f
      ..state = to
      ..t = 0;
    if (_ferryStep == _FerryStep.boarding) _ferryStep = _FerryStep.crossing;
  }

  void _dock(_Ferry f, _FerryState at) {
    f
      ..state = at
      ..t = 0;
    if (at == _FerryState.dockedB && _ferryStep == _FerryStep.crossing) {
      _ferryStep = _FerryStep.landing;
      _ferryT = 0;
      g.onNotice(const GameNotice('Phà cập bến — lái xe xuống phà, đi tiếp thôi!'));
    }
    if (at == _FerryState.dockedA && _ferryStep == _FerryStep.waiting) _board(f);
  }

  /// Đoạn trước bến: báo trước, tự vào bến xếp hàng (bám xe phía trước).
  void _ferryApproach(double dt) {
    final f = ferry;
    if (f == null || g.dir < 0) return;
    final s = g.player.s;
    if (s > f.a - 2200 && s < f.a) {
      g._notice('ferry${f.a.round()}', 'Sắp tới bến phà — xe tự vào bến xếp hàng, mua vé rồi lái lên phà.', NoticeKind.info);
    }
    if (_ferryStep == _FerryStep.none && s > f.a - GameConfig.ferryApproach && s < f.a) {
      _ferryStep = _FerryStep.approach;
      g._approach = null;
      pull = null;
    }
    if (_ferryStep != _FerryStep.approach) return;
    // Vào bến: giảm dần theo quãng còn lại / xe đang xếp hàng phía trước.
    final p = g.player;
    final decel = g._approachDecel;
    final stop = f.a - 34 - g.spec.length / 2;
    var want = min(GameConfig.stallApproachSpeed, sqrt(2 * decel * max(0.0, stop - s)));
    for (final v in g.traffic.vehicles) {
      if (v.oncoming) continue;
      final gap = v.s - s - (v.type.length + g.spec.length) / 2;
      if (gap < -4 || (v.d - p.d).abs() > (v.type.width + g.spec.width) / 2 + 30) continue;
      want = min(want, sqrt(v.speed * v.speed + 2 * decel * max(0.0, gap - 24)));
    }
    p
      ..throttle = false
      ..cruise = want;
    if (p.speed > want) p.speed = max(want, p.speed - 1.6 * decel * dt);
    p.steer = ((Lanes.center(1) - 30 - p.d) / 26).clamp(-1.0, 1.0);
    if (p.speed < 12) {
      p.stop();
      _ferryStep = _FerryStep.ticket;
      _ferryT = 0;
      _queueS = p.s;
      final paid = min(1, g.lixi);
      g.lixi -= paid;
      if (paid > 0) g._popAt(p.s, p.d + 20, '−1', const Color(0xffFF8A80));
      g.clock.addPenalty(GameConfig.ferryMinutes);
      g.onSound(GameSound.toll);
      g.onNotice(GameNotice('Mua vé phà${paid > 0 ? ' (−1 lì xì)' : ''} · xếp hàng chờ phà · mất chừng ${GameConfig.ferryMinutes.round()} phút'));
    }
  }

  /// Phà cập bến A, mình đang chờ: xe xếp hàng trước mình lên trước.
  void _board(_Ferry f) {
    _ferryStep = _FerryStep.boarding;
    _ferryT = 0;
    f.deck.clear();
    const slots = [(0.32, -48.0), (0.32, 48.0), (0.08, -48.0)];
    final ahead = [
      for (final v in g.traffic.vehicles)
        if (!v.oncoming && v.s > _queueS && v.s < f.a + 40) v,
    ]..sort((x, y) => y.s.compareTo(x.s));
    for (var i = 0; i < ahead.length; i++) {
      final v = ahead[i];
      g.traffic.remove(v);
      if (i >= slots.length) continue;
      final (k, d) = slots[i];
      f.deck.add(_DeckCar(v.type, v.variant, v.s, v.d, k * _Ferry.length, d));
    }
    g.onNotice(const GameNotice('Phà cập bến — lái xe lên phà'));
  }

  void _stepFerryTrip(_Ferry f, double dt) {
    if (!ferryBusy) return;
    _ferryT += dt;
    final p = g.player;
    switch (_ferryStep) {
      case _FerryStep.ticket:
        if (_ferryT > 1.2) {
          _ferryStep = _FerryStep.waiting;
          if (f.state == _FerryState.dockedA) {
            _board(f);
          } else {
            g.onNotice(const GameNotice('Phà đang ở bờ bên kia — chờ phà quay về…'));
          }
        }
      case _FerryStep.waiting:
        break;
      case _FerryStep.boarding:
        // Lái lên boong, đỗ phía đuôi phà.
        final k = _easeInOut((_ferryT / GameConfig.ferryBoardSeconds).clamp(0.0, 1.0));
        p
          ..s = _queueS + (f.center - 0.24 * _Ferry.length - _queueS) * k
          ..d = p.d + (_deckD - p.d) * min(1.0, 4 * dt);
        if (_ferryT > GameConfig.ferryBoardSeconds + 0.6) {
          _depart(f, _FerryState.toB);
          g.onNotice(const GameNotice('Phà rẽ sóng qua sông — gió sông mát rượi, khói bếp bên bờ…'));
        }
      case _FerryStep.crossing:
        p
          ..s = f.center - 0.24 * _Ferry.length
          ..d = _deckD;
      case _FerryStep.landing:
        // Xe trên boong xuống trước, mình theo sau.
        final from = f.center - 0.24 * _Ferry.length;
        final k = _easeIn((_ferryT / GameConfig.ferryLandSeconds).clamp(0.0, 1.0));
        p.s = from + (f.b + 90 - from) * k;
        if (_ferryT >= GameConfig.ferryLandSeconds) {
          for (final c in f.deck) {
            g.traffic.addVehicle(c.type, c.slotD < 0 ? 0 : 1, f.b + 260 + c.slotS, 0.55 * GameConfig.normalSpeed);
          }
          f.deck.clear();
          _ferryStep = _FerryStep.none;
          p
            ..speed = 0.25 * GameConfig.normalSpeed
            ..cruise = 0.25 * GameConfig.normalSpeed;
        }
      case _FerryStep.none:
      case _FerryStep.approach:
        break;
    }
    if (ferryBusy) {
      p
        ..throttle = false
        ..brake = false
        ..steer = 0
        ..lateralVelocity = 0
        ..speed = 0
        ..cruise = 0;
    }
  }

  /// Lệch ngang chỗ mình đỗ trên boong.
  double get _deckD => 46;

  /// Toạ độ (s, d) của một xe đậu trên boong lúc này.
  (double, double) deckSpot(_DeckCar c) {
    final f = ferry!;
    if (_ferryStep == _FerryStep.boarding) {
      final k = _easeInOut((_ferryT / GameConfig.ferryBoardSeconds).clamp(0.0, 1.0));
      return (c.fromS + (f.center + c.slotS - c.fromS) * k, c.fromD + (c.slotD - c.fromD) * k);
    }
    if (_ferryStep == _FerryStep.landing) {
      final k = _easeIn((_ferryT / GameConfig.ferryLandSeconds).clamp(0.0, 1.0));
      final s0 = f.center + c.slotS;
      return (s0 + (f.b + 260 + c.slotS - s0) * k, c.slotD);
    }
    return (f.center + c.slotS, c.slotD);
  }

  /// Chỗ xe AI phải dừng: hai đầu bến phà.
  List<StopPoint> ferryStops() {
    final f = ferry;
    if (f == null) return const [];
    return [StopPoint(s: f.a - 20, forward: true), StopPoint(s: f.b + 20, forward: false)];
  }
}

/// Sông, phà, xe trên boong (nhìn từ trên).
class _FerryLayer extends Component {
  _FerryLayer(this.game) : super(priority: 3);

  final VeQueGame game;
  double _t = 0;

  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _shadow = Paint()..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn);
  static final Paint _wake = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final ev = game._events;
    final f = ev.ferry;
    if (f == null || game._driverShown) return;
    if (f.center + _Ferry.length < game._camLeftS - 200 || f.center - _Ferry.length > game._camRightS + 200) return;
    final at = game.road.at(f.center);
    final (x, y) = game.road.worldAt(f.center, 0);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(at.heading + pi / 2);
    // Sóng rẽ hai bên mũi khi phà chạy.
    if (f.moving) {
      final forward = f.state == _FerryState.toB ? -1.0 : 1.0;
      for (var i = 0; i < 5; i++) {
        final k = (_t * 0.8 + i / 5) % 1;
        _wake
          ..color = Color.fromRGBO(240, 244, 240, 0.35 * (1 - k))
          ..strokeWidth = 3 + 4 * k;
        final y0 = forward * (_Ferry.length / 2 + k * 160);
        canvas.drawLine(Offset(-_Ferry.width / 2 - 10 - k * 60, y0), Offset(_Ferry.width / 2 + 10 + k * 60, y0), _wake);
      }
    }
    final img = game.images.fromCache(Img.imgFerry);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: Offset.zero, width: _Ferry.width, height: _Ferry.length);
    canvas.drawImageRect(img, src, dst.shift(const Offset(8, 8)), _shadow);
    canvas.drawImageRect(img, src, dst, _image);
    canvas.restore();
    // Xe đậu trên boong.
    for (final c in f.deck) {
      final (s, d) = ev.deckSpot(c);
      final path = TrafficLayer.dressedPath(c.type, c.variant, raining: false);
      if (!game.images.containsKey(path)) continue;
      final car = game.images.fromCache(path);
      final (cx, cy) = game.road.worldAt(s, d);
      final w = c.type.width * (c.type == TrafficType.motorbike ? GameConfig.motorbikeVisualScale : 1);
      final h = w * car.height / car.width;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(game.road.at(s).heading + pi / 2);
      final box = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      canvas.drawImageRect(car, Rect.fromLTWH(0, 0, car.width.toDouble(), car.height.toDouble()), box.shift(const Offset(3, 3)), _shadow);
      canvas.drawImageRect(car, Rect.fromLTWH(0, 0, car.width.toDouble(), car.height.toDouble()), box, _image);
      canvas.restore();
    }
  }
}

double _easeInOut(double k) => k * k * (3 - 2 * k);
double _easeIn(double k) => k * k;
