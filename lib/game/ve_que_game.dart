import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../model/trip.dart';
import '../resource/app_resource.dart';
import 'components/night_overlay.dart';
import 'components/pickups.dart';
import 'components/police_component.dart';
import 'components/road_features.dart';
import 'components/road_renderer.dart';
import 'components/scenery_layer.dart';
import 'components/traffic_layer.dart';
import 'components/vehicle_sprite.dart';
import 'components/world_paints.dart';
import 'game_config.dart';
import 'logic/chase.dart';
import 'logic/collision.dart';
import 'logic/cross_traffic.dart';
import 'logic/player_physics.dart';
import 'logic/road_layout.dart';
import 'logic/road_path.dart';
import 'logic/toll_gate.dart';
import 'logic/traffic_system.dart';
import 'logic/trip_clock.dart';
import 'stage.dart';
import 'vehicle_spec.dart';

/// Một chặng lái xe. Flutter (GameController) điều khiển qua các hàm
/// set*/honk/toggleHeadlights/payFine/flee và nhận số liệu qua các callback.
class VeQueGame extends FlameGame {
  VeQueGame({
    required this.setup,
    required this.onHud,
    required this.onPhaseChanged,
    required this.onChase,
    required this.onFinished,
    required this.onSound,
    required this.onNotice,
  });

  final StageSetup setup;
  final void Function(HudData hud) onHud;
  final void Function(GamePhase phase) onPhaseChanged;
  final void Function(double progress, double timeLeft) onChase;
  final void Function(StageResult result) onFinished;
  final void Function(GameSound sound) onSound;
  final void Function(GameNotice notice) onNotice;

  static const double _startS = 400;

  late final VehicleSpec spec = VehicleSpec.of(setup.vehicle);
  late final Random _random = Random(setup.seed);
  late final RoadLayout layout = RoadLayout.build(
    sections: setup.sections,
    startS: _startS,
    tollBooths: setup.tollBooths,
    random: Random(setup.seed * 104729 + 3),
    withBusStops: setup.vehicle == VehicleKind.bus,
  );
  late final RoadPath road = RoadPath.winding(
    random: Random(setup.seed * 7919 + 1),
    styleAt: layout.curveStyleAt,
    keepStraight: (a, b) => layout.featureWithin(a, b, margin: 200),
  );
  late final PlayerPhysics player = PlayerPhysics(
    spec: spec,
    s: _startS,
    d: Lanes.center(1),
    speed: 0.6 * GameConfig.normalSpeed,
  )..cargo = setup.startCargo;
  late final TrafficSystem traffic = TrafficSystem(Random(setup.seed * 31 + 7));
  late final CrossTraffic cross = CrossTraffic(Random(setup.seed * 17 + 9));
  late final List<TollGate> _gates = [for (final t in layout.tolls) TollGate(t, setup.vehicle)];
  late final TripClock clock = TripClock(minutes: setup.startClockMinutes);
  late int lixi = setup.startLixi;

  double get finishS => layout.endS;

  GamePhase phase = GamePhase.driving;
  IncidentKind incidentKind = IncidentKind.collision;
  Chase? chase;

  /// Giây chơi kể từ đầu chặng (chu kỳ đèn giao thông).
  double _time = 0;
  double get time => _time;

  StageEndReason? _endReason;
  double _endDelay = 0;
  bool _endReported = false;
  double _crashSpin = 0;

  late final WorldPaints _paints;
  late final RoadRenderer _roadRenderer;
  late final FeatureGroundLayer _featureGround;
  late final FeatureOverheadLayer _featureOverhead;
  late final VehicleSprite _playerSprite;
  late final TrafficLayer _trafficLayer;
  late final SceneryLayer _scenery;
  late final PowerLines _powerLines;
  late final PoliceComponent _police;
  late final NightOverlay _night;
  late final OvertakeWarning _overtakeArrow;
  late final BusStopLayer _busStops;

  /// Đang dừng đón khách ở điểm nào, đã dừng bao lâu.
  BusStop? _boardingStop;
  double _boardTimer = 0;

  final List<(Pickup, PositionComponent)> _pickups = [];
  double _lixiTimer = 1.5;
  double _potholeTimer = 6;
  double _giftTimer = 4;

  /// Tâm camera (toạ độ thế giới) và góc xoay: camera xoay theo đường nên
  /// đường luôn chạy ngang màn hình, khúc cua phía trước uốn lên / xuống.
  double _camX = 0;
  double _camY = 0;
  double _camAngle = 0;
  bool _cameraReady = false;
  double _screenFraction = GameConfig.playerScreenXSlow;
  double _shake = 0;
  double _camLeftS = 0;
  double _camRightS = 0;

  bool _policeVisible = false;
  double _policeS = 0;
  double _policeD = 0;

  HudData? _lastHud;
  int _cargoShown = -1;

  /// Đã phát tiếng phanh rít cho lần giữ phanh này chưa.
  bool _skidPlayed = false;

  /// Đã phát tiếng rít cho lần quệt lề này chưa.
  bool _scrapePlayed = false;

  // Còi, đèn
  bool headlightsOn = false;
  double _hornCooldown = 0;
  double _honkBackTimer = -1;

  // Xe vượt từ phía sau
  late double _overtakeTimer = _between(GameConfig.overtakeIntervalMin, GameConfig.overtakeIntervalMax);
  double _overtakeWarn = 0;
  int _overtakeLane = 0;

