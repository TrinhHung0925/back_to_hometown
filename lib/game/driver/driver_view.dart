part of '../ve_que_game.dart';

/// Một thứ cần vẽ trong cảnh ghế lái, xếp từ xa tới gần.
class _Drawn {
  _Drawn(this.depth, this.paint);

  final double depth;
  final void Function(Canvas canvas) paint;
}

/// Góc nhìn ghế lái: dựng lại con đường từ mắt người lái theo phối cảnh —
/// trời, dãy núi / lũy tre phía chân trời, mặt đường (dùng chung cách dựng
/// với bản đồ), nhà cửa, cây cối, quán xá, xe cộ dựng đứng; đèn đêm, mưa;
/// khung xe / ghi-đông của mình phía trước. Lối chơi giữ nguyên.
class _DriverView extends Component {
  _DriverView(this.game) : super(priority: 100);

  final VeQueGame game;
  final DriverCamera cam = DriverCamera();
  DriverArt? art;

  static const double _u = DriverArt.unitsPerMeter;
  static const double _half = GameConfig.roadHalfWidth;

  double _heading = 0;
  double _roll = 0;
  double _bob = 0;
  double _steer = 0;
  bool _ready = false;

  /// Mức chi tiết (0 thấp … 2 cao): máy yếu, khung hình chậm thì vẽ gần lại.
  int _quality = 2;
  double _slow = 0;
  double _fast = 0;

  /// Số xe AI tối đa (nhân với mức của bản đồ) theo mức chi tiết.
  int get trafficScale => const [2, 2, 3][_quality];

  /// Camera nhìn ra sau cho gương chiếu hậu.
  final DriverCamera _mirrorCam = DriverCamera();

  final Map<Image, Paint> _clampPaints = {};
  final Map<Image, Paint> _repeatPaints = {};
  final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  final List<(Offset, double, Color)> _glows = [];

  // ------------------------------------------------------------- Camera
  /// Đặt mắt người lái theo tư thế xe mình (gọi mỗi khung hình).
  void place(double dt) {
    final g = game;
    final pose = g._pose;
    final len = g.spec.length, wid = g.spec.width;
    final moto = g.spec.kind == VehicleKind.motorbike;
    final (eye, fwd, side, fov) = switch (g.spec.kind) {
      VehicleKind.motorbike => (1.65 * _u, 0.0, 0.0, 82.0),
      VehicleKind.car => (1.3 * _u, -0.06 * len, -0.2 * wid, 74.0),
      VehicleKind.bus => (2.5 * _u, 0.4 * len, -0.26 * wid, 72.0),
    };
    cam
      ..x = pose.x + pose.fx * fwd + pose.rx * side
      ..y = pose.y + pose.fy * fwd + pose.ry * side
      ..eye = eye;
    final target = atan2(pose.fy, pose.fx);
    if (!_ready) {
      _heading = target;
      _ready = true;
    } else {
      _heading += VeQueGame._wrapAngle(target - _heading) * (1 - exp(-14 * dt));
    }
    cam.heading = _heading;
    if (dt > 0.04) {
      _slow += dt;
    } else {
      _slow = max(0, _slow - 0.4 * dt);
    }
    _fast = dt < 1 / 50 ? _fast + dt : 0;
    if (_slow > 1.5 && _quality > 0) {
      _quality--;
      _slow = 0;
    } else if (_fast > 8 && _quality < 2) {
      _quality++;
      _fast = 0;
    }
    cam.far = const [2300.0, 3100.0, 4200.0][_quality];
    final shot = art?.cockpitInfo[switch (g.spec.kind) {
      VehicleKind.motorbike => 'moto',
      VehicleKind.car => 'car',
      VehicleKind.bus => 'bus',
    }];
    final camInfo = shot is Map && g.spec.kind != VehicleKind.motorbike ? shot['camera'] : null;
    final baseFov = camInfo is Map && camInfo['hfov_deg'] is num ? (camInfo['hfov_deg'] as num).toDouble() : fov;
    final speedRatio = (g.player.speed / g.spec.maxSpeed).clamp(0.0, 1.0);
    cam.hfov = (baseFov + 5 * speedRatio) * pi / 180;
    final steer = (g.player.lateralVelocity / g.spec.lateralSpeed).clamp(-1.0, 1.0);
    _steer += (steer - _steer) * (1 - exp(-8 * dt));
    // Xe máy nghiêng theo cua và theo tay lái; ô tô, xe khách không nghiêng.
    final lean = moto
        ? (g.player.curvature * g.dir * g.player.speed * g.player.speed * 0.0035 + _steer * 0.1 * speedRatio).clamp(-0.3, 0.3)
        : 0.0;
    _roll += (lean - _roll) * (1 - exp(-5 * dt));
    _bob = sin(g._time * 23) * 0.0015 * speedRatio + (g._shake > 0 ? (g._random.nextDouble() - 0.5) * 0.03 * g._shake : 0);
  }

  // -------------------------------------------------------------- Vẽ
  @override
  void render(Canvas canvas) {
    final a = art;
    if (a == null || !game._driverActive) return;
    final size = Size(game.size.x, game.size.y);
    cam.setup(size, horizon: 0.4 + _bob);
    _glows.clear();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (_roll.abs() > 1e-4) {
      final pivot = Offset(size.width / 2, size.height * 0.85);
      canvas
        ..translate(pivot.dx, pivot.dy)
        ..rotate(-_roll)
        ..translate(-pivot.dx, -pivot.dy);
    }
    final big = Rect.fromLTWH(-size.width * 0.3, -size.height * 0.4, size.width * 1.6, size.height * 1.8);
    _sky(canvas, big, a);
    _terrain(canvas, big);
    final ground = PerspectiveGroundSink(canvas, cam);
    game._roadRenderer.paintGround(ground);
    _groundExtras(ground);
    _cultureGround(ground);
    _haze(canvas, big);
    _fog(canvas, big);
    _objects(canvas, a);
    canvas.restore();
    _night(canvas, size);
    _cultureNight(canvas, size);
    _rainFx(canvas, size);
    _cockpit(canvas, size, a);
  }

  double get _night01 => game.nightLevel;

  Color get _horizonColor {
    final n = _night01;
    final day = Color.lerp(const Color(0xffDCE5EA), const Color(0xffB9C0C6), game._rain.clamp(0.0, 1.0))!;
    if (n < 0.5) return Color.lerp(day, const Color(0xffE9B38C), n * 2)!;
    return Color.lerp(const Color(0xffE9B38C), const Color(0xff1C2438), (n - 0.5) * 2)!;
  }

  Color get _zenithColor {
    final n = _night01;
    final day = Color.lerp(const Color(0xff5F8FC2), const Color(0xff8F979F), game._rain.clamp(0.0, 1.0))!;
    if (n < 0.5) return Color.lerp(day, const Color(0xff53618A), n * 2)!;
    return Color.lerp(const Color(0xff53618A), const Color(0xff0B1020), (n - 0.5) * 2)!;
  }

  /// Bầu trời (ảnh toàn cảnh trôi theo hướng nhìn) và dãy núi / lũy tre xa.
  void _sky(Canvas canvas, Rect r, DriverArt a) {
    final hy = cam.horizonY;
    canvas.drawRect(
      Rect.fromLTRB(r.left, r.top, r.right, hy + 2),
      Paint()..shader = Gradient.linear(Offset(0, hy - cam.focal * 0.75), Offset(0, hy), [_zenithColor, _horizonColor]),
    );
    final n = _night01;
    final layers = <(String, double)>[
      if (n < 0.6) ('sky_day', 1 - (n / 0.6).clamp(0.0, 1.0) * (n > 0.3 ? 1 : 0.5)),
      if (n > 0.2 && n < 0.9) ('sky_dusk', 1 - ((n - 0.55).abs() / 0.35).clamp(0.0, 1.0)),
      if (n > 0.6) ('sky_night', ((n - 0.6) / 0.3).clamp(0.0, 1.0)),
    ];
    // Mỗi ảnh trời phủ 180° hướng nhìn, 0–40° độ cao.
    final tileW = cam.focal * pi;
    final tileH = cam.focal * tan(40 * pi / 180);
    for (final (key, alpha) in layers) {
      final sky = a.props[key];
      if (sky == null || alpha <= 0.01) continue;
      _panorama(canvas, r, sky.image, tileW, hy - tileH, tileH, alpha * (1 - 0.5 * game._rain.clamp(0.0, 1.0)));
    }
    final hz = a.props[_horizonKey()];
    if (hz != null) {
      // Mỗi ảnh chân trời phủ 90° hướng nhìn, 0–10° độ cao.
      final w = cam.focal * pi / 2;
      final h = cam.focal * tan(10 * pi / 180);
      _panorama(canvas, r, hz.image, w, hy - h + 3, h, 1, tint: _horizonColor);
    }
  }

  String _horizonKey() => game.layout.kindAt(game.player.s) == RoadKind.city
      ? 'horizon_city'
      : switch (game.setup.theme) {
          MapTheme.coast => 'horizon_coast',
          MapTheme.mountain => 'horizon_mountain',
          _ => 'horizon_delta',
        };

