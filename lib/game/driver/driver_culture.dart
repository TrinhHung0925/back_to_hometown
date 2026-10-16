part of '../ve_que_game.dart';

/// Điểm 3D trong hệ thế giới (x, y như bản đồ; z lên trời).
typedef _P3 = (double, double, double);

/// Một mặt phẳng đã chiếu sẵn ra màn hình (lưới tam giác dán vân), vẽ bằng
/// một lần drawVertices.
class _FaceMesh {
  _FaceMesh(this.pos, this.tex, this.paint);

  final Float32List pos;
  final Float32List tex;
  final Paint paint;

  void draw(Canvas c, [Paint? override]) {
    final v = Vertices.raw(VertexMode.triangles, pos, textureCoordinates: tex);
    c.drawVertices(v, BlendMode.srcOver, override ?? paint);
    v.dispose();
  }
}

/// Ảnh biển cổng chào đã viết chữ (theo tỉnh, mặt trước / sau), giữ theo bộ
/// ảnh ghế lái đang dùng.
final Expando<Map<String, Image>> _gatePanels = Expando('gatePanels');

/// Mặt biển cổng chào đang thấy (ban đêm vẽ lại sau lớp tối cho sáng đèn).
final Expando<List<_FaceMesh>> _litPanels = Expando('litPanels');

/// Khối 3D thật cho góc nhìn ghế lái: nhà quê mái ngói / mái tôn dốc thật,
/// tường hồi, hiên, sân, tường rào; nhà phố mặt tiền + tường hông + mái bạt;
/// cổng chào tỉnh (trụ hộp, xà biển chữ, mái lợp ngói, rồng chầu nóc).
extension _DriverCulture on _DriverView {
  // Hướng tới mặt trời (từ tây bắc như bóng đổ trên bản đồ, cao chừng 50°).
  static const double _sunX = -0.386, _sunY = -0.514, _sunZ = 0.766;

  /// Lưới chia tối đa theo mức chi tiết (mặt lớn nhìn chéo cần chia nhỏ cho
  /// vân khỏi méo).
  int get _maxDiv => const [3, 4, 6][_quality];

