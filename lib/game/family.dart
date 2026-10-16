part of 've_que_game.dart';

/// Chở cả nhà về quê: nối [FamilyRide] (logic thuần, có kiểm thử) vào game.
/// Mỗi bước đo tình hình đường (tắc, mưa, đêm, chạy quá nhanh, chỗ dừng phía
/// trước…), báo phanh gấp, va chạm, sập ổ gà, ghé quán; bé khóc thì tay lái
/// phân tâm, người lái mau mệt.
class _Family {
  _Family(this.g);

  final VeQueGame g;

  late final FamilyRide? ride = g.setup.family && g.fatigue && g.spec.kind != VehicleKind.bus
      ? (FamilyRide(
          motorbike: g.spec.kind == VehicleKind.motorbike,
          random: Random(g.setup.seed * 97 + 5),
          toName: g.setup.toName,
          stageKm: g.setup.lengthKm,
          pace: g.setup.difficulty.drowsiness,
        )
        ..onLine = ((line) => g.onFamilyLine?.call(line))
        ..onNotice = ((text, warning) => g.onNotice(GameNotice(text, kind: warning ? NoticeKind.warning : NoticeKind.info))))
      : null;

  bool get on => ride != null;

  /// Xe máy chở cả nhà thì dùng ảnh xe có vợ ngồi sau, bé ngồi trước.
  bool get sprite => on && g.spec.kind == VehicleKind.motorbike;

  double _prevSpeed = 0;
  double _brakeFrom = -1;
  bool _brakeTold = false;
  int _collisions = 0;
  bool _resting = false;

  /// Trước khi xe chạy một bước: bé khóc ré bên tai thì tay lái kém ăn.
  void preMove() {
    final r = ride;
    if (r == null) return;
    g.player.distraction = max(g.player.distraction, r.distraction);
  }

  /// Tỉnh táo tụt nhanh hơn bao nhiêu lần (bé khóc).
  double get alertFactor => ride?.alertFactor ?? 1;

  void step(double dt) {
    final r = ride;
    if (r == null) return;
    final p = g.player;
    if (_resting) {
      _resting = false;
      r.leave();
    }
    _stepBrake();
    if (g.collisions != _collisions) {
      _collisions = g.collisions;
      r.crash();
    }
    final kmh = p.speed * GameConfig.displayKmhPerUnitSpeed;
    final curve = g.road.at(p.s).curvature.abs() > 1 / 900 && kmh > 35;
    r.step(FamilyInput(
      dt: dt,
      speedKmh: kmh,
      km: (g._maxS - VeQueGame._startS) / GameConfig.unitsPerKm,
      kmLeft: max(0.0, (g.finishS - p.s) / GameConfig.unitsPerKm),
      jam: _inJam,
      rain: g._rain,
      night: g.nightLevel,
      raincoat: g.raincoat,
      speeding: kmh > _comfortKmh,
      drowsy: g.alert < GameConfig.alertDrowsy,
      lightsNeeded: g.nightLevel > 0.6 && !g.headlightsOn,
      fuelLow: g.fuel.low,
      onPhone: g._events.talkingWhileDriving,
      curve: curve,
      peach: g._events.peach > 0,
      nextStopKm: g.dir > 0 ? _nextStopKm : null,
    ));
  }

  /// Giữ phanh lâu ở tốc độ cao (không phải chạm nhẹ hạ nấc ga): phanh gấp.
  void _stepBrake() {
    final p = g.player;
    if (p.brake) {
      if (_brakeFrom < 0) _brakeFrom = _prevSpeed;
      final dropped = _brakeFrom - p.speed;
      if (!_brakeTold && _brakeFrom > 0.6 * GameConfig.normalSpeed && dropped > 0.4 * GameConfig.normalSpeed) {
        _brakeTold = true;
        ride?.hardBrake();
      }
    } else {
      _brakeFrom = -1;
      _brakeTold = false;
    }
    _prevSpeed = p.speed;
  }

  /// Đang nhích trong đoạn tắc đường cửa ngõ.
  bool get _inJam {
    final j = g._events.jam;
    final s = g.player.s;
    return j != null && j.filled && g.dir > 0 && s > j.from - 300 && s < j.head + 40 && g.player.speed < 0.35 * GameConfig.normalSpeed;
  }

  /// Tốc độ vợ thấy còn yên tâm (chở con nhỏ): phố 50, quốc lộ xe máy 60 / ô
  /// tô 85, cao tốc 110 km/h; qua chốt thì theo biển hạn chế.
  double get _comfortKmh {
    final moto = g.spec.kind == VehicleKind.motorbike;
    return switch (g.layout.kindAt(g.player.s)) {
      RoadKind.city => moto ? 50 : 55,
      RoadKind.highway => moto ? 62 : 88,
      RoadKind.expressway => 112,
    };
  }

  /// Quán / cây xăng phía trước cùng chiều còn bao xa (km), trong 14 km.
  double? get _nextStopKm {
    final s = g.player.s;
    final reach = 14 * GameConfig.unitsPerKm;
    double? best;
    for (final t in g.layout.stallsBetween(s + 120, s + reach)) {
      if (t.side != g.dir) continue;
      if (!t.kind.food && t.kind != StallKind.xang) continue;
      final km = (t.s - s) / GameConfig.unitsPerKm;
      if (best == null || km < best) best = km;
    }
    return best;
  }

  /// Sập ổ gà, quệt lề mạnh.
  void bump() => ride?.bump();

  /// Vào quán: cả nhà xuống xe duỗi chân, bé đi vệ sinh.
  void stopAt() => ride?.stopAt();

  /// Đang ngồi quán (mỗi khung).
  void resting(double dt) {
    final r = ride;
    if (r == null) return;
    _resting = true;
    r.rest(dt);
  }

  /// Gọi món ở quán: món cho bé thì bé vui lên.
  void ate(StallItem item) {
    if (item is FamilySnack) ride?.eat(item);
  }

  FamilyHud? get hud => ride?.hud;

  /// Điểm cả nhà của chặng (về tới nơi thì cộng thưởng bé còn vui).
  int score({required bool arrived}) {
    final r = ride;
    if (r == null) return 0;
    return r.score + (arrived ? r.arrivalBonus : 0);
  }
}

/// Chở cả nhà: Flutter hỏi chế độ đang bật chưa và mua đồ cho bé ở quán.
extension FamilyStall on VeQueGame {
  /// Đang chở vợ con về quê.
  bool get familyRide => _family.on;

  /// Trạng thái bé trên xe (để kiểm thử, gỡ lỗi); null khi đi một mình.
  FamilyRide? get familyState => _family.ride;

  /// Mua bim bim / hộp sữa cho bé (đã ngồi xuống quán, cây xăng).
  void orderSnack(FamilySnack snack) {
    if (!_served || !_family.on) return;
    if (lixi < snack.price) {
      onNotice(const GameNotice('Không đủ lì xì rồi!', kind: NoticeKind.warning));
      return;
    }
    lixi -= snack.price;
    clock.addPenalty(snack.minutes);
    onSound(GameSound.gift);
    _family.ate(snack);
    onNotice(GameNotice('${snack.name} cho bé (−${snack.price} lì xì) · bé vui +${snack.patience.round()}', kind: NoticeKind.money));
    if (clock.isOver) leaveStall();
  }
}
