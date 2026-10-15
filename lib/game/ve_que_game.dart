import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../model/map_theme.dart';
import '../model/trip.dart';
import '../resource/app_resource.dart';
import 'components/animal_layer.dart';
import 'components/checkpoint_layer.dart';
import 'components/crew_layer.dart';
import 'components/effects_layer.dart';
import 'components/night_overlay.dart';
import 'components/pickups.dart';
import 'components/police_component.dart';
import 'components/rain_layer.dart';
import 'components/road_features.dart';
import 'components/road_renderer.dart';
import 'components/scenery_layer.dart';
import 'components/stall_layer.dart';
import 'components/traffic_layer.dart';
import 'components/vehicle_sprite.dart';
import 'components/world_paints.dart';
import 'driver/driver_art.dart';
import 'driver/driver_camera.dart';
import 'driver/ground_sink.dart';
import 'game_config.dart';
import 'logic/animals.dart';
import 'logic/chase.dart';
import 'logic/collision.dart';
import 'logic/cross_traffic.dart';
import 'logic/gas_chat.dart';
import 'logic/player_physics.dart';
import 'logic/road_layout.dart';
import 'logic/road_path.dart';
import 'logic/roadside.dart';
import 'logic/toll_gate.dart';
import 'logic/traffic_system.dart';
import 'logic/trip_clock.dart';
import 'logic/u_turn.dart';
import 'logic/vehicle_condition.dart';
import 'logic/weather.dart';
import 'stage.dart';
import 'vehicle_spec.dart';

