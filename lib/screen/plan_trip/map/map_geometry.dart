import 'dart:math';
import 'dart:ui';

import '../../../model/place.dart';
import '../../../model/trip.dart';
import '../../../resource/vn_map_shapes.dart';
import '../../../resource/vn_map_tiles.dart';
import '../../../resource/vn_route_data.dart';

/// Phép chiếu của bản đồ (giống tool/route_data/map_common.py):
/// x = (kinh độ - 88) · cos 15°, y = 32 - vĩ độ. 1 đơn vị ≈ 1 độ vĩ.
abstract class MapProjection {
  static final double _k = cos(15 * pi / 180);

  static Offset fromLonLat(double lon, double lat) => Offset((lon - 88) * _k, 32 - lat);

  /// Vùng có ảnh nền (mức xa nhất) — camera không được ra ngoài vùng này.
  static Rect get world {
    final ppu = VnMapTiles.levelPpu.first;
    final size = VnMapTiles.tileSize / ppu;
    final keys = VnMapTiles.tiles.first;
    final xs = keys.map((k) => k ~/ 1000);
    final ys = keys.map((k) => k % 1000);
    return Rect.fromLTRB(xs.reduce(min) * size, ys.reduce(min) * size, (xs.reduce(max) + 1) * size,
        (ys.reduce(max) + 1) * size);
  }

  /// Khung Việt Nam đất liền (để vừa màn hình lúc mở bản đồ).
  static Rect get vietnam => Rect.fromPoints(fromLonLat(102.1, 23.45), fromLonLat(109.6, 8.35));
}

/// Các nét vẽ cố định của bản đồ, dựng thành Path một lần.
class MapShapes {
  MapShapes._();

  static final MapShapes shared = MapShapes._();

  late final Path coast = _lines(VnMapShapes.vietnamCoast);
  late final Path border = _lines(VnMapShapes.vietnamBorder);
  late final Path otherBorders = _lines(VnMapShapes.otherBorders);
  late final Path majorRivers = _lines(VnMapShapes.majorRivers);
  late final Path rivers = _lines(VnMapShapes.rivers);
  late final Path expressways = _lines(VnMapShapes.expressways);
  late final Path highways = _lines(VnMapShapes.linkPaths);
  late final Path islands = _lines(VnMapShapes.islands, close: true);

  /// Tâm các đảo nhỏ — vẽ thêm chấm để vẫn thấy được khi thu nhỏ bản đồ.
  late final List<Offset> islandDots = [
    for (final ring in VnMapShapes.islands) _centroid(ring),
  ];

  static Path _lines(List<List<double>> items, {bool close = false}) {
    final path = Path();
    for (final pts in items) {
      path.moveTo(pts[0], pts[1]);
      for (var i = 2; i < pts.length; i += 2) {
        path.lineTo(pts[i], pts[i + 1]);
      }
      if (close) path.close();
    }
    return path;
  }

  static Offset _centroid(List<double> pts) {
    var x = 0.0, y = 0.0;
    final n = pts.length ~/ 2;
    for (var i = 0; i < pts.length; i += 2) {
      x += pts[i];
      y += pts[i + 1];
    }
    return Offset(x / n, y / n);
  }
}

/// Hình dạng lộ trình đang chọn: đường bám theo quốc lộ/cao tốc thật, vị trí
/// các trạm dừng giữa các chặng.
class RouteGeometry {
  RouteGeometry._(this.points, this._lengths, this.stops);

  /// Các điểm của đường đi theo toạ độ bản đồ.
  final List<Offset> points;

  /// Quãng đường tích luỹ (đơn vị bản đồ) tới từng điểm.
  final List<double> _lengths;

  /// Trạm dừng nghỉ giữa các chặng (không tính điểm đầu, điểm cuối).
  final List<Offset> stops;

  double get length => _lengths.last;

