import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../model/place.dart';
import '../../../resource/app_colors.dart';
import '../../../resource/vn_map_tiles.dart';
import 'map_camera.dart';
import 'map_geometry.dart';
import 'map_tile_cache.dart';

/// Màu riêng của bản đồ (chỉ dùng trong màn này).
abstract class MapColors {
  static const Color sea = AppColors.ff4B86BE;
  static const Color coast = Color(0xff3F6F86);
  static const Color border = Color(0xff9B2C5A);
  static const Color borderHalo = Color(0x55E07AA5);
  static const Color otherBorder = Color(0x99877C6E);
  static const Color river = Color(0xff4F95C8);
  static const Color highway = AppColors.ffEE9B2F;
  static const Color expressway = Color(0xff1E9C53);
  static const Color route = AppColors.ffD62828;
  static const Color label = Color(0xff1F2329);
  static const Color seaLabel = Color(0xffE8F3FA);
  static const Color countryLabel = Color(0xff8C7F6C);
  static const Color islandLabel = Color(0xff16466B);
  static const Color islandLand = Color(0xffD9C98F);
  static const Color from = AppColors.ff1E9C53;
  static const Color to = AppColors.ffD62828;
  static const Color stop = AppColors.ffFFD166;
}

/// Vẽ toàn bộ bản đồ: nền địa hình, sông, biên giới, mạng đường, lộ trình,
/// chấm thành phố và nhãn (tự tránh chồng lên nhau).
class TripMapPainter extends CustomPainter {
  TripMapPainter({
    required this.camera,
    required this.tiles,
    required this.places,
    required this.fromId,
    required this.toId,
    required this.route,
    required this.routeIds,
    required this.majorIds,
    required this.unit,
    required this.dpr,
    required this.text,
  }) : super(repaint: Listenable.merge([camera, tiles]));

  final MapCamera camera;
  final MapTileCache tiles;
  final List<Place> places;
  final String? fromId;
  final String? toId;
  final RouteGeometry? route;
  final Set<String> routeIds;
  final Set<String> majorIds;

