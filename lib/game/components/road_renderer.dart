import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../driver/ground_sink.dart';
import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/road_path.dart';
import 'world_paints.dart';

/// Vẽ mặt đất và mặt đường theo tim đường cong, đổi kiểu theo loại đường:
/// - Phố: bó vỉa, vỉa hè lát gạch; ngã tư có vạch dừng, vạch qua đường.
/// - Quốc lộ: lề đất đỏ, bờ cỏ, ruộng lúa / bãi cỏ.
/// - Cao tốc: lề nhựa, dải phân cách cứng, hộ lan tôn sóng.
/// Mọi thứ vẽ theo dải mẫu nên khúc cong nào cũng liền mạch.
class RoadRenderer extends Component {
  RoadRenderer({
    required this.road,
    required this.layout,
    required this.finishS,
    required this.paints,
    required this.images,
    required this.seed,
    this.ripeRice = false,
    this.theme = MapTheme.delta,
  }) : super(priority: 0);

  final RoadPath road;
  final RoadLayout layout;
  final double finishS;
  final WorldPaints paints;
  final Images images;
  final int seed;

  /// Lúa chín vàng (miền Nam dịp Tết) thay cho lúa non xanh (miền Bắc).
  final bool ripeRice;

  /// Cảnh hai bên quốc lộ theo bản đồ đã chọn.
  final MapTheme theme;

  /// Giờ trôi (giây) — sóng biển, mặt kênh gợn.
  double time = 0;

  /// Khoảng đường đang nhìn thấy — game cập nhật mỗi khung hình.
  double fromS = 0;
  double toS = 0;

  static const double _half = GameConfig.roadHalfWidth;
  static const double _sidewalk = GameConfig.sidewalkWidth;
  static const double _ground = 760;