  Rect get bounds {
    var r = Rect.fromLTRB(points.first.dx, points.first.dy, points.first.dx, points.first.dy);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromLTWH(p.dx, p.dy, 0, 0));
    }
    return r;
  }

  late final Path path = () {
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final q in points.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    return p;
  }();

  /// Vị trí và hướng (radian) tại tỉ lệ [t] (0..1) của đường đi.
  (Offset, double) at(double t) {
    final target = t.clamp(0.0, 1.0) * length;
    var lo = 0, hi = _lengths.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_lengths[mid] < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = points[lo], b = points[hi];
    final seg = _lengths[hi] - _lengths[lo];
    final f = seg == 0 ? 0.0 : (target - _lengths[lo]) / seg;
    return (Offset.lerp(a, b, f)!, atan2(b.dy - a.dy, b.dx - a.dx));
  }

  static RouteGeometry? of(TripPlan? plan) {
    if (plan == null || plan.placeIds.length < 2) return null;
    final links = VnRouteData.links;
    final points = <Offset>[];
    // km của từng đoạn nối + chiều dài hình vẽ của nó, để đặt trạm dừng theo km.
    final linkKm = <double>[];
    final linkStart = <int>[];
    for (var i = 0; i + 1 < plan.placeIds.length; i++) {
      final a = plan.placeIds[i], b = plan.placeIds[i + 1];
      final index = links.indexWhere((l) => (l.a == a && l.b == b) || (l.a == b && l.b == a));
      if (index < 0) return null;
      final raw = VnMapShapes.linkPaths[index];
      var pts = [for (var k = 0; k < raw.length; k += 2) Offset(raw[k], raw[k + 1])];
      if (links[index].a != a) pts = pts.reversed.toList();
      linkStart.add(points.length);
      points.addAll(points.isEmpty ? pts : pts.skip(1));
      linkKm.add(links[index].km);
    }
    final lengths = <double>[0];
    for (var i = 1; i < points.length; i++) {
      lengths.add(lengths.last + (points[i] - points[i - 1]).distance);
    }
    final geometry = RouteGeometry._(points, lengths, []);

    // Trạm dừng: theo km tích luỹ của các chặng, đổi ra vị trí trên hình vẽ.
    final totalKm = linkKm.fold<double>(0, (a, b) => a + b);
    final stageTotal = plan.stages.fold<double>(0, (a, s) => a + s.km);
    var cum = 0.0;
    for (final stage in plan.stages.take(plan.stages.length - 1)) {
      cum += stage.km;
      final km = cum / stageTotal * totalKm;
      var acc = 0.0;
      for (var l = 0; l < linkKm.length; l++) {
        if (km <= acc + linkKm[l] || l == linkKm.length - 1) {
          final f = ((km - acc) / linkKm[l]).clamp(0.0, 1.0);
          final startLen = lengths[linkStart[l]];
          final endLen = l + 1 < linkStart.length ? lengths[linkStart[l + 1]] : lengths.last;
          final t = (startLen + (endLen - startLen) * f) / geometry.length;
          geometry.stops.add(geometry.at(t).$1);
          break;
        }
        acc += linkKm[l];
      }
    }
    return geometry;
  }
}

/// Nhãn cố định trên bản đồ (biển, quần đảo, nước láng giềng).
class MapLabel {
  const MapLabel(this.text, this.lon, this.lat, this.kind, {this.sub});

  final String text;
  final String? sub;
  final double lon;
  final double lat;
  final MapLabelKind kind;

  Offset get position => MapProjection.fromLonLat(lon, lat);

  static const List<MapLabel> all = [
    MapLabel('Quần đảo Hoàng Sa', 112.0, 15.1, MapLabelKind.archipelago, sub: '(Việt Nam)'),
    MapLabel('Quần đảo Trường Sa', 113.9, 12.35, MapLabelKind.archipelago, sub: '(Việt Nam)'),
    MapLabel('Biển Đông', 115.2, 14.6, MapLabelKind.sea),
    MapLabel('Vịnh Bắc Bộ', 107.9, 19.55, MapLabelKind.bay),
    MapLabel('Vịnh Thái Lan', 102.6, 10.0, MapLabelKind.bay),
    MapLabel('TRUNG QUỐC', 106.6, 23.35, MapLabelKind.country),
    MapLabel('LÀO', 104.0, 19.3, MapLabelKind.country),
    MapLabel('CAMPUCHIA', 104.8, 12.9, MapLabelKind.country),
    MapLabel('THÁI LAN', 101.9, 15.6, MapLabelKind.country),
  ];
}

enum MapLabelKind { archipelago, sea, bay, country }

extension PlaceMapPosition on Place {
  Offset get position => Offset(x, y);
}