  /// 1 đơn vị thiết kế (1.h) — cỡ chữ, chấm, nét đều nhân với số này.
  final double unit;
  final double dpr;
  final MapTextCache text;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = MapColors.sea);
    canvas.save();
    canvas.translate(camera.focal.dx, camera.focal.dy);
    canvas.scale(camera.scale);
    canvas.translate(-camera.center.dx, -camera.center.dy);
    _paintTiles(canvas);
    _paintVectors(canvas);
    canvas.restore();
    _paintIslandGroups(canvas);
    _paintOverlay(canvas, size);
  }

  // ------------------------------------------------------------ Nền
  void _paintTiles(Canvas canvas) {
    final visible = camera.visible;
    final need = camera.scale * dpr;
    var top = VnMapTiles.levelPpu.length - 1;
    for (var l = 0; l < VnMapTiles.levelPpu.length; l++) {
      if (VnMapTiles.levelPpu[l] >= need * 0.8) {
        top = l;
        break;
      }
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = false;
    for (var l = 0; l <= top; l++) {
      final span = VnMapTiles.tileSize / VnMapTiles.levelPpu[l];
      final available = VnMapTiles.tiles[l];
      for (var i = (visible.left / span).floor(); i <= (visible.right / span).floor(); i++) {
        for (var j = (visible.top / span).floor(); j <= (visible.bottom / span).floor(); j++) {
          if (!available.contains(i * 1000 + j)) continue;
          final img = tiles.tile(l, i, j);
          if (img == null) continue;
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(i * span, j * span, span, span),
            paint,
          );
        }
      }
    }
  }

  // --------------------------------------------------------- Vector
  Paint _stroke(Color color, double px, {StrokeCap cap = StrokeCap.round}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = px / camera.scale
    ..strokeCap = cap
    ..strokeJoin = StrokeJoin.round;

  void _paintVectors(Canvas canvas) {
    final shapes = MapShapes.shared;
    final s = camera.scale;
    final zoomIn = ((s - 20) / 120).clamp(0.0, 1.0); // 0 lúc thu nhỏ hết, 1 khi phóng to

    // Sông: hiện rõ dần khi phóng to.
    canvas.drawPath(shapes.majorRivers, _stroke(MapColors.river.withValues(alpha: 0.55 + 0.4 * zoomIn), (0.9 + 1.2 * zoomIn) * unit));
    if (zoomIn > 0.1) {
      canvas.drawPath(shapes.rivers, _stroke(MapColors.river.withValues(alpha: 0.7 * zoomIn), (0.6 + 0.8 * zoomIn) * unit));
    }

    // Biên giới, bờ biển.
    canvas.drawPath(shapes.otherBorders, _stroke(MapColors.otherBorder, 0.9 * unit));
    canvas.drawPath(shapes.coast, _stroke(MapColors.coast.withValues(alpha: 0.55), 0.8 * unit));
    canvas.drawPath(shapes.border, _stroke(MapColors.borderHalo, 4.5 * unit));
    canvas.drawPath(shapes.border, _stroke(MapColors.border, 1.3 * unit));

    // Đảo nhỏ: tô kín + chấm tối thiểu để luôn thấy được.
    canvas.drawPath(shapes.islands, Paint()..color = MapColors.islandLand);
    canvas.drawPath(shapes.islands, _stroke(MapColors.coast, 0.7 * unit));
    final dot = Paint()..color = MapColors.islandLand;
    final dotEdge = _stroke(MapColors.coast, 0.7 * unit);
    for (final p in shapes.islandDots) {
      canvas.drawCircle(p, 1.4 * unit / s, dot);
      canvas.drawCircle(p, 1.4 * unit / s, dotEdge);
    }

    // Mạng đường: mờ đi khi đã có lộ trình.
    final dim = route == null ? 1.0 : 0.55;
    final roadW = (1.1 + 1.1 * zoomIn) * unit;
    canvas.drawPath(shapes.highways, _stroke(AppColors.ffFFFFFF.withValues(alpha: 0.75 * dim), roadW + 1.6 * unit));
    canvas.drawPath(shapes.highways, _stroke(MapColors.highway.withValues(alpha: dim), roadW));
    canvas.drawPath(shapes.expressways, _stroke(AppColors.ffFFFFFF.withValues(alpha: 0.85 * dim), roadW + 2.4 * unit));
    canvas.drawPath(shapes.expressways, _stroke(MapColors.expressway.withValues(alpha: dim), roadW + 0.6 * unit));

    // Lộ trình: bóng mờ, viền trắng, lõi đỏ.
    final r = route;
    if (r != null) {
      canvas.drawPath(
        r.path,
        _stroke(AppColors.ff000000.withValues(alpha: 0.28), 9 * unit)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * unit / s),
      );
      canvas.drawPath(r.path, _stroke(AppColors.ffFFFFFF, 8 * unit));
      canvas.drawPath(r.path, _stroke(MapColors.route, 4.6 * unit));
    }
  }

  /// Khung nét đứt quanh Hoàng Sa, Trường Sa cho dễ thấy khi thu nhỏ.
  void _paintIslandGroups(Canvas canvas) {
    final paint = Paint()
      ..color = MapColors.islandLabel.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * unit;
    for (final box in const [
      [111.05, 17.25, 113.0, 15.65],
      [111.35, 11.75, 116.4, 7.45],
    ]) {
      final a = camera.toScreen(MapProjection.fromLonLat(box[0], box[1]));
      final b = camera.toScreen(MapProjection.fromLonLat(box[2], box[3]));
      _dashedRRect(canvas, RRect.fromRectAndRadius(Rect.fromPoints(a, b), Radius.circular(10 * unit)), paint);
    }
  }

  void _dashedRRect(Canvas canvas, RRect rect, Paint paint) {
    final path = Path()..addRRect(rect);
    final dash = 6 * unit, gap = 5 * unit;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, min(d + dash, metric.length)), paint);
      }
    }
  }

  // ---------------------------------------------- Chấm, ghim, nhãn
  void _paintOverlay(Canvas canvas, Size size) {
    final u = unit;
    final view = (Offset.zero & size).inflate(60 * u);
    final placed = <Rect>[];
    bool free(Rect r) => !placed.any((p) => p.overlaps(r));

    final byId = {for (final p in places) p.id: p};
    final from = fromId == null ? null : byId[fromId];
    final to = toId == null ? null : byId[toId];

    // Chỗ của ghim điểm đi/đến: chặn trước để nhãn khác không đè lên.
    for (final p in [from, to]) {
      if (p == null) continue;
      final s = camera.toScreen(p.position);
      placed.add(Rect.fromCenter(center: s.translate(0, -16 * u), width: 26 * u, height: 34 * u));
    }

    // Chấm thành phố (dưới cùng), ưu tiên nhãn: trên lộ trình > thành phố lớn > còn lại.
    final showMinorLabels = camera.scale > 75;
    // Cùng hạng thì theo thứ tự ưu tiên của danh sách thành phố lớn.
    final majors = majorIds.toList();
    int priority(Place p) => _rank(p) * 100 + (majors.contains(p.id) ? majors.indexOf(p.id) : 99);
    final order = [...places]..sort((a, b) => priority(a).compareTo(priority(b)));
    for (final p in places) {
      if (p == from || p == to) continue;
      final s = camera.toScreen(p.position);
      if (!view.contains(s)) continue;
      _dot(canvas, s, p);
    }

    // Trạm dừng giữa các chặng (số = chặng bắt đầu từ đó), vẽ đè lên chấm.
    final stops = route?.stops ?? const <Offset>[];
    for (var k = 0; k < stops.length; k++) {
      final s = camera.toScreen(stops[k]);
      if (!view.contains(s)) continue;
      _stopBadge(canvas, s, k + 2);
      placed.add(Rect.fromCircle(center: s, radius: 5 * u));
    }

    // Nhãn quần đảo luôn hiện; biển, nước láng giềng nhường chỗ.
    final deferred = <MapLabel>[];
    for (final label in MapLabel.all) {
      if (label.kind == MapLabelKind.archipelago) {
        final rect = _fixedLabel(canvas, label, placed, force: true);
        if (rect != null) placed.add(rect);
      } else {
        deferred.add(label);
      }
    }

    // Chip tên điểm đi/đến luôn hiện.
    for (final entry in [(from, MapColors.from, 'Đi'), (to, MapColors.to, 'Về')]) {
      final p = entry.$1;
      if (p == null) continue;
      final s = camera.toScreen(p.position);
      final rect = _chip(canvas, s, p, entry.$2, entry.$3, placed);
      placed.add(rect);
    }

    for (final p in order) {
      if (p == from || p == to) continue;
      final rank = _rank(p);
      if (rank == 2 && !showMinorLabels) continue;
      final s = camera.toScreen(p.position);
      if (!view.contains(s)) continue;
      final rect = _cityLabel(canvas, s, p, bold: rank == 0, free: free);
      if (rect != null) placed.add(rect);
    }

    for (final label in deferred) {
      final rect = _fixedLabel(canvas, label, placed, force: false);
      if (rect != null) placed.add(rect);
    }

    // Ghim điểm đi/đến vẽ sau cùng cho nổi lên trên.
    if (from != null) _pin(canvas, camera.toScreen(from.position), MapColors.from, home: false);
    if (to != null) _pin(canvas, camera.toScreen(to.position), MapColors.to, home: true);
  }

  int _rank(Place p) => routeIds.contains(p.id)
      ? 0
      : majorIds.contains(p.id)
          ? 1
          : 2;

  void _dot(Canvas canvas, Offset s, Place p) {
    final u = unit;
    final onRoute = routeIds.contains(p.id);
    final r = (onRoute ? 4.6 : majorIds.contains(p.id) ? 4.2 : 3.4) * u;
    canvas.drawCircle(s.translate(0, 0.8 * u), r + 1.2 * u, Paint()..color = const Color(0x40000000));
    canvas.drawCircle(s, r, Paint()..color = AppColors.ffFFFFFF);
    canvas.drawCircle(
      s,
      r,
      Paint()
        ..color = onRoute ? MapColors.route : MapColors.label
        ..style = PaintingStyle.stroke
        ..strokeWidth = (onRoute ? 2.2 : 1.6) * u,
    );
  }

  Rect? _cityLabel(Canvas canvas, Offset s, Place p, {required bool bold, required bool Function(Rect) free}) {
    final u = unit;
    final painters = text.halo(p.name, fontSize: (bold ? 12.5 : 11.5) * u, weight: bold ? FontWeight.w800 : FontWeight.w700, color: MapColors.label, halo: AppColors.ffFFFFFF, haloWidth: 3 * u);
    final w = painters.$1.width, h = painters.$1.height;
    final gap = 8.5 * u;
    Offset sideOffset(LabelSide side) => switch (side) {
          LabelSide.right => Offset(s.dx + gap, s.dy - h / 2),
          LabelSide.left => Offset(s.dx - gap - w, s.dy - h / 2),
          LabelSide.top => Offset(s.dx - w / 2, s.dy - gap - h + 2 * u),
          LabelSide.bottom => Offset(s.dx - w / 2, s.dy + gap - 2 * u),
        };
    final sides = [p.label, ...LabelSide.values.where((v) => v != p.label)];
    for (final side in sides) {
      final o = sideOffset(side);
      final rect = Rect.fromLTWH(o.dx, o.dy, w, h).inflate(1.5 * u);
      if (free(rect)) {
        painters.$2.paint(canvas, o);
        painters.$1.paint(canvas, o);
        return rect;
      }
    }
    return null;
  }

  Rect? _fixedLabel(Canvas canvas, MapLabel label, List<Rect> placed, {required bool force}) {
    final u = unit;
    final s = camera.toScreen(label.position);
    final (double size, FontWeight weight, Color color, Color halo, double spacing, FontStyle style) = switch (label.kind) {
      MapLabelKind.archipelago => (11.5 * u, FontWeight.w800, MapColors.islandLabel, const Color(0xccE6F2F8), 0.0, FontStyle.normal),
      MapLabelKind.sea => (20 * u, FontWeight.w700, MapColors.seaLabel, const Color(0x552A5F92), 2.5 * u, FontStyle.italic),
      MapLabelKind.bay => (12 * u, FontWeight.w700, MapColors.seaLabel, const Color(0x552A5F92), 0.8 * u, FontStyle.italic),
      MapLabelKind.country => (11 * u, FontWeight.w700, MapColors.countryLabel, const Color(0x99F4F1EA), 3 * u, FontStyle.normal),
    };
    final main = text.halo(label.text, fontSize: size, weight: weight, color: color, halo: halo, haloWidth: 3 * u, letterSpacing: spacing, style: style);
    final sub = label.sub == null
        ? null
        : text.halo(label.sub!, fontSize: size * 0.85, weight: FontWeight.w700, color: color, halo: halo, haloWidth: 3 * u);
    final w = max(main.$1.width, sub?.$1.width ?? 0);
    final h = main.$1.height + (sub?.$1.height ?? 0);
    final rect = Rect.fromCenter(center: s, width: w, height: h);
    if (!force && placed.any((p) => p.overlaps(rect))) return null;
    var y = rect.top;
    for (final painters in [main, ?sub]) {
      final o = Offset(s.dx - painters.$1.width / 2, y);
      painters.$2.paint(canvas, o);
      painters.$1.paint(canvas, o);
      y += painters.$1.height;
    }
    return rect;
  }

  Rect _chip(Canvas canvas, Offset s, Place p, Color color, String tag, List<Rect> placed) {
    final u = unit;
    final name = text.plain(p.name, fontSize: 13 * u, weight: FontWeight.w800, color: MapColors.label);
    final tagText = text.plain(tag, fontSize: 10 * u, weight: FontWeight.w800, color: AppColors.ffFFFFFF);
    final pad = 6 * u;
    final tagW = tagText.width + 2 * pad;
    final w = tagW + name.width + 2 * pad;
    final h = max(name.height, tagText.height) + 2 * 3.5 * u;
    final headY = s.dy - 21 * u;
    Rect at(LabelSide side) => switch (side) {
          LabelSide.left => Rect.fromLTWH(s.dx - 16 * u - w, headY - h / 2, w, h),
          LabelSide.top => Rect.fromLTWH(s.dx - w / 2, headY - 16 * u - h, w, h),
          LabelSide.bottom => Rect.fromLTWH(s.dx - w / 2, s.dy + 6 * u, w, h),
          LabelSide.right => Rect.fromLTWH(s.dx + 16 * u, headY - h / 2, w, h),
        };
    final sides = [p.label, ...LabelSide.values.where((v) => v != p.label)];
    final rect = sides.map(at).firstWhere((r) => !placed.any((q) => q.overlaps(r)), orElse: () => at(p.label));
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
    canvas.drawRRect(rr.shift(Offset(0, 1.5 * u)), Paint()..color = const Color(0x44000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * u));
    canvas.drawRRect(rr, Paint()..color = AppColors.ffFFFFFF);
    final tagRect = RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 3 * u, rect.top + 3 * u, tagW - 3 * u, h - 6 * u), Radius.circular((h - 6 * u) / 2));
    canvas.drawRRect(tagRect, Paint()..color = color);
    tagText.paint(canvas, Offset(tagRect.left + (tagRect.width - tagText.width) / 2, rect.center.dy - tagText.height / 2));
    name.paint(canvas, Offset(rect.left + tagW + pad * 0.6, rect.center.dy - name.height / 2));
    return rect;
  }

  /// Ghim hình giọt nước, mũi nhọn chạm đúng vị trí thành phố.
  void _pin(Canvas canvas, Offset s, Color color, {required bool home}) {
    final u = unit;
    final r = 11 * u;
    final head = s.translate(0, -21 * u);
    final path = Path()
      ..moveTo(s.dx, s.dy)
      ..quadraticBezierTo(s.dx - r * 0.55, head.dy + r * 0.9, head.dx - r, head.dy)
      ..arcTo(Rect.fromCircle(center: head, radius: r), pi, pi, false)
      ..quadraticBezierTo(s.dx + r * 0.55, head.dy + r * 0.9, s.dx, s.dy)
      ..close();
    canvas.drawOval(Rect.fromCenter(center: s, width: 12 * u, height: 4.5 * u), Paint()..color = const Color(0x55000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * u));
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ffFFFFFF
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * u,
    );
    final white = Paint()..color = AppColors.ffFFFFFF;
    if (!home) {
      canvas.drawCircle(head, 4.2 * u, white);
      return;
    }
    // Ngôi nhà nhỏ: mái tam giác + thân nhà.
    final roof = Path()
      ..moveTo(head.dx - 6.5 * u, head.dy - 0.5 * u)
      ..lineTo(head.dx, head.dy - 6.5 * u)
      ..lineTo(head.dx + 6.5 * u, head.dy - 0.5 * u)
      ..close();
    canvas.drawPath(roof, white);
    canvas.drawRect(Rect.fromLTRB(head.dx - 4.5 * u, head.dy - 1 * u, head.dx + 4.5 * u, head.dy + 5 * u), white);
    canvas.drawRect(Rect.fromLTRB(head.dx - 1.4 * u, head.dy + 1.2 * u, head.dx + 1.4 * u, head.dy + 5 * u), Paint()..color = color);
  }

  void _stopBadge(Canvas canvas, Offset s, int number) {
    final u = unit;
    final r = 7.5 * u;
    canvas.drawCircle(s.translate(0, 1 * u), r + 1 * u, Paint()..color = const Color(0x55000000));
    canvas.drawCircle(s, r, Paint()..color = MapColors.stop);
    canvas.drawCircle(
      s,
      r,
      Paint()
        ..color = MapColors.label
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * u,
    );
    final label = text.plain('$number', fontSize: 9.5 * u, weight: FontWeight.w800, color: MapColors.label);
    label.paint(canvas, s - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(covariant TripMapPainter old) =>
      old.fromId != fromId ||
      old.toId != toId ||
      old.route != route ||
      old.unit != unit ||
      old.dpr != dpr ||
      old.places != places;
}

/// Giữ sẵn các TextPainter đã dàn chữ (vẽ lại bản đồ mỗi khung hình mà không
/// phải dàn chữ lại).
class MapTextCache {
  final _cache = <String, TextPainter>{};

  TextPainter plain(
    String value, {
    required double fontSize,
    required FontWeight weight,
    required Color color,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
  }) {
    final key = 'p|$value|$fontSize|${weight.value}|${color.toARGB32()}|$letterSpacing|${style.index}';
    return _cache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: fontSize,
            fontWeight: weight,
            color: color,
            letterSpacing: letterSpacing,
            fontStyle: style,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  /// (chữ, viền sáng phía sau) — vẽ viền trước rồi tới chữ.
  (TextPainter, TextPainter) halo(
    String value, {
    required double fontSize,
    required FontWeight weight,
    required Color color,
    required Color halo,
    required double haloWidth,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
  }) {
    final fill = plain(value, fontSize: fontSize, weight: weight, color: color, letterSpacing: letterSpacing, style: style);
    final key = 'h|$value|$fontSize|${weight.value}|${halo.toARGB32()}|$haloWidth|$letterSpacing|${style.index}';
    final outline = _cache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: fontSize,
            fontWeight: weight,
            letterSpacing: letterSpacing,
            fontStyle: style,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = haloWidth
              ..strokeJoin = StrokeJoin.round
              ..color = halo,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    return (fill, outline);
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

/// Xe nhỏ chạy dọc lộ trình (lớp riêng, vẽ lại theo hoạt ảnh).
class RouteVehiclePainter extends CustomPainter {
  RouteVehiclePainter({
    required this.camera,
    required this.route,
    required this.progress,
    required this.image,
    required this.length,
  }) : super(repaint: Listenable.merge([camera, progress]));

  final MapCamera camera;
  final RouteGeometry? route;
  final Animation<double> progress;
  final ui.Image? image;

  /// Chiều dài hình xe trên màn hình (điểm ảnh).
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final r = route;
    final img = image;
    if (r == null || img == null) return;
    final (pos, heading) = r.at(progress.value);
    final s = camera.toScreen(pos);
    final w = length * img.width / img.height;
    canvas.save();
    canvas.translate(s.dx, s.dy);
    canvas.rotate(heading + pi / 2); // hình xe gốc quay đầu lên trên
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: length),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RouteVehiclePainter old) =>
      old.route != route || old.image != image || old.length != length;
}