  late final Paint _white = paints.paint(const Color(0xffF4F4F0), 3.2);
  late final Paint _whiteWide = paints.paint(const Color(0xffF4F4F0), 6);
  late final Paint _yellow = paints.paint(const Color(0xffF0C23A), 2.6);
  late final Paint _zebra = paints.texture(Img.texPaint, 90, tint: const Color(0xffF4F4F0));
  final Paint _curbShadow = Paint()
    ..color = const Color(0x40000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _curbEdge = Paint()
    ..color = const Color(0x55000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _wear = Paint()
    ..color = const Color(0x16000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 12;
  final Paint _dike = Paint()
    ..color = const Color(0xff6E8F45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7;
  final Paint _dikeTop = Paint()
    ..color = const Color(0xff8DAA5B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _railShadow = Paint()
    ..color = const Color(0x33000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  final Paint _rail = Paint()
    ..color = const Color(0xffC9CED3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _railPost = Paint()..color = const Color(0xff5E646B);
  final Paint _medianFill = Paint()..color = const Color(0xffD6D3CB);
  final Paint _medianTop = Paint()
    ..color = const Color(0xffEDEBE5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _medianShadow = Paint()
    ..color = const Color(0x38000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6;
  final Paint _reflector = Paint()..color = const Color(0xffFFC53A);
  final Paint _cushionYellow = Paint()..color = const Color(0xffF2C12E);
  final Paint _cushionDark = Paint()..color = AppColors.ff1B1D22;
  final Paint _finishWhite = Paint()..color = const Color(0xffF4F4F0);
  final Paint _finishDark = Paint()..color = AppColors.ff1B1D22;
  final Paint _decal = Paint()..filterQuality = FilterQuality.medium;

  @override
  void render(Canvas canvas) => paintGround(FlatGroundSink(canvas));

  /// Vẽ mặt đất qua [g]: bản đồ nhìn từ trên hoặc phối cảnh ghế lái.
  void paintGround(GroundSink g) {
    // Camera xoay theo đường nên góc màn hình nhìn thấy đất của đoạn hơi xa.
    final groundFrom = fromS - 600;
    final groundTo = toS + 600;
    for (final zone in layout.zones) {
      if (zone.endS < groundFrom && zone != layout.zones.first) continue;
      if (zone.startS > groundTo && zone != layout.zones.last) continue;
      final a = zone == layout.zones.first ? groundFrom : max(groundFrom, zone.startS);
      final b = zone == layout.zones.last ? groundTo : min(groundTo, zone.endS);
      if (b <= a) continue;
      _zoneGround(g, zone, a, b);
    }
    // Chỗ đổi loại đường: cảnh của đoạn sau hoà dần vào đoạn trước.
    for (var i = 1; i < layout.zones.length && g.flat; i++) {
      final zone = layout.zones[i];
      if (zone.startS < groundFrom - _blend || zone.startS - _blend > groundTo) continue;
      _blendIn(g.canvas, zone);
    }

    final samples = road.samplesBetween(fromS, toS).toList(growable: false);
    if (samples.length < 2) return;

    // Trạm thu phí: mặt đường mở rộng (thêm làn xe máy) — vẽ trước nhựa chính.
    for (final t in layout.tollsBetween(fromS, toS)) {
      _tollApron(g, t);
    }
    // Đường ngang ở ngã tư.
    for (final l in layout.lightsBetween(fromS - 200, toS + 200)) {
      _crossRoad(g, l);
    }

    _strip(g, samples, -_half, _half, paints.asphalt);
    // Vệt bánh xe sẫm màu giữa mỗi làn.
    for (final lane in [-93.0, -33.0, 33.0, 93.0]) {
      _line(g, samples, lane - 12, _wear);
      _line(g, samples, lane + 12, _wear);
    }
    _decals(g);

    for (final zone in layout.zones) {
      final a = max(fromS, zone.startS);
      final b = min(toS, zone.endS);
      if (b <= a) continue;
      _zoneMarkings(g, zone, a, b);
    }
    for (final l in layout.lightsBetween(fromS - 200, toS + 200)) {
      _crossings(g, l);
    }
    if (finishS >= fromS && finishS <= toS) _finish(g);
  }

  static const double _blend = 260;

  /// Vẽ cảnh của [zone] lùi vào đoạn trước một quãng, độ đậm tăng dần từ 0
  /// tới 1 khi tới đầu [zone].
  void _blendIn(Canvas canvas, RoadZone zone) {
    final a = zone.startS - _blend, b = zone.startS + 2;
    final pa = road.at(a), pb = road.at(b);
    final bounds = Rect.fromPoints(Offset(pa.x, pa.y), Offset(pb.x, pb.y)).inflate(_ground + 40);
    canvas.saveLayer(bounds, Paint());
    _zoneGround(FlatGroundSink(canvas), zone, a, b);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = Gradient.linear(Offset(pa.x, pa.y), Offset(pb.x, pb.y), const [Color(0x00000000), Color(0xff000000)]),
    );
    canvas.restore();
  }

  // ---------------------------------------------------------- Mặt đất
  void _zoneGround(GroundSink g, RoadZone zone, double a, double b) {
    final samples = road.samplesBetween(a, b).where((p) => p.s <= b + 8).toList(growable: false);
    if (samples.length < 2) return;
    switch (zone.kind) {
      case RoadKind.city:
        _bothSides(g, samples, _half + _sidewalk, _ground, paints.concrete);
        final tiles = (zone.startS ~/ 1000).isEven ? paints.pavingRed : paints.paving;
        _bothSides(g, samples, _half + 5, _half + _sidewalk, tiles);
        _bothSides(g, samples, _half, _half + 5, paints.curb);
        _line(g, samples, _half + 5, _curbEdge);
        _line(g, samples, -_half - 5, _curbEdge);
        _line(g, samples, _half + 1.5, _curbShadow);
        _line(g, samples, -_half - 1.5, _curbShadow);
      case RoadKind.highway:
        switch (theme) {
          case MapTheme.coast:
            _coast(g, samples);
          case MapTheme.mountain:
            _mountain(g, samples);
          case MapTheme.mekong:
            _mekong(g, zone, samples, a, b);
          case MapTheme.delta:
          case MapTheme.auto:
            _fields(g, zone, samples, a, b);
            _bothSides(g, samples, _half + 24, _half + 62, paints.verge);
            _bothSides(g, samples, _half, _half + 24, paints.laterite);
        }
      case RoadKind.expressway:
        _bothSides(g, samples, _half + 30, _ground, paints.grassRough);
        _bothSides(g, samples, _half, _half + 30, paints.asphaltLight);
    }
  }

  /// Ven biển: phía d dương bãi cát, sóng vỗ bờ, biển xanh tới chân trời;
  /// phía kia cát lẫn cỏ bụi (rặng phi lao do lớp cảnh vật trồng).
  void _coast(GroundSink g, List<RoadSample> samples) {
    _strip(g, samples, _half, _half + 92, paints.sand);
    _strip(g, samples, _half + 92, _half + 108, paints.sandWet);
    _strip(g, samples, _half + 104, _seaReach, paints.sea(time));
    // Hai lằn sóng bạc đầu xô vào bờ.
    for (final (base, amp, alpha, width) in [(106.0, 4.0, 0.75, 5.0), (122.0, 6.0, 0.35, 3.5), (146.0, 7.0, 0.18, 3.0)]) {
      _line(g, samples, _half + base + amp * sin(time * 1.3), _foam(alpha, width));
    }
    _strip(g, samples, -_half - 34, -_half, paints.sand);
    _strip(g, samples, -_ground, -_half - 34, paints.scrub);
  }

  /// Biển / vực trải tới tận chân trời (góc nhìn ghế lái thấy xa).
  static const double _seaReach = 3200;

  Paint _foam(double alpha, double width) => Paint()
    ..color = Color.fromRGBO(255, 255, 255, alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  /// Đèo núi: phía d dương lề bê tông, hộ lan tôn sóng rồi vực rừng sâu;
  /// phía kia rãnh thoát nước dưới chân vách đá taluy, rừng trên đỉnh vách.
  void _mountain(GroundSink g, List<RoadSample> samples) {
    _strip(g, samples, _half, _half + 24, paints.asphaltLight);
    _strip(g, samples, _half + 24, _seaReach, paints.forestDeep);
    _strip(g, samples, _half + 24, _half + 64, Paint()..color = const Color(0x66000000));
    _line(g, samples, _half + 22, _railShadow);
    _line(g, samples, _half + 20, _rail);
    final a = samples.first.s, b = samples.last.s;
    for (var s = (a / 36).ceil() * 36.0; s < b; s += 36) {
      g.circle(_point(road.at(s), _half + 21), 2.2, _railPost);
    }
    _strip(g, samples, -_half - 14, -_half, paints.laterite);
    _strip(g, samples, -_half - 96, -_half - 14, paints.rock);
    _line(g, samples, -_half - 15, _curbShadow);
    _strip(g, samples, -_ground, -_half - 96, paints.forest);
  }

  /// Sông nước: phía d dương bờ cỏ rồi con kênh chạy dọc đường, bờ bên kia
  /// là vườn; phía kia ruộng lúa như đồng bằng.
  void _mekong(GroundSink g, RoadZone zone, List<RoadSample> samples, double a, double b) {
    _fields(g, zone, samples, a, b, sides: const [-1.0]);
    _strip(g, samples, -_half - 62, -_half - 24, paints.verge);
    _strip(g, samples, -_half - 24, -_half, paints.laterite);
    _strip(g, samples, _half, _half + 30, paints.grass);
    _strip(g, samples, _half + 30, _half + 38, paints.mud);
    _strip(g, samples, _half + 38, _half + 152, paints.canal);
    for (final (base, alpha) in [(70.0, 0.12), (104.0, 0.09), (128.0, 0.1)]) {
      _line(g, samples, _half + base + 3 * sin(time * 0.8 + base), _foam(alpha, 2.2));
    }
    _strip(g, samples, _half + 152, _half + 160, paints.mud);
    _strip(g, samples, _half + 160, _ground, paints.grass);
  }

  /// Ruộng lúa xen bãi cỏ, chia ô bằng bờ ruộng.
  void _fields(GroundSink g, RoadZone zone, List<RoadSample> samples, double a, double b, {List<double> sides = const [-1.0, 1.0]}) {
    const chunk = 1800.0;
    for (var k = (a / chunk).floor(); k * chunk < b; k++) {
      final from = max(a, k * chunk), to = min(b, (k + 1) * chunk);
      final part = samples.where((p) => p.s >= from - 8 && p.s <= to + 8).toList(growable: false);
      if (part.length < 2) continue;
      for (final side in sides) {
        final hash = Random(seed * 7349 + k * 31 + (side > 0 ? 1 : 0)).nextDouble();
        final paddy = hash < 0.62;
        _strip(g, part, side * (_half + 60), side * _ground, paddy ? (ripeRice ? paints.paddyRipe : paints.paddy) : paints.grass);
        if (!paddy) continue;
        // Bờ ruộng: một bờ dọc đường, các bờ ngang cách đều.
        _line(g, part, side * (_half + 64), _dike);
        _line(g, part, side * (_half + 64), _dikeTop);
        _line(g, part, side * (_half + 300), _dike);
        for (var s = (from / 260).ceil() * 260.0; s < to; s += 260) {
          final p = road.at(s);
          final o1 = _point(p, side * (_half + 64)), o2 = _point(p, side * _ground);
          g.segment(o1, o2, _dike);
          g.segment(o1, o2, _dikeTop);
        }
      }
    }
  }

  void _bothSides(GroundSink g, List<RoadSample> samples, double d1, double d2, Paint paint) {
    _strip(g, samples, d1, d2, paint);
    _strip(g, samples, -d2, -d1, paint);
  }

  // ---------------------------------------------------------- Vạch kẻ
  void _zoneMarkings(GroundSink g, RoadZone zone, double a, double b) {
    // Bỏ vạch ở trong lòng ngã tư.
    final ranges = <(double, double)>[(a, b)];
    for (final l in layout.lightsBetween(a - 100, b + 100)) {
      final cut = (l.s - l.halfWidth - 4, l.s + l.halfWidth + 4);
      final next = <(double, double)>[];
      for (final r in ranges) {
        if (cut.$2 <= r.$1 || cut.$1 >= r.$2) {
          next.add(r);
        } else {
          if (cut.$1 > r.$1) next.add((r.$1, cut.$1));
          if (cut.$2 < r.$2) next.add((cut.$2, r.$2));
        }
      }
      ranges
        ..clear()
        ..addAll(next);
    }
    const laneSplit = GameConfig.centerGap / 2 + GameConfig.laneWidth;
    for (final (from, to) in ranges) {
      final samples = road.samplesBetween(from, to).where((p) => p.s <= to + 8).toList(growable: false);
      if (samples.length < 2) continue;
      switch (zone.kind) {
        case RoadKind.city:
          _line(g, samples, -1.8, _yellow);
          _line(g, samples, 1.8, _yellow);
          _dashed(g, from, to, laneSplit, 30, 50, _white);
          _dashed(g, from, to, -laneSplit, 30, 50, _white);
        case RoadKind.highway:
          _line(g, samples, -_half + 5, _white);
          _line(g, samples, _half - 5, _white);
          _line(g, samples, -1.8, _yellow);
          _line(g, samples, 1.8, _yellow);
          _dashed(g, from, to, laneSplit, 50, 70, _white);
          _dashed(g, from, to, -laneSplit, 50, 70, _white);
        case RoadKind.expressway:
          _line(g, samples, -_half + 5, _white);
          _line(g, samples, _half - 5, _white);
          _dashed(g, from, to, laneSplit, 60, 90, _white);
          _dashed(g, from, to, -laneSplit, 60, 90, _white);
          _median(g, zone, from, to);
          _guardrails(g, samples);
      }
    }
  }

  /// Dải phân cách bê tông giữa hai chiều cao tốc, có đệm chống va ở hai đầu.
  void _median(GroundSink g, RoadZone zone, double from, double to) {
    final a = max(from, zone.startS + GameConfig.medianInset);
    final b = min(to, zone.endS - GameConfig.medianInset);
    if (b <= a) {
      // Ngoài dải phân cách: vạch vàng đôi như quốc lộ.
      final samples = road.samplesBetween(from, to).where((p) => p.s <= to + 8).toList(growable: false);
      _line(g, samples, -1.8, _yellow);
      _line(g, samples, 1.8, _yellow);
      return;
    }
    final samples = road.samplesBetween(a, b).where((p) => p.s <= b + 8).toList(growable: false);
    if (samples.length < 2) return;
    const w = GameConfig.medianHalfWidth;
    _line(g, samples, w + 3, _medianShadow);
    _strip(g, samples, -w, w, _medianFill);
    _line(g, samples, 0, _medianTop);
    for (var s = (a / 48).ceil() * 48.0; s < b; s += 48) {
      g.circle(_point(road.at(s), -w + 1.5), 1.6, _reflector);
      g.circle(_point(road.at(s), w - 1.5), 1.6, _reflector);
    }
    // Đệm chống va (sọc vàng đen) ở đầu và cuối dải.
    for (final end in [zone.startS + GameConfig.medianInset, zone.endS - GameConfig.medianInset]) {
      if (end < from - 40 || end > to + 40) continue;
      for (var i = 0; i < 4; i++) {
        final s0 = end == zone.startS + GameConfig.medianInset ? end - 32 + i * 8 : end + i * 8;
        _quad(g, s0, s0 + 8, -w - 1, w + 1, i.isEven ? _cushionYellow : _cushionDark);
      }
    }
  }

  void _guardrails(GroundSink g, List<RoadSample> samples) {
    for (final side in [-1.0, 1.0]) {
      final d = side * (_half + 30);
      _line(g, samples, d + 3, _railShadow);
      _line(g, samples, d, _rail);
    }
    final a = samples.first.s, b = samples.last.s;
    for (var s = (a / 36).ceil() * 36.0; s < b; s += 36) {
      final p = road.at(s);
      for (final side in [-1.0, 1.0]) {
        g.circle(_point(p, side * (_half + 32)), 2.2, _railPost);
      }
    }
  }

  // ------------------------------------------------------------ Ngã tư
  void _crossRoad(GroundSink g, TrafficLight l) {
    final hw = l.halfWidth;
    // Đường ngang + vỉa hè hai bên đường ngang.
    _quad(g, l.s - hw - _sidewalk, l.s + hw + _sidewalk, -_ground, _ground, paints.pavingRed);
    _quad(g, l.s - hw, l.s + hw, -_ground, _ground, paints.asphalt);
    // Bó vỉa dọc hai mép đường ngang (ngoài đường chính).
    for (final side in [-1.0, 1.0]) {
      for (final s in [l.s - hw, l.s + hw]) {
        final p = road.at(s);
        g.segment(_point(p, side * _half), _point(p, side * _ground), _curbShadow);
      }
      // Vạch giữa đường ngang (vàng đứt) và vạch dừng của đường ngang.
      for (var d = _half + 60.0; d < _ground; d += 70) {
        _seg(g, l.s, side * d, side * (d + 36), _yellow);
      }
      final stop = side * (_half + GameConfig.crossStopGap);
      final p0 = road.at(side < 0 ? l.s - hw + 4 : l.s + 2);
      final p1 = road.at(side < 0 ? l.s - 2 : l.s + hw - 4);
      g.segment(_point(p0, stop), _point(p1, stop), _whiteWide);
    }
  }

  void _crossings(GroundSink g, TrafficLight l) {
    final hw = l.halfWidth;
    // Vạch dừng: chiều mình (nửa dưới) và chiều ngược (nửa trên).
    _seg(g, l.stopLine, 3, _half - 3, _whiteWide);
    _seg(g, l.oncomingStopLine, -_half + 3, -3, _whiteWide);
    // Vạch người đi bộ qua đường chính, hai bên ngã tư.
    for (final (a, b) in [(l.stopLine + 6, l.s - hw - 3), (l.s + hw + 3, l.oncomingStopLine - 6)]) {
      for (var d = -_half + 6; d < _half - 6; d += 15) {
        _quad(g, a, b, d, d + 8, _zebra);
      }
    }
    // Vạch qua đường ngang, sát mép đường chính.
    for (final side in [-1.0, 1.0]) {
      final d0 = side * (_half + 6), d1 = side * (_half + 24);
      for (var s = l.s - hw + 4; s < l.s + hw - 6; s += 15) {
        _quad(g, s, s + 8, min(d0, d1), max(d0, d1), _zebra);
      }
    }
  }

  // ------------------------------------------------------ Trạm thu phí
  void _tollApron(GroundSink g, TollPlaza t) {
    final samples = road.samplesBetween(t.plazaStart - 220, t.plazaEnd + 220).toList(growable: false);
    final outer = <Offset>[], inner = <Offset>[];
    for (final p in samples) {
      final mirror = t.s + (t.s - p.s);
      final edge = max(t.maxEdge(p.s), t.maxEdge(mirror));
      outer.add(_point(p, edge + 4));
      inner.add(_point(p, -edge - 4));
    }
    g.band(outer, inner, paints.asphaltLight);
  }

  // -------------------------------------------- Miếng vá, vết dầu, nắp cống
  void _decals(GroundSink g) {
    const chunk = 230.0;
    for (var k = (fromS / chunk).floor(); k * chunk < toS; k++) {
      final r = Random(seed * 92821 + k);
      final s = k * chunk + r.nextDouble() * chunk;
      if (layout.nearFeature(s)) continue;
      final kind = layout.kindAt(s);
      final roll = r.nextDouble();
      String? path;
      double d = 0, width = 0;
      if (roll < 0.22 && kind != RoadKind.expressway) {
        path = Img.roadPatches[r.nextInt(Img.roadPatches.length)];
        d = (r.nextDouble() - 0.5) * 2 * (_half - 40);
        width = 60 + r.nextDouble() * 50;
      } else if (roll < 0.5) {
        path = Img.oilStains[r.nextInt(Img.oilStains.length)];
        d = [-93.0, -33.0, 33.0, 93.0][r.nextInt(4)] + (r.nextDouble() - 0.5) * 10;
        width = 22 + r.nextDouble() * 16;
      } else if (roll < 0.62 && kind == RoadKind.city) {
        path = Img.imgManhole;
        d = (r.nextBool() ? 1 : -1) * (40 + r.nextDouble() * 50);
        width = 26;
      } else if (roll < 0.8 && kind == RoadKind.city) {
        path = Img.imgDrain;
        d = (r.nextBool() ? 1 : -1) * (_half - 8);
        width = 30;
      }
      if (path == null) continue;
      final img = images.fromCache(path);
      final p = road.at(s);
      final o = _point(p, d);
      final angle = p.heading + (path == Img.imgDrain ? 0 : r.nextDouble() * 0.4 - 0.2);
      g.image(img, o, angle, width, width * img.height / img.width, _decal);
    }
  }

  // ------------------------------------------------------------- Hình học
  Offset _point(RoadSample p, double d) {
    // Phía trong khúc cua: không vẽ quá gần tâm cong, kẻo dải đất gập ngược.
    if (p.curvature * d > 0.9) d = 0.9 / p.curvature;
    return Offset(p.x - sin(p.heading) * d, p.y + cos(p.heading) * d);
  }

  void _strip(GroundSink g, List<RoadSample> samples, double d1, double d2, Paint paint) {
    g.band([for (final p in samples) _point(p, d1)], [for (final p in samples) _point(p, d2)], paint);
  }

  void _line(GroundSink g, List<RoadSample> samples, double d, Paint paint) {
    g.polyline([for (final p in samples) _point(p, d)], paint);
  }

  /// Tứ giác theo toạ độ đường (s từ [s0] tới [s1], d từ [d0] tới [d1]).
  void _quad(GroundSink g, double s0, double s1, double d0, double d1, Paint paint) {
    final a = road.at(s0), b = road.at(s1);
    g.polygon([_point(a, d0), _point(b, d0), _point(b, d1), _point(a, d1)], paint);
  }

  /// Đoạn thẳng ngang đường tại [s], từ [d0] tới [d1].
  void _seg(GroundSink g, double s, double d0, double d1, Paint paint) {
    final p = road.at(s);
    g.segment(_point(p, d0), _point(p, d1), paint);
  }

  /// Vạch đứt neo theo quãng đường nên trôi đúng theo mặt đường.
  void _dashed(GroundSink g, double from, double to, double d, double dash, double gap, Paint paint) {
    final period = dash + gap;
    for (var a = (from / period).floor() * period; a < to; a += period) {
      final s0 = max(a, from), s1 = min(a + dash, to);
      if (s1 <= s0) continue;
      g.segment(_point(road.at(s0), d), _point(road.at(s1), d), paint);
    }
  }

  /// Vạch đích dạng bàn cờ ngang mặt đường.
  void _finish(GroundSink g) {
    const cell = 12.0;
    final cols = (2 * _half / cell).ceil();
    for (var row = 0; row < 3; row++) {
      final s0 = finishS + row * cell;
      for (var col = 0; col < cols; col++) {
        final d0 = -_half + col * cell;
        _quad(g, s0, s0 + cell, d0, min(_half, d0 + cell), (row + col).isEven ? _finishWhite : _finishDark);
      }
    }
  }
}