  /// Đèn đỏ đã xét (mỗi ngã tư chỉ xét một lần) và thông báo đã hiện.
  final Set<double> _lightsPassed = {};
  final Set<String> _noticed = {};

  @override
  Color backgroundColor() => const Color(0xff6E8F45);

  @override
  Future<void> onLoad() async {
    // Đường dẫn ảnh khai báo đầy đủ trong Img, không dùng tiền tố mặc định.
    images.prefix = '';
    await images.loadAll([...Img.vehicles, ...Img.worldArt]);
    _paints = WorldPaints(images);

    camera.viewfinder.anchor = Anchor.center;
    _updateZoom();

    _roadRenderer = RoadRenderer(
      road: road,
      layout: layout,
      finishS: finishS,
      paints: _paints,
      images: images,
      seed: setup.seed,
      ripeRice: setup.south,
    );
    _featureGround = FeatureGroundLayer(road: road, layout: layout)..gates = _gates;
    _featureOverhead = FeatureOverheadLayer(road: road, layout: layout);
    _scenery = SceneryLayer(road: road, layout: layout, paints: _paints, random: Random(setup.seed * 13 + 5));
    _powerLines = PowerLines(road: road);
    _trafficLayer = TrafficLayer(traffic: traffic, cross: cross, road: road);
    _playerSprite = VehicleSprite(
      sprite: Sprite(images.fromCache(Img.player(spec.kind))),
      shadow: Sprite(images.fromCache(Img.imgShadowBox)),
      width: spec.width * (spec.kind == VehicleKind.motorbike ? GameConfig.motorbikeVisualScale : 1),
      priority: 6,
      motorbike: spec.kind == VehicleKind.motorbike,
    );
    _police = PoliceComponent(
      sprite: Sprite(images.fromCache(Img.imgScooterPolice)),
      shadow: Sprite(images.fromCache(Img.imgShadowBox)),
    );
    _busStops = BusStopLayer(
      road: road,
      layout: layout,
      people: [for (final p in Img.people) Sprite(images.fromCache(p))],
    );
    _night = NightOverlay();
    _overtakeArrow = OvertakeWarning();

    await world.addAll([
      _roadRenderer,
      _scenery,
      _featureGround,
      _busStops,
      _trafficLayer,
      _playerSprite,
      _police,
      _featureOverhead,
      _powerLines,
      _overtakeArrow,
      _night,
    ]);
    _updateCamera(0);
    _syncVisuals();
    _announceZone(force: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _updateZoom();
  }

  /// Luôn thấy đủ chiều cao mặt đường; máy gần vuông thì thu nhỏ thêm để
  /// vẫn đủ tầm nhìn phía trước.
  void _updateZoom() {
    if (size.x <= 0 || size.y <= 0) return;
    camera.viewfinder.zoom = min(
      size.y / GameConfig.visibleWorldHeight,
      size.x / GameConfig.minVisibleWorldWidth,
    );
  }

  double get _visibleWidth => size.x / camera.viewfinder.zoom;
  double get _visibleHeight => size.y / camera.viewfinder.zoom;

  // ------------------------------------------------------------ Đầu vào
  void setThrottle(bool on) => player.throttle = on;
  void setBrake(bool on) => player.brake = on;
  void setSteer(double value) => player.steer = value;

  /// Bóp còi xin đường. Trả về false nếu còi đang hồi.
  bool honk() {
    if (_hornCooldown > 0 || phase == GamePhase.finished) return false;
    _hornCooldown = GameConfig.hornCooldown;
    onSound(GameSound.horn);
    if (phase != GamePhase.driving && phase != GamePhase.chase) return true;
    switch (traffic.requestYield(_snapshot)) {
      case YieldResult.honkedBack:
        _honkBackTimer = 0.45;
        onNotice(const GameNotice('Xe to không nhường — bóp còi lại!', kind: NoticeKind.warning));
      case YieldResult.noRoom:
        onNotice(const GameNotice('Làn bên đang có xe, chưa tránh được'));
      case YieldResult.yielded:
      case YieldResult.nobody:
        break;
    }
    return true;
  }

  void toggleHeadlights() {
    headlightsOn = !headlightsOn;
    _pushHud();
  }

  // -------------------------------------------------------- Vòng lặp
  @override
  void update(double dt) {
    final step = min(dt, 1 / 30);
    _time += step;
    _hornCooldown = max(0, _hornCooldown - step);
    if (_honkBackTimer > 0) {
      _honkBackTimer -= step;
      if (_honkBackTimer <= 0) onSound(GameSound.hornOther);
    }
    switch (phase) {
      case GamePhase.driving:
        _stepDriving(step);
      case GamePhase.chase:
        _stepDriving(step);
        if (phase == GamePhase.chase) _stepChase(step);
      case GamePhase.incident:
        _stepIncident(step);
      case GamePhase.finished:
        _stepFinished(step);
    }
    _updateCamera(step);
    _syncVisuals();
    _pushHud();
    super.update(step);
  }

  RoadBox get _playerBox => RoadBox(s: player.s, d: player.d, length: spec.length, width: spec.width);

  PlayerSnapshot get _snapshot =>
      PlayerSnapshot(s: player.s, d: player.d, speed: player.speed, length: spec.length, width: spec.width);

  void _stepDriving(double dt) {
    if (player.brake && !_skidPlayed && player.speed > 0.55 * GameConfig.normalSpeed) {
      _skidPlayed = true;
      onSound(GameSound.skid);
    } else if (!player.brake) {
      _skidPlayed = false;
    }
    _applyBounds();
    final prevFront = player.s + spec.length / 2;
    road.ensureAhead(player.s + GameConfig.curveWarnDistance + 1500);
    player.curvature = road.at(player.s).curvature;
    player.update(dt);
    clock.advance(dt);
    _stepCurves();

    traffic.update(
      dt,
      _snapshot,
      spawnS: _camRightS + 150,
      despawnBehindS: _camLeftS - 400,
      despawnAheadS: _camRightS + 2500,
      stops: _stopPoints(),
      profileAt: _profileAt,
      canSpawnAt: (s) => !layout.nearFeature(s, margin: 160),
    );
    cross.update(dt, _time, layout.lightsBetween(_camLeftS - 300, _camRightS + 600), _playerBox);
    _stepTolls(dt);
    _stepBusStops(dt);
    _stepOvertakes(dt);
    _stepPickups(dt);
    _announceZone();

    // Va chạm: xe dọc đường, xe đường ngang, vật cản cố định.
    final hit = traffic.hit(_playerBox);
    if (hit != null) {
      _collide(relativeImpactSpeed(player.speed, hit.velocity), onMinor: () => traffic.remove(hit), stopOther: () => hit.speed = 0);
      return;
    }
    final crossHit = cross.hit(_playerBox);
    if (crossHit != null) {
      final rel = sqrt(player.speed * player.speed + crossHit.speed * crossHit.speed);
      _collide(rel, onMinor: () => cross.remove(crossHit), stopOther: () => crossHit.speed = 0);
      return;
    }
    if (_hitsObstacle()) {
      _collide(player.speed, onMinor: () {}, stopOther: () {}, backOff: true);
      return;
    }
    if (_ranRedLight(prevFront)) return;

    if (player.s >= finishS) {
      _end(StageEndReason.arrived, delay: 0.6);
    } else if (clock.isOver) {
      player.stop();
      _end(StageEndReason.timeUp, delay: 0.4);
    }
    road.trimBefore(_camLeftS - 2400);
  }

  /// Khúc cua gắt gần nhất phía trước (hoặc đang ở trong).
  RoadCurve? get sharpCurveAhead {
    for (final c in road.curvesBetween(player.s, player.s + GameConfig.curveWarnDistance)) {
      if (c.sharp) return c;
    }
    return null;
  }

  /// Báo trước cua gắt; vào cua nhanh quá bị văng tì mép đường thì rung, rít lốp.
  void _stepCurves() {
    final c = sharpCurveAhead;
    if (c != null && c.startS > player.s + spec.length) {
      _notice(
        'curve${c.startS.round()}',
        'Sắp vào cua gắt bên ${c.right ? 'phải' : 'trái'} — giảm tốc dưới ${c.adviseKmh} km/h, bẻ lái giữ làn!',
        NoticeKind.warning,
      );
    }
    if (!player.scraping) {
      _scrapePlayed = false;
      return;
    }
    _shake = max(_shake, 0.12);
    if (!_scrapePlayed) {
      _scrapePlayed = true;
      onSound(GameSound.skid);
    }
    _notice('scrape${(player.s / 1500).floor()}', 'Vào cua nhanh quá — xe bị văng ra sát mép đường!', NoticeKind.warning);
  }

  TrafficProfile _profileAt(double s) => switch (layout.kindAt(s)) {
        RoadKind.city => TrafficProfile.city,
        RoadKind.highway => TrafficProfile.highway,
        RoadKind.expressway => TrafficProfile.expressway,
      };

  /// Biên lệch ngang theo chỗ: dải phân cách cao tốc, làn xe máy ở trạm.
  void _applyBounds() {
    final half = spec.width / 2;
    var hi = GameConfig.roadHalfWidth - half;
    var lo = -hi;
    final toll = layout.tollAt(player.s);
    if (toll != null) {
      hi = toll.maxEdge(player.s) - half;
      lo = -(toll.maxEdge(toll.s + (toll.s - player.s))) + half;
    }
    if (layout.hasMedian(player.s)) {
      const m = GameConfig.medianHalfWidth;
      if (player.d >= 0) {
        lo = m + half + 1;
      } else {
        hi = -m - half - 1;
        _notice('wrongway${(player.s / 2000).floor()}', 'Đang đi ngược chiều cao tốc! Cẩn thận!', NoticeKind.warning);
      }
    }
    player
      ..minD = lo
      ..maxD = hi;
  }

  List<StopPoint> _stopPoints() {
    final stops = <StopPoint>[];
    for (final l in layout.lightsBetween(_camLeftS - 300, _camRightS + 900)) {
      if (l.colorAt(_time) == LightColor.green) continue;
      stops
        ..add(StopPoint(s: l.stopLine, forward: true))
        ..add(StopPoint(s: l.oncomingStopLine, forward: false));
    }
    for (final g in _gates) {
      if (g.plaza.plazaEnd < _camLeftS - 300 || g.plaza.plazaStart > _camRightS + 900) continue;
      stops.addAll(g.stops());
    }
    return stops;
  }

  bool _hitsObstacle() {
    final box = _playerBox;
    for (final g in _gates) {
      if (!g.plaza.contains(player.s)) continue;
      for (final o in g.obstacles()) {
        if (o.overlaps(box, shrink: 0.95)) {
          if (o.length < 10) onSound(GameSound.barrier);
          return true;
        }
      }
    }
    // Đệm chống va ở đầu dải phân cách cao tốc.
    for (final z in layout.zones.where((z) => z.kind == RoadKind.expressway)) {
      for (final end in [z.startS + GameConfig.medianInset - 16, z.endS - GameConfig.medianInset + 16]) {
        if (RoadBox(s: end, d: 0, length: 32, width: 2 * GameConfig.medianHalfWidth + 2).overlaps(box, shrink: 0.95)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Vượt đèn đỏ: đầu xe qua vạch dừng lúc đèn đỏ (đang trong ngã tư thì
  /// đèn chuyển đỏ không tính).
  bool _ranRedLight(double prevFront) {
    final front = player.s + spec.length / 2;
    for (final l in layout.lightsBetween(prevFront - 10, front + 10)) {
      if (_lightsPassed.contains(l.s)) continue;
      if (prevFront < l.stopLine && front >= l.stopLine) {
        _lightsPassed.add(l.s);
        if (l.colorAt(_time) == LightColor.red && player.d > -GameConfig.roadHalfWidth) {
          incidentKind = IncidentKind.redLight;
          player.stop();
          onSound(GameSound.crashLight);
          _startIncident();
          return true;
        }
      }
    }
    return false;
  }

  void _collide(double relative, {required void Function() onMinor, required void Function() stopOther, bool backOff = false}) {
    final severity = classifyCollision(relative);
    player.stop();
    if (severity == CollisionSeverity.accident) {
      onSound(GameSound.crashHeavy);
      stopOther();
      _shake = 0.7;
      _crashSpin = 6;
      _end(StageEndReason.accident, delay: 1.4);
      return;
    }
    _shake = 0.3;
    onSound(GameSound.crashLight);
    // Đụng barrier / đảo: lùi lại một đoạn để còn đường mà đi tiếp.
    if (backOff) player.s -= 36;
    if (phase == GamePhase.chase) {
      // Đang bỏ chạy mà quẹt xe: khựng lại (công an áp sát), xe kia tránh đi.
      onMinor();
      return;
    }
    incidentKind = IncidentKind.collision;
    _startIncident();
  }

  // ------------------------------------------------------ Trạm thu phí
  void _stepTolls(double dt) {
    for (final g in _gates) {
      if (g.plaza.plazaEnd < _camLeftS - 600 || g.plaza.plazaStart > _camRightS + 1500) continue;
      g.updateAi(dt, traffic.vehicles);
      if (player.s > g.plaza.plazaStart - 900 && player.s < g.plaza.plazaStart) {
        _notice(
          'toll${g.plaza.s}',
          spec.kind.fourWheels
              ? 'Trạm thu phí! Làn KHÔNG DỪNG: chạy chậm dưới ${(GameConfig.etcMaxSpeed * GameConfig.displayKmhPerUnitSpeed).round()} km/h · Làn THU PHÍ: dừng hẳn'
              : 'Trạm thu phí! Xe máy đi làn XE MÁY sát lề phải',
          NoticeKind.warning,
        );
      }
      final event = g.updatePlayer(dt, s: player.s, d: player.d, speed: player.speed, length: spec.length, lixi: lixi);
      switch (event) {
        case TollPaid(:final fee, :final broke, :final nonStop):
          lixi -= fee;
          onSound(GameSound.toll);
          if (broke) {
            clock.addPenalty(GameConfig.tollBrokeMinutes);
            onNotice(GameNotice('Không đủ lì xì trả phí — bị giữ lại ${GameConfig.tollBrokeMinutes.round()} phút', kind: NoticeKind.warning));
          } else {
            onNotice(GameNotice('${nonStop ? 'Thu phí tự động' : 'Đã trả phí'}: -$fee lì xì', kind: NoticeKind.money));
          }
        case TollFreeLane():
          onNotice(const GameNotice('Làn xe máy — miễn phí'));
        case null:
          break;
      }
    }
  }

  // ------------------------------------------------ Xe khách đón khách
  void _stepBusStops(double dt) {
    for (final stop in layout.busStops) {
      if (stop.served || stop.missed) continue;
      final ahead = stop.s - player.s;
      if (ahead > 0 && ahead < 1000) {
        _notice('stop${stop.s}', 'Điểm đón ${stop.passengers} khách phía trước — dừng sát lề phải', NoticeKind.info);
      }
      if (-ahead > GameConfig.busStopWindow + 40) {
        stop.missed = true;
        onNotice(GameNotice('Lỡ điểm đón — ${stop.passengers} khách đứng chờ mãi', kind: NoticeKind.warning));
        continue;
      }
      final atStop = ahead.abs() < GameConfig.busStopWindow && player.d > GameConfig.tollIslandInnerFrom;
      if (atStop && player.speed < GameConfig.tollStopSpeed) {
        _boardingStop = stop;
        _boardTimer += dt;
        if (_boardTimer >= GameConfig.busBoardSeconds) {
          stop.served = true;
          _boardingStop = null;
          _boardTimer = 0;
          final fare = stop.passengers * GameConfig.fareLixi;
          player.cargo += stop.passengers;
          lixi += fare;
          onSound(GameSound.toll);
          onNotice(GameNotice('Đón ${stop.passengers} khách về quê: +$fare lì xì', kind: NoticeKind.money));
        }
      } else if (identical(_boardingStop, stop)) {
        _boardingStop = null;
        _boardTimer = 0;
      }
    }
  }

  // ------------------------------------------------- Xe vượt phía sau
  void _stepOvertakes(double dt) {
    if (_overtakeWarn > 0) {
      _overtakeWarn -= dt;
      if (_overtakeWarn <= 0) {
        final speed = max(player.speed, GameConfig.normalSpeed) + GameConfig.overtakeExtraSpeed * GameConfig.normalSpeed;
        traffic.spawnOvertaker(_camLeftS - 140, _overtakeLane, speed, profile: _profileAt(player.s));
      }
      return;
    }
    if (layout.kindAt(player.s) == RoadKind.city || layout.nearFeature(player.s, margin: 600)) return;
    _overtakeTimer -= dt;
    if (_overtakeTimer > 0 || player.speed < 0.4 * GameConfig.normalSpeed) return;
    _overtakeTimer = _between(GameConfig.overtakeIntervalMin, GameConfig.overtakeIntervalMax);
    final playerLane = Lanes.at(player.d);
    final lane = playerLane == 0 ? 1 : 0;
    if (!traffic.isLaneClear(lane, _camLeftS, 400)) return;
    _overtakeLane = lane;
    _overtakeWarn = GameConfig.overtakeWarningSeconds;
    onSound(GameSound.hornOther);
    onNotice(const GameNotice('Xe phía sau xin vượt!', kind: NoticeKind.warning));
  }

  // ------------------------------------------------------- Công an
  void _startIncident() {
    phase = GamePhase.incident;
    _policeVisible = true;
    _policeS = _camLeftS - 120;
    _policeD = player.d;
    onPhaseChanged(phase);
  }

  void _stepIncident(double dt) {
    // Công an chạy tới dừng ngay sau xe mình.
    final target = player.s - spec.length / 2 - 34;
    _policeS += (target - _policeS) * (1 - exp(-2.5 * dt));
    _policeD += (player.d - _policeD) * (1 - exp(-3 * dt));
  }

  /// Nộp phạt: trừ lì xì, bị giữ lại một lúc, rồi đi tiếp.
  void payFine() {
    if (phase != GamePhase.incident) return;
    if (lixi >= GameConfig.fineLixi) {
      lixi -= GameConfig.fineLixi;
      clock.addPenalty(GameConfig.fineMinutes);
    } else {
      lixi = 0;
      clock.addPenalty(GameConfig.fineMinutes + GameConfig.fineExtraMinutesIfBroke);
    }
    _clearAroundPlayer();
    _policeVisible = false;
    if (clock.isOver) {
      _end(StageEndReason.timeUp, delay: 0.2);
      return;
    }
    phase = GamePhase.driving;
    onPhaseChanged(phase);
  }

  /// Bỏ chạy: bắt đầu rượt đuổi.
  void flee() {
    if (phase != GamePhase.incident) return;
    _clearAroundPlayer();
    chase = Chase(spec);
    phase = GamePhase.chase;
    onPhaseChanged(phase);
  }

  void _stepChase(double dt) {
    final c = chase!;
    c.update(dt, player.speed);
    _policeS = player.s - spec.length / 2 - 20 - c.gap;
    _policeD += (player.d - _policeD) * (1 - exp(-3 * dt));
    onChase(c.progress, c.timeLeft);
    switch (c.outcome) {
      case ChaseOutcome.running:
        break;
      case ChaseOutcome.escaped:
        chase = null;
        _policeVisible = false;
        phase = GamePhase.driving;
        onPhaseChanged(phase);
      case ChaseOutcome.caught:
        player.stop();
        _end(StageEndReason.caught, delay: 1.0);
    }
  }

  /// Sau sự cố, dọn các xe đang sát bên để đi tiếp không đâm lại ngay.
  void _clearAroundPlayer() {
    traffic.vehicles.removeWhere((v) => (v.s - player.s).abs() < 260);
    cross.vehicles.removeWhere((v) => (v.s - player.s).abs() < 260);
  }

  // ------------------------------------------- Lì xì, quà, ổ gà
  void _stepPickups(double dt) {
    _lixiTimer -= dt;
    if (_lixiTimer <= 0) {
      _lixiTimer = _between(GameConfig.lixiIntervalMin, GameConfig.lixiIntervalMax);
      _spawnLixiRow();
    }
    _potholeTimer -= dt;
    if (_potholeTimer <= 0) {
      _potholeTimer = _between(GameConfig.potholeIntervalMin, GameConfig.potholeIntervalMax);
      _spawnPothole();
    }
    _giftTimer -= dt;
    if (_giftTimer <= 0 && spec.kind != VehicleKind.bus) {
      _giftTimer = _between(GameConfig.giftIntervalMin, GameConfig.giftIntervalMax);
      _spawnGift();
    }

    final box = _playerBox;
    for (final (pickup, component) in _pickups) {
      if (pickup.consumed) continue;
      final hit = RoadBox(s: pickup.s, d: pickup.d, length: pickup.length, width: pickup.width).overlaps(box, shrink: 0.9);
      if (!hit) continue;
      pickup.consumed = true;
      component.removeFromParent();
      switch (pickup.kind) {
        case PickupKind.lixi:
          lixi++;
          onSound(GameSound.lixi);
        case PickupKind.gift:
          if (player.cargo < spec.cargoCapacity) {
            player.cargo++;
            onSound(GameSound.gift);
            onNotice(GameNotice('Nhặt được quà Tết! (${player.cargo}/${spec.cargoCapacity}) — xe nặng hơn'));
          } else {
            onNotice(const GameNotice('Xe đã chất đầy quà rồi!'));
          }
        case PickupKind.pothole:
          player.bump();
          onSound(GameSound.pothole);
          _shake = max(_shake, 0.18);
          // Xóc mạnh làm rơi một món quà (xe khách thì khách chỉ kêu ca).
          if (spec.kind == VehicleKind.bus) {
            onNotice(const GameNotice('Ổ gà! Khách trên xe kêu ầm lên', kind: NoticeKind.warning));
          } else if (player.cargo > 0) {
            player.cargo--;
            onNotice(const GameNotice('Ổ gà! Rơi mất 1 món quà', kind: NoticeKind.warning));
          }
      }
    }
    _pickups.removeWhere((item) {
      final (pickup, component) = item;
      if (!pickup.consumed && pickup.s > _camLeftS - 200) return false;
      component.removeFromParent();
      return true;
    });
  }

  double _between(double a, double b) => a + _random.nextDouble() * (b - a);

  bool _canPlace(double s, int lane) =>
      !layout.nearFeature(s, margin: 80) && traffic.isLaneClear(lane, s, 160) && !_pickups.any((p) => (p.$1.s - s).abs() < 100);

  /// Thường nằm ở làn chiều mình; thỉnh thoảng nằm bên làn ngược chiều để
  /// dụ người chơi lấn làn (trừ cao tốc).
  void _spawnLixiRow() {
    final s0 = _camRightS + 60;
    final oncomingOk = !layout.hasMedian(s0) && layout.kindAt(s0) != RoadKind.expressway;
    final lanes = oncomingOk && _random.nextDouble() > 0.75 ? Lanes.oncoming : Lanes.sameDirection;
    final lane = lanes[_random.nextInt(lanes.length)];
    final count = 1 + _random.nextInt(3);
    if (!_canPlace(s0 + 70.0 * count / 2, lane)) return;
    for (var i = 0; i < count; i++) {
      _addPickup(Pickup(kind: PickupKind.lixi, s: s0 + i * 70, d: Lanes.center(lane)), LixiComponent(Sprite(images.fromCache(Img.imgLixi))));
    }
  }

  void _spawnPothole() {
    final s0 = _camRightS + 60;
    if (layout.kindAt(s0) == RoadKind.expressway) return;
    final lane = Lanes.sameDirection[_random.nextInt(2)];
    if (!_canPlace(s0, lane)) return;
    final d = Lanes.center(lane) + (_random.nextDouble() - 0.5) * 16;
    final sprite = Sprite(images.fromCache(Img.potholes[_random.nextInt(Img.potholes.length)]));
    _addPickup(Pickup(kind: PickupKind.pothole, s: s0, d: d), PotholeComponent(sprite));
  }

  void _spawnGift() {
    final s0 = _camRightS + 60;
    final lane = Lanes.sameDirection[_random.nextInt(2)];
    if (!_canPlace(s0, lane)) return;
    final sprite = Sprite(images.fromCache(Img.cargo[_random.nextInt(Img.cargo.length)]));
    _addPickup(Pickup(kind: PickupKind.gift, s: s0, d: Lanes.center(lane)), GiftComponent(sprite));
  }

  void _addPickup(Pickup pickup, PositionComponent component) {
    placeOnRoad(component, road, pickup.s, pickup.d);
    world.add(component);
    _pickups.add((pickup, component));
  }

  // ------------------------------------------------------ Thông báo
  void _notice(String key, String text, NoticeKind kind) {
    if (_noticed.add(key)) onNotice(GameNotice(text, kind: kind));
  }

  /// Báo khi sắp vào đoạn đường loại khác.
  void _announceZone({bool force = false}) {
    final ahead = player.s + 700;
    final zone = layout.zoneAt(force ? player.s : ahead);
    final key = 'zone${zone.startS}';
    if (!force && (zone.startS < player.s || zone.startS > ahead)) return;
    switch (zone.kind) {
      case RoadKind.city:
        _notice(key, 'Vào phố — chú ý đèn đỏ ở ngã tư', NoticeKind.info);
      case RoadKind.highway:
        _notice(key, 'Ra quốc lộ — coi chừng xe ngược chiều, ổ gà', NoticeKind.info);
      case RoadKind.expressway:
        _notice(key, 'Lên cao tốc — về làn bên phải, có dải phân cách cứng', NoticeKind.warning);
    }
  }

  // -------------------------------------------------------- Kết thúc
  void _end(StageEndReason reason, {required double delay}) {
    if (phase == GamePhase.finished) return;
    phase = GamePhase.finished;
    _endReason = reason;
    _endDelay = delay;
    player.throttle = false;
    player.brake = false;
    onPhaseChanged(phase);
  }

  void _stepFinished(double dt) {
    if (_endReason == StageEndReason.arrived) {
      // Về đích thì xe chạy chậm dần qua vạch.
      player.speed = max(0, player.speed - 400 * dt);
      player.s += player.speed * dt;
    }
    _crashSpin = max(0, _crashSpin - dt * 5);
    if (_endReported) return;
    _endDelay -= dt;
    if (_endDelay > 0) return;
    _endReported = true;
    onFinished(StageResult(
      reason: _endReason!,
      lixi: lixi,
      cargo: player.cargo,
      clockMinutes: clock.minutes,
      minutesLeft: max(0, clock.minutesLeft),
    ));
  }

  // ---------------------------------------------------- Camera, hình
  void _updateCamera(double dt) {
    final w = _visibleWidth, h = _visibleHeight;
    final speedRatio = (player.speed / spec.maxSpeed).clamp(0.0, 1.0);
    final targetFraction =
        GameConfig.playerScreenXSlow + (GameConfig.playerScreenXFast - GameConfig.playerScreenXSlow) * speedRatio;
    _screenFraction += (targetFraction - _screenFraction) * (1 - exp(-2.5 * dt));
    final lead = (0.5 - _screenFraction) * w;

    // Camera xoay theo dây cung từ xe tới một điểm phía trước: đoạn đường từ
    // xe tới đó nằm ngang màn hình, khúc cua xa hơn uốn hẳn lên hoặc xuống.
    final p0 = road.at(player.s);
    final p1 = road.at(player.s + lead + GameConfig.cameraChordAhead);
    final targetAngle = atan2(p1.y - p0.y, p1.x - p0.x);
    if (!_cameraReady) {
      _camAngle = targetAngle;
    } else {
      _camAngle += _wrapAngle(targetAngle - _camAngle) * (1 - exp(-GameConfig.cameraTurnRate * dt));
    }
    final ux = cos(_camAngle), uy = sin(_camAngle);
    // Theo chiều ngang màn hình: xe ở đúng tỉ lệ đã chọn. Theo chiều dọc: tim
    // đường lệch lên trên để chừa chỗ dưới cùng cho cần lái và cụm nút.
    final tx = p0.x + ux * lead - uy * GameConfig.cameraRoadOffsetY;
    final ty = p0.y + uy * lead + ux * GameConfig.cameraRoadOffsetY;
    if (!_cameraReady) {
      _camX = tx;
      _camY = ty;
      _cameraReady = true;
    } else {
      final dx = tx - _camX, dy = ty - _camY;
      final along = dx * ux + dy * uy;
      final across = (-dx * uy + dy * ux) * (1 - exp(-4 * dt));
      _camX += ux * along - uy * across;
      _camY += uy * along + ux * across;
    }

    var shakeX = 0.0;
    var shakeY = 0.0;
    if (_shake > 0) {
      _shake = max(0, _shake - dt);
      final amp = 10 * _shake;
      shakeX = (_random.nextDouble() - 0.5) * 2 * amp;
      shakeY = (_random.nextDouble() - 0.5) * 2 * amp;
    }
    camera.viewfinder
      ..position = Vector2(_camX + shakeX, _camY + shakeY)
      ..angle = _camAngle;
    _updateVisibleRange(w, h);
  }

  static double _wrapAngle(double a) => (a + pi) % (2 * pi) - pi;

  /// Quãng s đang thấy trong khung nhìn (đã xoay): dò dọc đường về hai phía
  /// tới chỗ mặt đường ra khỏi khung.
  void _updateVisibleRange(double w, double h) {
    final ux = cos(_camAngle), uy = sin(_camAngle);
    const margin = GameConfig.roadHalfWidth + 60;
    bool inView(double s) {
      final p = road.at(s);
      final dx = p.x - _camX, dy = p.y - _camY;
      return (dx * ux + dy * uy).abs() < w / 2 + margin && (-dx * uy + dy * ux).abs() < h / 2 + margin;
    }

    const step = 24.0;
    var right = player.s, left = player.s;
    for (var s = player.s; s < player.s + 2 * w; s += step) {
      if (inView(s)) right = s;
    }
    for (var s = player.s; s > player.s - 1.5 * w; s -= step) {
      if (inView(s)) left = s;
    }
    _camLeftS = left;
    _camRightS = right;
  }

  void _syncVisuals() {
    final fromS = _camLeftS - 80, toS = _camRightS + 80;
    _roadRenderer
      ..fromS = fromS
      ..toS = toS;
    _featureGround
      ..fromS = fromS
      ..toS = toS;
    _busStops
      ..fromS = fromS
      ..toS = toS
      ..boarding = _boardingStop
      ..boardProgress = (_boardTimer / GameConfig.busBoardSeconds).clamp(0.0, 1.0)
      ..doorS = player.s + spec.length * 0.32
      ..doorD = player.d + spec.width / 2;
    _featureOverhead
      ..fromS = fromS
      ..toS = toS
      ..time = _time;
    _scenery.sync(_camLeftS, _camRightS);
    _powerLines.sync(_camLeftS, _camRightS, layout);

    final night = nightLevel;
    _trafficLayer
      ..lightsOn = night > 0.3
      ..sync();
    if (_cargoShown != player.cargo && spec.kind != VehicleKind.bus) {
      _cargoShown = player.cargo;
      _playerSprite.cargo = [
        for (var i = 0; i < min(player.cargo, 3); i++) Sprite(images.fromCache(Img.cargo[i % Img.cargo.length])),
      ];
    }
    _playerSprite
      ..braking = player.brake && player.speed > 1
      ..lightsOn = headlightsOn
      ..placeOn(road, player.s, player.d, yaw: player.yawOffset + _crashSpin * 0.25);
    if (_policeVisible) {
      _police.placeOn(road, _policeS, _policeD);
    } else {
      _police.placeOn(road, _camLeftS - 1000, 0);
    }
    _overtakeArrow.active = _overtakeWarn > 0;
    if (_overtakeArrow.active) _overtakeArrow.placeOn(road, _camLeftS + 60, Lanes.center(_overtakeLane));
    _syncNight(night);
  }

  /// Mức tối theo giờ trong ngày của đồng hồ chuyến đi (0 ngày .. 1 đêm).
  double get nightLevel {
    final t = clock.minutes % 1440;
    double ramp(double a, double b, double x) => ((x - a) / (b - a)).clamp(0.0, 1.0);
    if (t >= GameConfig.duskStart) return ramp(GameConfig.duskStart, GameConfig.duskEnd, t);
    if (t <= GameConfig.dawnEnd) return 1 - ramp(GameConfig.dawnStart, GameConfig.dawnEnd, t);
    return 0;
  }

  void _syncNight(double level) {
    _night.level = level;
    _night.lights.clear();
    if (level <= 0.01) return;
    final w = _visibleWidth, h = _visibleHeight;
    // Khung nhìn đã xoay: lấy hình chữ nhật thẳng bao ngoài.
    final c = cos(_camAngle).abs(), sn = sin(_camAngle).abs();
    _night.view = Rect.fromCenter(center: Offset(_camX, _camY), width: w * c + h * sn, height: w * sn + h * c);
    final p = road.at(player.s);
    final (px, py) = road.worldAt(player.s, player.d);
    final pos = Offset(px, py);
    final dir = p.heading + player.yawOffset;
    _night.lights.add(NightLight.round(pos, GameConfig.noHeadlightRadius, 0.9));
    if (headlightsOn) {
      final front = pos + Offset(cos(dir), sin(dir)) * spec.length * 0.45;
      _night.lights.add(NightLight.cone(front, dir, GameConfig.headlightReach, 0.32, 0.95));
    } else {
      _notice('headlights${(clock.minutes / 120).floor()}', 'Trời tối rồi — bấm nút Đèn để nhìn xa hơn!', NoticeKind.warning);
    }
    // Đèn xe khác: quầng sáng nhỏ + chùm ngắn phía trước.
    for (final v in traffic.vehicles) {
      final (x, y) = road.worldAt(v.s, v.d);
      final h0 = road.at(v.s).heading + (v.oncoming ? pi : 0);
      final c = Offset(x, y);
      _night.lights.add(NightLight.round(c, 70, 0.55));
      _night.lights.add(NightLight.cone(c + Offset(cos(h0), sin(h0)) * v.type.length * 0.45, h0, 260, 0.3, 0.7));
    }
    // Đèn đường ở phố, đèn trạm thu phí.
    for (var s = (_camLeftS / 180).floor() * 180.0; s < _camRightS + 180; s += 180) {
      if (layout.kindAt(s) != RoadKind.city) continue;
      for (final side in [-1.0, 1.0]) {
        final (x, y) = road.worldAt(s + (side > 0 ? 90 : 0), side * (GameConfig.roadHalfWidth + 10));
        _night.lights.add(NightLight.round(Offset(x, y), 150, 0.7));
      }
    }
    for (final g in _gates) {
      if (g.plaza.plazaEnd < _camLeftS || g.plaza.plazaStart > _camRightS) continue;
      final (x, y) = road.worldAt(g.plaza.s - 25, 0);
      _night.lights.add(NightLight.round(Offset(x, y), 260, 0.85));
    }
    for (final l in layout.lightsBetween(_camLeftS - 100, _camRightS + 100)) {
      final (x, y) = road.worldAt(l.s, 0);
      _night.lights.add(NightLight.round(Offset(x, y), 200, 0.75));
    }
  }

  LightHud? _nextLight() {
    final front = player.s + spec.length / 2;
    for (final l in layout.lightsBetween(front, front + 1600)) {
      if (l.stopLine < front - 2) continue;
      return LightHud(
        color: l.colorAt(_time),
        seconds: l.remainingAt(_time).ceil(),
        meters: ((l.stopLine - front) / GameConfig.unitsPerKm * 1000).round(),
      );
    }
    return null;
  }

  CurveHud? _curveHud() {
    final c = sharpCurveAhead;
    if (c == null) return null;
    final front = player.s + spec.length / 2;
    return CurveHud(
      right: c.right,
      meters: (max(0.0, c.startS - front) / GameConfig.unitsPerKm * 1000 / 10).round() * 10,
      adviseKmh: c.adviseKmh,
      tooFast: player.speed > c.adviseSpeed + 8,
    );
  }

  void _pushHud() {
    final hud = HudData(
      kmDone: ((player.s - _startS) / GameConfig.unitsPerKm).clamp(0, setup.lengthKm).floor(),
      kmTotal: setup.lengthKm.round(),
      speedKmh: (player.speed * GameConfig.displayKmhPerUnitSpeed).round(),
      clockLabel: clock.label,
      minutesLeft: max(0, clock.minutesLeft).floor(),
      lixi: lixi,
      cargo: player.cargo,
      danger: player.speed >= dangerSpeed || player.d < 0,
      light: _nextLight(),
      curve: _curveHud(),
      headlightsOn: headlightsOn,
      night: nightLevel > 0.3,
    );
    if (hud == _lastHud) return;
    _lastHud = hud;
    onHud(hud);
  }
}