part 'driver/driver_view.dart';

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
    this.onRest,
    this.onJob,
    this.fatigue = true,
  });

  final StageSetup setup;
  final void Function(HudData hud) onHud;
  final void Function(GamePhase phase) onPhaseChanged;
  final void Function(double progress, double timeLeft) onChase;
  final void Function(StageResult result) onFinished;
  final void Function(GameSound sound) onSound;
  final void Function(GameNotice notice) onNotice;

  /// Ghé quán: báo quán đang ghé (null khi đã lên đường).
  final void Function(StallVisit? visit)? onRest;

  /// Việc bên lề (thay lốp, chờ xăng, thợ vá) đang làm tới đâu; null khi xong.
  final void Function(JobState? job)? onJob;

  /// Có tính buồn ngủ, xăng, mưa, sự cố không (nền màn menu thì tắt).
  final bool fatigue;

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
    // Bản đồ đèo núi: quốc lộ thành đường đèo cua liên tục.
    styleAt: setup.theme == MapTheme.mountain
        ? (s) => layout.kindAt(s) == RoadKind.highway ? CurveStyle.mountain : layout.curveStyleAt(s)
        : layout.curveStyleAt,
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
  late final AnimalSystem animals = AnimalSystem(Random(setup.seed * 7 + 3));
  late double _animalTimer = 14 + _random.nextDouble() * 20;
  late final List<TollGate> _gates = [for (final t in layout.tolls) TollGate(t, setup.vehicle)];
  late final TripClock clock = TripClock(minutes: setup.startClockMinutes);
  late int lixi = setup.startLixi;

  late final FuelTank fuel = FuelTank(spec.kind, level: fatigue ? setup.startFuel : 1);
  late final Tires tires = Tires(spec.kind);
  late final Weather weather = fatigue
      ? Weather.forStage(
          random: Random(setup.seed * 271 + 11),
          south: setup.south,
          startMinutes: setup.startClockMinutes,
          expectedMinutes: setup.lengthKm * GameConfig.playSecondsPerKm * GameConfig.gameSecondsPerPlaySecond / 60,
        )
      : Weather.clear;

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
  late final StallLayer _stalls;
  late final Sprite _riderSprite;
  late final Sprite _parkedSprite;
  late final Sprite _raincoatSprite;
  late final Sprite _walkerSprite;
  late final Sprite _riderShadow;
  late final Sprite _parkedShadow;
  late final Sprite _raincoatShadow;
  late final CheckpointLayer _checkpoints;
  late final NailLayer _nailLayer;
  late final RainGroundLayer _rainGround;
  late final RainSkyLayer _rainSky;
  late final RainStreaks _rainStreaks;
  late final CrewLayer _crew;
  late final AnimalLayer _animalLayer;
  final GroundEffects _groundFx = GroundEffects();
  final AirEffects _airFx = AirEffects();
  final Fireworks _fireworks = Fireworks();
  final SpeechLayer _speech = SpeechLayer();

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

  // Quay đầu, đi ngược
  UTurn? _uTurn;

  /// Chỗ xa nhất đã tới theo chiều về quê (đi ngược tối đa
  /// [GameConfig.maxBacktrack] so với đây; đường, cảnh phía sau giữ lại).
  double _maxS = _startS;

  /// Chiều đang đi: 1 về quê, -1 sau khi quay đầu.
  int get dir => player.dir;

  double get _keepFromS => _maxS - GameConfig.maxBacktrack - 600;

  // Tỉnh táo, ngủ gật
  late double alert = fatigue ? GameConfig.alertStart : 100;
  double _sleepIn = 6;
  double _sleepLeft = 0;
  double _sleepTotal = 0;

  // Ghé quán
  Stall? _restStall;
  _RestStep _restStep = _RestStep.parking;
  double _restT = 0;
  List<String> _restChatter = const [];
  int _stallTips = 0;
  double _baseZoom = 1;
  double _zoomFactor = 1;

  // Xăng
  /// Hết xăng, xe máy dắt bộ.
  bool pushing = false;
  bool _tiltUsed = false;
  double _tiltT = 0;
  double _sputterLeft = 0;
  double _sputterIn = 1.2;

  // Lốp, đường ướt
  double _slipLeft = 0;
  double _puddleTimer = 2;
  final Set<String> _nailsChecked = {};

  // Mưa
  double _rain = 0;
  double _wet = 0;
  RainSpell? _spell;

  /// Xe máy: đã mặc áo mưa chưa, ướt bao nhiêu (0..1).
  bool raincoat = false;
  double soaked = 0;

  // Chốt CSGT
  /// Chốt đang vẫy xe mình vào, chiều đi lúc bị vẫy, lỗi bị ghi.
  Checkpoint? _wavedBy;
  int _wavedDir = 1;
  Violation? violation;
  final Set<String> _radarChecked = {};

  /// Quay đầu trong vùng cấm quanh chốt: quay xong là bị gọi vào.
  Checkpoint? _uTurnSeenBy;

  /// Quay đầu ở ngã tư có biển cấm: vài giây sau camera phạt nguội.
  double _coldFineIn = -1;

  // Việc bên lề: thay lốp, chờ xăng, thợ vá lưu động
  RoadsideJob? _job;
  double _jobT = 0;
  double _jobReported = -1;

  // Còi, đèn
  bool headlightsOn = false;

  /// Góc nhìn ghế lái (bật bằng nút trên HUD). Ghé quán, gặp công an, sửa
  /// xe… thì tạm về bản đồ nhìn từ trên cho dễ thấy.
  bool driverView = false;
  late final _DriverView _driver = _DriverView(this);
  bool _driverShown = false;

  /// Nhìn từ ghế lái thì thấy xa phía trước bấy nhiêu.
  static const double _driverReach = 3900;

  bool get _driverActive =>
      driverView && _driver.art != null && (phase == GamePhase.driving || phase == GamePhase.chase) && _job == null;

  /// Bật / tắt góc nhìn ghế lái; lần đầu bật thì nạp ảnh (trả về khi xong).
  Future<void> setDriverView(bool on) async {
    driverView = on;
    if (on && _driver.art == null) {
      _driver.art = await DriverArt.load(images, Img.traffic);
    }
  }
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
      ripeRice: setup.south || setup.theme == MapTheme.mekong,
      theme: setup.theme,
    );
    _featureGround = FeatureGroundLayer(road: road, layout: layout)..gates = _gates;
    _featureOverhead = FeatureOverheadLayer(road: road, layout: layout);
    _scenery = SceneryLayer(road: road, layout: layout, paints: _paints, random: Random(setup.seed * 13 + 5), theme: setup.theme);
    _powerLines = PowerLines(road: road);
    _trafficLayer = TrafficLayer(traffic: traffic, cross: cross, road: road);
    _riderSprite = Sprite(images.fromCache(Img.player(spec.kind)));
    _parkedSprite = spec.kind == VehicleKind.motorbike ? Sprite(images.fromCache(Img.imgScooterParked)) : _riderSprite;
    _raincoatSprite = spec.kind == VehicleKind.motorbike ? Sprite(images.fromCache(Img.imgScooterPlayerRaincoat)) : _riderSprite;
    _walkerSprite = Sprite(images.fromCache(spec.kind == VehicleKind.motorbike ? Img.imgDriverMoto : Img.imgDriverCar));
    _stalls = StallLayer(road: road, layout: layout, paints: _paints, images: images)..guestSprite = _walkerSprite;
    _checkpoints = CheckpointLayer(road: road, layout: layout, paints: _paints, images: images);
    _nailLayer = NailLayer(road: road, layout: layout);
    _rainGround = RainGroundLayer(road: road);
    _rainSky = RainSkyLayer();
    _rainStreaks = RainStreaks();
    _crew = CrewLayer(road: road, images: images);
    _animalLayer = AnimalLayer(road: road, animals: animals, images: images);
    _riderShadow = Sprite(images.fromCache(Img.playerShadow(spec.kind)));
    _parkedShadow = spec.kind == VehicleKind.motorbike ? Sprite(images.fromCache(Img.imgShadowScooterParked)) : _riderShadow;
    _raincoatShadow = spec.kind == VehicleKind.motorbike ? Sprite(images.fromCache(Img.imgShadowScooterRaincoat)) : _riderShadow;
    _playerSprite = VehicleSprite(
      sprite: _riderSprite,
      shadow: _riderShadow,
      width: spec.width * (spec.kind == VehicleKind.motorbike ? GameConfig.motorbikeVisualScale : 1),
      priority: 6,
      motorbike: spec.kind == VehicleKind.motorbike,
    );
    if (spec.kind == VehicleKind.motorbike) _playerSprite.fitMotorbike3d();
    _police = PoliceComponent(
      sprite: Sprite(images.fromCache(Img.imgScooterPolice)),
      shadow: Sprite(images.fromCache(Img.shadowOf(Img.imgScooterPolice))),
    )..fitMotorbike3d();
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
      _stalls,
      _featureGround,
      _nailLayer,
      _rainGround,
      _groundFx,
      _busStops,
      _animalLayer,
      _trafficLayer,
      _checkpoints,
      _playerSprite,
      _crew,
      _police,
      _featureOverhead,
      _powerLines,
      _overtakeArrow,
      _airFx,
      _rainSky,
      _night,
      _fireworks,
      _speech,
    ]);
    await camera.viewport.add(_rainStreaks);
    await add(_driver);
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
    _baseZoom = min(
      size.y / GameConfig.visibleWorldHeight,
      size.x / GameConfig.minVisibleWorldWidth,
    );
    camera.viewfinder.zoom = _baseZoom * _zoomFactor;
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
    final scared = animals.scare(player.s, dir, GameConfig.hornReach + 200);
    if (scared != null) {
      _notice('scare${scared.s.round()}', switch (scared.kind) {
        AnimalKind.duck => 'Bóp còi — đàn vịt nháo nhác vỗ cánh chạy!',
        AnimalKind.chicken => 'Bóp còi — gà hoảng hốt chạy toán loạn!',
        AnimalKind.dog => 'Bóp còi — con chó cụp đuôi chạy mất!',
      }, NoticeKind.info);
    }
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
      case GamePhase.resting:
        _stepResting(step);
      case GamePhase.chase:
        _stepDriving(step);
        if (phase == GamePhase.chase) _stepChase(step);
      case GamePhase.incident:
        _stepIncident(step);
      case GamePhase.finished:
        _stepFinished(step);
    }
    _updateCamera(step);
    final shown = _driverActive;
    if (shown != _driverShown) {
      _driverShown = shown;
      // Nhìn từ ghế lái thì không vẽ bản đồ phía sau cho nhẹ.
      camera.world = shown ? null : world;
    }
    if (shown) _driver.place(step);
    _stepEffects(step);
    _syncVisuals();
    _pushHud();
    super.update(step);
  }

  /// Hộp va chạm của xe mình (đang quay đầu thì thân xe nằm chéo ngang đường).
  RoadBox get _playerBox {
    final (length, width) = _uTurn?.boxSize(spec.length, spec.width) ?? (spec.length, spec.width);
    return RoadBox(s: player.s, d: player.d, length: length, width: width);
  }

  PlayerSnapshot get _snapshot {
    final box = _playerBox;
    return PlayerSnapshot(
      s: player.s,
      d: player.d,
      speed: player.speed,
      length: box.length,
      width: box.width,
      forward: (_uTurn?.dirFrom ?? dir) > 0,
      maneuvering: _uTurn != null,
    );
  }

  /// Đầu xe theo chiều đang đi.
  double get _front => player.s + dir * spec.length / 2;

  /// Mép khung nhìn phía trước / phía sau theo chiều đang đi.
  double get _aheadEdgeS => dir > 0 ? _camRightS : _camLeftS;
  double get _behindEdgeS => dir > 0 ? _camLeftS : _camRightS;

  /// Hai làn của chiều mình đang đi, hai làn của chiều kia.
  List<int> get _myLanes => dir > 0 ? Lanes.sameDirection : Lanes.oncoming;
  List<int> get _otherLanes => dir > 0 ? Lanes.oncoming : Lanes.sameDirection;

  void _stepDriving(double dt) {
    if (player.brake && !_skidPlayed && player.speed > 0.55 * GameConfig.normalSpeed) {
      _skidPlayed = true;
      onSound(GameSound.skid);
    } else if (!player.brake) {
      _skidPlayed = false;
    }
    _applyBounds();
    final prevFront = _front;
    final prevS = player.s;
    road.ensureAhead(player.s + GameConfig.curveWarnDistance + 1500);
    if (_uTurn != null) {
      _stepUTurn(dt);
    } else {
      player.curvature = road.at(player.s).curvature;
      _stepAlert(dt);
      _stepCondition(dt);
      player.update(dt);
    }
    _afterMove((player.s - prevS).abs());
    _limitBacktrack();
    clock.advance(dt);
    _stepWeather(dt);
    _stepCurves();
    _stepWorld(dt);
    _stepTolls(dt);
    _stepBusStops(dt);
    _stepOvertakes(dt);
    _stepPickups(dt);
    _stepAnimals(dt);
    _stepNails();
    _stepStallNotices();
    _stepServiceNotices();
    _announceZone();
    _stepColdFine(dt);

    // Va chạm: xe dọc đường, xe đường ngang, vật cản cố định.
    final hit = traffic.hit(_playerBox);
    if (hit != null) {
      _collide(relativeImpactSpeed(dir * player.speed, hit.velocity),
          headOn: hit.velocity * dir < 0, onMinor: () => traffic.remove(hit), stopOther: () => hit.speed = 0);
      return;
    }
    final crossHit = cross.hit(_playerBox);
    if (crossHit != null) {
      final rel = sqrt(player.speed * player.speed + crossHit.speed * crossHit.speed);
      _collide(rel, onMinor: () => cross.remove(crossHit), stopOther: () => crossHit.speed = 0);
      return;
    }
    final critter = _uTurn == null ? animals.hit(_playerBox) : null;
    if (critter != null) _hitAnimal(critter);
    if (_hitsObstacle()) {
      _collide(player.speed, onMinor: () {}, stopOther: () {}, backOff: true);
      return;
    }
    if (_uTurn == null && _ranRedLight(prevFront)) return;
    if (_caughtUTurn() || _stepCheckpoints(prevFront)) return;

    if (dir > 0 && player.s >= finishS) {
      _end(StageEndReason.arrived, delay: 0.6);
    } else if (clock.isOver) {
      player.stop();
      _end(StageEndReason.timeUp, delay: 0.4);
    }
    road.trimBefore(min(_camLeftS, _keepFromS) - 2400);
  }

  /// Dòng xe dọc đường và đường ngang vẫn chạy (cả lúc mình ngồi quán).
  void _stepWorld(double dt) {
    traffic.update(
      dt,
      _snapshot,
      spawnS: dir > 0 ? _camRightS + 150 : _camLeftS - 150,
      despawnBehindS: dir > 0 ? _camLeftS - 400 : _camLeftS - 2500,
      despawnAheadS: dir > 0 ? _camRightS + 2500 : _camRightS + 400,
      stops: _stopPoints(),
      profileAt: _profileAt,
      canSpawnAt: (s) => !layout.nearFeature(s, margin: 160),
      // Nhìn xa gấp mấy lần bản đồ thì cho đông xe tương ứng.
      capScale: _driverActive ? 3 : 1,
    );
    cross.update(dt, _time, layout.lightsBetween(_camLeftS - 300, _camRightS + 600), _playerBox);
    animals.update(dt);
  }

  /// Đi ngược quá xa so với chỗ xa nhất đã tới (hoặc lùi về quá điểm xuất
  /// phát) thì không cho đi tiếp.
  void _limitBacktrack() {
    _maxS = max(_maxS, player.s);
    final limit = max(_startS - 200, _maxS - GameConfig.maxBacktrack);
    if (dir > 0 || player.s >= limit) return;
    player
      ..s = limit
      ..stop();
    _notice('backtrack${_maxS.round()}', 'Quay lại xa quá rồi — quay đầu về quê thôi!', NoticeKind.warning);
  }

  /// Khúc cua gắt gần nhất phía trước theo chiều đang đi (hoặc đang ở trong):
  /// khúc cua, quãng còn tới đầu cua, cua phải hay trái theo chiều đi.
  ({RoadCurve curve, double ahead, bool right})? get sharpCurveAhead {
    final s = player.s;
    if (dir > 0) {
      for (final c in road.curvesBetween(s, s + GameConfig.curveWarnDistance)) {
        if (c.sharp) return (curve: c, ahead: c.startS - s, right: c.right);
      }
      return null;
    }
    RoadCurve? best;
    for (final c in road.curvesBetween(s - GameConfig.curveWarnDistance, s)) {
      if (c.sharp && (best == null || c.endS > best.endS)) best = c;
    }
    return best == null ? null : (curve: best, ahead: s - best.endS, right: !best.right);
  }

  /// Báo trước cua gắt; vào cua nhanh quá bị văng tì mép đường thì rung, rít lốp.
  void _stepCurves() {
    final c = sharpCurveAhead;
    if (c != null && c.ahead > spec.length) {
      _notice(
        'curve${c.curve.startS.round()}/$dir',
        'Sắp vào cua gắt bên ${c.right ? 'phải' : 'trái'} — giảm tốc dưới ${c.curve.adviseKmh} km/h, bẻ lái giữ làn!',
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

  // ---------------------------------------------------- Tỉnh táo
  /// Lái lâu thì buồn ngủ (ban đêm nhanh hơn); dưới mức báo động thì thỉnh
  /// thoảng ngủ gật: mắt nhắm, tay lái không ăn, xe tự dạt khỏi làn.
  void _stepAlert(double dt) {
    if (!fatigue) return;
    if (player.speed > 20) {
      final night = nightLevel > 0.5 ? GameConfig.alertNightFactor : 1.0;
      // Ướt sũng, lạnh run thì mau mệt.
      final cold = 1 + (GameConfig.soakAlertFactor - 1) * soaked;
      final before = alert;
      alert = max(0, alert - GameConfig.alertDecayPerSecond * night * cold * dt);
      if (before >= GameConfig.alertDrowsy && alert < GameConfig.alertDrowsy) {
        onNotice(const GameNotice('Bắt đầu buồn ngủ rồi… Ghé quán ven đường uống cốc trà đá đi!', kind: NoticeKind.warning));
      }
    }
    if (_sleepLeft > 0) {
      _sleepLeft -= dt;
      if (_sleepLeft <= 0) {
        player.asleep = false;
        _notice('nod${(clock.minutes / 15).floor()}', 'Suýt ngủ gật! Nguy hiểm lắm — ghé quán nghỉ một lát đi', NoticeKind.warning);
      }
      return;
    }
    if (alert >= GameConfig.alertMicrosleep || player.speed < 30) return;
    _sleepIn -= dt;
    if (_sleepIn > 0) return;
    final k = (alert / GameConfig.alertMicrosleep).clamp(0.0, 1.0);
    _sleepIn = (GameConfig.microsleepGapMin + (GameConfig.microsleepGapMax - GameConfig.microsleepGapMin) * k) * (0.7 + 0.6 * _random.nextDouble());
    _sleepTotal = GameConfig.microsleepSeconds * (alert < GameConfig.alertSevere ? 1.5 : 1);
    _sleepLeft = _sleepTotal;
    player
      ..asleep = true
      ..sleepDrift = (_random.nextBool() ? 1 : -1) * GameConfig.microsleepDrift;
  }

  /// Độ díp mắt 0..1 cho HUD: đang gật thì nhắm hẳn, buồn ngủ thì mép tối dần.
  double get _drowse {
    if (_sleepLeft > 0) {
      final done = _sleepTotal - _sleepLeft;
      return min(1.0, min(done, _sleepLeft) / 0.15);
    }
    return ((GameConfig.alertDrowsy - alert) / GameConfig.alertDrowsy).clamp(0.0, 1.0) * 0.45;
  }

  // ------------------------------------------------ Xăng, lốp, đường ướt
  /// Tình trạng xe trước khi tính chuyển động: đường ướt bám kém, hết xăng /
  /// khục khặc thì mất ga, lốp xẹp chạy chậm và kéo lệch, trượt nước.
  void _stepCondition(double dt) {
    player.grip = 1 - (1 - GameConfig.wetGrip) * _wet;
    if (fuel.empty) {
      player.engineOff = !pushing;
      // Máy tắt: xe trôi tới đâu thì mức ga về tới đó (dắt bộ phải bấm Ga lại).
      if (!pushing) player.cruise = min(player.cruise, player.speed);
    } else if (fuel.sputtering && player.cruise > 1) {
      if (_sputterLeft > 0) {
        _sputterLeft -= dt;
      } else {
        _sputterIn -= dt;
        if (_sputterIn <= 0) {
          _sputterLeft = 0.25 + _random.nextDouble() * 0.35;
          _sputterIn = 0.8 + _random.nextDouble() * 1.6;
          onSound(GameSound.sputter);
        }
      }
      player.engineOff = _sputterLeft > 0;
    } else {
      _sputterLeft = 0;
      player.engineOff = false;
    }
    player.speedCap = pushing ? GameConfig.pushSpeed : tires.speedCap;
    // Lạnh run: tay lái run run.
    final shiver = soaked > 0.6 ? sin(_time * 21) * 9 * soaked : 0.0;
    player.pull = pushing ? 0 : tires.pull + shiver;
    if (_slipLeft > 0) _slipLeft -= dt;
    player.slipping = _slipLeft > 0;
    _tiltT = max(0, _tiltT - dt);
  }

  /// Xe vừa đi thêm [moved]: tốn xăng, chạy lốp xẹp thì mòn săm.
  void _afterMove(double moved) {
    if (!fatigue) return;
    final before = fuel.level;
    if (!pushing) fuel.burn(moved, player.speed, player.cargo);
    if (before >= GameConfig.fuelLow && fuel.low) {
      onSound(GameSound.sputter);
      onNotice(GameNotice('Đèn báo xăng sáng — còn chừng ${fuel.kmLeft.round()} km, tìm cây xăng đổ thôi!', kind: NoticeKind.warning));
    }
    if (before > 0 && fuel.empty) {
      onSound(GameSound.sputter);
      onNotice(GameNotice(
        spec.kind == VehicleKind.motorbike
            ? 'Hết sạch xăng! Nghiêng xe dồn xăng, dắt bộ tới chỗ bán xăng hoặc gọi người mang tới'
            : 'Hết sạch xăng! Tấp vào lề gọi cứu hộ mang xăng tới',
        kind: NoticeKind.warning,
      ));
    }
    if (pushing && !fuel.empty) pushing = false;
    if (tires.roll(moved)) {
      onNotice(GameNotice(
        spec.kind == VehicleKind.motorbike
            ? 'Chạy lốp xẹp xa quá — nát săm rồi, phải thay săm mới!'
            : 'Chạy lốp xẹp xa quá — nát lốp rồi, phải thay lốp!',
        kind: NoticeKind.warning,
      ));
    }
  }

  /// Xì lốp: rít hơi, xe khựng, báo tìm tiệm vá.
  void _puncture(String cause, {bool nails = false}) {
    tires.puncture(_random);
    _flatFromNails = nails;
    onSound(GameSound.tireHiss);
    _shake = max(_shake, 0.25);
    final spare = spec.kind.fourWheels && tires.spare;
    onNotice(GameNotice(
      '$cause Chạy chậm tìm tiệm vá xe${spare ? ', hoặc tấp lề thay lốp dự phòng' : ''}',
      kind: NoticeKind.warning,
    ));
  }

  /// Cán qua bãi đinh tặc: lốp xì (tuỳ xe), mỗi bãi xét một lần mỗi chiều.
  void _stepNails() {
    if (!fatigue || _uTurn != null) return;
    final box = _playerBox;
    for (final n in layout.nailsBetween(player.s - 160, player.s + 160)) {
      final patch = RoadBox(s: n.s, d: Lanes.center(n.lane), length: NailPatch.length, width: NailPatch.width);
      if (!patch.overlaps(box, shrink: 0.9) || player.speed < 5) continue;
      if (!_nailsChecked.add('${n.seed}/$dir')) continue;
      if (tires.ok && _random.nextDouble() < tires.flatChanceOnNails) {
        _puncture('Cán phải đinh tặc — xì lốp rồi!', nails: true);
      } else if (tires.ok) {
        onNotice(const GameNotice('Lạo xạo… cán qua bãi đinh. May quá, lốp chưa sao!', kind: NoticeKind.warning));
      }
    }
  }

  /// Mưa đến, mưa tạnh; xe máy không áo mưa thì ướt dần.
  void _stepWeather(double dt) {
    final m = clock.minutes;
    _rain = weather.rainAt(m);
    _wet = weather.wetAt(m);
    final spell = weather.spellAt(m);
    if (spell != null && _rain > 0.08 && !identical(spell, _spell)) {
      _spell = spell;
      final moto = spec.kind == VehicleKind.motorbike && !raincoat;
      onNotice(GameNotice(
        spell.kind == RainKind.shower
            ? 'Mưa rào nặng hạt! Đường trơn, phanh sớm, tránh vũng nước${moto ? ' — ghé quán mua áo mưa' : ''}'
            : 'Trời đổ mưa phùn, đường ướt trơn — giảm tốc${moto ? ', ghé quán mua áo mưa' : ''}',
        kind: NoticeKind.warning,
      ));
    } else if (spell == null && _spell != null && _rain <= 0) {
      _spell = null;
      onNotice(const GameNotice('Tạnh mưa rồi — đường còn ướt một lúc, vẫn phải đi cẩn thận'));
    }
    final exposed = spec.kind == VehicleKind.motorbike && !raincoat && phase == GamePhase.driving;
    final before = soaked;
    if (exposed && _rain > 0.1) {
      soaked = min(1, soaked + GameConfig.soakPerSecond * _rain * dt);
    } else {
      soaked = max(0, soaked - 0.012 * dt);
    }
    if (before < 0.6 && soaked >= 0.6) {
      onNotice(const GameNotice('Ướt sũng, lạnh run cầm cập… mau mệt lắm — mua áo mưa đi!', kind: NoticeKind.warning));
    }
  }

  /// Báo chỗ đổ xăng / vá xe gần nhất khi cần.
  void _stepServiceNotices() {
    if (_uTurn != null) return;
    if (fuel.low && !fuel.empty) {
      final next = _nextService((t) => t.kind.sellsFuel && (t.kind == StallKind.xang || spec.kind == VehicleKind.motorbike));
      if (next != null && next.$2 < 900) {
        _notice('fuelstop${next.$1.seed}/$dir', '${next.$1.kind.title} ${next.$1.side == dir ? 'bên phải' : 'bên kia đường'} phía trước — tấp vào đổ xăng', NoticeKind.info);
      }
    }
    if (!tires.ok) {
      final next = _nextService((t) => t.kind.fixesTires);
      if (next != null && next.$2 < 900) {
        _notice('tirestop${next.$1.seed}/$dir', 'Tiệm vá xe ${next.$1.side == dir ? 'bên phải' : 'bên kia đường'} phía trước — dừng sát lề để vá', NoticeKind.info);
      }
    }
  }

  /// Quán gần nhất phía trước theo chiều đi thoả [test]: quán, quãng còn lại.
  (Stall, double)? _nextService(bool Function(Stall t) test) {
    final s = player.s;
    final range = 40 * GameConfig.unitsPerKm;
    final candidates = dir > 0 ? layout.stallsBetween(s - 60, s + range) : layout.stallsBetween(s - range, s + 60).toList().reversed;
    for (final t in candidates) {
      if (test(t)) return (t, max(0.0, dir * (t.s - s)));
    }
    return null;
  }

  String? _serviceLabel(bool Function(Stall t) test) {
    final next = _nextService(test);
    // Đang đứng ngay trước quán thì nút Ghé quán đã đủ, không cần nhắc nữa.
    if (next == null || next.$2 < 60) return null;
    final km = next.$2 / GameConfig.unitsPerKm;
    final distance = km < 1 ? '${(km * 1000 / 50).round() * 50} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${next.$1.kind.title} $distance';
  }

  // ------------------------------------------------- Hết xăng, việc bên lề
  bool get _stopped => player.speed < 8 && _uTurn == null && phase == GamePhase.driving;

  /// Nghiêng xe cho xăng dồn sang bình (mẹo quen của dân đi xe máy).
  void tiltBike() {
    if (!_stopped || !fuel.empty || spec.kind != VehicleKind.motorbike || _tiltUsed) return;
    _tiltUsed = true;
    _tiltT = 0.9;
    fuel.add(GameConfig.fuelTilt);
    pushing = false;
    onNotice(GameNotice('Nghiêng xe dồn xăng — đủ chạy thêm chừng ${fuel.kmLeft.round()} km nữa, tìm chỗ đổ ngay!', kind: NoticeKind.money));
  }

  /// Xuống dắt bộ xe máy hết xăng.
  void startPushing() {
    if (!_stopped || !fuel.empty || spec.kind != VehicleKind.motorbike || pushing) return;
    pushing = true;
    final where = _serviceLabel((t) => t.kind.sellsFuel);
    onNotice(GameNotice('Dắt bộ — giữ Ga để đẩy xe${where == null ? '' : '. $where'}'));
  }

  /// Gọi người mang xăng tới (xe máy) / gọi cứu hộ (ô tô, xe khách).
  void callFuel() {
    if (!fuel.empty || player.speed > 8 || phase != GamePhase.driving || _uTurn != null) return;
    final moto = spec.kind == VehicleKind.motorbike;
    _startJob(RoadsideJob(
      kind: RoadsideJobKind.fuelDelivery,
      title: moto ? 'Gọi người mang xăng tới' : 'Gọi cứu hộ mang xăng',
      steps: moto
          ? const ['Gọi điện nhờ xe ôm đầu làng', 'Chờ xe chở can xăng tới', 'Đổ xăng vào bình, trả tiền']
          : const ['Bật đèn khẩn cấp', 'Đặt biển cảnh báo sau xe', 'Chờ xe cứu hộ tới', 'Đổ can xăng vào bình'],
      minutes: moto ? GameConfig.fuelRescueMinutesMotorbike : GameConfig.fuelRescueMinutesCar,
      lixi: switch (spec.kind) {
        VehicleKind.motorbike => GameConfig.fuelRescueLixiMotorbike,
        VehicleKind.car => GameConfig.fuelRescueLixiCar,
        VehicleKind.bus => GameConfig.fuelRescueLixiBus,
      },
    ));
  }

  /// Thay lốp dự phòng bên lề (ô tô, xe khách): phải tấp sát lề phải.
  void changeSpare() {
    if (!_stopped || tires.ok || !spec.kind.fourWheels || !tires.spare) return;
    if (dir * player.d < player.maxOffset - 40) {
      onNotice(const GameNotice('Tấp sát lề phải rồi hãy thay lốp — đứng giữa đường nguy hiểm lắm', kind: NoticeKind.warning));
      return;
    }
    _startJob(RoadsideJob(
      kind: RoadsideJobKind.spareTire,
      title: 'Thay lốp dự phòng',
      steps: const ['Bật đèn khẩn cấp', 'Đặt biển cảnh báo sau xe', 'Kích xe, tháo lốp xẹp', 'Lắp lốp dự phòng, siết ốc'],
      minutes: spec.kind == VehicleKind.bus ? GameConfig.spareMinutesBus : GameConfig.spareMinutesCar,
    ));
  }

  /// Gọi thợ vá xe lưu động tới tận nơi.
  void callMechanic() {
    if (!_stopped || tires.ok) return;
    _startJob(const RoadsideJob(
      kind: RoadsideJobKind.mobileRepair,
      title: 'Gọi thợ vá xe lưu động',
      steps: ['Gọi số điện thoại dán trên cột điện', 'Chờ thợ chạy xe tới', 'Tháo bánh, vá săm, bơm căng'],
      minutes: GameConfig.mobileRepairMinutes,
      lixi: GameConfig.mobileRepairLixi,
    ));
  }

  /// Bắt đầu một việc bên lề: dừng hẳn, trả tiền, tốn phút; việc chạy vài giây
  /// cho thấy từng bước rồi lên đường tiếp.
  void _startJob(RoadsideJob job) {
    phase = GamePhase.resting;
    player
      ..stop()
      ..throttle = false
      ..brake = false
      ..steer = 0
      ..asleep = false;
    _sleepLeft = 0;
    pushing = false;
    _job = job;
    _jobT = 0;
    _jobReported = -1;
    if (job.lixi > 0) {
      if (lixi >= job.lixi) {
        lixi -= job.lixi;
        onSound(GameSound.toll);
      } else {
        // Không đủ tiền: đưa hết, năn nỉ người ta chờ thêm.
        lixi = 0;
        clock.addPenalty(10);
        onNotice(const GameNotice('Không đủ lì xì — đưa hết, năn nỉ mãi người ta mới chịu', kind: NoticeKind.warning));
      }
    }
    clock.addPenalty(job.minutes);
    onPhaseChanged(phase);
    onJob?.call(JobState(job, 0));
  }

  double get _jobSeconds => switch (_job?.kind) {
        RoadsideJobKind.spareTire => spec.kind == VehicleKind.bus ? 5.5 : 4.5,
        // Thợ chạy tới, vừa sửa vừa nói chuyện với mình.
        RoadsideJobKind.mobileRepair => 12,
        RoadsideJobKind.fuelDelivery => 6.5,
        _ => 4.2,
      };

  /// Tiến độ cho thẻ việc: có người tới giúp thì ba bước khớp thực tế — gọi
  /// điện, chờ người tới (tới lúc xe đỗ), làm việc tới hết.
  double get _jobProgress {
    final total = _jobSeconds;
    if (_job?.kind == RoadsideJobKind.spareTire || (_job?.steps.length ?? 0) != 3) return (_jobT / total).clamp(0.0, 1.0);
    if (_jobT < 0.6) return _jobT / 0.6 / 3;
    if (_jobT < _helperArrive) return 1 / 3 + (_jobT - 0.6) / (_helperArrive - 0.6) / 3;
    return (2 / 3 + (_jobT - _helperArrive) / (total - _helperArrive) / 3).clamp(0.0, 1.0);
  }

  void _stepJob(double dt) {
    final job = _job!;
    final before = _jobT;
    _jobT += dt;
    _stepWorld(dt);
    if (before < _helperArrive && _jobT >= _helperArrive) _helperArrived(job);
    if (job.kind == RoadsideJobKind.mobileRepair && _jobT >= _helperArrive) {
      final (s, d) = _wheelSpot;
      _repairFx(dt, _talkT, s, d, patch: (3.0, 6.0), pump: (6.3, 7.6));
    }
    final progress = _jobProgress;
    if (progress - _jobReported >= 0.02 || progress >= 1) {
      _jobReported = progress;
      onJob?.call(JobState(job, progress));
    }
    if (progress < 1) return;
    switch (job.kind) {
      case RoadsideJobKind.fuelDelivery:
        fuel.add(GameConfig.fuelRescue);
        _tiltUsed = false;
        onNotice(GameNotice('Đổ được một can xăng — chạy thêm chừng ${fuel.kmLeft.round()} km, ghé cây xăng đổ đầy nhé', kind: NoticeKind.money));
      case RoadsideJobKind.spareTire:
        tires
          ..fix()
          ..spare = false;
        onNotice(const GameNotice('Đã lắp lốp dự phòng — hết lốp dự phòng rồi, đi cẩn thận!', kind: NoticeKind.money));
      case RoadsideJobKind.mobileRepair:
        tires.fix();
        onNotice(const GameNotice('Thợ vá xong — lốp căng rồi, lên đường thôi!', kind: NoticeKind.money));
    }
    _job = null;
    phase = GamePhase.driving;
    onJob?.call(null);
    onPhaseChanged(phase);
    if (clock.isOver) _end(StageEndReason.timeUp, delay: 0.4);
  }

  // ------------------------------------------------------------ CSGT
  /// Qua chốt: súng bắn tốc độ đo xe đang tới; quá tốc độ thì CSGT vẫy vào.
  /// Bị vẫy mà không dừng thì CSGT đuổi theo. Trả về true nếu đổi pha.
  bool _stepCheckpoints(double prevFront) {
    if (!fatigue || phase != GamePhase.driving) return false;
    final front = _front;
    for (final c in layout.checkpointsBetween(player.s - 1500, player.s + 1500)) {
      final sign = dir > 0 ? c.signS : c.oncomingSignS;
      final toSign = dir * (sign - player.s);
      if (toSign > 0 && toSign < 600) {
        _notice('cp${c.seed}/$dir', 'Chốt CSGT phía trước — tốc độ tối đa ${c.limitKmh} km/h, cấm quay đầu!', NoticeKind.warning);
      }
      final radar = c.radarS(dir);
      final crossed = dir > 0 ? prevFront < radar && front >= radar : prevFront > radar && front <= radar;
      if (!crossed || _wavedBy != null || !_radarChecked.add('${c.seed}/$dir')) continue;
      final kmh = (player.speed * GameConfig.displayKmhPerUnitSpeed).round();
      if (kmh > c.limitKmh + GameConfig.speedTolerance) {
        _wavedBy = c;
        _wavedDir = dir;
        violation = Violation(IncidentKind.speeding, measuredKmh: kmh, limitKmh: c.limitKmh, place: _placeName());
        onSound(GameSound.whistle);
        onNotice(GameNotice('Toét toét! Súng bắn tốc độ: $kmh/${c.limitKmh} km/h — CSGT vẫy vào, tấp lề dừng xe!', kind: NoticeKind.warning));
      }
    }
    final w = _wavedBy;
    if (w == null) return false;
    final past = _wavedDir * (player.s - w.radarS(_wavedDir));
    if (dir == _wavedDir && player.speed < 15 && past < GameConfig.pullOverReach) {
      _wavedBy = null;
      incidentKind = IncidentKind.speeding;
      player.stop();
      _startIncident();
      return true;
    }
    if (dir != _wavedDir || past > GameConfig.pullOverReach) {
      _wavedBy = null;
      onSound(GameSound.whistle);
      onNotice(const GameNotice('Không dừng xe — CSGT nổ máy đuổi theo!', kind: NoticeKind.warning));
      incidentKind = IncidentKind.speeding;
      _policeVisible = true;
      _policeS = _behindEdgeS - dir * 120;
      _policeD = player.d;
      _startChase();
      return true;
    }
    return false;
  }

  /// Quay đầu ở ngã tư có biển cấm: vài giây sau báo bị camera phạt nguội.
  void _stepColdFine(double dt) {
    if (_coldFineIn < 0) return;
    _coldFineIn -= dt;
    if (_coldFineIn >= 0) return;
    final fine = min(lixi, GameConfig.coldFineLixi);
    lixi -= fine;
    onSound(GameSound.toll);
    onNotice(GameNotice('Camera phạt nguội: quay đầu nơi có biển cấm — trừ $fine lì xì', kind: NoticeKind.warning));
  }

  /// Tên chỗ ghi vào biên bản: quốc lộ / phố, km thứ mấy của chặng.
  String _placeName() {
    final km = ((player.s - _startS) / GameConfig.unitsPerKm).round();
    return '${layout.kindAt(player.s) == RoadKind.city ? 'Phố' : 'Quốc lộ'}, km $km đoạn ${setup.fromName} – ${setup.toName}';
  }

  // ------------------------------------------------------- Quay đầu
  /// Đủ chậm, không ở cao tốc (dải phân cách), không trong trạm thu phí.
  bool get canUTurn =>
      phase == GamePhase.driving &&
      _uTurn == null &&
      _wavedBy == null &&
      (!fuel.empty || pushing) &&
      player.speed <= GameConfig.uTurnMaxSpeed &&
      layout.kindAt(player.s) != RoadKind.expressway &&
      layout.tollAt(player.s) == null;

  /// Quay đầu xe (luôn quay về bên trái). Xe khách chỉ quay ở ngã tư; ô tô
  /// phải tấp sát lề phải mới đủ chỗ.
  void uTurn() {
    if (!canUTurn) return;
    final light = layout.lights.where((l) => (l.s - player.s).abs() < l.halfWidth + 40).firstOrNull;
    final junction = light != null;
    if (spec.kind == VehicleKind.bus && !junction) {
      onNotice(const GameNotice('Xe khách dài quá — chỉ quay đầu được ở ngã tư', kind: NoticeKind.warning));
      return;
    }
    final edge = player.maxOffset;
    var minRadius = UTurn.minRadius(spec.kind);
    // Ở ngã tư có thêm chỗ của đường ngang để xe dài lượn qua.
    if (junction) minRadius = min(minRadius, (dir * player.d + edge) / 2);
    final radius = UTurn.plan(d: player.d, dir: dir, minRadius: minRadius, lo: -edge, hi: edge);
    if (radius == null) {
      onNotice(const GameNotice('Chưa đủ chỗ — tấp sát lề phải rồi hãy quay đầu', kind: NoticeKind.warning));
      return;
    }
    _uTurn = UTurn(s0: player.s, d0: player.d, dirFrom: dir, radius: radius, duration: UTurn.seconds(spec.kind));
    player
      ..throttle = false
      ..brake = false
      ..lateralVelocity = 0;
    onNotice(GameNotice(dir > 0 ? 'Quay đầu xe — đi ngược lại một đoạn' : 'Quay đầu — về quê thôi!'));
    // Quay đầu ngay trước mặt chốt CSGT / ở ngã tư có biển cấm.
    if (fatigue) {
      _uTurnSeenBy = layout.checkpointNear(player.s);
      if (light != null && light.noUTurn) _coldFineIn = 3.5;
    }
  }

  void _stepUTurn(double dt) {
    final u = _uTurn!..update(dt);
    player
      ..s = u.s
      ..d = u.d
      ..speed = u.speed;
    if (u.done) _finishUTurn();
  }

  /// Vừa quay đầu xong trong vùng cấm quanh chốt: CSGT gọi vào.
  bool _caughtUTurn() {
    final c = _uTurnSeenBy;
    if (c == null || _uTurn != null || phase != GamePhase.driving) return false;
    _uTurnSeenBy = null;
    incidentKind = IncidentKind.illegalUTurn;
    violation = Violation(IncidentKind.illegalUTurn, place: _placeName());
    onSound(GameSound.whistle);
    player.stop();
    _startIncident();
    return true;
  }

  /// Xong cú quay đầu (hoặc bị đâm giữa chừng): đổi chiều nếu đã quay quá nửa.
  void _finishUTurn() {
    final u = _uTurn;
    if (u == null) return;
    _uTurn = null;
    if (u.theta > pi / 2) {
      player.dir = -u.dirFrom;
      _lightsPassed.clear();
    } else {
      _uTurnSeenBy = null;
    }
    player
      ..d = player.d.clamp(-player.maxOffset, player.maxOffset)
      ..speed = u.done ? 20 : 0
      ..cruise = u.done ? 20 : 0
      ..lateralVelocity = 0;
  }

  // ------------------------------------------------------ Quán ven đường
  /// Quán mình đang dừng sát lề ngay trước mặt (ghé được), null nếu không.
  /// Xăng lẻ chỉ bán cho xe máy.
  Stall? get stallHere {
    if (phase != GamePhase.driving || _uTurn != null) return null;
    if (player.speed > GameConfig.stallStopSpeed) return null;
    if (dir * player.d < player.maxOffset - 34) return null;
    for (final t in layout.stallsBetween(player.s - GameConfig.stallStopWindow - 40, player.s + GameConfig.stallStopWindow + 40)) {
      if (t.side != dir || (t.s - player.s).abs() > t.halfLength + 10) continue;
      if (t.kind == StallKind.xangLe && spec.kind != VehicleKind.motorbike) continue;
      return t;
    }
    return null;
  }

  /// Báo có quán phía trước (lúc buồn ngủ, hoặc vài quán đầu cho biết).
  void _stepStallNotices() {
    if (_uTurn != null) return;
    final a = player.s + dir * 150, b = player.s + dir * 700;
    for (final t in layout.stallsBetween(min(a, b), max(a, b))) {
      if (!t.kind.food) continue;
      final mine = t.side == dir;
      if (!(alert < 60 || _stallTips < 2) || (!mine && alert >= 50)) continue;
      if (_notice(
        'stall${t.seed}/$dir',
        mine ? '${t.kind.title} bên phải phía trước — tấp sát lề, dừng hẳn để ghé' : '${t.kind.title} bên kia đường — muốn ghé thì quay đầu',
        NoticeKind.info,
      )) {
        _stallTips++;
      }
    }
  }

  /// Ghé quán: tấp xe vào lề (cây xăng thì chạy vào cạnh cột bơm), quán nước
  /// và tiệm vá xe thì xuống xe đi vào ghế ngồi; cây xăng, xăng lẻ thì người
  /// bán ra tận xe.
  void stopAtStall() {
    final stall = stallHere;
    if (stall == null) return;
    phase = GamePhase.resting;
    player
      ..stop()
      ..throttle = false
      ..brake = false
      ..steer = 0
      ..asleep = false;
    _sleepLeft = 0;
    pushing = false;
    _restStall = stall;
    _restStep = _RestStep.parking;
    _restT = 0;
    _parkFrom = (player.s, player.d);
    final plan = _stalls.planOf(stall);
    if (stall.kind == StallKind.xang) {
      final local = plan.bayFor(stall.side * (player.s - stall.s));
      _parkTo = plan.toRoad(local);
    } else {
      _parkTo = (player.s + dir * 30, stall.side * (GameConfig.roadHalfWidth + spec.width / 2 - 4));
    }
    _restChatter = _chatter(stall);
    clock.addPenalty(GameConfig.stallBaseMinutes);
    onPhaseChanged(phase);
    onRest?.call(StallVisit(stall: stall, chatter: _restChatter, seated: false));
  }

  /// Ngồi xong / được phục vụ rồi thì mới gọi được món, đổ xăng, vá xe.
  bool get _served => phase == GamePhase.resting && _restStep == _RestStep.seated && _restStall != null;

  /// Gọi một món: trả lì xì, tỉnh táo lại, mất thêm ít phút.
  void order(StallItem item) {
    if (!_served) return;
    if (lixi < item.price) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return;
    }
    lixi -= item.price;
    alert = min(100, alert + item.alert);
    clock.addPenalty(item.minutes);
    onSound(item.price > 0 ? GameSound.toll : GameSound.gift);
    onNotice(GameNotice(
      '${item.name}${item.price > 0 ? ' (−${item.price} lì xì)' : ''} · tỉnh táo +${item.alert.round()} · ${item.minutes.round()} phút',
      kind: NoticeKind.money,
    ));
    if (clock.isOver) leaveStall();
  }

  /// Đổ xăng ở cây xăng: [lixiSpent] lì xì (null = đổ đầy bình). Trả về phần
  /// bình vừa đổ thêm (để bảng cột bơm chạy số).
  double refuel({int? lixiSpent}) {
    final stall = _restStall;
    if (!_served || stall?.kind != StallKind.xang) return 0;
    final price = lixiSpent ?? fuel.fullPrice;
    if (price <= 0) return 0;
    if (lixi < price) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return 0;
    }
    final added = fuel.add(lixiSpent == null ? 1 : price * fuel.perLixi);
    if (added <= 0) return 0;
    lixi -= price;
    _afterRefuel(added, minutes: 2 + added * 4);
    return added;
  }

  /// Mua một chai xăng lẻ (xe máy).
  double buyBottle() {
    if (!_served || _restStall?.kind != StallKind.xangLe || fuel.level >= 0.99) return 0;
    if (lixi < 1) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return 0;
    }
    final added = fuel.add(GameConfig.fuelBottle);
    lixi -= 1;
    _afterRefuel(added, minutes: 2);
    return added;
  }

  void _afterRefuel(double added, {required double minutes}) {
    clock.addPenalty(minutes);
    _tiltUsed = false;
    onSound(GameSound.fuelPump);
    onNotice(GameNotice('Đổ xăng: bình còn ${(fuel.level * 100).round()}% · chạy được chừng ${fuel.kmLeft.round()} km', kind: NoticeKind.money));
  }

  /// Vá / thay ở tiệm vá xe. Thay lốp xong thì có lại lốp dự phòng.
  void repair(RepairOption option) {
    if (!_served || _restStall?.kind.fixesTires != true || tires.ok) return;
    if (tires.state == TireState.ruined && !option.forRuined) return;
    if (lixi < option.price) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return;
    }
    lixi -= option.price;
    clock.addPenalty(option.minutes);
    tires.fix();
    if (spec.kind.fourWheels) tires.spare = true;
    _repairT = _shopRepairSeconds;
    _repairOption = option;
    _shopTalk(_restStall!, option);
    onSound(GameSound.toll);
    onNotice(GameNotice('${option.name} xong (−${option.price} lì xì · ${option.minutes.round()} phút) — lốp căng rồi!', kind: NoticeKind.money));
  }

  /// Mua áo mưa giấy (xe máy).
  void buyRaincoat() {
    if (!_served || spec.kind != VehicleKind.motorbike || raincoat) return;
    if (lixi < GameConfig.raincoatLixi) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return;
    }
    lixi -= GameConfig.raincoatLixi;
    raincoat = true;
    clock.addPenalty(2);
    onSound(GameSound.gift);
    onNotice(const GameNotice('Mặc áo mưa cánh dơi vào — hết lo ướt!', kind: NoticeKind.money));
  }

  /// Tán gẫu với nhân viên cây xăng (bảng thoại riêng trên màn hình): mình
  /// trả lời [reply]; nhân viên đáp lại, có khi tặng chai nước, lì xì lấy may
  /// hay mách tin đường phía trước. Trả về (câu mình, câu đáp).
  (String, String) chatAnswer(ChatReply reply) {
    if (!_served || _restStall?.kind != StallKind.xang) return ('', '');
    final mine = reply.text.replaceAll('{to}', setup.toName);
    final react = reply.react.replaceAll('{tip}', _roadTip());
    switch (reply.perk) {
      case ChatPerk.water:
        alert = min(100, alert + GameConfig.chatWaterAlert);
        onSound(GameSound.gift);
        onNotice(GameNotice('Được tặng chai nước suối · tỉnh táo +${GameConfig.chatWaterAlert.round()}', kind: NoticeKind.money));
      case ChatPerk.lixi:
        lixi += 1;
        _popAt(player.s, player.d, '+1', const Color(0xffFFD54F));
        onSound(GameSound.gift);
        onNotice(const GameNotice('Nhân viên lì xì lấy may đầu năm · +1 lì xì', kind: NoticeKind.money));
      case ChatPerk.tip:
      case ChatPerk.none:
        break;
    }
    return (mine, react);
  }

  /// Tin đường phía trước nhân viên mách (chuyện gần nhất trước).
  String _roadTip() {
    final s = player.s;
    int km(double at) => max(1, ((at - s) / GameConfig.unitsPerKm).round());
    final cp = layout.checkpoints.where((c) => c.s > s).firstOrNull;
    if (cp != null && cp.s - s < 60 * GameConfig.unitsPerKm) {
      return 'Chừng ${km(cp.s)} cây nữa có chốt bắn tốc độ đó, giữ tốc độ cho lành nha sếp!';
    }
    road.ensureAhead(s + 12 * GameConfig.unitsPerKm);
    if (road.curvesBetween(s, s + 12 * GameConfig.unitsPerKm).any((c) => c.sharp)) {
      return 'Đoạn trước có khúc cua gắt lắm, tới biển báo là nhả ga nha sếp!';
    }
    final toll = layout.tolls.where((t) => t.s > s).firstOrNull;
    if (toll != null && toll.s - s < 60 * GameConfig.unitsPerKm) {
      return 'Thêm ${km(toll.s)} cây là tới trạm thu phí, để sẵn lì xì mà trả nha!';
    }
    final city = layout.zones.where((z) => z.startS > s && z.kind == RoadKind.city).firstOrNull;
    if (city != null && city.startS - s < 40 * GameConfig.unitsPerKm) {
      return 'Thêm ${km(city.startS)} cây là vào phố, đèn đỏ nhiều lắm, đừng vượt ẩu nha!';
    }
    return 'Đường phía trước thông thoáng, mà xe khách chạy ẩu lắm, đi cẩn thận nha sếp!';
  }

  /// Đứng dậy đi ra xe, lên đường.
  void leaveStall() {
    if (phase != GamePhase.resting || _job != null) return;
    if (_restStep == _RestStep.walkingOut || _restStep == _RestStep.pullingOut) return;
    _stopTalk();
    _repairT = 0;
    if (_restStep == _RestStep.parking || !_riderLeaves(_restStall!)) {
      _restStep = _RestStep.pullingOut;
      _parkFrom = (player.s, player.d);
      final stall = _restStall!;
      _parkTo = (player.s + dir * (stall.kind == StallKind.xang ? 170 : 90), stall.side * min(Lanes.center(1), player.maxOffset));
    } else {
      _restStep = _RestStep.walkingOut;
    }
    _restT = 0;
    onRest?.call(null);
  }

  /// Quán nước, tiệm vá xe: người lái xuống xe vào ghế ngồi. Cây xăng, xăng
  /// lẻ: ngồi yên trên xe, người bán ra tận nơi.
  bool _riderLeaves(Stall stall) => stall.kind.canSit;

  /// Đường xe lượn từ [_parkFrom] tới [_parkTo]: đầu và cuối xuôi theo đường.
  (double, double) _parkFrom = (0, 0);
  (double, double) _parkTo = (0, 0);

  /// Thợ đang vá xe (giây còn lại của cảnh vá).
  double _repairT = 0;
  RepairOption? _repairOption;
  static const double _shopRepairSeconds = 9.5;

  /// Vị trí, góc lệch của xe trên đường lượn vào / ra (k = 0..1).
  (double, double, double) _parkPath(double k) {
    final (s0, d0) = _parkFrom;
    final (s1, d1) = _parkTo;
    final len = (s1 - s0).abs();
    final p0 = Offset(s0, d0), p3 = Offset(s1, d1);
    final p1 = Offset(s0 + dir * len / 3, d0), p2 = Offset(s1 - dir * len / 3, d1);
    Offset at(double t) {
      final u = 1 - t;
      return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
    }

    final e = k * k * (3 - 2 * k);
    final p = at(e);
    final q = at(min(1.0, e + 0.02));
    final r = at(max(0.0, e - 0.02));
    final ds = q.dx - r.dx, dd = q.dy - r.dy;
    final yaw = ds.abs() + dd.abs() < 1e-6 ? 0.0 : atan2(dir * dd, dir * ds).clamp(-0.9, 0.9);
    return (p.dx, p.dy, yaw);
  }

  double _parkYaw = 0;

  /// Chỗ người lái bước xuống (cạnh xe, phía quán) và chỗ ngồi trong quán.
  (double, double) get _doorAt => (player.s, player.d + _restStall!.side * (spec.width / 2 + 6));

  void _stepResting(double dt) {
    if (_job != null) {
      _stepJob(dt);
      return;
    }
    final stall = _restStall!;
    final plan = _stalls.planOf(stall);
    _restT += dt;
    _repairT = max(0, _repairT - dt);
    if (_repairT > 0 && stall.kind.fixesTires) {
      final (s, d) = _wheelSpot;
      final patching = _repairOption?.art.startsWith('va') ?? true;
      _repairFx(dt, _shopRepairSeconds - _repairT, s, d, patch: patching ? (2.0, 4.6) : (0, 0), pump: (5.0, 6.4));
    }
    _stepWorld(dt);
    for (final g in _gates) {
      if (g.plaza.plazaEnd > _camLeftS - 600 && g.plaza.plazaStart < _camRightS + 1500) g.updateAi(dt, traffic.vehicles);
    }
    double ease(double k) => k * k * (3 - 2 * k);
    final parkSeconds = stall.kind == StallKind.xang ? 1.8 : 0.9;
    switch (_restStep) {
      case _RestStep.parking:
        final k = (_restT / parkSeconds).clamp(0.0, 1.0);
        final (s, d, yaw) = _parkPath(k);
        player
          ..s = s
          ..d = d;
        _parkYaw = yaw;
        if (k >= 1) {
          _parkYaw = 0;
          _restStep = _riderLeaves(stall) ? _RestStep.walkingIn : _RestStep.served;
          _restT = 0;
        }
      case _RestStep.walkingIn:
        if (_restT >= 1.3) {
          _restStep = _RestStep.seated;
          onRest?.call(StallVisit(stall: stall, chatter: _restChatter, seated: true));
        }
      case _RestStep.served:
        // Người bán đi ra tới xe.
        if (_restT >= 1.1) {
          _restStep = _RestStep.seated;
          onRest?.call(StallVisit(stall: stall, chatter: _restChatter, seated: true));
        }
      case _RestStep.seated:
        break;
      case _RestStep.walkingOut:
        if (_restT >= 1.1) {
          _restStep = _RestStep.pullingOut;
          _restT = 0;
          _parkFrom = (player.s, player.d);
          _parkTo = (player.s + dir * 90, stall.side * min(Lanes.center(1), player.maxOffset));
        }
      case _RestStep.pullingOut:
        final k = (_restT / (stall.kind == StallKind.xang ? 1.6 : 0.9)).clamp(0.0, 1.0);
        final (s, d, yaw) = _parkPath(k);
        player
          ..s = s
          ..d = d
          ..speed = 30
          ..cruise = 30;
        _parkYaw = yaw;
        if (k >= 1) {
          _parkYaw = 0;
          _restStall = null;
          phase = GamePhase.driving;
          onPhaseChanged(phase);
          if (clock.isOver) _end(StageEndReason.timeUp, delay: 0.4);
          return;
        }
    }
    _placeGuest(stall, plan, ease);
    _placeWorker(stall, plan, ease);
  }

  /// Người lái đi bộ giữa xe và ghế (toạ độ đường).
  void _placeGuest(Stall stall, StallPlan plan, double Function(double) ease) {
    if (!_riderLeaves(stall)) return;
    final seat = plan.toRoad(plan.seat);
    final (doorS, doorD) = _doorAt;
    final walking = _restStep == _RestStep.walkingIn || _restStep == _RestStep.walkingOut;
    if (walking) {
      final k = ease((_restT / (_restStep == _RestStep.walkingIn ? 1.3 : 1.1)).clamp(0.0, 1.0));
      final (fromS, fromD, toS, toD) =
          _restStep == _RestStep.walkingIn ? (doorS, doorD, seat.$1, seat.$2) : (seat.$1, seat.$2, doorS, doorD);
      _stalls
        ..guestS = fromS + (toS - fromS) * k
        ..guestD = fromD + (toD - fromD) * k;
      final (ax, ay) = road.worldAt(fromS, fromD);
      final (bx, by) = road.worldAt(toS, toD);
      _stalls.guestAngle = atan2(by - ay, bx - ax) + pi / 2;
    } else if (_restStep == _RestStep.seated) {
      _stalls
        ..guestS = seat.$1
        ..guestD = seat.$2
        ..guestAngle = road.at(stall.s).heading + (stall.side > 0 ? 0 : pi) + plan.seatAngle;
    }
  }

  /// Người bán / thợ đi từ chỗ đứng ra cạnh xe mình (thợ vá chỉ ra khi đang
  /// vá), xong việc thì về chỗ.
  void _placeWorker(Stall stall, StallPlan plan, double Function(double) ease) {
    final worker = plan.worker;
    if (worker == null) {
      _stalls.servingStall = null;
      return;
    }
    final home = plan.toRoad(Offset(worker.x, worker.y));
    final job = (player.s - dir * spec.length * 0.15, player.d + stall.side * (spec.width / 2 + 12));
    final repairing = _shopRepairSeconds - _repairT;
    final out = switch (stall.kind) {
      // Thợ đi ra cạnh xe (1 giây), làm, xong thì đi về chỗ.
      StallKind.vaXe => _repairT <= 0
          ? 0.0
          : repairing < 1
              ? ease(repairing)
              : _repairT < 1
                  ? ease(_repairT)
                  : 1.0,
      _ => switch (_restStep) {
          _RestStep.served => ease((_restT / 1.1).clamp(0.0, 1.0)),
          _RestStep.seated => 1.0,
          _ => 0.0,
        },
    };
    if (out <= 0) {
      _stalls.servingStall = null;
      return;
    }
    final (hs, hd) = home;
    final (js, jd) = job;
    final ws = hs + (js - hs) * out, wd = hd + (jd - hd) * out;
    final (wx, wy) = road.worldAt(ws, wd);
    // Đang đi thì nhìn về phía trước, tới nơi thì quay mặt vào xe.
    final (tx, ty) = out >= 1 ? road.worldAt(player.s, player.d) : road.worldAt(js, jd);
    final busy = stall.kind == StallKind.vaXe && out >= 1 ? sin(_time * 9) * 0.14 : 0.0;
    _stalls
      ..servingStall = stall
      ..workerS = ws
      ..workerD = wd
      ..workerAngle = atan2(ty - wy, tx - wx) + pi / 2 + busy;
  }

  /// Chuyện nghe được ở quán: chào hỏi, chuyện Tết, và tin thật về đoạn đường
  /// phía trước (trạm thu phí, cua gắt, còn bao xa).
  List<String> _chatter(Stall stall) {
    final r = Random(stall.seed + clock.minutes.round());
    final owner = switch (stall.kind) {
      StallKind.xang => 'Nhân viên',
      _ => stall.owner.isEmpty ? 'Chủ quán' : stall.owner,
    };
    // Người bán tự xưng theo vai: chú, anh, cô, chị, bà (Út thì xưng em).
    final first = owner.split(' ').first.toLowerCase();
    final me = switch (first) {
      'chú' || 'anh' || 'cô' || 'chị' || 'bà' => first,
      _ => 'em',
    };
    String pick(List<String> options) => options[r.nextInt(options.length)];
    final lines = <String>[
      '$owner: ${pick(switch (stall.kind) {
        StallKind.xang => const ['Đổ bao nhiêu anh ơi? Về quê ăn Tết hả?', 'Mời anh vào, tắt máy giúp em nhé!'],
        StallKind.xangLe => const ['Xăng chai đây, đổ một chai là chạy tới thị trấn.', 'Hết xăng hả? Ở đây có xăng, đổ luôn cho.'],
        StallKind.vaXe => ['Lốp làm sao đấy? Dắt vào đây $me xem cho.', 'Ngồi uống cốc trà, để đấy $me làm cho.'],
        _ => const [
            'Về quê ăn Tết hả? Ngồi đi, uống cốc nước cho mát!',
            'Tết nhất ai cũng vội, nhưng an toàn là trên hết nhé.',
            'Năm nào hai mươi tám Tết đường cũng kín xe thế này.',
            'Ngồi nghỉ chút cho đỡ mỏi lưng rồi hẵng đi tiếp.',
          ],
      })}',
      switch (stall.kind) {
        StallKind.traDa => '$owner: Trà đá nước giếng đấy, mát lắm!',
        StallKind.nuocMia => '$owner: Mía ép tươi, thêm tí tắc cho thơm.',
        StallKind.caPheVong => '$owner: Mấy anh tài xế đường dài đêm nào cũng ghé nằm võng chợp mắt.',
        StallKind.banhMi => '$owner: Bánh mì nóng giòn, pate nhà làm đấy.',
        StallKind.com => '$owner: Có cá kho, rau muống luộc, ăn cho chắc bụng rồi đi.',
        StallKind.vaXe => stall.gouging
            ? '$owner: Đoạn này đinh nhiều lắm, ngày nào $me cũng vá cả chục xe. Giá Tết hơi cao tí nhé!'
            : '$owner: Đi đường xa nhớ xem lốp xe nhé, Tết đinh tặc nhiều lắm.',
        StallKind.xang => '$owner: Xăng RON95 hay E5 ạ? Đổ đầy bình cho yên tâm.',
        StallKind.xangLe => '$owner: Xăng chai đắt hơn cây xăng tí, nhưng ở đây xa cây xăng lắm.',
      },
    ];
    final nextGas = layout.stalls.where((t) => t.kind == StallKind.xang && t.s > player.s + 300).firstOrNull;
    if (stall.kind.sellsFuel && nextGas != null) {
      lines.add('$owner: Cây xăng tới cách đây chừng ${((nextGas.s - player.s) / GameConfig.unitsPerKm).round()} cây số.');
    }
    if (_rain > 0.1 && spec.kind == VehicleKind.motorbike && !raincoat) {
      lines.add('$owner: Mưa thế này mà không có áo mưa à? Mua cái áo mưa giấy mà mặc, ướt là ốm đấy.');
    } else if (_rain > 0.1) {
      lines.add('Khách bàn bên: Mưa phùn thế này đường trơn lắm, phanh từ xa nhé.');
    }
    final cp = layout.checkpoints.where((c) => c.s > player.s).firstOrNull;
    if (cp != null && cp.s - player.s < 25 * GameConfig.unitsPerKm && stall.kind != StallKind.xang) {
      lines.add('Khách bàn bên: Phía trước chừng ${((cp.s - player.s) / GameConfig.unitsPerKm).round()} cây có chốt CSGT bắn tốc độ đấy, đi chậm thôi!');
    }
    if (dir < 0) lines.add('$owner: Đi ngược lại à? Quên đồ ở đâu hay sao?');
    final s = player.s;
    final toll = layout.tolls.where((t) => t.s > s).firstOrNull;
    if (toll != null && toll.s - s < 40 * GameConfig.unitsPerKm) {
      lines.add('Khách bàn bên: Đi thêm chừng ${((toll.s - s) / GameConfig.unitsPerKm).round()} cây nữa là tới trạm thu phí, để sẵn lì xì mà trả.');
    }
    road.ensureAhead(s + 6 * GameConfig.unitsPerKm);
    if (road.curvesBetween(s, s + 6 * GameConfig.unitsPerKm).any((c) => c.sharp)) {
      lines.add('Khách bàn bên: Đoạn trước có khúc cua gắt lắm, tuần trước có xe tải lật đấy. Đi chậm thôi!');
    }
    final next = layout.zones.where((z) => z.startS > s).firstOrNull;
    if (next != null && next.startS - s < 25 * GameConfig.unitsPerKm) {
      final km = ((next.startS - s) / GameConfig.unitsPerKm).round();
      lines.add(switch (next.kind) {
        RoadKind.city => '$owner: Đi $km cây nữa là vào phố, đèn đỏ nhiều, coi chừng bị phạt.',
        RoadKind.expressway => 'Khách bàn bên: Thêm $km cây là lên cao tốc, đường đẹp, nhớ đi làn phải.',
        RoadKind.highway => '$owner: Ra khỏi phố là quốc lộ, xe khách chạy ẩu lắm đấy.',
      });
    }
    lines.add('$owner: Từ đây về ${setup.toName} còn chừng ${((finishS - s) / GameConfig.unitsPerKm).round()} cây nữa.');
    if (nightLevel > 0.3) lines.add('$owner: Tối rồi, nhớ bật đèn mà đi, đường quê tối lắm.');
    if (alert < GameConfig.alertDrowsy) lines.add('$owner: Mắt đỏ hết rồi kìa, nghỉ thêm chút đi, buồn ngủ là nguy lắm.');
    return lines;
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
      }
      if (player.d * dir < 0) {
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
    stops.addAll(animals.stops());
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

  /// Vượt đèn đỏ: đầu xe qua vạch dừng (của chiều đang đi) lúc đèn đỏ (đang
  /// trong ngã tư thì đèn chuyển đỏ không tính).
  bool _ranRedLight(double prevFront) {
    final front = _front;
    for (final l in layout.lightsBetween(min(prevFront, front) - 10, max(prevFront, front) + 10)) {
      final key = dir * l.s;
      if (_lightsPassed.contains(key)) continue;
      final line = dir > 0 ? l.stopLine : l.oncomingStopLine;
      final crossed = dir > 0 ? prevFront < line && front >= line : prevFront > line && front <= line;
      if (!crossed) continue;
      _lightsPassed.add(key);
      if (l.colorAt(_time) == LightColor.red && player.d.abs() < GameConfig.roadHalfWidth) {
        incidentKind = IncidentKind.redLight;
        violation = Violation(IncidentKind.redLight, place: _placeName());
        player.stop();
        onSound(GameSound.crashLight);
        _startIncident();
        return true;
      }
    }
    return false;
  }

  void _collide(double relative,
      {required void Function() onMinor, required void Function() stopOther, bool backOff = false, bool headOn = false}) {
    final severity = classifyCollision(relative, headOn: headOn);
    _impactFx(relative);
    _finishUTurn();
    player.stop();
    // Đang bỏ chạy mà đâm mạnh thì hết đường chạy.
    if (severity == CollisionSeverity.fatal || (severity == CollisionSeverity.crash && phase == GamePhase.chase)) {
      onSound(GameSound.crashHeavy);
      stopOther();
      _shake = 0.7;
      _crashSpin = 6;
      _end(StageEndReason.accident, delay: 1.4);
      return;
    }
    if (severity == CollisionSeverity.crash) {
      // Tai nạn: xe văng xoay, xe kia đứng lại; quà buộc sau xe rơi vỡ mất một món.
      onSound(GameSound.crashHeavy);
      stopOther();
      _shake = 0.6;
      _crashSpin = 4;
      if (player.cargo > 0) player.cargo -= 1;
      incidentKind = IncidentKind.crash;
      violation = Violation(IncidentKind.crash, place: _placeName());
      _startIncident();
      return;
    }
    _shake = 0.3;
    onSound(GameSound.crashLight);
    // Đụng barrier / đảo: lùi lại một đoạn để còn đường mà đi tiếp.
    if (backOff) player.s -= dir * 36;
    if (phase == GamePhase.chase) {
      // Đang bỏ chạy mà quẹt xe: khựng lại (công an áp sát), xe kia tránh đi.
      onMinor();
      return;
    }
    incidentKind = IncidentKind.collision;
    violation = Violation(IncidentKind.collision, place: _placeName());
    _startIncident();
  }

  // ------------------------------------------------------ Trạm thu phí
  void _stepTolls(double dt) {
    for (final g in _gates) {
      if (g.plaza.plazaEnd < _camLeftS - 600 || g.plaza.plazaStart > _camRightS + 1500) continue;
      g.updateAi(dt, traffic.vehicles);
      // Đi ngược qua trạm: làn chiều kia không có barrier, không thu phí.
      if (dir < 0) continue;
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
          if (fee > 0) _popAt(player.s, player.d, '−$fee', const Color(0xffFF8A80));
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
    if (dir < 0) return;
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
          _popAt(player.s, player.d, '+$fare', const Color(0xffFFD166));
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
    if (dir < 0 || _uTurn != null) {
      _overtakeWarn = 0;
      return;
    }
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
    _policeS = _behindEdgeS - dir * 120;
    _policeD = player.d;
    onPhaseChanged(phase);
  }

  void _stepIncident(double dt) {
    _crashSpin = max(0, _crashSpin - dt * 5);
    // Công an chạy tới dừng ngay sau xe mình.
    final target = player.s - dir * (spec.length / 2 + 34);
    _policeS += (target - _policeS) * (1 - exp(-2.5 * dt));
    _policeD += (player.d - _policeD) * (1 - exp(-3 * dt));
  }

  /// Nộp phạt: trừ lì xì, bị giữ lại một lúc, rồi đi tiếp.
  void payFine() {
    if (phase != GamePhase.incident) return;
    final fine = incidentKind.fineLixi;
    if (lixi > 0) _popAt(player.s, player.d, '−${min(fine, lixi)}', const Color(0xffFF8A80));
    if (lixi >= fine) {
      lixi -= fine;
      clock.addPenalty(incidentKind.fineMinutes);
    } else {
      lixi = 0;
      clock.addPenalty(incidentKind.fineMinutes + GameConfig.fineExtraMinutesIfBroke);
    }
    violation = null;
    _clearAroundPlayer();
    _policeVisible = false;
    if (clock.isOver) {
      _end(StageEndReason.timeUp, delay: 0.2);
      return;
    }
    phase = GamePhase.driving;
    onPhaseChanged(phase);
  }

  /// Bỏ chạy: bắt đầu rượt đuổi (xe vừa tai nạn hỏng thì không chạy được).
  void flee() {
    if (phase != GamePhase.incident || incidentKind == IncidentKind.crash) return;
    _startChase();
  }

  void _startChase() {
    _clearAroundPlayer();
    violation = null;
    chase = Chase(spec);
    phase = GamePhase.chase;
    onPhaseChanged(phase);
  }

  void _stepChase(double dt) {
    final c = chase!;
    c.update(dt, player.speed);
    _policeS = player.s - dir * (spec.length / 2 + 20 + c.gap);
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
    // Đường ướt đọng vũng: mưa càng to càng nhiều vũng.
    if (_wet > 0.3) {
      _puddleTimer -= dt * _wet;
      if (_puddleTimer <= 0) {
        _puddleTimer = _between(GameConfig.puddleIntervalMin, GameConfig.puddleIntervalMax);
        _spawnPuddle();
      }
    }

    final box = _playerBox;
    for (final (pickup, component) in _pickups) {
      if (pickup.consumed) continue;
      final hit = RoadBox(s: pickup.s, d: pickup.d, length: pickup.length, width: pickup.width).overlaps(box, shrink: 0.9);
      if (!hit) continue;
      pickup.consumed = true;
      // Vũng nước vẫn nằm đó sau khi xe lội qua.
      if (pickup.kind != PickupKind.puddle) component.removeFromParent();
      switch (pickup.kind) {
        case PickupKind.lixi:
          lixi++;
          onSound(GameSound.lixi);
          _popAt(pickup.s, pickup.d, '+1', const Color(0xffFFD166));
        case PickupKind.gift:
          if (player.cargo < spec.cargoCapacity) {
            player.cargo++;
            onSound(GameSound.gift);
            _popAt(pickup.s, pickup.d, '+1 quà', const Color(0xffFF8FAB));
            onNotice(GameNotice('Nhặt được quà Tết! (${player.cargo}/${spec.cargoCapacity}) — xe nặng hơn'));
          } else {
            onNotice(const GameNotice('Xe đã chất đầy quà rồi!'));
          }
        case PickupKind.puddle:
          if (player.speed > GameConfig.aquaplaneSpeed && _uTurn == null) {
            _slipLeft = GameConfig.aquaplaneSeconds;
            player.slipDrift = (_random.nextBool() ? 1 : -1) * GameConfig.aquaplaneDrift;
            _shake = max(_shake, 0.15);
            onSound(GameSound.skid);
            _notice('aqua${(player.s / 3000).floor()}', 'Lao qua vũng nước nhanh quá — xe trượt nước, tay lái không ăn!', NoticeKind.warning);
          } else {
            player.speed *= 0.92;
          }
        case PickupKind.pothole:
          if (fatigue && player.speed > GameConfig.potholeFlatSpeed && tires.ok && _random.nextDouble() < GameConfig.potholeFlatChance) {
            _puncture('Sập ổ gà mạnh quá — xì lốp rồi!');
          }
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
      final stays = !pickup.consumed || pickup.kind == PickupKind.puddle;
      if (stays && dir * (pickup.s - _behindEdgeS) > -200) return false;
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
    final s0 = _aheadEdgeS + dir * 60;
    final oncomingOk = !layout.hasMedian(s0) && layout.kindAt(s0) != RoadKind.expressway;
    final lanes = oncomingOk && _random.nextDouble() > 0.75 ? _otherLanes : _myLanes;
    final lane = lanes[_random.nextInt(lanes.length)];
    final count = 1 + _random.nextInt(3);
    if (!_canPlace(s0 + dir * 70.0 * count / 2, lane)) return;
    for (var i = 0; i < count; i++) {
      _addPickup(Pickup(kind: PickupKind.lixi, s: s0 + dir * i * 70, d: Lanes.center(lane)), LixiComponent(Sprite(images.fromCache(Img.imgLixi))));
    }
  }

  void _spawnPothole() {
    final s0 = _aheadEdgeS + dir * 60;
    if (layout.kindAt(s0) == RoadKind.expressway) return;
    final lane = _myLanes[_random.nextInt(2)];
    if (!_canPlace(s0, lane)) return;
    final d = Lanes.center(lane) + (_random.nextDouble() - 0.5) * 16;
    final sprite = Sprite(images.fromCache(Img.potholes[_random.nextInt(Img.potholes.length)]));
    _addPickup(Pickup(kind: PickupKind.pothole, s: s0, d: d), PotholeComponent(sprite));
  }

  void _spawnPuddle() {
    final s0 = _aheadEdgeS + dir * 60;
    final lanes = [..._myLanes, if (!layout.hasMedian(s0)) ..._otherLanes];
    final lane = lanes[_random.nextInt(lanes.length)];
    if (!_canPlace(s0, lane)) return;
    final d = Lanes.center(lane) + (_random.nextDouble() - 0.5) * 20;
    _addPickup(Pickup(kind: PickupKind.puddle, s: s0, d: d), PuddleComponent(_random.nextInt(1 << 20)));
  }

  void _spawnGift() {
    final s0 = _aheadEdgeS + dir * 60;
    final lane = _myLanes[_random.nextInt(2)];
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
  /// Báo một lần theo [key]; trả về true nếu vừa báo.
  bool _notice(String key, String text, NoticeKind kind) {
    if (!_noticed.add(key)) return false;
    onNotice(GameNotice(text, kind: kind));
    return true;
  }

  /// Báo khi sắp vào đoạn đường loại khác.
  void _announceZone({bool force = false}) {
    if (dir < 0) return;
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

  // ------------------------------------------- Thợ sửa xe nói chuyện
  /// Lời thoại đang chạy theo giây (tính từ lúc bắt đầu nói chuyện).
  List<({double at, bool mine, String text})> _talk = const [];
  double _talkT = 0;
  int _talkNext = 0;
  String _talkName = '';
  (double, double) Function()? _talkThem;
  bool _flatFromNails = false;
  bool _hissed = false;
  double _fxT = 0;

  /// Thợ lưu động chạy xe tới mất bấy nhiêu giây.
  static const double _helperArrive = 2.5;

  /// Chỗ thợ lưu động ngồi sửa (cạnh bánh sau, phía lề) và chỗ bánh xe.
  (double, double) get _mechanicSpot =>
      (player.s - dir * spec.length * 0.25, player.d + dir * (spec.width / 2 + 14));
  (double, double) get _wheelSpot =>
      (player.s - dir * spec.length * (spec.kind == VehicleKind.motorbike ? 0.32 : 0.28), player.d + dir * (spec.width / 2 + 6));

  /// Chỗ mình đang đứng / ngồi (để gắn bong bóng thoại của mình).
  (double, double) _meAt() {
    if (_riderOff && _restStall != null) return road.worldAt(_stalls.guestS, _stalls.guestD);
    return road.worldAt(player.s, player.d);
  }

  /// Xưng hô theo tên: "Chú Tư" → chú / cháu; "Anh Hùng" → anh / em.
  static (String self, String you) _pronouns(String name) =>
      name.startsWith('Chú') || name.startsWith('Bác') ? ('chú', 'cháu') : name.startsWith('Cô') || name.startsWith('Bà') ? ('cô', 'cháu') : ('anh', 'em');

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _startTalk(String name, (double, double) Function() them, List<({double at, bool mine, String text})> lines) {
    _talk = lines;
    _talkT = 0;
    _talkNext = 0;
    _talkName = name;
    _talkThem = them;
    _hissed = false;
    _speech.clear();
  }

  void _stopTalk() {
    _talk = const [];
    _talkThem = null;
    _speech.clear();
  }

  void _stepTalk(double dt) {
    if (_talkThem == null) return;
    _talkT += dt;
    while (_talkNext < _talk.length && _talk[_talkNext].at <= _talkT) {
      final line = _talk[_talkNext++];
      if (line.mine) {
        _speech.say('me', _meAt, line.text, name: 'Mình', mine: true);
      } else {
        _speech.say('them', _talkThem!, line.text, name: _talkName);
      }
    }
  }

  /// Hiệu ứng lúc sửa: khói vá nóng bốc lên từ bánh xe, rồi bơm hơi xì xì.
  void _repairFx(double dt, double t, double s, double d, {required (double, double) patch, required (double, double) pump}) {
    _fxT -= dt;
    final (x, y) = road.worldAt(s, d);
    if (t >= patch.$1 && t < patch.$2 && _fxT <= 0) {
      _fxT = 0.18;
      _airFx.dust(_random, x, y, count: 1, size: 13, color: const Color(0xffD8D4CC));
    }
    if (t >= pump.$1 && t < pump.$2) {
      if (!_hissed) {
        _hissed = true;
        onSound(GameSound.tireHiss);
      }
      if (_fxT <= 0) {
        // Hơi xì ra ở van khi bơm: từng luồng trắng ngắn.
        _fxT = 0.09;
        _airFx.dust(_random, x, y, count: 1, size: 8, color: const Color(0xffF4F7FA));
      }
    }
  }

  /// Người giúp vừa tới: thợ lưu động hỏi chuyện, người mang xăng dặn dò.
  void _helperArrived(RoadsideJob job) {
    final name = mechanicNames[_random.nextInt(mechanicNames.length)];
    final (self, you) = _pronouns(name);
    final them = self;
    final car = spec.kind != VehicleKind.motorbike;
    switch (job.kind) {
      case RoadsideJobKind.mobileRepair:
        _startTalk(name, () => road.worldAt(_mechanicSpot.$1, _mechanicSpot.$2), [
          (at: 0.2, mine: false, text: 'Xì lốp hả $you? Để $self xem nào.'),
          (at: 1.7, mine: true, text: 'Vâng, đang chạy tự dưng xì hết hơi $them ạ.'),
          (at: 3.1, mine: false, text: _flatFromNails ? 'Đinh tặc đây này! Đoạn này tụi nó rải suốt, Tết càng nhiều.' : 'Sập ổ gà mạnh quá, rách ${car ? 'lốp' : 'săm'} rồi.'),
          (at: 4.6, mine: false, text: car ? 'Rút đinh, nút lốp cái là xong, $you đứng nghỉ tí.' : 'Vá nóng cái là xong, $you ngồi nghỉ tí đi.'),
          (at: 6.0, mine: true, text: 'Tết nhất $them vẫn đi sửa xe à?'),
          (at: 7.2, mine: false, text: 'Tết mới đông việc chứ! Bơm căng rồi đấy, thượng lộ bình an nhé!'),
          (at: 8.4, mine: true, text: '${_cap(you)} cảm ơn $them! Chúc $them năm mới phát tài!'),
        ]);
      case RoadsideJobKind.fuelDelivery:
        _startTalk(name, () {
          final (s, d) = (player.s - dir * (spec.length / 2 + 46), player.d);
          return road.worldAt(s, d);
        }, [
          (at: 0.2, mine: false, text: 'Xăng đây $you ơi! Can này đủ chạy tới cây xăng.'),
          (at: 1.8, mine: true, text: 'May quá, $you cảm ơn $them nhiều!'),
          (at: 3.2, mine: false, text: 'Lần sau thấy đèn xăng nháy thì đổ luôn nhé!'),
        ]);
      case RoadsideJobKind.spareTire:
        break;
    }
  }

  /// Thợ ở tiệm vá xe vừa làm vừa nói chuyện (tiệm "chặn đầu" bãi đinh thì
  /// nói kiểu khác).
  void _shopTalk(Stall stall, RepairOption option) {
    final name = stall.owner.isEmpty ? 'Thợ vá xe' : stall.owner;
    final (self, you) = _pronouns(name);
    final them = self;
    final first = switch (option.art) {
      'va_sam' => 'Để $self vá cho, nhanh thôi!',
      'thay_sam' => 'Săm nát bét rồi, thay cái mới cho chắc nhé.',
      'va_lop' => 'Rút đinh, nút lốp cái là xong.',
      _ => 'Lốp này hỏng rồi, thay lốp mới cho an toàn.',
    };
    _startTalk(name, () => road.worldAt(_stalls.workerS, _stalls.workerD), [
      (at: 0.9, mine: false, text: first),
      if (stall.gouging) ...[
        (at: 2.4, mine: false, text: 'Đường này đinh nhiều lắm, may mà gặp $self đấy!'),
        (at: 3.8, mine: true, text: 'Sao giá đắt thế $them...'),
        (at: 5.0, mine: false, text: 'Tết mà $you, giá Tết!'),
      ] else ...[
        (at: 2.4, mine: false, text: _flatFromNails ? 'Lại đinh tặc! Hôm nay $self vá cả chục cái rồi.' : 'Sập ổ gà à? Đường này ổ gà to như cái chậu.'),
        (at: 3.8, mine: true, text: 'Tết nhất đông khách không $them?'),
        (at: 5.0, mine: false, text: 'Ngày giáp Tết xe về quê đông lắm $you ạ.'),
      ],
      (at: 6.6, mine: false, text: 'Xong rồi, bơm căng rồi đấy. Đi cẩn thận nhé!'),
      (at: 7.8, mine: true, text: '${_cap(you)} cảm ơn $them, chúc $them năm mới an khang!'),
    ]);
  }

  // ------------------------------------------------------- Gà vịt chó
  /// Thỉnh thoảng trên quốc lộ có gà vịt chó qua đường ngay phía trước.
  void _stepAnimals(double dt) {
    for (final g in animals.groups) {
      if (g.announced) continue;
      final ahead = (g.s - player.s) * dir;
      if (ahead < 0 || ahead > _visibleWidth * 0.75) continue;
      g.announced = true;
      _notice('animal${g.s.round()}', switch (g.kind) {
        AnimalKind.duck => 'Đàn vịt qua đường phía trước — giảm tốc, bóp còi cho chúng tránh!',
        AnimalKind.chicken => 'Gà chạy qua đường — coi chừng con quay đầu chạy ngược!',
        AnimalKind.dog => 'Chó chạy rông ra đường — đi chậm thôi!',
      }, NoticeKind.warning);
    }
    if (_uTurn != null || player.speed < 0.5 * GameConfig.normalSpeed) return;
    _animalTimer -= dt;
    if (_animalTimer > 0) return;
    _animalTimer = 30 + _random.nextDouble() * 35;
    final spawnS = (dir > 0 ? _camRightS : _camLeftS) + dir * 160;
    if (layout.kindAt(spawnS) != RoadKind.highway || layout.nearFeature(spawnS, margin: 450)) return;
    if (animals.groups.any((g) => (g.s - spawnS).abs() < 1500)) return;
    if (traffic.vehicles.any((v) => (v.s - spawnS).abs() < 160)) return;
    final r = _random.nextDouble();
    final kind = setup.south
        ? (r < 0.5 ? AnimalKind.duck : r < 0.8 ? AnimalKind.chicken : AnimalKind.dog)
        : (r < 0.28 ? AnimalKind.duck : r < 0.72 ? AnimalKind.chicken : AnimalKind.dog);
    animals.spawn(kind, spawnS, _random.nextBool() ? 1 : -1);
  }

  /// Tông phải con vật: lông bay, xe khựng lại; gà vịt nhà người ta thì phải
  /// dừng đền (mỗi đàn đền một lần).
  void _hitAnimal(Animal a) {
    final (x, y) = road.worldAt(a.s, a.d);
    final dog = a.kind == AnimalKind.dog;
    _airFx.dust(_random, x, y, count: dog ? 3 : 7, size: dog ? 14 : 9, color: switch (a.kind) {
      AnimalKind.duck => a.variant == 1 ? const Color(0xffF4F2EA) : const Color(0xffA88A64),
      AnimalKind.chicken => const Color(0xffC8823C),
      AnimalKind.dog => const Color(0xffC9A06A),
    });
    player.speed *= dog ? 0.6 : 0.82;
    _shake = max(_shake, dog ? 0.3 : 0.12);
    onSound(GameSound.pothole);
    if (dog) {
      if (spec.kind == VehicleKind.motorbike) _tiltT = 0.6;
      _notice('dog${a.s.round()}', 'Chó lao ra đường — suýt ngã! Đi chậm thôi', NoticeKind.warning);
      return;
    }
    final group = animals.groups.firstWhere((g) => g.animals.contains(a));
    if (group.fined) return;
    group.fined = true;
    final pay = min(lixi, 1);
    lixi -= pay;
    clock.addPenalty(4);
    if (pay > 0) _popAt(player.s, player.d, '−1', const Color(0xffFF8A80));
    onNotice(GameNotice(
      a.kind == AnimalKind.duck ? 'Quệt phải con vịt — người chăn chạy tới, đền ${pay > 0 ? '1 lì xì' : 'lời xin lỗi'} mất 4 phút' : 'Quệt phải con gà nhà người ta — đền ${pay > 0 ? '1 lì xì' : 'lời xin lỗi'}, mất 4 phút',
      kind: NoticeKind.warning,
    ));
  }

  // ------------------------------------------------------------ Hiệu ứng
  double _exhaustT = 0;
  double _heavySmokeT = 0;
  double _sprayT = 0;
  double _fireworkT = 1.5;
  List<(double, double)>? _skidFrom;

  /// Hướng mũi xe mình (góc thế giới), vị trí, véc-tơ tới và sang phải.
  ({double x, double y, double fx, double fy, double rx, double ry}) get _pose {
    final u = _uTurn;
    final backward = (u?.dirFrom ?? dir) < 0;
    final yaw = u != null ? -u.theta : (phase == GamePhase.resting ? _parkYaw : player.yawOffset);
    final a = road.at(player.s).heading + yaw + (backward ? pi : 0);
    final (x, y) = road.worldAt(player.s, player.d);
    return (x: x, y: y, fx: cos(a), fy: sin(a), rx: -sin(a), ry: cos(a));
  }

  /// Khói pô, vệt phanh, tia lửa, bụi nước theo xe mình; pháo hoa giao thừa.
  void _stepEffects(double dt) {
    _airFx.cameraAngle = _camAngle;
    _speech.cameraAngle = _camAngle;
    _stepTalk(dt);
    _stepFireworks(dt);
    final driving = phase == GamePhase.driving || phase == GamePhase.chase;
    if (!driving) {
      _skidFrom = null;
      return;
    }
    final p = _pose;
    final v = player.speed;
    final vx = p.fx * v, vy = p.fy * v;
    final len = spec.length, wid = spec.width;
    final moto = spec.kind == VehicleKind.motorbike;

    // Khói pô: vặn ga (đang tăng tốc) thì phụt dày, chạy đều thì mỏng.
    final engineOn = !player.engineOff && !pushing;
    if (engineOn) {
      final accelerating = player.throttle || player.speed < player.cruise - 4;
      final interval = accelerating ? 0.05 : (v < 5 ? 0.3 : 0.15);
      _exhaustT -= dt;
      if (_exhaustT <= 0) {
        _exhaustT = interval;
        final side = switch (spec.kind) {
          VehicleKind.motorbike => 0.32,
          VehicleKind.car => 0.28,
          VehicleKind.bus => -0.34,
        };
        final ex = p.x - p.fx * len * 0.5 + p.rx * wid * side;
        final ey = p.y - p.fy * len * 0.5 + p.ry * wid * side;
        _airFx.exhaust(_random, ex, ey, vx * 0.12 - p.fx * 26, vy * 0.12 - p.fy * 26,
            strength: accelerating ? 1 : 0.55, diesel: spec.kind == VehicleKind.bus);
      }
    }

    // Xe tải, xe khách chạy cùng đường thỉnh thoảng phụt khói đen.
    _heavySmokeT -= dt;
    if (_heavySmokeT <= 0) {
      _heavySmokeT = 0.12;
      for (final t in traffic.vehicles) {
        if (!t.type.heavy || t.s < _camLeftS - 100 || t.s > _camRightS + 100 || _random.nextDouble() > 0.35) continue;
        final back = t.oncoming ? 1.0 : -1.0;
        final ta = road.at(t.s).heading + (t.oncoming ? pi : 0);
        final (x, y) = road.worldAt(t.s + back * t.type.length / 2, t.d - back * t.type.width * 0.3);
        _airFx.exhaust(_random, x, y, -cos(ta) * 30, -sin(ta) * 30, strength: 0.8, diesel: true);
      }
    }

    // Bánh sau (xe máy một vết, ô tô hai vết).
    final rear = -len * (moto ? 0.34 : 0.3);
    final wheels = moto ? const [0.0] : [-wid * 0.38, wid * 0.38];
    final points = [for (final w in wheels) (p.x + p.fx * rear + p.rx * w, p.y + p.fy * rear + p.ry * w)];

    // Phanh gấp / trượt cua trên đường khô: vệt lốp in xuống mặt đường.
    final hardBrake = player.brake && v > 0.3 * GameConfig.normalSpeed;
    final skidding = (hardBrake || player.scraping || player.lateralVelocity.abs() > 0.75 * player.steerAuthority && v > GameConfig.normalSpeed) && _wet < 0.3;
    if (skidding) {
      final from = _skidFrom;
      if (from != null && from.length == points.length) {
        for (var i = 0; i < points.length; i++) {
          _groundFx.skid(from[i].$1, from[i].$2, points[i].$1, points[i].$2, width: moto ? 3 : 4.2, alpha: hardBrake ? 0.34 : 0.22);
        }
      }
      _skidFrom = points;
    } else {
      _skidFrom = null;
    }

    // Quệt lề: tia lửa toé ở hông xe phía mép đường.
    if (player.scraping) {
      final side = (player.d > 0 ? 1.0 : -1.0) * dir;
      final along = (_random.nextDouble() - 0.5) * len * 0.6;
      _airFx.sparks(_random, p.x + p.rx * side * wid / 2 + p.fx * along, p.y + p.ry * side * wid / 2 + p.fy * along, vx, vy);
    }

    // Đường ướt: bánh xe tung bụi nước phía sau.
    if (_wet > 0.3 && v > 0.3 * GameConfig.normalSpeed) {
      _sprayT -= dt;
      if (_sprayT <= 0) {
        _sprayT = 0.035;
        final strength = (_wet * v / GameConfig.normalSpeed).clamp(0.3, 1.0);
        for (final (x, y) in points) {
          _airFx.spray(_random, x, y, vx * 0.25 - p.fx * v * 0.12, vy * 0.25 - p.fy * v * 0.12, strength: strength);
        }
      }
    }
  }

  /// Va chạm: mảnh vỡ văng ra, khói bụi bốc lên ở đầu xe.
  void _impactFx(double relative) {
    final p = _pose;
    final fx = p.x + p.fx * spec.length / 2, fy = p.y + p.fy * spec.length / 2;
    final hard = relative / GameConfig.accidentRelativeSpeed;
    _groundFx.shatter(_random, fx, fy, p.fx * player.speed, p.fy * player.speed, count: (6 + 14 * hard.clamp(0.0, 1.5)).round());
    _airFx.dust(_random, fx, fy, count: hard > 1 ? 9 : 4, size: hard > 1 ? 24 : 14);
  }

  /// Chữ nổi tại chỗ (s, d) trên đường.
  void _popAt(double s, double d, String text, Color color) {
    final (x, y) = road.worldAt(s, d);
    _airFx.popup(x, y, text, color);
  }

  /// Gần giao thừa (từ 22:30) trời bắt đầu có pháo hoa, càng sát nửa đêm càng
  /// dày; về tới nhà ở chặng cuối thì pháo hoa mừng nổ rộ.
  void _stepFireworks(double dt) {
    final m = clock.minutes;
    final celebrate = phase == GamePhase.finished && _endReason == StageEndReason.arrived && setup.stageNumber >= setup.stageCount;
    double rate;
    if (celebrate) {
      rate = 3;
    } else if (m >= TripClock.midnight - 90 && m < TripClock.midnight + 30) {
      final k = ((m - (TripClock.midnight - 90)) / 90).clamp(0.0, 1.0);
      rate = 0.25 + 2.2 * k * k;
    } else {
      return;
    }
    _fireworkT -= dt;
    if (_fireworkT > 0) return;
    _fireworkT = (0.4 + 1.2 * _random.nextDouble()) / rate;
    // Chỗ nổ: ngẫu nhiên trong khung nhìn (theo hướng camera).
    final w = _visibleWidth, h = _visibleHeight;
    final ax = (_random.nextDouble() - 0.5) * w * 0.9, ay = (_random.nextDouble() - 0.5) * h * 0.8;
    final c = cos(_camAngle), s = sin(_camAngle);
    _fireworks.burst(_random, _camX + ax * c - ay * s, _camY + ax * s + ay * c, radius: 80 + _random.nextDouble() * 90);
  }

  /// Chạy tiếp ở tốc độ thường (từ chỗ đang đứng tới hết chuyến) thì về tới
  /// nhà dư (dương) / trễ (âm) bao nhiêu phút so với giao thừa.
  double get spareMinutes {
    final done = ((player.s - _startS) / GameConfig.unitsPerKm).clamp(0.0, setup.lengthKm);
    var seconds = 0.0;
    var at = 0.0;
    for (final section in setup.sections) {
      final from = max(at, done);
      final to = at + section.km;
      if (to > from && section.km > 0) seconds += section.playSeconds * (to - from) / section.km;
      at = to;
    }
    final need = seconds * GameConfig.gameSecondsPerPlaySecond / 60 + setup.laterMinutes;
    return clock.minutesLeft - need;
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
      fuel: fuel.level,
    ));
  }

  // ---------------------------------------------------- Camera, hình
  void _updateCamera(double dt) {
    final w = _visibleWidth, h = _visibleHeight;
    final speedRatio = (player.speed / spec.maxSpeed).clamp(0.0, 1.0);
    // Đang làm việc bên lề (thợ tới sửa, chờ xăng): đưa xe vào gần giữa để
    // thấy cả người giúp đỗ phía sau.
    final targetFraction = _job != null
        ? 0.3
        : GameConfig.playerScreenXSlow + (GameConfig.playerScreenXFast - GameConfig.playerScreenXSlow) * speedRatio;
    _screenFraction += (targetFraction - _screenFraction) * (1 - exp(-2.5 * dt));
    final lead = (0.5 - _screenFraction) * w;

    // Camera xoay theo dây cung từ xe tới một điểm phía trước (theo chiều
    // đang đi): đoạn đường từ xe tới đó nằm ngang màn hình, khúc cua xa hơn
    // uốn hẳn lên hoặc xuống. Đang quay đầu thì camera xoay theo xe.
    final u = _uTurn;
    final chordDir = u?.dirFrom ?? dir;
    final p0 = road.at(player.s);
    final p1 = road.at(player.s + chordDir * (lead + GameConfig.cameraChordAhead));
    final targetAngle = atan2(p1.y - p0.y, p1.x - p0.x) - (u?.theta ?? 0);
    if (!_cameraReady) {
      _camAngle = targetAngle;
    } else {
      _camAngle += _wrapAngle(targetAngle - _camAngle) * (1 - exp(-GameConfig.cameraTurnRate * dt));
    }
    final ux = cos(_camAngle), uy = sin(_camAngle);
    // Theo chiều ngang màn hình: xe ở đúng tỉ lệ đã chọn. Theo chiều dọc: tim
    // đường lệch lên trên để chừa chỗ dưới cùng cho cần lái và cụm nút.
    var tx = p0.x + ux * lead - uy * GameConfig.cameraRoadOffsetY;
    var ty = p0.y + uy * lead + ux * GameConfig.cameraRoadOffsetY;
    // Ngồi quán: camera dịch vào giữa xe và quán, phóng to.
    final stall = _restStall;
    final resting = phase == GamePhase.resting && stall != null;
    if (resting) {
      final (sx, sy) = road.worldAt(stall.s, (player.d + stall.side * (Stall.plotFrom + min(70.0, stall.depth * 0.3))) / 2);
      // Bảng thực đơn che nửa trái: dời camera để quán nằm ở nửa phải.
      final shift = w / 1.35 * 0.26;
      tx = sx - ux * shift;
      ty = sy - uy * shift;
    }
    // Chạy nhanh thì camera lùi ra một chút: thấy xa hơn, cảm giác tốc độ.
    final zoomTarget = resting ? 1.35 : 1.0 - 0.13 * speedRatio;
    if ((_zoomFactor - zoomTarget).abs() > 0.001) {
      _zoomFactor += (zoomTarget - _zoomFactor) * (1 - exp(-2.5 * dt));
      camera.viewfinder.zoom = _baseZoom * _zoomFactor;
    }
    if (!_cameraReady) {
      _camX = tx;
      _camY = ty;
      _cameraReady = true;
    } else if (resting || _zoomFactor > 1.01) {
      final k = 1 - exp(-3 * dt);
      _camX += (tx - _camX) * k;
      _camY += (ty - _camY) * k;
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
    if (_driverActive) {
      // Ghế lái: thấy xa phía trước, phía sau thì chỉ cần một đoạn ngắn.
      _camLeftS = dir > 0 ? player.s - 500 : player.s - _driverReach;
      _camRightS = dir > 0 ? player.s + _driverReach : player.s + 500;
      return;
    }
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
      ..toS = toS
      ..time = _time;
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
    _scenery.sync(_camLeftS, _camRightS, keepFrom: min(_camLeftS, _keepFromS));
    _powerLines.sync(_camLeftS, _camRightS, layout, keepFrom: min(_camLeftS, _keepFromS));
    _syncStalls(fromS, toS);
    _checkpoints
      ..fromS = fromS
      ..toS = toS
      ..waving = _wavedBy
      ..wavingDir = _wavedDir;
    _nailLayer
      ..fromS = fromS
      ..toS = toS;

    final night = darkness;
    _trafficLayer
      ..lightsOn = night > 0.3
      ..raining = _rain > 0.15
      ..sync();
    _syncRain();
    _syncCrew();
    if (_cargoShown != player.cargo && spec.kind != VehicleKind.bus) {
      _cargoShown = player.cargo;
      _playerSprite.cargo = [
        for (var i = 0; i < min(player.cargo, 3); i++) Sprite(images.fromCache(Img.cargo[i % Img.cargo.length])),
      ];
    }
    final u = _uTurn;
    final moving = player.speed > 20;
    final wobble = (!tires.ok && moving ? sin(_time * 15) * 0.035 : 0.0) + (_tiltT > 0 ? sin(_tiltT * 22) * 0.12 : 0.0);
    final resting = phase == GamePhase.resting;
    _playerSprite
      ..braking = player.brake && player.speed > 1
      ..lightsOn = headlightsOn
      ..hazard = spec.kind.fourWheels && (_job != null || (fuel.empty && !moving) || (_wavedBy != null))
      ..walker = pushing || (_job?.kind == RoadsideJobKind.fuelDelivery && spec.kind == VehicleKind.motorbike) ? _walkerSprite : null
      ..sprite = _riderOff || pushing || (resting && _job != null && spec.kind == VehicleKind.motorbike)
          ? _parkedSprite
          : (raincoat ? _raincoatSprite : _riderSprite)
      ..shadow = _riderOff || pushing || (resting && _job != null && spec.kind == VehicleKind.motorbike)
          ? _parkedShadow
          : (raincoat ? _raincoatShadow : _riderShadow)
      ..placeOn(
        road,
        player.s,
        player.d,
        facingBackward: (u?.dirFrom ?? dir) < 0,
        yaw: u != null ? -u.theta : (resting ? _parkYaw : player.yawOffset) + _crashSpin * 0.25 + wobble,
      );
    if (_policeVisible) {
      _police.placeOn(road, _policeS, _policeD, facingBackward: dir < 0);
    } else {
      _police.placeOn(road, _camLeftS - 1000, 0);
    }
    _overtakeArrow.active = _overtakeWarn > 0;
    if (_overtakeArrow.active) _overtakeArrow.placeOn(road, _camLeftS + 60, Lanes.center(_overtakeLane));
    _syncNight(night);
  }

  /// Người lái đã xuống xe (đang đi bộ / ngồi quán).
  bool get _riderOff =>
      phase == GamePhase.resting &&
      (_restStep == _RestStep.walkingIn || _restStep == _RestStep.seated || _restStep == _RestStep.walkingOut);

  void _syncStalls(double fromS, double toS) {
    final stall = _restStall;
    _stalls
      ..fromS = fromS
      ..toS = toS
      ..underCanopy = phase == GamePhase.resting && stall?.kind == StallKind.xang ? stall : null
      ..guestStall = _riderOff ? stall : null
      ..guestInHammock = _restStep == _RestStep.seated && stall?.kind == StallKind.caPheVong;
    if (_restStep == _RestStep.walkingIn && _restT < 0.02 && stall != null) {
      final (s, d) = _doorAt;
      _stalls
        ..guestS = s
        ..guestD = d;
    }
  }

  /// Trời tối thực tế: theo giờ, cộng mây mưa vần vũ.
  double get darkness => min(1.0, nightLevel + _rain * GameConfig.rainDarkness);

  /// Mưa: lớp mặt đường ướt, lớp trời xám, hạt mưa trên màn hình.
  void _syncRain() {
    final kind = _spell?.kind ?? weather.spells.firstOrNull?.kind ?? RainKind.drizzle;
    final c = cos(_camAngle).abs(), sn = sin(_camAngle).abs();
    final w = _visibleWidth, h = _visibleHeight;
    final view = Rect.fromCenter(center: Offset(_camX, _camY), width: w * c + h * sn, height: w * sn + h * c);
    PuddleComponent.rain = _rain;
    _stalls.rain = _rain;
    _rainGround
      ..rain = _rain
      ..wet = _wet
      ..kind = kind
      ..view = view
      ..fromS = _camLeftS - 80
      ..toS = _camRightS + 80;
    _rainSky
      ..rain = _rain
      ..kind = kind
      ..view = view;
    _rainStreaks
      ..rain = _rain
      ..kind = kind
      ..flow = dir * player.speed * camera.viewfinder.zoom * cos(_wrapAngle(road.at(player.s).heading - _camAngle));
    _rainGround.sprays.clear();
    if (_wet > 0.15) {
      Spray spray(double s, double d, double heading, double speed, double length, double width) {
        final (x, y) = road.worldAt(s, d);
        final rear = Offset(x, y) - Offset(cos(heading), sin(heading)) * length / 2;
        return Spray(rear, heading, (speed / GameConfig.normalSpeed).clamp(0.0, 1.0), width);
      }

      final heading = road.at(player.s).heading + (dir < 0 ? pi : 0);
      _rainGround.sprays.add(spray(player.s, player.d, heading, player.speed, spec.length, spec.width));
      for (final v in traffic.vehicles) {
        final hv = road.at(v.s).heading + (v.oncoming ? pi : 0);
        _rainGround.sprays.add(spray(v.s, v.d, hv, v.speed, v.type.length, v.type.width));
      }
    }
  }

  /// Bày đồ quanh xe lúc làm việc bên lề: biển tam giác, lốp dự phòng, con
  /// đội, người ngồi sửa, xe người mang xăng / thợ vá chạy tới.
  void _syncCrew() {
    _crew.items.clear();
    final job = _job;
    if (job == null) return;
    final k = (_jobT / _jobSeconds).clamp(0.0, 1.0);
    final heading = road.at(player.s).heading + (dir < 0 ? pi : 0);
    final curb = dir.toDouble();
    final moto = spec.kind == VehicleKind.motorbike;
    if (!moto && job.kind != RoadsideJobKind.mobileRepair && k > 0.2) {
      _crew.items.add(CrewItem(Img.imgWarningTriangle, player.s - dir * (spec.length / 2 + 70), player.d, heading - pi / 2, 20, 18));
    }
    switch (job.kind) {
      case RoadsideJobKind.spareTire:
        final rear = player.s - dir * spec.length * 0.3;
        final side = player.d + curb * (spec.width / 2 + 16);
        if (k > 0.4) _crew.items.add(CrewItem(Img.imgCarJack, rear, player.d + curb * (spec.width / 2 + 2), heading, 18, 10));
        _crew.items.add(CrewItem(Img.imgSpareTire, player.s + dir * spec.length * 0.05, player.d + curb * (spec.width / 2 + 22), heading, 24, 24));
        if (k > 0.3) {
          _crew.items.add(CrewItem(Img.imgDriverCarCrouch, rear, side, heading - curb * pi / 2 + pi, 30, 30, shadow: false));
        }
      case RoadsideJobKind.fuelDelivery:
      case RoadsideJobKind.mobileRepair:
        // Xe người giúp: chạy tới đỗ sau xe mình (2,5 giây), xong việc thì chạy đi.
        final arrive = (_jobT / _helperArrive).clamp(0.0, 1.0);
        final leave = ((_jobT - (_jobSeconds - 1.2)) / 1.2).clamp(0.0, 1.0);
        final park = player.s - dir * (spec.length / 2 + 46);
        final from = _behindEdgeS - dir * 40;
        final hs = leave > 0 ? park + dir * leave * 900 : from + (park - from) * (1 - pow(1 - arrive, 2));
        final hd = player.d + curb * (leave > 0 ? -30 * leave : 0);
        final helperHeading = heading;
        _crew.items.add(CrewItem(job.kind == RoadsideJobKind.fuelDelivery ? Img.imgScooterFuel : Img.imgScooterMechanic, hs, hd, helperHeading + pi / 2,
            27 * GameConfig.motorbikeVisualScale, 27 * GameConfig.motorbikeVisualScale * 150 / 64));
        if (job.kind == RoadsideJobKind.fuelDelivery && leave <= 0) {
          final atCar = arrive >= 1 && k > 0.45;
          _crew.items.add(CrewItem(Img.imgJerrycan, atCar ? player.s : hs - dir * 22, atCar ? player.d + curb * (spec.width / 2 + 10) : hd, heading, 14, 18));
        }
        if (job.kind == RoadsideJobKind.mobileRepair && arrive >= 1 && leave <= 0) {
          // Thợ ngồi cạnh bánh xe, tay thoăn thoắt (người lắc lư theo nhịp làm).
          final (ms, md) = _mechanicSpot;
          final busy = _talkT > 1 ? sin(_time * 9) : 0.0;
          _crew.items.add(CrewItem(Img.imgMechanic, ms + dir * busy * 1.4, md, heading - curb * pi / 2 + pi + busy * 0.12, 26, 26, shadow: false));
          if (_talkT > 3) _crew.items.add(CrewItem(Img.imgWaterBasin, player.s + dir * spec.length * 0.2, player.d + curb * (spec.width / 2 + 18), 0, 20, 20));
          // Săm / lốp thợ kéo ra để trên đất lúc vá.
          if (_talkT > 3 && _talkT < 6.3) {
            _crew.items.add(CrewItem(Img.item(moto ? 'va_sam' : 'va_lop'), ms - dir * 22, md + curb * 8, heading, 20, 20));
          }
        }
    }
  }

  /// Mức tối theo giờ trong ngày của đồng hồ chuyến đi (0 ngày .. 1 đêm).
  double get nightLevel {
    switch (setup.sky) {
      case SkyMode.day:
        return 0;
      case SkyMode.night:
        return 1;
      case SkyMode.clock:
        break;
    }
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
    final u = _uTurn;
    final dir = p.heading + ((u?.dirFrom ?? this.dir) < 0 ? pi : 0) + (u != null ? -u.theta : player.yawOffset);
    _night.lights.add(NightLight.round(pos, GameConfig.noHeadlightRadius, 0.9));
    if (headlightsOn && !_riderOff) {
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
    // Cây xăng sáng trưng dưới mái che; quán nước treo bóng đèn.
    for (final t in layout.stallsBetween(_camLeftS - 200, _camRightS + 200)) {
      final gas = t.kind == StallKind.xang;
      final (x, y) = road.worldAt(t.s, t.side * (Stall.plotFrom + (gas ? 64 : 50)));
      _night.lights.add(NightLight.round(Offset(x, y), gas ? 230 : 110, gas ? 0.9 : 0.6));
    }
  }

  LightHud? _nextLight() {
    final front = _front;
    final lights = dir > 0 ? layout.lightsBetween(front, front + 1600) : layout.lightsBetween(front - 1600, front).toList().reversed;
    for (final l in lights) {
      final line = dir > 0 ? l.stopLine : l.oncomingStopLine;
      final ahead = dir * (line - front);
      if (ahead < -2) continue;
      return LightHud(
        color: l.colorAt(_time),
        seconds: l.remainingAt(_time).ceil(),
        meters: (ahead / GameConfig.unitsPerKm * 1000).round(),
      );
    }
    return null;
  }

  CurveHud? _curveHud() {
    final c = sharpCurveAhead;
    if (c == null) return null;
    // Đường ướt bám kém: tốc độ khuyên dùng thấp hơn.
    final advise = c.curve.adviseSpeed * sqrt(player.grip);
    return CurveHud(
      right: c.right,
      meters: (max(0.0, c.ahead - spec.length / 2) / GameConfig.unitsPerKm * 1000 / 10).round() * 10,
      adviseKmh: (advise * GameConfig.displayKmhPerUnitSpeed / 5).floor() * 5,
      tooFast: player.speed > advise + 8,
    );
  }

  /// Biển hạn chế tốc độ ở chốt CSGT phía trước (từ biển tới súng bắn tốc độ).
  SpeedLimitHud? _speedLimitHud() {
    if (!fatigue) return null;
    for (final c in layout.checkpointsBetween(player.s - 1200, player.s + 1200)) {
      final sign = dir > 0 ? c.signS : c.oncomingSignS;
      final radar = c.radarS(dir);
      final fromSign = dir * (player.s - sign);
      final toRadar = dir * (radar - player.s);
      if (fromSign < -500 || toRadar < -60) continue;
      final kmh = player.speed * GameConfig.displayKmhPerUnitSpeed;
      return SpeedLimitHud(
        limit: c.limitKmh,
        meters: (max(0.0, toRadar) / GameConfig.unitsPerKm * 1000 / 10).round() * 10,
        over: kmh > c.limitKmh + GameConfig.speedTolerance,
      );
    }
    return null;
  }

  /// Nút theo tình huống đang dùng được.
  List<RoadAction> _actions() {
    if (phase != GamePhase.driving) return const [];
    final stopped = _stopped;
    final moto = spec.kind == VehicleKind.motorbike;
    return [
      if (stallHere != null) RoadAction.visit,
      if (fuel.empty && stopped && moto && !_tiltUsed) RoadAction.tiltBike,
      if (fuel.empty && stopped && moto && !pushing) RoadAction.push,
      if (fuel.empty && player.speed < 8 && _uTurn == null) RoadAction.callFuel,
      if (!tires.ok && stopped && spec.kind.fourWheels && tires.spare) RoadAction.spareTire,
      if (!tires.ok && stopped) RoadAction.callMechanic,
      if (canUTurn) RoadAction.uTurn,
    ];
  }

  void _pushHud() {
    final here = stallHere;
    final hud = HudData(
      kmDone: ((player.s - _startS) / GameConfig.unitsPerKm).clamp(0, setup.lengthKm).floor(),
      kmTotal: setup.lengthKm.round(),
      speedKmh: (player.speed * GameConfig.displayKmhPerUnitSpeed).round(),
      cruiseKmh: (player.cruise * GameConfig.displayKmhPerUnitSpeed).round(),
      spareMinutes: spareMinutes.round(),
      clockLabel: clock.label,
      minutesLeft: max(0, clock.minutesLeft).floor(),
      lixi: lixi,
      cargo: player.cargo,
      danger: player.speed >= dangerSpeed || player.d * dir < 0,
      light: _nextLight(),
      curve: _curveHud(),
      headlightsOn: headlightsOn,
      night: darkness > 0.3,
      alert: alert.round(),
      drowse: (_drowse * 20).round() / 20,
      canUTurn: canUTurn,
      stallPrompt: here?.name,
      stallKind: here?.kind,
      reversed: dir < 0,
      fuel: (fuel.level * 100).ceil() / 100,
      fuelKm: fuel.kmLeft.round(),
      tire: tires.state,
      spare: spec.kind.fourWheels && tires.spare,
      rain: (_rain * 10).round() / 10,
      rainKind: _spell?.kind,
      raincoat: raincoat,
      soaked: (soaked * 10).round() / 10,
      speedLimit: _speedLimitHud(),
      pullOver: _wavedBy == null
          ? null
          : (max(0.0, GameConfig.pullOverReach - _wavedDir * (player.s - _wavedBy!.radarS(_wavedDir))) / GameConfig.unitsPerKm * 1000 / 10).round() * 10,
      outOfFuel: fuel.empty,
      pushing: pushing,
      fuelAhead: fuel.low ? _serviceLabel((t) => t.kind == StallKind.xang || (t.kind == StallKind.xangLe && spec.kind == VehicleKind.motorbike)) : null,
      repairAhead: tires.ok ? null : _serviceLabel((t) => t.kind.fixesTires),
      actions: _actions(),
    );
    if (hud == _lastHud) return;
    _lastHud = hud;
    onHud(hud);
  }
}

/// Các bước ghé quán: tấp xe vào lề, đi bộ vào ghế, ngồi, đi ra, lên xe.
enum _RestStep {
  parking,
  walkingIn,

  /// Cây xăng, xăng lẻ: người bán đang đi ra xe.
  served,
  seated,
  walkingOut,
  pullingOut,
}