  /// Ảnh lặp ngang quanh 360° theo hướng nhìn.
  void _panorama(Canvas canvas, Rect r, Image img, double tileW, double top, double h, double alpha, {Color? tint}) {
    final shift = (_heading / (2 * pi) * tileW * (2 * pi * cam.focal / tileW)) % tileW;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, alpha);
    if (tint != null && _night01 > 0.4) {
      paint.colorFilter = ColorFilter.mode(Color.lerp(const Color(0xffFFFFFF), const Color(0xff39415A), (_night01 - 0.4) / 0.6)!, BlendMode.modulate);
    }
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    for (var x = r.left - shift; x < r.right; x += tileW) {
      canvas.drawImageRect(img, src, Rect.fromLTWH(x, top, tileW + 0.5, h), paint);
    }
  }

  /// Đất nền dưới chân trời (ngoài dải đất bản đồ vẽ tới).
  void _terrain(Canvas canvas, Rect r) {
    final hy = cam.horizonY;
    final near = _groundColor;
    final dim = 1 - 0.75 * game.darkness;
    canvas.drawRect(
      Rect.fromLTRB(r.left, hy - 1, r.right, r.bottom),
      Paint()
        ..shader = Gradient.linear(Offset(0, hy), Offset(0, hy + cam.height * 0.22), [
          _horizonColor,
          Color.fromRGBO((near.r * 255 * dim).round(), (near.g * 255 * dim).round(), (near.b * 255 * dim).round(), 1),
        ]),
    );
  }

  /// Màu đất nền gần (ngoài dải đất bản đồ vẽ tới).
  Color get _groundColor => switch (game.layout.kindAt(game.player.s)) {
      RoadKind.city => const Color(0xff8B877F),
      RoadKind.highway => switch (game.setup.theme) {
          MapTheme.coast => const Color(0xffB9AE84),
          MapTheme.mountain => const Color(0xff3D5636),
          MapTheme.mekong => const Color(0xffA99A55),
          _ => game.setup.south ? const Color(0xffA99A55) : const Color(0xff6F8248),
        },
      RoadKind.expressway => const Color(0xff74874D),
    };

  /// Hơi sương xa che chỗ mặt đất hết tầm vẽ.
  void _haze(Canvas canvas, Rect r) {
    final hy = cam.horizonY;
    final c = _horizonColor;
    canvas.drawRect(
      Rect.fromLTRB(r.left, hy - 2, r.right, hy + cam.height * 0.07),
      Paint()..shader = Gradient.linear(Offset(0, hy), Offset(0, hy + cam.height * 0.07), [c.withValues(alpha: 0.9), c.withValues(alpha: 0)]),
    );
  }

  /// Ổ gà, vũng nước nằm trên mặt đường; boong phà trên mặt sông.
  void _groundExtras(PerspectiveGroundSink ground) {
    final f = game._events.ferry;
    if (f != null && game.images.containsKey(Img.imgFerry)) {
      final (x, y) = game.road.worldAt(f.center, 0);
      ground.image(game.images.fromCache(Img.imgFerry), Offset(x, y), game.road.at(f.center).heading + pi / 2, _Ferry.width,
          _Ferry.length, _image);
    }
    for (final (p, _) in game._pickups) {
      if (p.consumed) continue;
      final at = game.road.at(p.s);
      final (x, y) = game.road.worldAt(p.s, p.d);
      switch (p.kind) {
        case PickupKind.pothole:
          final img = game.images.fromCache(Img.potholes[p.s.round() % Img.potholes.length]);
          ground.image(img, Offset(x, y), at.heading, p.length, p.width, _image);
        case PickupKind.puddle:
          ground.polygon([
            for (var i = 0; i < 10; i++)
              Offset(x, y) +
                  Offset(cos(at.heading) * cos(i * pi / 5) * p.length / 2 - sin(at.heading) * sin(i * pi / 5) * p.width / 2,
                      sin(at.heading) * cos(i * pi / 5) * p.length / 2 + cos(at.heading) * sin(i * pi / 5) * p.width / 2),
          ], Paint()..color = const Color(0x8C5E6E7A));
        case PickupKind.sand:
          ground.polygon([
            for (var i = 0; i < 12; i++)
              Offset(x, y) +
                  Offset(cos(at.heading) * cos(i * pi / 6) * p.length / 2 - sin(at.heading) * sin(i * pi / 6) * p.width / 2,
                      sin(at.heading) * cos(i * pi / 6) * p.length / 2 + cos(at.heading) * sin(i * pi / 6) * p.width / 2),
          ], Paint()..color = const Color(0xB3D9C69A));
        case PickupKind.lixi:
        case PickupKind.gift:
          break;
      }
    }
  }

  // ---------------------------------------------------------- Cảnh đứng
  void _objects(Canvas canvas, DriverArt a) {
    final items = <_Drawn>[];
    final camS = game.player.s;
    _scenery(items, a, camS);
    _cliff(items, a, camS);
    _rails(items, camS);
    _poles(items);
    _stalls(items, a, camS);
    _features(items, a, camS);
    _gates3d(items, a, camS);
    _eventProps(items, a, camS);
    _critters(items, a);
    _traffic(items, a);
    items.sort((x, y) => y.depth.compareTo(x.depth));
    for (final it in items) {
      it.paint(canvas);
    }
  }

  double _fade(double z) {
    final t = ((z - cam.far * 0.7) / (cam.far * 0.3)).clamp(0.0, 1.0);
    return (1 - t * t * (3 - 2 * t)) * (1 - _fogAt(z));
  }

  /// Độ đục sương mù ở khoảng cách [z] (0 trong suốt … gần 1 trắng hẳn).
  double _fogAt(double z) {
    final fog = game._events.fog;
    if (fog < 0.02) return 0;
    final k = z / game._events.visibility;
    return fog * (1 - exp(-1.3 * k * k));
  }

  /// Sương mù: trời trắng đục, mặt đất mờ dần theo khoảng cách (vật đứng
  /// thì mờ theo [_fade]).
  void _fog(Canvas canvas, Rect r) {
    final fog = game._events.fog;
    if (fog < 0.02) return;
    final dim = 1 - 0.7 * game.darkness;
    final c = Color.fromRGBO((222 * dim).round(), (228 * dim).round(), (232 * dim).round(), 1);
    final hy = cam.horizonY;
    canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, hy + 1), Paint()..color = c.withValues(alpha: 0.9 * fog));
    // Hàng điểm ảnh y dưới chân trời ứng với mặt đất cách z = focal·eye / (y − chân trời).
    final ks = [8.0, 3.0, 1.6, 1.0, 0.6, 0.3];
    final ys = <double>[], colors = <Color>[];
    for (final k in ks) {
      final z = k * game._events.visibility;
      ys.add(hy + cam.focal * cam.eye / z);
      colors.add(c.withValues(alpha: _fogAt(z)));
    }
    final top = hy, bottom = max(ys.last, hy + 2);
    canvas.drawRect(
      Rect.fromLTRB(r.left, top, r.right, bottom),
      Paint()
        ..shader = Gradient.linear(Offset(0, top), Offset(0, bottom), [c.withValues(alpha: 0.9 * fog), ...colors],
            [0, for (final y in ys) ((y - top) / (bottom - top)).clamp(0.0, 1.0)]),
    );
  }

  static final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  Paint _clamp(Image img) => _clampPaints.putIfAbsent(
      img, () => Paint()..shader = ImageShader(img, TileMode.clamp, TileMode.clamp, _identity, filterQuality: FilterQuality.medium));

  Paint _repeat(Image img) => _repeatPaints.putIfAbsent(
      img, () => Paint()..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, _identity, filterQuality: FilterQuality.medium));

  /// Ảnh đứng trên mặt đất tại (wx, wy): rộng [w], cao [h] (đơn vị bản đồ).
  Rect? _board(List<_Drawn> items, double wx, double wy, double w, double h, Image? img,
      {bool mirror = false,
      Color fallback = const Color(0xff5E7444),
      double lift = 0,
      double bias = 0,
      double anchorY = 1,
      void Function(Canvas c, Rect rect, double fade)? after}) {
    final p = cam.toCam(wx, wy, lift);
    if (p.z < DriverCamera.near * 2 || p.z > cam.far) return null;
    final k = cam.focal / p.z;
    final base = cam.project(p);
    final rw = w * k, rh = h * k;
    final top = base.dy - rh * anchorY;
    if (base.dx + rw / 2 < -cam.width * 0.3 || base.dx - rw / 2 > cam.width * 1.3 || top > cam.height * 1.2) return null;
    final rect = Rect.fromLTWH(base.dx - rw / 2, top, rw, rh);
    final fade = _fade(p.z);
    items.add(_Drawn(p.z + bias, (c) {
      if (img == null) {
        if (fallback.a > 0) c.drawRect(rect, Paint()..color = fallback.withValues(alpha: fallback.a * fade));
      } else {
        _image.color = Color.fromRGBO(255, 255, 255, fade);
        final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
        if (mirror) {
          c.save();
          c.translate(rect.center.dx, 0);
          c.scale(-1, 1);
          c.translate(-rect.center.dx, 0);
          c.drawImageRect(img, src, rect, _image);
          c.restore();
        } else {
          c.drawImageRect(img, src, rect, _image);
        }
      }
      after?.call(c, rect, fade);
    }));
    return rect;
  }

  /// Mặt đứng từ chân [a] tới chân [b] (toạ độ thế giới), cao [z0]..[z1],
  /// dán [paint] theo toạ độ vân u ([ua] → [ub]) và v ([vt] trên → [vb] dưới).
  /// Đỉnh phía [b] có thể cao khác ([z1b], vân [vtb]) cho mép trên nhấp nhô.
  void _wall(List<_Drawn> items, Offset a, Offset b, double z0, double z1, Paint paint, double ua, double ub, double vt, double vb,
      {double bias = 0, Color? tint, double? z1b, double? vtb}) {
    final q = [
      cam.toCam(a.dx, a.dy, z1, ua, vt),
      cam.toCam(b.dx, b.dy, z1b ?? z1, ub, vtb ?? vt),
      cam.toCam(b.dx, b.dy, z0, ub, vb),
      cam.toCam(a.dx, a.dy, z0, ua, vb),
    ];
    if (q.every((p) => p.z < DriverCamera.near) || q.every((p) => p.z > cam.far)) return;
    final depth = q.map((p) => p.z).reduce(max) * 0.5 + q.map((p) => p.z).reduce(min) * 0.5;
    final fade = _fade(depth);
    items.add(_Drawn(depth + bias, (c) {
      final p = Paint()
        ..shader = paint.shader
        ..color = (tint ?? paint.color).withValues(alpha: fade);
      PerspectiveGroundSink(c, cam).wall(q, p);
    }));
  }

  Offset _at(double s, double d) {
    final (x, y) = game.road.worldAt(s, d);
    return Offset(x, y);
  }

  // Cây, chuối, nhà.
  void _scenery(List<_Drawn> items, DriverArt a, double camS) {
    final city = game.layout.kindAt(camS) == RoadKind.city;
    for (final it in game._scenery.items) {
      final ahead = (it.s - camS) * game.dir;
      if (ahead < -300 || ahead > cam.far) continue;
      final o = _at(it.s, it.d);
      switch (it.kind) {
        case SceneryKind.tree:
          final species = it.species ?? (!city && game.setup.theme == MapTheme.delta && it.seed % 5 == 0 ? 'tree_bamboo' : 'tree_broad');
          final art = a.prop('${species}_${1 + it.seed % (_variants[species] ?? 2)}');
          if (art == null) {
            final w = it.size * (_widthFactor[species] ?? 1.15);
            _board(items, o.dx, o.dy, w, w * 1.3, null, mirror: it.seed.isOdd);
          } else {
            final h = art.heightM * _u * (it.size / (_refSize[species] ?? 100)).clamp(0.7, 1.3);
            _board(items, o.dx, o.dy, h * art.aspect, h, art.image, mirror: it.seed.isOdd);
          }
        case SceneryKind.banana:
          final art = a.prop('banana_${1 + it.seed % 2}');
          final h = (art?.heightM ?? 3.5) * _u * (it.size / 60).clamp(0.75, 1.3);
          _board(items, o.dx, o.dy, art == null ? h : h * art.aspect, h, art?.image, mirror: it.seed.isOdd);
        case SceneryKind.house:
          _house3d(items, a, it, camS);
      }
    }
  }

  /// Số ảnh của mỗi loài cây; bề ngang ảnh đứng so với tán nhìn từ trên.
  static const Map<String, int> _variants = {
    'tree_broad': 4,
    'tree_bamboo': 2,
    'palm_coconut': 2,
    'tree_casuarina': 2,
    'tree_pine': 2,
    'bush': 3,
    'banana': 2,
  };
  /// Cỡ tán nhìn từ trên ứng với cây cao đúng như ảnh đứng.
  static const Map<String, double> _refSize = {
    'palm_coconut': 125,
    'tree_pine': 105,
    'tree_casuarina': 90,
  };
  static const Map<String, double> _widthFactor = {
    'tree_broad': 1.15,
    'tree_bamboo': 1.0,
    'palm_coconut': 1.2,
    'tree_casuarina': 0.9,
    'tree_pine': 0.85,
    'bush': 1.1,
  };

  void _house(List<_Drawn> items, DriverArt a, SceneryItem it, double camS) {
    final town = game.layout.kindAt(it.s) == RoadKind.city;
    final key = town ? 'house_town_${1 + it.seed % 6}' : 'house_village_${1 + it.seed % 4}';
    final art = a.prop(key);
    final side = it.d.sign;
    final w = it.size;
    final h = art == null ? (town ? 150.0 : 95.0) : art.heightM * _u;
    // Đứng trên đường nhìn vào: bên phải thì đầu xa (s lớn) là mép trái ảnh.
    final left = _at(it.s + side * w / 2, it.d), right = _at(it.s - side * w / 2, it.d);
    if (art != null) {
      final img = art.image;
      _wall(items, left, right, 0, h, _clamp(img), 0, img.width.toDouble(), 0, img.height.toDouble(), tint: _dayTint);
    } else {
      _wall(items, left, right, 0, h, Paint()..color = const Color(0xffD9C9A4), 0, 1, 0, 1);
    }
    // Tường hông đầu gần mắt (nhà liền kề che bớt, đúng như thật).
    final nearS = camS < it.s ? it.s - w / 2 : it.s + w / 2;
    final depth = min(it.house?.size.y ?? 120, 140.0);
    final wallArt = a.prop('wall_side_${1 + it.seed % 3}');
    final a0 = _at(nearS, it.d), a1 = _at(nearS, it.d + side * depth);
    // Nhà quê mái dốc: tường hông chỉ tới chân mái.
    final hw = h * (town ? 0.8 : 0.5);
    if (wallArt != null) {
      final img = wallArt.image;
      final rep = img.width / (3 * _u);
      _wall(items, a0, a1, 0, hw, _repeat(img), 0, depth * rep, 0, hw * rep, bias: 2, tint: _dayTint);
    } else {
      _wall(items, a0, a1, 0, hw, Paint()..color = const Color(0xffB9AC8E), 0, 1, 0, 1, bias: 2);
    }
  }

  /// Ánh sáng ban ngày / chập tối lên mặt tường (đêm thì tối hẳn).
  Color get _dayTint => const Color(0xffFFFFFF);

  /// Đèo núi: vách đá taluy dựng đứng bên trái đường (phía d âm).
  void _cliff(List<_Drawn> items, DriverArt a, double camS) {
    if (game.setup.theme != MapTheme.mountain) return;
    final rock = game.images.containsKey(Img.texRock) ? game.images.fromCache(Img.texRock) : null;
    final paint = rock != null ? _repeat(rock) : (Paint()..color = const Color(0xff8B867D));
    final rep = rock == null ? 1.0 : rock.width / (10 * _u);
    const step = 60.0;
    final from = (min(camS - 200, camS + game.dir * cam.far) / step).floor() * step;
    final to = max(camS - 200 * game.dir, camS + game.dir * cam.far);
    for (var s = from; s < to; s += step) {
      if (game.layout.kindAt(s) != RoadKind.highway || _stallNear(s, -1) || _gateNear(s)) continue;
      final ahead = (s - camS) * game.dir;
      if (ahead < -step * 2 || ahead > cam.far) continue;
      // Đỉnh vách nhấp nhô; vân bám theo độ cao thật để không bị kéo giãn.
      double top(double at) => 160 + 70 * sin(at / 170) + 40 * sin(at / 53 + 1.3);
      final d = -(_half + 15);
      final t0 = top(s), t1 = top(s + step);
      _wall(items, _at(s, d), _at(s + step, d), 0, t0, paint, s * rep, (s + step) * rep, (300 - t0) * rep, 300 * rep,
          bias: 30, z1b: t1, vtb: (300 - t1) * rep);
    }
  }

  /// Đoạn rẽ vào đường cứu nạn (hộ lan bên phải chừa trống).
  bool _rampNear(double s) => game._events.ramps.any((r) => s > r.s - 40 && s < r.s + GameConfig.rampLength + 40);

  /// Có quán / cây xăng ở phía [side] gần [s]: vách đá, hộ lan chừa lối vào.
  bool _stallNear(double s, double side) => game.layout.stallsBetween(s - 190, s + 190).any((t) => t.side == side);

  /// Hộ lan tôn sóng dựng đứng: mép vực đường đèo và hai bên cao tốc; dải
  /// phân cách bê tông giữa hai chiều cao tốc.
  void _rails(List<_Drawn> items, double camS) {
    final dir = game.dir;
    final mountain = game.setup.theme == MapTheme.mountain;
    final beam = Paint()..color = const Color(0xffC3C9CF);
    final beamShade = Paint()..color = const Color(0xff8F969D);
    final barrier = Paint()..color = const Color(0xffD9D6CE);
    const w = GameConfig.medianHalfWidth;
    var ahead = -160.0;
    while (ahead < 2600) {
      final step = ahead < 500 ? 36.0 : ahead < 1400 ? 72.0 : 144.0;
      final s0 = camS + dir * ahead, s1 = camS + dir * (ahead + step);
      ahead += step;
      final zone = game.layout.zoneAt(s0);
      final sides = switch (zone.kind) {
        RoadKind.expressway => const [-1.0, 1.0],
        RoadKind.highway when mountain => const [1.0],
        _ => const <double>[],
      };
      for (final side in sides) {
        if (_stallNear(s0, side) || (side > 0 && _rampNear(s0)) || _gateNear(s0)) continue;
        final d = side * (zone.kind == RoadKind.expressway ? _half + 30 : _half + 20);
        // Tấm tôn sáng phía trên, rãnh sóng tối phía dưới (cao 0,5–0,8 m).
        _wall(items, _at(s0, d), _at(s1, d), 13.5, 16.5, beam, 0, 1, 0, 1);
        _wall(items, _at(s0, d), _at(s1, d), 10.5, 13.5, beamShade, 0, 1, 0, 1, bias: 0.1);
        final post = _at(s0, d + side * 2);
        _board(items, post.dx, post.dy, 2.6, 14, null, fallback: const Color(0xff5E646B), bias: 0.2);
      }
      if (zone.kind == RoadKind.expressway &&
          s0 > zone.startS + GameConfig.medianInset &&
          s0 < zone.endS - GameConfig.medianInset) {
        // Mặt dải phân cách quay về phía mình (cao chừng 0,8 m).
        final d = dir * w;
        _wall(items, _at(s0, d), _at(s1, d), 0, 17, barrier, 0, 1, 0, 1);
      }
    }
  }

  // Cột điện và dây điện võng giữa các cột.
  void _poles(List<_Drawn> items) {
    final poles = game._powerLines.poles;
    final pole = Paint()..color = const Color(0xffA9A69F);
    final wire = Paint()
      ..color = const Color(0xff24282C)
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < poles.length; i++) {
      final (s, d) = poles[i];
      final ahead = (s - game.player.s) * game.dir;
      if (ahead < -200 || ahead > cam.far) continue;
      final o = _at(s, d);
      _board(items, o.dx, o.dy, 7, 200, null, fallback: const Color(0xffA9A69F), after: (c, rect, fade) {
        c.drawRect(Rect.fromLTWH(rect.left - rect.width * 3, rect.top + rect.height * 0.04, rect.width * 7, rect.height * 0.025),
            Paint()..color = const Color(0xff6B6F74).withValues(alpha: fade));
      });
      if (i + 1 >= poles.length) continue;
      final (s1, d1) = poles[i + 1];
      if (s1 - s > 200) continue;
      final spans = <List<Offset>>[];
      double depthSum = 0;
      for (final off in [-9.0, 0.0, 9.0]) {
        final pts = <Offset>[];
        for (var k = 0; k <= 8; k++) {
          final t = k / 8;
          final ws = s + (s1 - s) * t;
          final w = _at(ws, d + (d1 - d) * t + off);
          final z = (off == 0 ? 188.0 : 194.0) - 14 * 4 * t * (1 - t);
          final p = cam.toCam(w.dx, w.dy, z);
          if (p.z < DriverCamera.near) {
            pts.clear();
            continue;
          }
          depthSum += p.z;
          pts.add(cam.project(p));
        }
        if (pts.length > 1) spans.add(pts);
      }
      if (spans.isEmpty) continue;
      final depth = depthSum / 27;
      final fade = _fade(depth);
      items.add(_Drawn(depth, (c) {
        wire
          ..strokeWidth = (cam.focal / depth * 1.4).clamp(0.6, 2.2)
          ..color = const Color(0xff24282C).withValues(alpha: fade * 0.9);
        for (final pts in spans) {
          c.drawPath(Path()..addPolygon(pts, false), wire);
        }
      }));
    }
    pole.color = pole.color;
  }

  // Quán ven đường, cây xăng.
  void _stalls(List<_Drawn> items, DriverArt a, double camS) {
    for (final t in game.layout.stallsBetween(camS - 400, camS + cam.far)) {
      if ((t.s - camS) * game.dir < -300) continue;
      if (t.kind == StallKind.xang) {
        _gasStation(items, a, t);
        continue;
      }
      final key = switch (t.kind) {
        StallKind.traDa => 'stall_tra_da',
        StallKind.nuocMia => 'stall_nuoc_mia',
        StallKind.caPheVong => 'stall_ca_phe_vong',
        StallKind.banhMi => 'stall_banh_mi',
        StallKind.com => 'stall_com',
        StallKind.vaXe => 'stall_va_xe',
        StallKind.xangLe => 'stall_xang_le',
        StallKind.xang => 'gas_shop',
      };
      final art = a.prop(key);
      final h = (art?.heightM ?? 3) * _u;
      final w = art == null ? 90.0 : h * art.aspect;
      final o = _at(t.s, t.side * (_half + 40 + w * 0.15));
      _board(items, o.dx, o.dy, w, h, art?.image, mirror: t.side * game.dir < 0 && t.seed.isOdd, fallback: const Color(0xffC8372D));
    }
  }

  void _gasStation(List<_Drawn> items, DriverArt a, Stall t) {
    final side = t.side.toDouble();
    final d1 = side * (_half + 50), d2 = side * (_half + 200);
    const z0 = 112.0, z1 = 140.0;
    final fascia = a.prop('gas_canopy_fascia');
    final paint = fascia != null ? _repeat(fascia.image) : (Paint()..color = const Color(0xffC1121F));
    final rep = fascia == null ? 1.0 : fascia.image.width / (12 * _u);
    final vb = fascia?.image.height.toDouble() ?? 1;
    final s0 = t.s - 105, s1 = t.s + 105;
    // Mặt trước mái che (quay ra đường) và mặt hông phía gần.
    _wall(items, _at(side > 0 ? s1 : s0, d1), _at(side > 0 ? s0 : s1, d1), z0, z1, paint, 0, 210 * rep, 0, vb);
    final nearS = game.player.s < t.s ? s0 : s1;
    _wall(items, _at(nearS, d1), _at(nearS, d2), z0, z1, paint, 0, 150 * rep, 0, vb, bias: 3);
    // Trần mái che sáng đèn.
    final under = [
      cam.toCam(_at(s0, d1).dx, _at(s0, d1).dy, z0),
      cam.toCam(_at(s1, d1).dx, _at(s1, d1).dy, z0),
      cam.toCam(_at(s1, d2).dx, _at(s1, d2).dy, z0),
      cam.toCam(_at(s0, d2).dx, _at(s0, d2).dy, z0),
    ];
    if (!under.every((p) => p.z < DriverCamera.near) && !under.every((p) => p.z > cam.far)) {
      final depth = under.map((p) => p.z).reduce(max) + 4;
      items.add(_Drawn(depth, (c) => PerspectiveGroundSink(c, cam).wall(under, Paint()..color = const Color(0xffE6E4DE))));
    }
    for (final ds in [-60.0, 60.0]) {
      final o = _at(t.s + ds, (d1 + d2) / 2);
      _board(items, o.dx, o.dy, 9, z0, null, fallback: const Color(0xffEDEDED));
    }
    final pump = a.prop('gas_pump');
    for (final ds in [-30.0, 30.0]) {
      final o = _at(t.s + ds, (d1 + d2) / 2);
      final h = (pump?.heightM ?? 2.2) * _u;
      _board(items, o.dx, o.dy, pump == null ? 20 : h * pump.aspect, h, pump?.image, fallback: const Color(0xffC1121F));
    }
    final shop = a.prop('gas_shop');
    if (shop != null) {
      final o = _at(t.s + 40, side * (_half + 270));
      final h = shop.heightM * _u;
      _board(items, o.dx, o.dy, h * shop.aspect, h, shop.image);
    }
    final sign = a.prop('gas_price_sign');
    if (sign != null) {
      final o = _at(t.s - side * 150, side * (_half + 35));
      final h = sign.heightM * _u;
      _board(items, o.dx, o.dy, h * sign.aspect, h, sign.image);
    }
  }

  // Đèn giao thông, chốt CSGT, biển báo, trạm thu phí, điểm đón, cổng đích.
  void _features(List<_Drawn> items, DriverArt a, double camS) {
    final dir = game.dir;
    final from = camS - 400, to = camS + cam.far;
    for (final l in game.layout.lightsBetween(min(from, camS - cam.far), max(to, camS + cam.far))) {
      if ((l.s - camS) * dir < -200 || (l.s - camS) * dir > cam.far) continue;
      final color = l.colorAt(game._time);
      final stop = dir > 0 ? l.stopLine : l.oncomingStopLine;
      final far = l.s + dir * (l.halfWidth + 25);
      for (final (s, d) in [(stop - dir * 10, dir * (_half + 18)), (far, -dir * (_half + 18))]) {
        final o = _at(s, d);
        // Cần đèn vươn ra phía lòng đường.
        final toRoad = _at(s, d * 0.5);
        _trafficLight(items, a, o, color, armRight: cam.sideOf(toRoad.dx, toRoad.dy) > cam.sideOf(o.dx, o.dy));
      }
    }
    for (final c in game.layout.checkpoints) {
      final ahead = (c.s - camS) * dir;
      if (ahead < -400 || ahead > cam.far + 800) continue;
      _prop(items, a, 'police_tent', c.s, _half + 95, fallbackH: 3.2, fallback: const Color(0xff2F6FB5));
      _prop(items, a, 'police_table', c.s - 40, _half + 55, fallbackH: 0.9);
      _prop(items, a, 'police_officer_radar', c.radarS(dir), (_half + 22) * (dir > 0 ? 1 : 1), fallbackH: 1.75, fallback: const Color(0xffC4D23E));
      _prop(items, a, game._wavedBy == c ? 'police_officer_wave' : 'police_officer_stand', c.s - 120, _half + 18,
          fallbackH: 1.75, fallback: const Color(0xffC4D23E));
      for (var k = 0; k < 5; k++) {
        _prop(items, a, 'traffic_cone', c.s - 260 + k * 60, _half + 6, fallbackH: 0.7, fallback: const Color(0xffF26B1D));
      }
      final signS = dir > 0 ? c.signS : c.oncomingSignS;
      _prop(items, a, 'sign_speed_${_limitArt(c.limitKmh)}', signS, dir * (_half + 30), fallbackH: 2.8, fallback: const Color(0xffD62828));
    }
    // Biển báo cua gắt phía trước.
    game.road.ensureAhead(camS + cam.far);
    for (final c in game.road.curvesBetween(min(camS, camS + dir * cam.far), max(camS, camS + dir * cam.far))) {
      if (!c.sharp) continue;
      final signS = dir > 0 ? c.startS - 330 : c.endS + 330;
      if ((signS - camS) * dir < 0) continue;
      final right = c.right == (dir > 0);
      _prop(items, a, right ? 'sign_curve_right' : 'sign_curve_left', signS, dir * (_half + 26), fallbackH: 2.6, fallback: const Color(0xffF2C12E));
    }
    for (final g in game._gates) {
      final t = g.plaza;
      final ahead = (t.s - camS) * dir;
      if (ahead < -300 || ahead > cam.far) continue;
      final edge = t.maxEdge(t.s) + 24;
      final fascia = a.prop('toll_fascia');
      final paint = fascia != null ? _repeat(fascia.image) : (Paint()..color = const Color(0xff2E6FB0));
      final rep = fascia == null ? 1.0 : fascia.image.width / (12 * _u);
      final vb = fascia?.image.height.toDouble() ?? 1;
      _wall(items, _at(t.s, -dir * edge), _at(t.s, dir * edge), 118, 150, paint, 0, 2 * edge * rep, 0, vb);
      for (final d in [-2 * GameConfig.laneWidth - 3, -GameConfig.laneWidth, 0.0, GameConfig.laneWidth, 2 * GameConfig.laneWidth + 3]) {
        final booth = a.prop('toll_booth');
        final h = (booth?.heightM ?? 2.6) * _u;
        final o = _at(t.s - dir * 10, d);
        _board(items, o.dx, o.dy, booth == null ? 26 : h * booth.aspect * 0.8, h, booth?.image, fallback: const Color(0xffE4E7EA));
        if (d != 0) _board(items, _at(t.s - dir * 10, d).dx, _at(t.s - dir * 10, d).dy, 8, 118, null, fallback: const Color(0xffD6D9DC));
      }
    }
    for (final b in game.layout.busStops) {
      final ahead = (b.s - camS) * dir;
      if (ahead < -300 || ahead > cam.far) continue;
      _prop(items, a, 'bus_shelter', b.s, _half + 50, fallbackH: 2.8, fallback: const Color(0xff2F6FB5));
      if (!b.served) {
        for (var k = 0; k < b.passengers; k++) {
          _prop(items, a, 'person_${1 + (b.seed + k) % 8}', b.s - 30 + k * 22, _half + 28, fallbackH: 1.65, fallback: const Color(0xff8E44AD));
        }
      }
    }
    for (final n in game.layout.nails) {
      if (!n.warned) continue;
      final signS = n.s - dir * 280;
      if ((signS - camS) * dir < 0 || (signS - camS) * dir > cam.far) continue;
      _prop(items, a, 'nail_sign', signS, dir * (_half + 14), fallbackH: 1.4, fallback: const Color(0xffC9A06A));
    }
    final f = game.finishS;
    if ((f - camS) * dir > 0 && (f - camS) * dir < cam.far) {
      final arch = a.prop('arch_tet');
      final h = arch == null ? 170.0 : arch.heightM * _u;
      final w = arch == null ? 2 * (_half + 40) : h * arch.aspect;
      final paint = arch != null ? _clamp(arch.image) : (Paint()..color = const Color(0xffC1121F));
      final iw = arch?.image.width.toDouble() ?? 1, ih = arch?.image.height.toDouble() ?? 1;
      _wall(items, _at(f, -dir * w / 2), _at(f, dir * w / 2), 0, h, paint, 0, iw, 0, ih);
    }
  }

  static int _limitArt(int kmh) => kmh <= 55 ? 50 : kmh <= 70 ? 60 : 80;

  void _trafficLight(List<_Drawn> items, DriverArt a, Offset o, LightColor color, {required bool armRight}) {
    final pole = a.prop('traffic_light_pole');
    final head = a.prop('traffic_light_head_${color.name}');
    final glow = switch (color) {
      LightColor.red => const Color(0xffFF3B30),
      LightColor.yellow => const Color(0xffFFC53A),
      LightColor.green => const Color(0xff34E07A),
    };
    final lampV = switch (color) {
      LightColor.red => 0.2,
      LightColor.yellow => 0.42,
      LightColor.green => 0.64,
    };
    final ph = (pole?.heightM ?? 5.2) * _u;
    final tip = pole?.anchor('arm_tip');
    if (pole == null || head == null || tip == null) {
      _board(items, o.dx, o.dy, pole == null ? 6 : ph * pole.aspect, ph, pole?.image, fallback: const Color(0xff3A3E44));
      final hh = (head?.heightM ?? 1.0) * _u;
      _board(items, o.dx, o.dy, head == null ? 14 : hh * head.aspect, hh, head?.image, lift: ph * 0.72, bias: -1, fallback: glow,
          after: (c, rect, fade) {
        if (game.darkness > 0.2) _glows.add((Offset(rect.center.dx, rect.top + rect.height * lampV), rect.width * 0.9, glow));
      });
      return;
    }
    // Ảnh cột có cần vươn sang trái; đèn treo ở đầu cần.
    final mount = head.anchor('mount') ?? const Offset(0.5, 0);
    _board(items, o.dx, o.dy, ph * pole.aspect, ph, pole.image, mirror: armRight, after: (c, rect, fade) {
      final k = rect.height / ph;
      final hw = head.heightM * _u * head.aspect * k, hh = head.heightM * _u * k;
      final u = armRight ? 1 - tip.dx : tip.dx;
      final at = Offset(rect.left + u * rect.width, rect.top + tip.dy * rect.height);
      final mx = armRight ? 1 - mount.dx : mount.dx;
      final box = Rect.fromLTWH(at.dx - mx * hw, at.dy - mount.dy * hh, hw, hh);
      _image.color = Color.fromRGBO(255, 255, 255, fade);
      final src = Rect.fromLTWH(0, 0, head.image.width.toDouble(), head.image.height.toDouble());
      if (armRight) {
        c.save();
        c
          ..translate(box.center.dx, 0)
          ..scale(-1, 1)
          ..translate(-box.center.dx, 0);
        c.drawImageRect(head.image, src, box, _image);
        c.restore();
      } else {
        c.drawImageRect(head.image, src, box, _image);
      }
      if (game.darkness > 0.2) _glows.add((Offset(box.center.dx, box.top + box.height * lampV), box.width * 0.9, glow));
    });
  }

  /// Ảnh đứng theo toạ độ đường (s, d).
  void _prop(List<_Drawn> items, DriverArt a, String key, double s, double d,
      {required double fallbackH, Color fallback = const Color(0xff7C6A55), bool mirror = false, double scale = 1, double lift = 0}) {
    final art = a.prop(key);
    final h = (art?.heightM ?? fallbackH) * _u * scale;
    final w = art == null ? h * 0.45 : h * art.aspect;
    final o = _at(s, d);
    _board(items, o.dx, o.dy, w, h, art?.image, fallback: fallback, mirror: mirror, lift: lift);
  }

  // Lì xì, quà Tết trên đường; gà vịt chó qua đường.
  void _critters(List<_Drawn> items, DriverArt a) {
    for (final (p, _) in game._pickups) {
      if (p.consumed) continue;
      switch (p.kind) {
        case PickupKind.lixi:
          final bob = sin(game._time * 3 + p.s) * 4;
          _prop(items, a, 'lixi_float', p.s, p.d, fallbackH: 1.4, fallback: const Color(0xffD62828), lift: 8 + bob, scale: 5.5);
        case PickupKind.gift:
          _prop(items, a, const ['gift_peach', 'gift_kumquat', 'gift_box'][p.s.round() % 3], p.s, p.d, fallbackH: 1.2, scale: 1.8);
        case PickupKind.pothole:
        case PickupKind.puddle:
        case PickupKind.sand:
          break;
      }
    }
    for (final g in game.animals.groups) {
      for (final an in g.animals) {
        final o = _at(an.s + an.sway, an.d);
        final frame = (an.t * (an.fleeing ? 10 : 6)).floor().isEven;
        final key = switch (an.kind) {
          AnimalKind.duck => an.variant == 1 ? 'duck_white_1' : (frame ? 'duck_1' : 'duck_2'),
          AnimalKind.chicken => frame ? 'chicken_1' : 'chicken_2',
          AnimalKind.dog => frame ? 'dog_1' : 'dog_2',
        };
        // Ảnh quay mặt sang trái: con vật chạy sang phải màn hình thì lật.
        final ahead = _at(an.s + an.sway, an.d + an.dir * 10);
        final movingRight = cam.sideOf(ahead.dx, ahead.dy) > cam.sideOf(o.dx, o.dy);
        final art = a.prop(key);
        final h = (art?.heightM ?? (an.kind == AnimalKind.dog ? 0.65 : 0.45)) * _u * 1.6;
        _board(items, o.dx, o.dy, art == null ? h : h * art.aspect, h, art?.image, mirror: movingRight, fallback: const Color(0xffC8823C));
      }
      final herder = g.herder;
      if (herder != null) _prop(items, a, 'person_${1 + g.s.round() % 8}', g.s + 18, herder, fallbackH: 1.65);
    }
  }

  /// Góc chụp sẵn của ảnh xe: góc so với ngay sau đuôi (dương = mắt mình lệch
  /// sang hông trái xe), tên ảnh, có lật ngang không.
  static const List<(double, String, bool)> _vehicleAngles = [
    (0, 'rear', false), (25, 'l25', false), (-25, 'r25', false), (50, 'l50', false), (-50, 'r50', false), //
    (75, 'l75', false), (-75, 'r75', false), (90, 'side', false), (-90, 'side', true), (115, 'l115', false), //
    (-115, 'r115', false), (145, 'l145', false), (-145, 'r145', false), (180, 'front', false), (-180, 'front', false),
  ];

  /// Góc nhìn ảnh xe: thấy đuôi khi nhìn theo hướng xe chạy, ở làn bên hay
  /// trên khúc cua thì thấy chéo cả hông (ảnh chụp sẵn quanh mô hình 3D).
  (Image, String, bool)? _vehicleView(DriverArt a, String path, double yaw) {
    (Image, String, bool)? best;
    var bestGap = double.infinity;
    for (final (angle, view, mirror) in _vehicleAngles) {
      final gap = (angle - yaw).abs();
      if (gap >= bestGap) continue;
      final img = a.vehicle(path, view);
      if (img == null) continue;
      best = (img, view, mirror);
      bestGap = gap;
    }
    return best;
  }

  // Xe cộ dọc đường: chọn ảnh theo góc giữa hướng xe chạy và hướng từ xe tới
  // mắt mình; xe đường ngang thấy hông.
  void _traffic(List<_Drawn> items, DriverArt a) {
    final raining = game._trafficLayer.raining;
    final dark = game.darkness;
    for (final v in game.traffic.vehicles) {
      final path = TrafficLayer.dressedPath(v.type, v.variant, raining: raining);
      final heading = game.road.at(v.s).heading + (v.oncoming ? pi : 0);
      final hx = cos(heading), hy = sin(heading);
      final center = _at(v.s, v.d);
      final dx = cam.x - center.dx, dy = cam.y - center.dy;
      final dist = max(1e-6, sqrt(dx * dx + dy * dy));
      final yaw = atan2(dx * hy - dy * hx, -(dx * hx + dy * hy)) * 180 / pi;
      final pick = _vehicleView(a, path, yaw);
      final img = pick?.$1;
      final mirror = pick?.$3 ?? false;
      final key = '${DriverArt.baseOf(path)}_${pick?.$2 ?? 'rear'}';
      // Điểm trên mép thân xe gần mắt mình nhất (cùng tia nhìn với tâm xe):
      // đặt ảnh ở đó cho đúng độ to; mặt đất dưới tâm xe trong ảnh lùi lên
      // tương ứng.
      final ux = dx / dist, uy = dy / dist;
      final along = (ux * hx + uy * hy).abs(), across = (ux * hy - uy * hx).abs();
      final r = min(along > 1e-3 ? v.type.length / 2 / along : double.infinity, across > 1e-3 ? v.type.width / 2 / across : double.infinity);
      final near = center + Offset(ux, uy) * min(r, dist * 0.5);
      final ground = a.vehicleGround[key];
      final anchorY = img == null || ground == null
          ? 1.0
          : ((ground.dy + r / _u * _sinBillboardElev * DriverArt.vehiclePixelsPerMeter) / img.height).clamp(0.0, 1.0);
      final w = img == null ? v.type.width : img.width / DriverArt.vehiclePixelsPerMeter * _u;
      final h = img == null ? v.type.width * 0.8 : img.height / DriverArt.vehiclePixelsPerMeter * _u;
      final lamps = a.lamps[DriverArt.baseOf(path)]?[pick?.$2 ?? 'rear'] ?? const <Offset>[];
      final tail = yaw.abs() < 90;
      final braking = v.braking && (v.oncoming ? -1 : 1) == game.dir;
      _board(items, near.dx, near.dy, w, h, img, mirror: mirror, anchorY: anchorY, fallback: const Color(0xff4B5563), after: (c, rect, fade) {
        if (img == null) return;
        if ((v.blinker != 0 || v.hazard) && (game._time * 2.6).floor().isEven) _blink(c, v, center, img, rect, lamps, fade);
        final glowOn = tail ? (braking || dark > 0.25) : dark > 0.25;
        if (!glowOn) return;
        for (final l in lamps) {
          final lx = mirror ? img.width - l.dx : l.dx;
          final p = Offset(rect.left + lx / img.width * rect.width, rect.top + l.dy / img.height * rect.height);
          final r = rect.width * (tail ? (braking ? 0.16 : 0.09) : 0.22);
          _glows.add((p, r, tail ? const Color(0xffFF2A1F) : const Color(0xffFFF3D6)));
          if (tail && braking) c.drawCircle(p, rect.width * 0.035, Paint()..color = const Color(0xffFF5A4E).withValues(alpha: fade));
        }
      });
    }
    for (final v in game.cross.vehicles) {
      final path = TrafficLayer.dressedPath(v.type, v.variant, raining: raining);
      final img = a.vehicle(path, 'side');
      final o = _at(v.s, v.d);
      final next = _at(v.s, v.d + (v.down ? 10 : -10));
      final movingRight = cam.sideOf(next.dx, next.dy) > cam.sideOf(o.dx, o.dy);
      final w = img == null ? v.type.length : img.width / DriverArt.vehiclePixelsPerMeter * _u;
      final h = img == null ? v.type.width * 0.8 : img.height / DriverArt.vehiclePixelsPerMeter * _u;
      _board(items, o.dx, o.dy, w, h, img, mirror: movingRight, fallback: const Color(0xff4B5563));
    }
  }

  /// Xi-nhan (một bên) hoặc đèn khẩn cấp (cả hai bên) nháy vàng cam.
  void _blink(Canvas c, TrafficVehicle v, Offset o, Image img, Rect rect, List<Offset> lamps, double fade) {
    final pts = lamps.isEmpty ? [Offset(img.width * 0.5, img.height * 0.55)] : lamps;
    final single = pts.length == 1;
    final xs = pts.map((p) => p.dx);
    final y = pts.first.dy;
    final spread = img.width * 0.32;
    final left = single ? pts.first.dx - spread : xs.reduce(min), right = single ? pts.first.dx + spread : xs.reduce(max);
    final List<double> at;
    if (v.hazard) {
      at = [left, right];
    } else {
      final toward = _at(v.s, v.d + v.blinker * 20);
      at = [cam.sideOf(toward.dx, toward.dy) > cam.sideOf(o.dx, o.dy) ? right : left];
    }
    for (final x in at) {
      final p = Offset(rect.left + x / img.width * rect.width, rect.top + y / img.height * rect.height);
      _glows.add((p, rect.width * 0.14, const Color(0xffFFA51F)));
      c.drawCircle(p, max(1.2, rect.width * 0.028), Paint()..color = const Color(0xffFFC24A).withValues(alpha: fade));
    }
  }

  // Khách vẫy xe, CSGT phân luồng chỗ tắc đường, biển đường cứu nạn, biển
  // sương mù.
  void _eventProps(List<_Drawn> items, DriverArt a, double camS) {
    final ev = game._events;
    final dir = game.dir;
    bool inView(double s) => (s - camS) * dir > -200 && (s - camS) * dir < cam.far;
    final frame = (game._time * 2.2).floor().isEven ? 1 : 2;
    for (final h in ev.hitches) {
      if (h.state == _HitchState.riding || !inView(h.standS)) continue;
      if (h.state == _HitchState.done && (h.standS - camS).abs() > 900) continue;
      final key = 'hitch_${h.art}_$frame';
      _prop(items, a, a.prop(key) != null ? key : 'person_${1 + (h.art * 3) % 8}', h.standS, h.side,
          fallbackH: 1.65, fallback: const Color(0xff8E44AD));
    }
    final j = ev.jam;
    if (j != null && inView(j.head)) {
      _prop(items, a, 'police_officer_wave', j.head + 14, 0, fallbackH: 1.75, fallback: const Color(0xffC4D23E));
      for (var k = 0; k < 4; k++) {
        _prop(items, a, 'traffic_cone', j.head - 40 + k * 24, -8, fallbackH: 0.7, fallback: const Color(0xffF26B1D));
      }
    }
    for (final r in ev.ramps) {
      if (inView(r.s - 320)) _prop(items, a, 'sign_runaway_ramp', r.s - 320, _half + 28, fallbackH: 2.8, fallback: const Color(0xff2F6FB5));
    }
    final f = ev.ferry;
    if (f != null && dir > 0) {
      if (inView(f.a - 900)) _prop(items, a, 'sign_ferry', f.a - 900, _half + 28, fallbackH: 2.8, fallback: const Color(0xff2F6FB5));
      if (inView(f.a - 150)) _prop(items, a, 'ferry_booth', f.a - 150, _half + 52, fallbackH: 2.8, fallback: const Color(0xff2F6FB5));
    }
    if (f != null) _ferry(items, a, f);
    for (final b in ev.fogBanks) {
      final s = dir > 0 ? b.from - 300 : b.to + 300;
      if (inView(s)) _prop(items, a, 'sign_fog', s, dir * (_half + 26), fallbackH: 2.6, fallback: const Color(0xffF2C12E));
    }
  }

  // ------------------------------------------------------------------ Phà
  /// Ảnh boong nhìn từ trên (img_ferry.png, 482 × 1420, hàng 0 là đầu phía
  /// bờ bên kia) trải trên mặt sông ở [_groundExtras]; ở đây dựng phần đứng
  /// theo đúng chỗ trên ảnh: thành mạn trắng gỉ, lan can ống, phao cứu sinh,
  /// ca-bin lái kính đen bên phải, cột cờ, cầu dẫn đầu xa đang kéo lên.
  void _ferry(List<_Drawn> items, DriverArt a, _Ferry f) {
    const rows = 1420.0, cols = 482.0;
    final len = _Ferry.length, wid = _Ferry.width;
    final (fx, fy) = game.road.worldAt(f.center, 0);
    final z = cam.depthOf(fx, fy);
    if (z < -len || z > cam.far + len) return;
    double sAt(double row) => f.center + len / 2 - row / rows * len;
    double dAt(double col) => (col - cols / 2) / cols * wid;
    const m = _u;
    final hull = Paint()
      ..shader = Gradient.linear(Offset.zero, const Offset(0, 1), [const Color(0xffEEF0EB), const Color(0xffC9C2B4), const Color(0xff8E7A66)],
          [0, 0.7, 1]);
    final rail = Paint()..color = const Color(0xffE8EAE6);
    final nearS = sAt(1330), farS = sAt(90);
    // Thành mạn và lan can hai bên.
    for (final side in const [-1.0, 1.0]) {
      final d = side * (wid / 2 - 0.12 * m);
      _wall(items, _at(nearS, d), _at(farS, d), 0, 0.7 * m, hull, 0, 1, 0, 1);
      _wall(items, _at(nearS, d), _at(farS, d), 0.97 * m, 1.06 * m, rail, 0, 1, 0, 1);
    }
    // Cầu dẫn đầu bên kia kéo lên: thép xám, mép vàng.
    final rampD = 3.9 * m;
    _wall(items, _at(farS, -rampD), _at(farS, rampD), 0, 1.5 * m, Paint()..color = const Color(0xff6E7472), 0, 1, 0, 1);
    _wall(items, _at(farS, -rampD), _at(farS, rampD), 1.36 * m, 1.5 * m, Paint()..color = const Color(0xffDEBA28), 0, 1, 0, 1, bias: -0.5);
    // Ca-bin lái: mặt gần và mặt hông phía mình đang nhìn thấy.
    final c0 = sAt(780), c1 = sAt(569), dA = dAt(373), dB = dAt(462);
    final top = 2.45 * m;
    final white = Paint()
      ..shader = Gradient.linear(Offset.zero, const Offset(0, 1), [const Color(0xffF4F4EF), const Color(0xffD5D3CA)]);
    final night = game.darkness > 0.3;
    final glass = Paint()
      ..shader = Gradient.linear(Offset.zero, const Offset(0, 1),
          night ? [const Color(0xffFFD98A), const Color(0xffE7A84A)] : [const Color(0xff5D6B78), const Color(0xff161C22)]);
    final pd = game.player.d;
    final faces = <(Offset, Offset)>[
      (_at(c0, dA), _at(c0, dB)),
      if (pd < dA) (_at(c0, dA), _at(c1, dA)),
      if (pd > dB) (_at(c0, dB), _at(c1, dB)),
    ];
    for (final (p, q) in faces) {
      _wall(items, p, q, 0, top, white, 0, 1, 0, 1);
      _wall(items, p, q, 1.45 * m, 2.2 * m, glass, 0, 1, 0, 1, bias: -0.6);
      _wall(items, p, q, top - 0.04 * m, top + 0.1 * m, Paint()..color = const Color(0xffB9BBB5), 0, 1, 0, 1, bias: -0.8);
    }
    // Cột cờ trên nóc ca-bin, cờ đỏ sao vàng bay.
    final mast = _at(sAt(616), dAt(417));
    _board(items, mast.dx, mast.dy, 0.08 * m, 1.9 * m, null, fallback: const Color(0xffB8BCC0), lift: top, bias: -1);
    final wave = sin(game._time * 5) * 0.04;
    _board(items, mast.dx, mast.dy, 0.7 * m, 0.46 * m, null, fallback: const Color(0x00000000), lift: top + 1.35 * m, bias: -1.2,
        after: (c, rect, fade) {
      final r = rect.shift(Offset(rect.width / 2, 0));
      final flag = Path()
        ..moveTo(r.left, r.top)
        ..quadraticBezierTo(r.center.dx, r.top + r.height * wave, r.right, r.top + r.height * 0.05)
        ..lineTo(r.right, r.bottom - r.height * 0.05)
        ..quadraticBezierTo(r.center.dx, r.bottom + r.height * wave, r.left, r.bottom)
        ..close();
      c.drawPath(flag, Paint()..color = const Color(0xffD7262B).withValues(alpha: fade));
      c.drawPath(_star(r.center, r.height * 0.3), Paint()..color = const Color(0xffFADB30).withValues(alpha: fade));
    });
    // Phao cứu sinh đỏ trắng treo trên lan can.
    for (final (row, col) in const [(240.0, 22.0), (710.0, 22.0), (1180.0, 22.0), (287.0, 460.0), (1110.0, 460.0)]) {
      final o = _at(sAt(row), dAt(col));
      _board(items, o.dx, o.dy, 0.72 * m, 0.72 * m, null, fallback: const Color(0x00000000), lift: 0.3 * m, bias: -0.4, after: (c, rect, fade) {
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.width * 0.22;
        for (var i = 0; i < 4; i++) {
          ring.color = (i.isEven ? const Color(0xffD9262A) : const Color(0xffF5F3EE)).withValues(alpha: fade);
          c.drawArc(Rect.fromCircle(center: rect.center, radius: rect.width * 0.38), i * pi / 2, pi / 2, false, ring);
        }
      });
    }
    // Xe đang lên / đậu trên boong.
    final raining = game._trafficLayer.raining;
    for (final car in f.deck) {
      final (cs, cd) = game._events.deckSpot(car);
      final path = TrafficLayer.dressedPath(car.type, car.variant, raining: raining);
      final img = a.vehicle(path, 'rear');
      final o = _at(cs - game.dir * car.type.length / 2, cd);
      final w = img == null ? car.type.width : img.width / DriverArt.vehiclePixelsPerMeter * _u;
      final h = img == null ? car.type.width * 0.8 : img.height / DriverArt.vehiclePixelsPerMeter * _u;
      _board(items, o.dx, o.dy, w, h, img, fallback: const Color(0xff4B5563));
    }
  }

  /// Ngôi sao năm cánh tâm [c], bán kính ngoài [r].
  static Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final k = i.isEven ? r : r * 0.4;
      final p = c + Offset(cos(a) * k, sin(a) * k);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  // ----------------------------------------------------- Đêm, mưa, xe mình
  void _night(Canvas canvas, Size size) {
    final dark = game.darkness;
    if (dark > 0.02) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xff050A18).withValues(alpha: 0.68 * dark));
      if (game.headlightsOn || game.nightLevel > 0.3) {
        // Vệt đèn pha xe mình hắt lên mặt đường phía trước.
        final hy = cam.horizonY;
        final beam = Path()
          ..moveTo(size.width * 0.12, size.height)
          ..lineTo(size.width * 0.42, hy + size.height * 0.05)
          ..lineTo(size.width * 0.58, hy + size.height * 0.05)
          ..lineTo(size.width * 0.88, size.height)
          ..close();
        canvas.drawPath(
          beam,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = Gradient.linear(Offset(0, size.height), Offset(0, hy), [
              const Color(0xffFFF1C8).withValues(alpha: 0.34 * dark),
              const Color(0xffFFF1C8).withValues(alpha: 0.0),
            ]),
        );
      }
    }
    for (final (p, r, c) in _glows) {
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = Gradient.radial(p, r, [c.withValues(alpha: 0.85), c.withValues(alpha: 0)]),
      );
    }
  }

  void _rainFx(Canvas canvas, Size size) {
    final rain = game._rain;
    if (rain < 0.05) return;
    final paint = Paint()
      ..color = const Color(0xffDCE6EE).withValues(alpha: 0.28 * rain)
      ..strokeWidth = 1.2;
    final n = (90 * rain).round();
    final t = game._time;
    for (var i = 0; i < n; i++) {
      final hx = (i * 0.618034 + 0.13) % 1;
      final hy = ((i * 0.381966 + t * (1.6 + (i % 5) * 0.12)) % 1);
      final x = hx * size.width, y = hy * size.height;
      canvas.drawLine(Offset(x, y), Offset(x - 6, y + 22), paint);
    }
  }

  /// Khung xe mình phía trước mắt: ghi-đông xe máy, táp-lô và vô-lăng ô tô,
  /// xe khách. Vô-lăng xoay theo tay lái.
  /// Góc chúc xuống của máy ảnh chụp ảnh xe (BB_ELEV = 7°).
  static final double _sinBillboardElev = sin(7 * pi / 180);

  /// Ghi-đông xe máy chiếm bao nhiêu bề ngang màn hình.
  static const double _motoCockpitScale = 0.84;

  void _cockpit(Canvas canvas, Size size, DriverArt a) {
    final kind = game.spec.kind;
    final key = switch (kind) {
      VehicleKind.motorbike => 'cockpit_moto',
      VehicleKind.car => 'cockpit_car',
      VehicleKind.bus => 'cockpit_bus',
    };
    final img = a.cockpits[key];
    final dim = 1 - 0.75 * game.darkness;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(Color.fromRGBO((255 * dim).round(), (255 * dim).round(), (255 * dim).round(), 1), BlendMode.modulate);
    if (img == null) {
      _cockpitFallback(canvas, size, kind);
      return;
    }
    final scale = size.width / img.width;
    final top = size.height - img.height * scale;
    final dest = Rect.fromLTWH(0, top, size.width, img.height * scale);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final info = a.cockpitInfo[switch (kind) {
      VehicleKind.motorbike => 'moto',
      VehicleKind.car => 'car',
      VehicleKind.bus => 'bus',
    }];
    if (kind == VehicleKind.motorbike) {
      // Ghi-đông nhỏ hơn bề ngang màn hình một chút (thấy nhiều đường hơn),
      // canh giữa đáy; mép ảnh kẹp lại nên hai ống tay áo vẫn kéo tới mép
      // màn hình. Cả đồng hồ, gương quay nhẹ theo tay lái.
      final k = scale * _motoCockpitScale;
      final left = (size.width - img.width * k) / 2, mTop = size.height - img.height * k;
      final pivot = Offset(size.width / 2, size.height * 1.1);
      canvas.save();
      canvas
        ..translate(pivot.dx, pivot.dy)
        ..rotate(_steer * 0.05)
        ..translate(-pivot.dx + left, -pivot.dy);
      final shader = ImageShader(img, TileMode.clamp, TileMode.clamp, Float64List.fromList([k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, mTop, 0, 1]),
          filterQuality: FilterQuality.medium);
      canvas.drawRect(Rect.fromLTRB(-left, mTop, size.width - left, size.height + 4), paint..shader = shader);
      if (info is Map) {
        _dash(canvas, info, k, mTop, dim);
        _mirrors(canvas, info, k, mTop);
      }
      canvas.restore();
      return;
    }
    canvas.drawImageRect(img, src, dest, paint);
    if (info is Map) {
      _dash(canvas, info, scale, top, dim);
      _mirrors(canvas, info, scale, top);
    }
    final wheel = a.cockpits['${key}_wheel'];
    if (wheel == null || info is! Map) return;
    final spec = info['wheel'];
    final rect = _rectOf(spec, wheel, img);
    final center = _pointOf(spec is Map ? spec['pivot'] : null, rect.center);
    final r = Rect.fromLTWH(rect.left * scale, top + rect.top * scale, rect.width * scale, rect.height * scale);
    final c = Offset(center.dx * scale, top + center.dy * scale);
    canvas.save();
    canvas
      ..translate(c.dx, c.dy)
      ..rotate(_steer * 1.6)
      ..translate(-c.dx, -c.dy);
    canvas.drawImageRect(wheel, Rect.fromLTWH(0, 0, wheel.width.toDouble(), wheel.height.toDouble()), r, paint);
    canvas.restore();
  }

  /// Kim đồng hồ tốc độ / vòng tua chạy theo xe thật, đèn xi-nhan nháy.
  void _dash(Canvas canvas, Map info, double scale, double top, double dim) {
    Offset at(Object? v) {
      final p = _pointOf(v, Offset.zero);
      return Offset(p.dx * scale, top + p.dy * scale);
    }

    final kmh = game.player.speed * GameConfig.displayKmhPerUnitSpeed;
    final dials = info['dials'];
    if (dials is List) {
      for (final d in dials) {
        if (d is! Map) continue;
        double n(String k, double or) => (d[k] as num?)?.toDouble() ?? or;
        final a0 = n('angle0_deg', 135) * pi / 180, a1 = n('angle1_deg', 405) * pi / 180;
        final value = d['kind'] == 'rpm' ? _rpm(kmh) : kmh;
        final k = (value / n('max', 120)).clamp(0.0, 1.02);
        _needle(canvas, at(d['center']), a0 + (a1 - a0) * k, n('length', 40) * scale, dim);
      }
    }
    final ind = info['indicators'];
    final blinker = game._events.blinker;
    if (ind is Map && blinker != 0 && (game._time * 2.6).floor().isEven) {
      final c = at(ind[blinker > 0 ? 'right' : 'left']);
      final sz = ((ind['size'] as num?)?.toDouble() ?? 10) * scale;
      final x = blinker.toDouble();
      final arrow = Path()
        ..moveTo(c.dx + x * sz, c.dy)
        ..lineTo(c.dx - x * sz * 0.6, c.dy - sz * 0.8)
        ..lineTo(c.dx - x * sz * 0.6, c.dy + sz * 0.8)
        ..close();
      canvas.drawCircle(
        c,
        sz * 2.4,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = Gradient.radial(c, sz * 2.4, const [Color(0x7748FF7A), Color(0x0048FF7A)]),
      );
      canvas.drawPath(arrow, Paint()..color = const Color(0xff47FF7C));
    }
  }

  /// Vòng tua (nghìn vòng/phút) giả theo số: lên dần trong mỗi số, tụt khi
  /// sang số; vặn ga thì vọt lên chút.
  double _rpm(double kmh) {
    if (game.player.engineOff) return 0;
    const gears = [0.0, 22.0, 42.0, 65.0, 95.0, 140.0, 999.0];
    var i = 0;
    while (kmh > gears[i + 1]) {
      i++;
    }
    final frac = ((kmh - gears[i]) / (gears[i + 1] - gears[i])).clamp(0.0, 1.0);
    return 0.9 + (i == 0 ? frac * 2.6 : 1.4 + frac * 2.8) + (game.player.throttle ? 0.4 : 0);
  }

  void _needle(Canvas canvas, Offset c, double angle, double len, double dim) {
    final d = Offset(cos(angle), sin(angle));
    final n = Offset(-d.dy, d.dx);
    final w = max(1.1, len * 0.06);
    final tail = c - d * (len * 0.18);
    final path = Path()
      ..moveTo(tail.dx + n.dx * w, tail.dy + n.dy * w)
      ..lineTo(c.dx + d.dx * len, c.dy + d.dy * len)
      ..lineTo(tail.dx - n.dx * w, tail.dy - n.dy * w)
      ..close();
    // Ban đêm đồng hồ sáng đèn: kim cam dạ quang.
    final color = game.darkness > 0.3 ? const Color(0xffFF7A3A) : Color.lerp(const Color(0xffE5482C), const Color(0xff000000), 1 - dim)!;
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(c, w * 1.8, Paint()..color = const Color(0xff1A1C1F));
  }

  /// Gương chiếu hậu: cảnh phía sau (lật trái phải) — mặt đường, xe đi sau
  /// mình, xe ngược chiều vừa qua.
  void _mirrors(Canvas canvas, Map info, double scale, double top) {
    final list = info['mirrors'];
    if (list is! List) return;
    for (final m in list) {
      if (m is! Map || m['rect'] is! List) continue;
      final r = [for (final v in m['rect'] as List) (v as num).toDouble()];
      if (r.length < 4) continue;
      final rect = Rect.fromLTWH(r[0] * scale, top + r[1] * scale, r[2] * scale, r[3] * scale);
      final shape = Path();
      final ellipse = m['shape'] == 'ellipse';
      if (ellipse) {
        shape.addOval(rect);
      } else {
        shape.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(((m['radius'] as num?)?.toDouble() ?? 8) * scale)));
      }
      // Gương hai bên nhìn chéo ra sau về phía mình; gương giữa nhìn thẳng.
      final yaw = ellipse ? (r[0] + r[2] / 2 < 800 ? 0.3 : -0.3) : 0.0;
      canvas.save();
      canvas.clipPath(shape);
      _mirrorView(canvas, rect, yaw);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(rect.topLeft, rect.bottomRight, const [Color(0x33E8F2FF), Color(0x00FFFFFF), Color(0x1AFFFFFF)],
              const [0, 0.5, 1]),
      );
      canvas.restore();
    }
  }

  void _mirrorView(Canvas canvas, Rect rect, double yaw) {
    final a = art;
    if (a == null || rect.width < 4 || rect.height < 4) return;
    final mc = _mirrorCam
      ..x = cam.x
      ..y = cam.y
      ..eye = cam.eye
      ..heading = _heading + pi + yaw
      ..hfov = 0.55
      ..far = 1600;
    mc.setup(Size(rect.width, rect.height), horizon: 0.45);
    final w = rect.width, h = rect.height, hy = mc.horizonY;
    final dark = game.darkness;
    canvas.save();
    // Gương: trái phải đảo ngược.
    canvas
      ..translate(rect.right, rect.top)
      ..scale(-1, 1);
    canvas.drawRect(Rect.fromLTRB(0, 0, w, hy + 1), Paint()..shader = Gradient.linear(Offset.zero, Offset(0, hy), [_zenithColor, _horizonColor]));
    final gc = _groundColor;
    final dim = 1 - 0.75 * dark;
    canvas.drawRect(
      Rect.fromLTRB(0, hy, w, h),
      Paint()..color = Color.fromRGBO((gc.r * 255 * dim).round(), (gc.g * 255 * dim).round(), (gc.b * 255 * dim).round(), 1),
    );
    final s0 = game.player.s, s1 = game.player.s - game.dir * 1600;
    final samples = game.road.samplesBetween(min(s0, s1), max(s0, s1) + 20).toList(growable: false);
    if (samples.length > 1) {
      final sink = PerspectiveGroundSink(canvas, mc);
      Offset on(RoadSample p, double d) => Offset(p.x - sin(p.heading) * d, p.y + cos(p.heading) * d);
      sink.band([for (final p in samples) on(p, -_half)], [for (final p in samples) on(p, _half)], game._paints.asphalt);
      final yellow = Paint()
        ..color = const Color(0xffF0C23A)
        ..strokeWidth = 2.6;
      final white = Paint()
        ..color = const Color(0xffF4F4F0)
        ..strokeWidth = 3.2;
      sink.polyline([for (final p in samples) on(p, 0)], yellow);
      sink.polyline([for (final p in samples) on(p, _half - 5)], white);
      sink.polyline([for (final p in samples) on(p, -_half + 5)], white);
    }
    final shown = <(double, Image?, Rect, List<Offset>, bool)>[];
    for (final v in game.traffic.vehicles) {
      final behind = (game.player.s - v.s) * game.dir;
      if (behind < game.spec.length / 2 || behind > 1600) continue;
      final following = (v.oncoming ? -1 : 1) == game.dir;
      final view = following ? 'front' : 'rear';
      final path = TrafficLayer.dressedPath(v.type, v.variant, raining: game._trafficLayer.raining);
      final img = a.vehicle(path, view);
      final o = _at(v.s + game.dir * v.type.length / 2, v.d);
      final p = mc.toCam(o.dx, o.dy, 0);
      if (p.z < DriverCamera.near * 2 || p.z > mc.far) continue;
      final k = mc.focal / p.z;
      final base = mc.project(p);
      final bw = (img == null ? v.type.width : img.width / DriverArt.vehiclePixelsPerMeter * _u) * k;
      final bh = (img == null ? v.type.width * 0.8 : img.height / DriverArt.vehiclePixelsPerMeter * _u) * k;
      shown.add((p.z, img, Rect.fromLTWH(base.dx - bw / 2, base.dy - bh, bw, bh), a.lamps[DriverArt.baseOf(path)]?[view] ?? const [], following));
    }
    shown.sort((x, y) => y.$1.compareTo(x.$1));
    final lamps = <(Offset, double, Color)>[];
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final (_, img, r, points, following) in shown) {
      if (img == null) {
        canvas.drawRect(r, Paint()..color = const Color(0xff4B5563));
        continue;
      }
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, paint);
      if (dark > 0.25) {
        for (final l in points) {
          final p = Offset(r.left + l.dx / img.width * r.width, r.top + l.dy / img.height * r.height);
          lamps.add((p, r.width * (following ? 0.3 : 0.12), following ? const Color(0xffFFF3D6) : const Color(0xffFF2A1F)));
        }
      }
    }
    if (dark > 0.02) canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xff050A18).withValues(alpha: 0.62 * dark));
    for (final (p, r, c) in lamps) {
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = Gradient.radial(p, r, [c.withValues(alpha: 0.9), c.withValues(alpha: 0)]),
      );
    }
    canvas.restore();
  }

  /// Vị trí ảnh vô-lăng trong khung buồng lái (đọc từ cockpits.json, chấp
  /// nhận vài kiểu ghi: {pos, size}, [x, y, w, h] hoặc {x, y, w, h}).
  static Rect _rectOf(Object? v, Image wheel, Image frame) {
    if (v is Map && v['pos'] is List) {
      final pos = _pointOf(v['pos'], Offset.zero);
      final size = _pointOf(v['size'], Offset(wheel.width.toDouble(), wheel.height.toDouble()));
      return Rect.fromLTWH(pos.dx, pos.dy, size.dx, size.dy);
    }
    if (v is List && v.length >= 4) {
      return Rect.fromLTWH((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble(), (v[3] as num).toDouble());
    }
    if (v is Map) {
      double n(List<String> keys, double or) {
        for (final k in keys) {
          if (v[k] is num) return (v[k] as num).toDouble();
        }
        return or;
      }

      return Rect.fromLTWH(n(['x', 'left'], 0), n(['y', 'top'], 0), n(['w', 'width'], wheel.width.toDouble()), n(['h', 'height'], wheel.height.toDouble()));
    }
    if (wheel.width == frame.width && wheel.height == frame.height) return Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble());
    return Rect.fromLTWH(0, 0, wheel.width.toDouble(), wheel.height.toDouble());
  }

  static Offset _pointOf(Object? v, Offset or) {
    if (v is List && v.length >= 2) return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
    if (v is Map && v['x'] is num && v['y'] is num) return Offset((v['x'] as num).toDouble(), (v['y'] as num).toDouble());
    return or;
  }

  /// Chưa có ảnh buồng lái: vẽ tạm khung tối đơn giản.
  void _cockpitFallback(Canvas canvas, Size size, VehicleKind kind) {
    final dark = Paint()..color = const Color(0xff17191C);
    if (kind == VehicleKind.motorbike) {
      final y = size.height * 0.9;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(size.width * 0.2, y, size.width * 0.8, y + 10), const Radius.circular(5)), dark);
      canvas.drawOval(Rect.fromCenter(center: Offset(size.width / 2, size.height * 1.02), width: size.width * 0.22, height: size.height * 0.3),
          Paint()..color = const Color(0xffB01C22));
      return;
    }
    canvas.drawRect(Rect.fromLTRB(0, size.height * 0.84, size.width, size.height), dark);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, size.height * 0.06), dark);
  }
}
