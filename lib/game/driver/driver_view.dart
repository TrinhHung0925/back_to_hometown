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
      VehicleKind.car => (1.2 * _u, -0.06 * len, -0.2 * wid, 74.0),
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
    final speedRatio = (g.player.speed / g.spec.maxSpeed).clamp(0.0, 1.0);
    cam.hfov = (fov + 7 * speedRatio) * pi / 180;
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
    _haze(canvas, big);
    _objects(canvas, a);
    canvas.restore();
    _night(canvas, size);
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
    final tileW = cam.focal * pi / 2;
    final tileH = cam.focal * tan(40 * pi / 180);
    for (final (key, alpha) in layers) {
      final sky = a.props[key];
      if (sky == null || alpha <= 0.01) continue;
      _panorama(canvas, r, sky.image, tileW, hy - tileH, tileH, alpha * (1 - 0.5 * game._rain.clamp(0.0, 1.0)));
    }
    final hz = a.props[_horizonKey()];
    if (hz != null) {
      final w = cam.focal * pi / 3;
      final h = w * hz.image.height / hz.image.width;
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
    final near = switch (game.layout.kindAt(game.player.s)) {
      RoadKind.city => const Color(0xff8B877F),
      RoadKind.highway => switch (game.setup.theme) {
          MapTheme.coast => const Color(0xffB9AE84),
          MapTheme.mountain => const Color(0xff3D5636),
          MapTheme.mekong => const Color(0xffA99A55),
          _ => game.setup.south ? const Color(0xffA99A55) : const Color(0xff6F8248),
        },
      RoadKind.expressway => const Color(0xff74874D),
    };
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

  /// Hơi sương xa che chỗ mặt đất hết tầm vẽ.
  void _haze(Canvas canvas, Rect r) {
    final hy = cam.horizonY;
    final c = _horizonColor;
    canvas.drawRect(
      Rect.fromLTRB(r.left, hy - 2, r.right, hy + cam.height * 0.07),
      Paint()..shader = Gradient.linear(Offset(0, hy), Offset(0, hy + cam.height * 0.07), [c.withValues(alpha: 0.9), c.withValues(alpha: 0)]),
    );
  }

  /// Ổ gà, vũng nước nằm trên mặt đường.
  void _groundExtras(PerspectiveGroundSink ground) {
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
    _critters(items, a);
    _traffic(items, a);
    items.sort((x, y) => y.depth.compareTo(x.depth));
    for (final it in items) {
      it.paint(canvas);
    }
  }

  double _fade(double z) {
    final t = ((z - cam.far * 0.7) / (cam.far * 0.3)).clamp(0.0, 1.0);
    return 1 - t * t * (3 - 2 * t);
  }

  static final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  Paint _clamp(Image img) => _clampPaints.putIfAbsent(
      img, () => Paint()..shader = ImageShader(img, TileMode.clamp, TileMode.clamp, _identity, filterQuality: FilterQuality.medium));

  Paint _repeat(Image img) => _repeatPaints.putIfAbsent(
      img, () => Paint()..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, _identity, filterQuality: FilterQuality.medium));

  /// Ảnh đứng trên mặt đất tại (wx, wy): rộng [w], cao [h] (đơn vị bản đồ).
  Rect? _board(List<_Drawn> items, double wx, double wy, double w, double h, Image? img,
      {bool mirror = false, Color fallback = const Color(0xff5E7444), double lift = 0, double bias = 0, void Function(Canvas c, Rect rect, double fade)? after}) {
    final p = cam.toCam(wx, wy, lift);
    if (p.z < DriverCamera.near * 2 || p.z > cam.far) return null;
    final k = cam.focal / p.z;
    final base = cam.project(p);
    final rw = w * k, rh = h * k;
    if (base.dx + rw / 2 < -cam.width * 0.3 || base.dx - rw / 2 > cam.width * 1.3 || base.dy - rh > cam.height * 1.2) return null;
    final rect = Rect.fromLTWH(base.dx - rw / 2, base.dy - rh, rw, rh);
    final fade = _fade(p.z);
    items.add(_Drawn(p.z + bias, (c) {
      if (img == null) {
        c.drawRect(rect, Paint()..color = fallback.withValues(alpha: fade));
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
          final w = it.size * (_widthFactor[species] ?? 1.15);
          _board(items, o.dx, o.dy, w, art == null ? w * 1.3 : w / art.aspect, art?.image, mirror: it.seed.isOdd);
        case SceneryKind.banana:
          final art = a.prop('banana_${1 + it.seed % 2}');
          final w = it.size * 1.1;
          _board(items, o.dx, o.dy, w, art == null ? w : w / art.aspect, art?.image, mirror: it.seed.isOdd);
        case SceneryKind.house:
          _house(items, a, it, camS);
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
    final h = art == null ? (town ? 150.0 : 95.0) : w / art.aspect;
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
    final hw = h * 0.8;
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
      if (game.layout.kindAt(s) != RoadKind.highway || _stallNear(s, -1)) continue;
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
        if (_stallNear(s0, side)) continue;
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
        _trafficLight(items, a, o, color);
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
      final w = 2 * (_half + 40);
      final h = arch == null ? 170.0 : w / arch.aspect;
      final paint = arch != null ? _clamp(arch.image) : (Paint()..color = const Color(0xffC1121F));
      final iw = arch?.image.width.toDouble() ?? 1, ih = arch?.image.height.toDouble() ?? 1;
      _wall(items, _at(f, -dir * w / 2), _at(f, dir * w / 2), 0, h, paint, 0, iw, 0, ih);
    }
  }

  static int _limitArt(int kmh) => kmh <= 55 ? 50 : kmh <= 70 ? 60 : 80;

  void _trafficLight(List<_Drawn> items, DriverArt a, Offset o, LightColor color) {
    final pole = a.prop('traffic_light_pole');
    final head = a.prop('traffic_light_head_${color.name}');
    final ph = (pole?.heightM ?? 5.2) * _u;
    _board(items, o.dx, o.dy, pole == null ? 6 : ph * pole.aspect, ph, pole?.image, fallback: const Color(0xff3A3E44));
    final hh = (head?.heightM ?? 1.0) * _u;
    _board(items, o.dx, o.dy, head == null ? 14 : hh * head.aspect, hh, head?.image, lift: ph * 0.72, bias: -1, fallback: switch (color) {
      LightColor.red => const Color(0xffFF2A1F),
      LightColor.yellow => const Color(0xffFFC53A),
      LightColor.green => const Color(0xff2BD46B),
    }, after: (c, rect, fade) {
      if (game.darkness > 0.2) {
        final lamp = Offset(rect.center.dx, rect.top + rect.height * (color == LightColor.red ? 0.2 : color == LightColor.yellow ? 0.42 : 0.64));
        _glows.add((lamp, rect.width * 0.9, switch (color) {
          LightColor.red => const Color(0xffFF3B30),
          LightColor.yellow => const Color(0xffFFC53A),
          LightColor.green => const Color(0xff34E07A),
        }));
      }
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
          _prop(items, a, 'lixi_float', p.s, p.d, fallbackH: 1.4, fallback: const Color(0xffD62828), lift: 8 + bob);
        case PickupKind.gift:
          _prop(items, a, const ['gift_peach', 'gift_kumquat', 'gift_box'][p.s.round() % 3], p.s, p.d, fallbackH: 1.2);
        case PickupKind.pothole:
        case PickupKind.puddle:
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

  // Xe cộ: xe cùng chiều thấy đuôi, xe ngược chiều thấy đầu, xe đường ngang
  // thấy hông.
  void _traffic(List<_Drawn> items, DriverArt a) {
    final raining = game._trafficLayer.raining;
    final dark = game.darkness;
    for (final v in game.traffic.vehicles) {
      final path = TrafficLayer.dressedPath(v.type, v.variant, raining: raining);
      final same = (v.oncoming ? -1 : 1) == game.dir;
      final view = same ? 'rear' : 'front';
      final img = a.vehicle(path, view);
      final o = _at(v.s, v.d);
      final scale = v.type == TrafficType.motorbike ? 1.15 : 1.0;
      final w = img == null ? v.type.width : img.width / DriverArt.vehiclePixelsPerMeter * _u * scale;
      final h = img == null ? v.type.width * 0.8 : img.height / DriverArt.vehiclePixelsPerMeter * _u * scale;
      final lamps = a.lamps[DriverArt.baseOf(path)]?[view] ?? const <Offset>[];
      _board(items, o.dx, o.dy, w, h, img, fallback: const Color(0xff4B5563), after: (c, rect, fade) {
        if (img == null) return;
        final glowOn = same ? (v.braking || dark > 0.25) : dark > 0.25;
        if (!glowOn) return;
        for (final l in lamps) {
          final p = Offset(rect.left + l.dx / img.width * rect.width, rect.top + l.dy / img.height * rect.height);
          final r = rect.width * (same ? (v.braking ? 0.16 : 0.09) : 0.22);
          _glows.add((p, r, same ? const Color(0xffFF2A1F) : const Color(0xffFFF3D6)));
          if (same && v.braking) c.drawCircle(p, rect.width * 0.035, Paint()..color = const Color(0xffFF5A4E).withValues(alpha: fade));
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
  void _cockpit(Canvas canvas, Size size, DriverArt a) {
    final kind = game.spec.kind;
    final key = switch (kind) {
      VehicleKind.motorbike => 'cockpit_moto',
      VehicleKind.car => 'cockpit_car',
      VehicleKind.bus => 'cockpit_bus',
    };
    final img = a.cockpits[key];
    final dim = 1 - 0.6 * game.darkness;
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
    if (kind == VehicleKind.motorbike) {
      // Ghi-đông quay nhẹ theo tay lái.
      final pivot = Offset(size.width / 2, size.height * 1.1);
      canvas.save();
      canvas
        ..translate(pivot.dx, pivot.dy)
        ..rotate(_steer * 0.05)
        ..translate(-pivot.dx, -pivot.dy);
      canvas.drawImageRect(img, src, dest, paint);
      canvas.restore();
      return;
    }
    canvas.drawImageRect(img, src, dest, paint);
    final wheel = a.cockpits['${key}_wheel'];
    final info = a.cockpitInfo[kind == VehicleKind.car ? 'car' : 'bus'];
    if (wheel == null || info is! Map) return;
    final rect = _rectOf(info['wheel_rect'] ?? info['wheel'], wheel, img);
    final center = _pointOf(info['rotation_center'] ?? info['center'], rect.center);
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

  /// Vị trí ảnh vô-lăng trong khung buồng lái (đọc từ cockpits.json, chấp
  /// nhận vài kiểu ghi: [x, y, w, h] hoặc {x, y, w, h} / {left, top, width, height}).
  static Rect _rectOf(Object? v, Image wheel, Image frame) {
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