  /// Dựng một mặt phẳng: bốn góc [p] (tam giác thì lặp góc cuối), toạ độ vân
  /// [uv]. Mặt quay lưng về mắt (so với tâm khối [center]) thì bỏ. Màu vân
  /// nhân [tint] và độ nắng theo hướng mặt: [ambient] + [diffuse]·(n·nắng).
  _FaceMesh? _mesh(List<_P3> p, List<Offset> uv, Paint base,
      {_P3? center, bool cull = true, Color tint = const Color(0xffFFFFFF), double ambient = 0.62, double diffuse = 0.46}) {
    // Pháp tuyến (Newell) hướng ra ngoài khối.
    var nx = 0.0, ny = 0.0, nz = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4];
      nx += (a.$2 - b.$2) * (a.$3 + b.$3);
      ny += (a.$3 - b.$3) * (a.$1 + b.$1);
      nz += (a.$1 - b.$1) * (a.$2 + b.$2);
    }
    final len = sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-9) return null;
    nx /= len;
    ny /= len;
    nz /= len;
    if (center != null) {
      final cx = (p[0].$1 + p[2].$1) / 2 - center.$1, cy = (p[0].$2 + p[2].$2) / 2 - center.$2, cz = (p[0].$3 + p[2].$3) / 2 - center.$3;
      if (nx * cx + ny * cy + nz * cz < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
    }
    if (cull) {
      final vx = cam.x - p[0].$1, vy = cam.y - p[0].$2, vz = cam.eye - p[0].$3;
      if (nx * vx + ny * vy + nz * vz <= 0) return null;
    }
    final cp = [for (var i = 0; i < 4; i++) cam.toCam(p[i].$1, p[i].$2, p[i].$3)];
    if (cp.every((q) => q.z < DriverCamera.near) || cp.every((q) => q.z > cam.far)) return null;
    int div(CamPoint a, CamPoint b) {
      final lo = max(min(a.z, b.z), DriverCamera.near), hi = max(max(a.z, b.z), DriverCamera.near);
      final r = hi / lo;
      return r < 1.3 ? 1 : min(_maxDiv, (log(r) / log(1.3)).ceil());
    }

    final nu = max(div(cp[0], cp[1]), div(cp[3], cp[2]));
    final nv = max(div(cp[0], cp[3]), div(cp[1], cp[2]));
    final grid = <CamPoint>[];
    for (var j = 0; j <= nv; j++) {
      final v = j / nv;
      for (var i = 0; i <= nu; i++) {
        final u = i / nu;
        double mix(double a, double b, double c, double d) => (a * (1 - u) + b * u) * (1 - v) + (d * (1 - u) + c * u) * v;
        grid.add(cam.toCam(
          mix(p[0].$1, p[1].$1, p[2].$1, p[3].$1),
          mix(p[0].$2, p[1].$2, p[2].$2, p[3].$2),
          mix(p[0].$3, p[1].$3, p[2].$3, p[3].$3),
          mix(uv[0].dx, uv[1].dx, uv[2].dx, uv[3].dx),
          mix(uv[0].dy, uv[1].dy, uv[2].dy, uv[3].dy),
        ));
      }
    }
    final pos = <double>[], tex = <double>[];
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity;
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        var cell = [grid[j * (nu + 1) + i], grid[j * (nu + 1) + i + 1], grid[(j + 1) * (nu + 1) + i + 1], grid[(j + 1) * (nu + 1) + i]];
        if (cell.every((q) => q.z < DriverCamera.near)) continue;
        if (cell.any((q) => q.z < DriverCamera.near)) {
          cell = DriverCamera.clipNear(cell);
          if (cell.length < 3) continue;
        }
        final scr = [for (final q in cell) cam.project(q)];
        for (final o in scr) {
          minX = min(minX, o.dx);
          maxX = max(maxX, o.dx);
          minY = min(minY, o.dy);
        }
        for (var k = 1; k + 1 < scr.length; k++) {
          for (final t in [0, k, k + 1]) {
            pos
              ..add(scr[t].dx)
              ..add(scr[t].dy);
            tex
              ..add(cell[t].tu)
              ..add(cell[t].tv);
          }
        }
      }
    }
    if (pos.isEmpty || maxX < -cam.width * 0.2 || minX > cam.width * 1.2 || minY > cam.height * 1.2) return null;
    final sun = max(0.0, nx * _sunX + ny * _sunY + nz * _sunZ);
    final k = (ambient + diffuse * sun).clamp(0.0, 1.15);
    final depth = cp.map((q) => q.z).reduce(max) * 0.5 + cp.map((q) => q.z).reduce(min) * 0.5;
    final alpha = _fade(depth);
    Color shade(Color c) => Color.from(alpha: 1, red: (c.r * k).clamp(0.0, 1.0), green: (c.g * k).clamp(0.0, 1.0), blue: (c.b * k).clamp(0.0, 1.0));
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (base.shader != null) {
      paint
        ..shader = base.shader
        ..color = Color.fromRGBO(255, 255, 255, alpha)
        ..colorFilter = ColorFilter.mode(shade(tint), BlendMode.modulate);
    } else {
      paint.color = shade(base.color).withValues(alpha: alpha * base.color.a);
    }
    return _FaceMesh(Float32List.fromList(pos), Float32List.fromList(tex), paint);
  }

  // ------------------------------------------------------------ Nhà
  /// Hệ toạ độ riêng của lô nhà (đúng như ảnh nhà nhìn từ trên): gốc giữa
  /// mặt tiền, trục x dọc mặt tiền, trục y ra xa đường; nhà phía trong khúc
  /// cua co dần theo [House.taper].
  _P3 Function(double lx, double ly, double z) _lotFrame(SceneryItem it) {
    final at = game.road.at(it.s);
    final (ox, oy) = game.road.worldAt(it.s, it.d);
    final h = at.heading + (it.d >= 0 ? 0 : pi);
    final ex = Offset(cos(h), sin(h)), ey = Offset(-sin(h), cos(h));
    final taper = it.house?.taper ?? 0;
    return (lx, ly, z) {
      final k = ly > 0 ? (1 - ly * taper) : 1.0;
      return (ox + ex.dx * lx * k + ey.dx * ly, oy + ex.dy * lx * k + ey.dy * ly, z);
    };
  }

  /// Mặt đứng từ (x0, y0) tới (x1, y1) trong hệ lô nhà, cao [z0]..[z1]
  /// (đỉnh phía cuối có thể cao khác: [z1b]).
  List<_P3> _side(_P3 Function(double, double, double) at, double x0, double y0, double x1, double y1, double z0, double z1,
          [double? z1b]) =>
      [at(x0, y0, z1), at(x1, y1, z1b ?? z1), at(x1, y1, z0), at(x0, y0, z0)];

  /// Chọn ảnh có bề ngang gần [w] nhất (trong vài ảnh gần nhất, theo [seed]).
  int _byWidth(DriverArt a, String prefix, int count, double w, int seed, {Set<int>? only}) {
    final opts = <(double, int)>[];
    for (var i = 1; i <= count; i++) {
      if (only != null && !only.contains(i)) continue;
      final art = a.prop('$prefix$i');
      if (art == null) continue;
      final fw = ((art.info['facade_w_m'] as num?)?.toDouble() ?? art.heightM * art.aspect) * _DriverView._u;
      opts.add(((fw - w).abs(), i));
    }
    if (opts.isEmpty) return 0;
    opts.sort((x, y) => x.$1.compareTo(y.$1));
    final near = opts.where((o) => o.$1 < opts.first.$1 + 12).toList();
    return near[seed % near.length].$2;
  }

  /// Nhà ven đường dựng khối: nhà quê có sân thì mái dốc thật, còn lại là
  /// nhà ống mặt phố. Thiếu ảnh thì vẽ kiểu cũ (mặt tiền phẳng).
  void _house3d(List<_Drawn> items, DriverArt a, SceneryItem it, double camS) {
    final h = it.house;
    if (h == null) return _house(items, a, it, camS);
    if (h.yard > 0 && a.prop('house3d_body_1') != null) return _villageHouse(items, a, it, h);
    if (a.prop('house_town_1') != null) return _townHouse(items, a, it, h);
    _house(items, a, it, camS);
  }

  /// Mái nhà: ngói đỏ (đậm / nhạt như ảnh nhìn từ trên) hoặc tôn theo màu.
  (Paint, Color, double) _roofPaint(House h) {
    if (h.roof == RoofKind.clay) {
      final img = game.images.fromCache(Img.texRoofClay);
      return (_repeat(img), h.clayDark ? const Color(0xffB08A7A) : const Color(0xffF4E2D8), img.width / (110.0));
    }
    final img = game.images.fromCache(Img.texRoofIron);
    const tints = [Color(0xff6E93C2), Color(0xffB4675A), Color(0xffD8DADC), Color(0xff7FA98A)];
    return (_repeat(img), tints[h.ironTint % tints.length], img.width / 90.0);
  }

  void _villageHouse(List<_Drawn> items, DriverArt a, SceneryItem it, House h) {
    const u = _DriverView._u;
    final at = _lotFrame(it);
    final w = h.size.x, depth = h.size.y, hw = w / 2;
    final v = _byWidth(a, 'house3d_body_', 6, w, it.seed);
    final body = a.prop('house3d_body_$v');
    if (body == null) return _house(items, a, it, game.player.s);
    final he = ((body.info['eave_m'] as num?)?.toDouble() ?? 3.25) * u;
    const pitch = 0.5;
    final ov = 0.5 * u, ovs = 0.32 * u;
    final ze = he + 0.12 * u - ov * pitch, zr = he + 0.12 * u + depth / 2 * pitch;
    final center = at(0, depth / 2, he * 0.6);
    final meshes = <_FaceMesh?>[];
    // Tường hồi hai đầu (đầu xa quay lưng thì tự bỏ).
    final sideArt = a.prop('house3d_side_$v') ?? a.prop('wall_side_1');
    final wallPaint = sideArt != null ? _repeat(sideArt.image) : (Paint()..color = const Color(0xffD9C9A4));
    final rep = sideArt == null ? 1.0 : sideArt.image.width / (3 * u);
    final hip = h.hip;
    for (final sx in const [-1.0, 1.0]) {
      final x = sx * hw;
      if (hip) {
        meshes.add(_mesh(_side(at, x, 0, x, depth, 0, he), [Offset.zero, Offset(depth * rep, 0), Offset(depth * rep, he * rep), Offset(0, he * rep)],
            wallPaint, center: center));
      } else {
        // Tường hồi nhọn lên tới nóc mái.
        for (final (y0, y1, z0, z1) in [(0.0, depth / 2, he, zr - 0.1 * u), (depth / 2, depth, zr - 0.1 * u, he)]) {
          meshes.add(_mesh(_side(at, x, y0, x, y1, 0, z0, z1),
              [Offset(y0 * rep, (zr - z0) * rep), Offset(y1 * rep, (zr - z1) * rep), Offset(y1 * rep, zr * rep), Offset(y0 * rep, zr * rep)],
              wallPaint, center: center));
        }
      }
    }
    // Mặt tiền: ảnh nhà (hiên cột, cửa, đèn lồng); mép trái ảnh ở x dương.
    final img = body.image;
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    meshes.add(_mesh(_side(at, hw, 0, -hw, 0, 0, he), [Offset.zero, Offset(iw, 0), Offset(iw, ih), Offset(0, ih)], _clamp(img),
        center: center, ambient: 0.84, diffuse: 0.22));
    // Gầm mái hắt phía trước (nhìn từ dưới lên) và diềm mái.
    final eaveX = hip ? hw + ov : hw + ovs;
    meshes.add(_mesh([at(-eaveX, -ov, ze - 0.06 * u), at(eaveX, -ov, ze - 0.06 * u), at(eaveX, 0, he), at(-eaveX, 0, he)], const [
      Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1),
    ], Paint()..color = const Color(0xff4C433B), cull: false, ambient: 1, diffuse: 0));
    final (roof, tint, k) = _roofPaint(h);
    final fascia = Paint()..color = h.roof == RoofKind.clay ? const Color(0xffCFC8BA) : Color.lerp(tint, const Color(0xff000000), 0.25)!;
    meshes.add(_mesh(_side(at, -eaveX, -ov, eaveX, -ov, ze - 0.2 * u, ze + 0.02 * u), const [
      Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1),
    ], fascia, center: center, ambient: 0.75, diffuse: 0.3));
    // Mái: hai mái dốc (tường hồi) hoặc bốn mái (mái chéo có hai mái tam
    // giác ở hai đầu). Vân ngói chạy dọc theo chiều dốc.
    final slope = (depth / 2 + ov) * sqrt(1 + pitch * pitch);
    final rx = hip ? max(0.0, hw - min(hw * 0.7, depth * 0.3)) : eaveX;
    List<Offset> roofUv(double x0, double x1, double x2, double x3) =>
        [Offset(x0 * k, slope * k), Offset(x1 * k, slope * k), Offset(x2 * k, 0), Offset(x3 * k, 0)];
    meshes.add(_mesh([at(eaveX, -ov, ze), at(-eaveX, -ov, ze), at(-rx, depth / 2, zr), at(rx, depth / 2, zr)],
        roofUv(eaveX, -eaveX, -rx, rx), roof, center: center, tint: tint));
    meshes.add(_mesh([at(-eaveX, depth + ov, ze), at(eaveX, depth + ov, ze), at(rx, depth / 2, zr), at(-rx, depth / 2, zr)],
        roofUv(-eaveX, eaveX, rx, -rx), roof, center: center, tint: tint));
    if (hip) {
      for (final sx in const [-1.0, 1.0]) {
        final apex = at(sx * rx, depth / 2, zr);
        final run = (depth + 2 * ov);
        meshes.add(_mesh([at(sx * eaveX, -ov, ze), at(sx * eaveX, depth + ov, ze), apex, apex],
            [Offset(0, slope * k), Offset(run * k, slope * k), Offset(run * k / 2, 0), Offset(run * k / 2, 0)], roof,
            center: center, tint: tint));
      }
    }
    // Bờ nóc: dải ngói úp sẫm màu dọc nóc mái.
    final ridge = Paint()..color = h.roof == RoofKind.clay ? const Color(0xff7A3E2A) : Color.lerp(tint, const Color(0xff000000), 0.35)!;
    final rr = hip ? max(rx, 0.3 * u) : eaveX;
    meshes.add(_mesh([at(rr, depth / 2 - 0.28 * u, zr - 0.28 * u * pitch + 0.05 * u), at(-rr, depth / 2 - 0.28 * u, zr - 0.28 * u * pitch + 0.05 * u),
      at(-rr, depth / 2, zr + 0.1 * u), at(rr, depth / 2, zr + 0.1 * u)], const [Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1)], ridge,
        center: center));
    final front = cam.toCam(at(0, 0, he / 2).$1, at(0, 0, he / 2).$2, he / 2);
    final drawn = [for (final m in meshes) ?m];
    if (drawn.isNotEmpty) {
      items.add(_Drawn(front.z + 6, (c) {
        for (final m in drawn) {
          m.draw(c);
        }
      }));
    }
    _villageYard(items, a, it, h, v, at);
  }

  /// Tường rào, cổng sắt trước sân; cột cờ, bàn thờ thiên ngoài sân.
  void _villageYard(List<_Drawn> items, DriverArt a, SceneryItem it, House h, int v, _P3 Function(double, double, double) at) {
    const u = _DriverView._u;
    final yard = h.yard, hw = h.size.x / 2;
    final fence = a.prop('house3d_fence_$v');
    if (fence != null) {
      final img = fence.image;
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final fh = fence.heightM * u;
      final center = at(0, -yard / 2, 0.6 * u);
      final meshes = <_FaceMesh?>[
        _mesh(_side(at, hw, -yard, -hw, -yard, 0, fh), [Offset.zero, Offset(iw, 0), Offset(iw, ih), Offset(0, ih)], _clamp(img),
            center: center, ambient: 0.84, diffuse: 0.22),
      ];
      // Tường rào hai bên sân: lấy đoạn tường trơn ở mép ảnh.
      final wallH = 1.33 * u;
      final ppm = iw / (fence.heightM * fence.aspect * u);
      final seg = min(yard * ppm, iw * 0.2);
      for (final sx in const [-1.0, 1.0]) {
        meshes.add(_mesh(_side(at, sx * hw, -yard, sx * hw, 0, 0, wallH),
            [Offset(0, ih - wallH * ppm), Offset(seg, ih - wallH * ppm), Offset(seg, ih), Offset(0, ih)], _clamp(img),
            center: center, ambient: 0.8, diffuse: 0.25));
      }
      final drawn = [for (final m in meshes) ?m];
      final f = at(0, -yard, 0.5 * u);
      final z = cam.toCam(f.$1, f.$2, f.$3).z;
      if (drawn.isNotEmpty) {
        items.add(_Drawn(z, (c) {
          for (final m in drawn) {
            m.draw(c);
          }
        }));
      }
    }
    // Cột cờ tre cắm trong sân (nhà có cờ cắm cột), bàn thờ thiên.
    if (const {2, 3, 6}.contains(v)) {
      final pole = a.prop('house3d_flagpole');
      if (pole != null) {
        final p = at(hw - 0.9 * u, -yard + 0.7 * u, 0);
        final ph = pole.heightM * u;
        // Ảnh cột cờ: cột ở mép trái ảnh, lá cờ bay sang phải — dời tâm ảnh
        // sang phải (theo hướng nhìn) để chân cột đứng đúng chỗ.
        final pw = ph * pole.aspect;
        final k = 0.42 * pw;
        _board(items, p.$1 - sin(cam.heading) * k, p.$2 + cos(cam.heading) * k, pw, ph, pole.image);
      }
    }
    if (v == 3) {
      final shrine = a.prop('house3d_shrine');
      if (shrine != null) {
        final p = at(-hw + 1.1 * u, -yard * 0.45, 0);
        final sh = shrine.heightM * u;
        _board(items, p.$1, p.$2, sh * shrine.aspect, sh, shrine.image);
      }
    }
  }

  /// Chiều cao đỉnh tường chắn mái của ảnh nhà phố (m), theo số tầng; nhà
  /// mái thái (ảnh 4, 6) tường thấp hơn.
  static double _townWallTop(int key, int floors) => 3.7 + (floors - 1) * 3.3 + (key == 4 || key == 6 ? 0.5 : 1.1);

  void _townHouse(List<_Drawn> items, DriverArt a, SceneryItem it, House h) {
    const u = _DriverView._u;
    final at = _lotFrame(it);
    final w = h.size.x, depth = min(h.size.y, 300.0), hw = w / 2;
    // Nhà mái bằng ven quốc lộ (xóm) thường chỉ hai, ba tầng.
    final town = game.layout.kindAt(it.s) == RoadKind.city;
    final key = max(1, _byWidth(a, 'house_town_', 6, w, it.seed, only: town ? null : const {1, 2, 4, 6}));
    final art = a.prop('house_town_$key');
    if (art == null) return _house(items, a, it, game.player.s);
    final img = art.image;
    final ht = art.heightM * u;
    final floors = (art.info['floors'] as num?)?.toInt() ?? 3;
    final top = _townWallTop(key, floors) * u;
    final center = at(0, depth / 2, top / 2);
    final meshes = <_FaceMesh?>[];
    // Tường hông hai đầu, cao tới tường chắn mái, sâu hết lô đất.
    // Tường hông: phần nhiều trát xi măng ố mốc, có nhà sơn vàng, nhà để gạch trần.
    final wallArt = a.prop('wall_side_${const [2, 2, 1, 2, 3, 1, 2, 3, 1, 2][it.seed % 10]}');
    final wallPaint = wallArt != null ? _repeat(wallArt.image) : (Paint()..color = const Color(0xffB9AC8E));
    final rep = wallArt == null ? 1.0 : wallArt.image.width / (3 * u);
    for (final sx in const [-1.0, 1.0]) {
      meshes.add(_mesh(_side(at, sx * hw, 0, sx * hw, depth, 0, top),
          [Offset.zero, Offset(depth * rep, 0), Offset(depth * rep, top * rep), Offset(0, top * rep)], wallPaint, center: center));
      _wallDecals(meshes, a, at, sx, hw, depth, top, floors, it.seed + (sx > 0 ? 7 : 0), center);
    }
    // Mái tôn / mái ngói hai dốc sau tường chắn mái (nóc chạy vào trong
    // như ảnh nhìn từ trên), đầu hồi tam giác nhô lên sau mặt tiền.
    if (h.roof != RoofKind.flat && key != 4 && key != 6) {
      final (roof, tint, k) = _roofPaint(h);
      final z0 = top - 0.35 * u, zr = z0 + hw * 0.36;
      final y0 = 0.25 * u;
      final slope = (hw + 0.2 * u) * 1.06;
      for (final sx in const [-1.0, 1.0]) {
        meshes.add(_mesh([at(sx * (hw + 0.2 * u), y0, z0 - 0.07 * u), at(sx * (hw + 0.2 * u), depth, z0 - 0.07 * u), at(0, depth, zr), at(0, y0, zr)],
            [Offset(0, slope * k), Offset(depth * k, slope * k), Offset(depth * k, 0), const Offset(0, 0)], roof, center: center, tint: tint));
      }
      final gable = at(0, y0, zr);
      meshes.add(_mesh([at(-hw, y0, z0), at(hw, y0, z0), gable, gable],
          [Offset(0, (zr - z0) * rep), Offset(w * rep, (zr - z0) * rep), Offset(hw * rep, 0), Offset(hw * rep, 0)], wallPaint, center: center));
    }
    meshes.add(_mesh(_side(at, hw, 0, -hw, 0, 0, ht), [Offset.zero, Offset(img.width.toDouble(), 0), Offset(img.width.toDouble(), img.height.toDouble()),
      Offset(0, img.height.toDouble())], _clamp(img), center: center, ambient: 0.84, diffuse: 0.22));
    // Mái bạt che vỉa hè: dốc ra phía đường, sọc màu, diềm rủ.
    final aw = h.awning;
    if (aw != null) {
      final d = h.awningDepth, x = hw - 0.12 * u;
      final hi = 2.85 * u, lo = 2.35 * u;
      // Bạt sọc: dải màu xen trắng; bạt trơn: sẫm dần vào phía chân tường.
      final stripe = h.striped
          ? (Paint()
            ..shader = Gradient.linear(Offset.zero, const Offset(12, 0), [aw, aw, const Color(0xffF2F0EA), const Color(0xffF2F0EA)],
                const [0, 0.5, 0.5, 1], TileMode.repeated))
          : (Paint()..shader = Gradient.linear(Offset.zero, Offset(0, d), [Color.lerp(aw, const Color(0xff000000), 0.3)!, aw]));
      meshes.add(_mesh([at(x, 0, hi), at(-x, 0, hi), at(-x, -d, lo), at(x, -d, lo)], [Offset.zero, Offset(2 * x, 0), Offset(2 * x, d), Offset(0, d)],
          stripe, cull: false, ambient: 0.72, diffuse: 0.2));
      meshes.add(_mesh([at(x, -d, lo), at(-x, -d, lo), at(-x, -d, lo - 0.24 * u), at(x, -d, lo - 0.24 * u)],
          [Offset.zero, Offset(2 * x, 0), Offset(2 * x, 6), Offset(0, 6)], stripe, cull: false, ambient: 0.8, diffuse: 0.25));
    }
    final f = at(0, 0, ht / 3);
    final z = cam.toCam(f.$1, f.$2, f.$3).z;
    final drawn = [for (final m in meshes) ?m];
    if (drawn.isNotEmpty) {
      items.add(_Drawn(z + 4, (c) {
        for (final m in drawn) {
          m.draw(c);
        }
      }));
    }
  }

  /// Cửa sổ nhỏ, chữ quảng cáo sơn tay trên tường hông nhà ống (lộ ra ở đầu
  /// ngõ, ngã tư, cạnh nhà thấp hơn). Hướng chữ theo người đứng ngoài nhìn vào.
  void _wallDecals(List<_FaceMesh?> meshes, DriverArt a, _P3 Function(double, double, double) at, double sx, double hw, double depth,
      double top, int floors, int seed, _P3 center) {
    const u = _DriverView._u;
    final r = Random(seed);
    final x = sx * (hw + 1.2);
    final o = at(0, 0, 0), e = at(1, 0, 0), f = at(0, 1, 0);
    // Pháp tuyến ra ngoài = sx·ex; tay phải người nhìn vào tường = (n_y, −n_x).
    final nx = sx * (e.$1 - o.$1), ny = sx * (e.$2 - o.$2);
    final along = (f.$1 - o.$1) * ny + (f.$2 - o.$2) * -nx;
    void decal(BillboardArt art, double y0, double z0) {
      final w = art.heightM * art.aspect * u, hgt = art.heightM * u;
      final y1 = y0 + w;
      if (y1 > depth - 0.5 * u) return;
      final img = art.image;
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final uv = along > 0
          ? [Offset.zero, Offset(iw, 0), Offset(iw, ih), Offset(0, ih)]
          : [Offset(iw, 0), Offset.zero, Offset(0, ih), Offset(iw, ih)];
      meshes.add(_mesh(_side(at, x, y0, x, y1, z0, z0 + hgt), uv, _clamp(img), center: center, ambient: 0.8, diffuse: 0.3));
    }

    for (var k = 1; k < floors; k++) {
      final win = a.prop('wall_window_${1 + r.nextInt(2)}');
      final roll = r.nextDouble();
      if (win == null || roll > 0.55) continue;
      decal(win, depth * (0.12 + 0.3 * r.nextDouble()), (3.7 + (k - 1) * 3.3 + 0.75) * u);
    }
    final ad = a.prop('wall_ad_${1 + r.nextInt(4)}');
    if (ad != null && top > 6 * u && r.nextDouble() < 0.35) {
      decal(ad, depth * (0.08 + 0.2 * r.nextDouble()), top - (ad.heightM + 0.9) * u);
    }
  }

  /// Sân gạch đỏ trước nhà quê (nằm trên mặt đất, vẽ cùng mặt đường).
  void _cultureGround(PerspectiveGroundSink ground) {
    final camS = game.player.s;
    for (final it in game._scenery.items) {
      final h = it.house;
      if (h == null || h.yard <= 0) continue;
      final ahead = (it.s - camS) * game.dir;
      if (ahead < -300 || ahead > cam.far) continue;
      final at = _lotFrame(it);
      final hw = h.size.x / 2;
      Offset o(double x, double y) {
        final p = at(x, y, 0);
        return Offset(p.$1, p.$2);
      }

      ground.polygon([o(-hw, -h.yard), o(hw, -h.yard), o(hw, 0), o(-hw, 0)], game._paints.pavingRed);
    }
  }

  // ------------------------------------------------------- Cổng chào
  /// Biển xà ngang đã viết chữ: tên tỉnh + "KÍNH CHÀO QUÝ KHÁCH" (mặt
  /// trước), "HẸN GẶP LẠI QUÝ KHÁCH" (mặt sau).
  Image? _panelImage(DriverArt a, BorderGate g, bool front) {
    final bg = a.prop('gate_panel');
    if (bg == null) return null;
    final cache = _gatePanels[a] ??= {};
    final key = '${g.to}|$front';
    final hit = cache[key];
    if (hit != null) return hit;
    final img = bg.image;
    final w = img.width.toDouble(), h = img.height.toDouble();
    final tb = bg.info['text_box'];
    final box = tb is List && tb.length == 4
        ? Rect.fromLTRB((tb[0] as num) * w, (tb[1] as num) * h, (tb[2] as num) * w, (tb[3] as num) * h)
        : Rect.fromLTRB(w * 0.2, h * 0.16, w * 0.8, h * 0.84);
    final rec = PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(img, Offset.zero, Paint());
    final name = Provinces.byName(g.to)?.gateName ?? g.to.toUpperCase();
    final second = front ? 'KÍNH CHÀO QUÝ KHÁCH' : 'HẸN GẶP LẠI QUÝ KHÁCH';
    void line(String text, String family, FontWeight weight, double size, double cy, List<Color> colors) {
      Paragraph build(double fs, Paint fg) {
        final pb = ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center, maxLines: 1))
          ..pushStyle(TextStyle(fontFamily: family, fontWeight: weight, fontSize: fs, foreground: fg, letterSpacing: fs * 0.03, height: 1))
          ..addText(text);
        return pb.build()..layout(ParagraphConstraints(width: box.width));
      }

      var fs = size;
      final probe = build(fs, Paint());
      if (probe.maxIntrinsicWidth > box.width) fs *= box.width / probe.maxIntrinsicWidth * 0.98;
      probe.dispose();
      final top = cy - fs * 0.56;
      // Viền sẫm, bóng đổ, rồi chữ nhũ vàng chuyển sắc.
      final outline = build(fs, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fs * 0.09
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xff4A0806));
      final shadow = build(fs, Paint()..color = const Color(0x99300000));
      final fill = build(fs, Paint()
        ..shader = Gradient.linear(Offset(0, top), Offset(0, top + fs), colors, const [0, 0.5, 1]));
      c.drawParagraph(shadow, Offset(box.left + fs * 0.04, top + fs * 0.07));
      c.drawParagraph(outline, Offset(box.left, top));
      c.drawParagraph(fill, Offset(box.left, top));
      for (final p in [outline, shadow, fill]) {
        p.dispose();
      }
    }

    const gold = [Color(0xffFFF3B0), Color(0xffF6C93C), Color(0xffD08E12)];
    const pale = [Color(0xffFFFDF2), Color(0xffFBE7A6), Color(0xffEBC062)];
    line(name, 'PaytoneOne', FontWeight.w400, box.height * 0.5, box.top + box.height * 0.33, gold);
    line(second, 'Manrope', FontWeight.w800, box.height * 0.27, box.top + box.height * 0.8, pale);
    final pic = rec.endRecording();
    final out = pic.toImageSync(img.width, img.height);
    pic.dispose();
    cache[key] = out;
    return out;
  }

  /// Quãng [s] sát trụ cổng chào: vách đá, hộ lan chừa chỗ cho trụ.
  bool _gateNear(double s) => game.layout.gates.any((g) => (g.s - s).abs() < 90);

  /// Cổng chào tỉnh: hai trụ đá trên bệ granite có mũ mái bốn dốc, đầu đao,
  /// bầu hồ lô; xà ngang biển son chữ vàng, mái ngói hai dốc, lưỡng long chầu
  /// nhật trên nóc; đèn lồng treo dưới xà, cờ đỏ dọc đường, chậu đào / mai.
  void _gates3d(List<_Drawn> items, DriverArt a, double camS) {
    final lit = _litPanels[this] ??= [];
    lit.clear();
    for (final g in game.layout.gates) {
      final ahead = (g.s - camS) * game.dir;
      if (ahead < -400 || ahead > cam.far + 400) continue;
      _gate(items, a, g, lit);
    }
  }

  void _gate(List<_Drawn> items, DriverArt a, BorderGate g, List<_FaceMesh> lit) {
    const u = _DriverView._u;
    const pd = _GateLayer.pillarD, ph = _GateLayer.pillarHalf, bh = _GateLayer.beamHalf;
    final s = g.s;
    _P3 at(double ds, double d, double z) {
      final o = _at(s + ds, d);
      return (o.dx, o.dy, z);
    }

    // Mặt đứng hình chữ nhật theo (ds, d) hai mép trái → phải như người
    // đứng trước mặt đó nhìn vào.
    List<_P3> face(double ds0, double d0, double ds1, double d1, double z0, double z1) =>
        [at(ds0, d0, z1), at(ds1, d1, z1), at(ds1, d1, z0), at(ds0, d0, z0)];
    List<Offset> full(Image img) =>
        [Offset.zero, Offset(img.width.toDouble(), 0), Offset(img.width.toDouble(), img.height.toDouble()), Offset(0, img.height.toDouble())];
    const unit = [Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1)];
    final zMid = cam.toCam(at(0, 0, 0).$1, at(0, 0, 0).$2, 0).z;

    void add(double depth, List<_FaceMesh?> meshes) {
      final drawn = [for (final m in meshes) ?m];
      if (drawn.isEmpty) return;
      items.add(_Drawn(depth, (c) {
        for (final m in drawn) {
          m.draw(c);
        }
      }));
    }

    /// Bốn mặt đứng của khối hộp ds ∈ [a0, a1], d ∈ [b0, b1]; [tex] cho
    /// từng mặt (trước, sau, hông d dương, hông d âm).
    List<_FaceMesh?> box(double a0, double a1, double b0, double b1, double z0, double z1, List<(Paint, List<Offset>)> tex,
        {double ambient = 0.62, double diffuse = 0.46}) {
      final center = at((a0 + a1) / 2, (b0 + b1) / 2, (z0 + z1) / 2);
      final faces = [face(a0, b0, a0, b1, z0, z1), face(a1, b1, a1, b0, z0, z1), face(a0, b1, a1, b1, z0, z1), face(a1, b0, a0, b0, z0, z1)];
      return [
        for (var i = 0; i < 4; i++) _mesh(faces[i], tex[i].$2, tex[i].$1, center: center, ambient: ambient, diffuse: diffuse),
      ];
    }

    final roofImg = game.images.containsKey(Img.texRoofClay) ? game.images.fromCache(Img.texRoofClay) : null;
    final roof = roofImg != null ? _repeat(roofImg) : (Paint()..color = const Color(0xff9A3B26));
    final rk = roofImg == null ? 1.0 : roofImg.width / 110.0;
    const roofTint = Color(0xffE09A7E);
    final gold = Paint()..color = const Color(0xffE0AE3A);
    final lacquer = Paint()..color = const Color(0xff8E1A16);

    // ----- Trụ cổng
    final base = a.prop('gate_base'), side = a.prop('gate_pillar_side');
    for (final sd in const [-1.0, 1.0]) {
      final d0 = sd * pd;
      final meshes = <_FaceMesh?>[];
      final baseTex = base != null ? (_clamp(base.image), full(base.image)) : (Paint()..color = const Color(0xff97928A), unit);
      const bz = 1.1 * u, bw = 23.0;
      meshes.addAll(box(-bw, bw, d0 - bw, d0 + bw, 0, bz, [baseTex, baseTex, baseTex, baseTex]));
      meshes.add(_mesh([at(-bw, d0 - bw, bz), at(bw, d0 - bw, bz), at(bw, d0 + bw, bz), at(-bw, d0 + bw, bz)], unit,
          Paint()..color = const Color(0xffA8A39A), center: at(0, d0, 0)));
      // Mặt trước / sau: trụ bên trái người nhìn mang vế câu đối đầu.
      final frontL = sd < 0, backL = sd > 0;
      (Paint, List<Offset>) pillarTex(bool left) {
        final art = a.prop(left ? 'gate_pillar_l' : 'gate_pillar_r');
        return art != null ? (_clamp(art.image), full(art.image)) : (Paint()..color = const Color(0xffD8C9A0), unit);
      }

      final sideTex = side != null ? (_clamp(side.image), full(side.image)) : (Paint()..color = const Color(0xffD2C29A), unit);
      const z1 = 10.0 * u;
      meshes.addAll(box(-ph, ph, d0 - ph, d0 + ph, bz, z1, [pillarTex(frontL), pillarTex(backL), sideTex, sideTex], ambient: 0.7, diffuse: 0.36));
      // Mũ trụ: tấm đế vàng, mái bốn dốc lợp ngói, đầu đao cong vút ở bốn góc.
      const cw = 22.0, ew = 28.0, zc = z1 + 0.25 * u, apex = z1 + 1.45 * u;
      meshes.addAll(box(-cw, cw, d0 - cw, d0 + cw, z1, zc, [(gold, unit), (gold, unit), (gold, unit), (gold, unit)]));
      final tip = at(0, d0, apex);
      final corners = [at(-ew, d0 - ew, zc), at(-ew, d0 + ew, zc), at(ew, d0 + ew, zc), at(ew, d0 - ew, zc)];
      final cap = at(0, d0, zc);
      for (var i = 0; i < 4; i++) {
        final p0 = corners[i], p1 = corners[(i + 1) % 4];
        final run = 2 * ew * rk;
        meshes.add(_mesh([p0, p1, tip, tip], [Offset(0, ew * 1.5 * rk), Offset(run, ew * 1.5 * rk), Offset(run / 2, 0), Offset(run / 2, 0)], roof,
            center: cap, tint: roofTint));
      }
      for (final (cs, cd) in const [(-1.0, -1.0), (-1.0, 1.0), (1.0, 1.0), (1.0, -1.0)]) {
        // Đầu đao: mũi mái cong vểnh lên ở góc.
        final c0 = at(cs * ew, d0 + cd * (ew - 9), zc), c1 = at(cs * (ew - 9), d0 + cd * ew, zc);
        final t = at(cs * (ew + 8), d0 + cd * (ew + 8), zc + 0.55 * u);
        meshes.add(_mesh([c0, c1, t, t], unit, Paint()..color = const Color(0xff7A2A1C), cull: false));
      }
      add(zMid - 6, meshes);
      final fin = a.prop('gate_finial');
      if (fin != null) {
        final fh = fin.heightM * u;
        _board(items, tip.$1, tip.$2, fh * fin.aspect, fh, fin.image, lift: apex - 3, bias: -8);
      }
      // Chậu đào (miền Bắc) / mai (miền Nam) hai bên chân trụ, mỗi mặt cổng.
      final flower = a.prop(game.setup.south ? 'flower_apricot_1' : 'flower_peach_1');
      if (flower != null) {
        for (final ds in const [-36.0, 36.0]) {
          final o = _at(s + ds, sd * (pd - 24));
          final fh = flower.heightM * u;
          _board(items, o.dx, o.dy, fh * flower.aspect, fh, flower.image, mirror: ds > 0);
        }
      }
    }

    // ----- Xà ngang: biển son chữ vàng hai mặt, gầm xà sơn son
    const inner = pd - ph, zb0 = 6.0 * u, zb1 = 8.0 * u;
    final beam = <_FaceMesh?>[];
    for (final front in const [true, false]) {
      final img = _panelImage(a, g, front);
      final tex = img != null ? _clamp(img) : (Paint()..color = const Color(0xffB3261E));
      final uv = img != null ? full(img) : unit;
      final m = _mesh(front ? face(-bh, -inner, -bh, inner, zb0, zb1) : face(bh, inner, bh, -inner, zb0, zb1), uv, tex,
          center: at(0, 0, (zb0 + zb1) / 2), ambient: 0.86, diffuse: 0.2);
      beam.add(m);
      if (m != null && game.darkness > 0.25) lit.add(m);
    }
    beam.add(_mesh([at(-bh, -inner, zb0), at(-bh, inner, zb0), at(bh, inner, zb0), at(bh, -inner, zb0)], unit, lacquer,
        center: at(0, 0, zb1), ambient: 0.7, diffuse: 0.1));
    add(zMid + 4, beam);

    // ----- Mái xà: hai dốc lợp ngói, diềm vàng, gầm mái, bờ nóc
    const ov = 10.0, zr = 9.35 * u, ze = zb1 - 0.1 * u;
    final run = 2 * inner * rk, slope = (bh + ov) * 1.4 * rk;
    final roofCenter = at(0, 0, zb1);
    final top = <_FaceMesh?>[
      _mesh([at(-bh - ov, inner, ze), at(-bh - ov, -inner, ze), at(0, -inner, zr), at(0, inner, zr)],
          [Offset(run, slope), Offset(0, slope), Offset.zero, Offset(run, 0)], roof, center: roofCenter, tint: roofTint),
      _mesh([at(bh + ov, -inner, ze), at(bh + ov, inner, ze), at(0, inner, zr), at(0, -inner, zr)],
          [Offset(0, slope), Offset(run, slope), Offset(run, 0), Offset.zero], roof, center: roofCenter, tint: roofTint),
      for (final sgn in const [-1.0, 1.0]) ...[
        _mesh(face(sgn * (bh + ov), -sgn * inner, sgn * (bh + ov), sgn * inner, ze - 0.28 * u, ze + 0.02 * u), unit, gold,
            center: roofCenter, ambient: 0.75, diffuse: 0.3),
        _mesh([at(sgn * (bh + ov), -inner, ze - 0.28 * u), at(sgn * (bh + ov), inner, ze - 0.28 * u), at(sgn * bh, inner, zb1),
          at(sgn * bh, -inner, zb1)], unit, lacquer, cull: false, ambient: 0.55, diffuse: 0),
        _mesh([at(sgn * 5, inner, zr - 3), at(sgn * 5, -inner, zr - 3), at(0, -inner, zr + 3), at(0, inner, zr + 3)], unit, gold,
            center: roofCenter, ambient: 0.7, diffuse: 0.4),
      ],
    ];
    add(zMid + 2, top);
    // Lưỡng long chầu nhật đứng trên nóc (mặt phẳng dọc nóc, nhìn hai phía).
    final dragons = a.prop('gate_dragons');
    if (dragons != null) {
      final dw = dragons.heightM * dragons.aspect * u / 2, dh = dragons.heightM * u;
      final img = dragons.image;
      final m = _mesh(face(0, -dw, 0, dw, zr - 4, zr - 4 + dh), full(img), _clamp(img), cull: false, ambient: 0.85, diffuse: 0.2);
      add(zMid + 1, [m]);
    }
    // Đèn lồng treo dưới xà.
    final lantern = a.prop('gate_lantern');
    if (lantern != null) {
      final lh = lantern.heightM * u;
      for (final d in const [-94.0, -34.0, 34.0, 94.0]) {
        final o = _at(s, d);
        final sway = sin(game._time * 1.3 + d) * 0.4;
        _board(items, o.dx + sway, o.dy, lh * lantern.aspect, lh, lantern.image, lift: zb0 - lh + 2, bias: -2, after: (c, rect, fade) {
          if (game.darkness > 0.2) _glows.add((Offset(rect.center.dx, rect.top + rect.height * 0.42), rect.width * 1.1, const Color(0xffFF5A2E)));
        });
      }
    }
    // Cờ đỏ sao vàng cắm dọc hai bên đường trước và sau cổng.
    for (final sd in const [-1.0, 1.0]) {
      for (final ds in const [-460.0, -340.0, -220.0, 220.0, 340.0]) {
        if (_stallNear(s + ds, sd)) continue;
        _flagPole(items, _at(s + ds, sd * (_DriverView._half + 22)), ds + sd);
      }
    }
  }

  /// Cột cờ thép bên đường, lá cờ đỏ sao vàng bay phấp phới.
  void _flagPole(List<_Drawn> items, Offset o, double seed) {
    const u = _DriverView._u;
    _board(items, o.dx, o.dy, 0.09 * u, 6.2 * u, null, fallback: const Color(0xffC9CCCF));
    final wave = sin(game._time * 4.2 + seed) * 0.06;
    _board(items, o.dx, o.dy, 1.5 * u, 1.0 * u, null, fallback: const Color(0x00000000), lift: 4.9 * u, bias: -0.5,
        after: (c, rect, fade) {
      final r = rect.shift(Offset(rect.width / 2, 0));
      final flag = Path()
        ..moveTo(r.left, r.top)
        ..quadraticBezierTo(r.center.dx, r.top + r.height * wave, r.right, r.top + r.height * 0.06)
        ..lineTo(r.right, r.bottom - r.height * 0.02)
        ..quadraticBezierTo(r.center.dx, r.bottom + r.height * wave, r.left, r.bottom)
        ..close();
      c.drawPath(flag, Paint()..color = const Color(0xffD7262B).withValues(alpha: fade));
      c.drawPath(_DriverView._star(r.center + Offset(0, r.height * wave * 0.5), r.height * 0.3),
          Paint()..color = const Color(0xffFADB30).withValues(alpha: fade));
    });
  }

  /// Ban đêm: biển cổng chào đèn hắt sáng (vẽ lại sau lớp tối).
  void _cultureNight(Canvas canvas, Size size) {
    final lit = _litPanels[this];
    final dark = game.darkness;
    if (lit == null || lit.isEmpty || dark < 0.25) return;
    canvas.save();
    if (_roll.abs() > 1e-4) {
      final pivot = Offset(size.width / 2, size.height * 0.85);
      canvas
        ..translate(pivot.dx, pivot.dy)
        ..rotate(-_roll)
        ..translate(-pivot.dx, -pivot.dy);
    }
    for (final m in lit) {
      final p = Paint()
        ..shader = m.paint.shader
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, (0.62 * dark).clamp(0.0, 1.0) * m.paint.color.a)
        ..colorFilter = const ColorFilter.mode(Color(0xffFFE9C4), BlendMode.modulate);
      m.draw(canvas, p);
    }
    canvas.restore();
  }
}
