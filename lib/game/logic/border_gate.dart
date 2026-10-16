import '../../model/trip.dart';
import '../../service/route_service.dart';
import '../vehicle_spec.dart';
import 'provinces.dart';
import 'road_layout.dart';

/// Chỗ chặng đi qua ranh giới hai tỉnh: giữa hai điểm kề nhau trên lộ trình
/// thuộc hai tỉnh khác nhau.
class BorderCrossing {
  const BorderCrossing({
    required this.from,
    required this.to,
    required this.stretch,
    required this.stretches,
    required this.fraction,
  });

  /// Tỉnh rời đi và tỉnh đi vào.
  final String from;
  final String to;

  /// Ranh giới nằm ở khúc ngoài phố thứ mấy của chặng (đếm từ đầu chặng), trên
  /// tổng số [stretches] khúc dự kiến (mỗi đoạn nối giữa hai điểm là một khúc,
  /// chặng bắt đầu từ trạm nghỉ thì có thêm khúc đầu).
  final int stretch;
  final int stretches;

  /// Vị trí dự phòng theo tỉ lệ chiều dài chặng (khi số khúc không khớp).
  final double fraction;

  /// Các ranh giới tỉnh trên chặng từ [fromName] tới [toName] (tên điểm hoặc
  /// "Trạm nghỉ trên đường tới …"). Chặng bắt đầu ở trạm nghỉ thì coi như đã
  /// ở tỉnh của điểm sắp tới (cổng chào nằm ở chặng trước).
  static List<BorderCrossing> forStage(String fromName, String toName, VehicleKind vehicle, {RouteService? routes}) {
    final r = routes ?? RouteService.shared;
    final a = Provinces.placeOf(fromName, r.places), b = Provinces.placeOf(toName, r.places);
    if (a == null || b == null || a.id == b.id) return const [];
    final fromStop = fromName != a.name;
    final ids = r.plan(a.id, b.id, vehicle)?.placeIds ?? [a.id, b.id];
    final hops = ids.length - 1;
    double km(String x, String y) {
      for (final l in r.links) {
        if ((l.a == x && l.b == y) || (l.a == y && l.b == x)) return l.km;
      }
      return 1;
    }

    final kms = [for (var i = 0; i < hops; i++) km(ids[i], ids[i + 1])];
    final total = kms.fold<double>(0, (s, k) => s + k);
    final out = <BorderCrossing>[];
    var cum = 0.0;
    for (var i = 0; i < hops; i++) {
      final pa = Provinces.of(r.place(ids[i])), pb = Provinces.of(r.place(ids[i + 1]));
      if (pa != pb) {
        out.add(BorderCrossing(
          from: pa,
          to: pb,
          stretch: i + (fromStop ? 1 : 0),
          stretches: hops + (fromStop ? 1 : 0),
          fraction: (cum + kms[i] * 0.5) / total,
        ));
      }
      cum += kms[i];
    }
    return out;
  }
}

/// Cổng chào tỉnh bắc ngang quốc lộ ở ranh giới hai tỉnh: mặt trước (chiều
/// về quê) "… KÍNH CHÀO QUÝ KHÁCH", mặt sau "HẸN GẶP LẠI QUÝ KHÁCH".
class BorderGate {
  const BorderGate({required this.s, required this.from, required this.to});

  /// Tim cổng (giữa hai trụ) theo quãng s.
  final double s;
  final String from;
  final String to;

  /// Đường giữ thẳng trước cổng (nhìn thấy cổng từ xa) và sau cổng.
  static const double keepBefore = 1300;
  static const double keepAfter = 350;

  /// Khoảng quanh cổng không đặt quán, ổ gà, cây cối (trụ cổng, chậu hoa).
  static const double reach = 140;

  bool near(double at, {double margin = 0}) => (at - s).abs() < reach + margin;

  bool within(double a, double b, {double margin = 0}) => s + keepAfter + margin > a && s - keepBefore - margin < b;
}

/// Đặt cổng chào cho các ranh giới [crossings]: giữa khúc ngoài phố ứng với
/// đoạn nối (lệch chút theo tên tỉnh), trên đoạn thẳng không vướng phố,
/// trạm thu phí, đầu và cuối chặng. Không tìm được chỗ thì bỏ qua.
List<BorderGate> placeBorderGates({
  required List<BorderCrossing> crossings,
  required List<RoadZone> zones,
  required List<TollPlaza> tolls,
  required double startS,
  required double endS,
}) {
  if (crossings.isEmpty || zones.isEmpty) return const [];
  // Các khúc ngoài phố liền nhau (quốc lộ, cao tốc) theo thứ tự.
  final open = <(double, double)>[];
  double? runStart;
  for (final z in zones) {
    if (z.kind != RoadKind.city) {
      runStart ??= z.startS;
    } else if (runStart != null) {
      open.add((runStart, z.startS));
      runStart = null;
    }
  }
  if (runStart != null) open.add((runStart, zones.last.endS));

  RoadKind kindAt(double s) {
    for (final z in zones) {
      if (s >= z.startS && s < z.endS) return z.kind;
    }
    return zones.last.kind;
  }

  final gates = <BorderGate>[];
  bool fits(double s) {
    if (s < startS + 2200 || s > endS - 1800) return false;
    // Cả quãng nhìn thấy cổng cùng một loại đường, không phải phố.
    final kind = kindAt(s);
    if (kind == RoadKind.city) return false;
    for (var x = s - BorderGate.keepBefore - 300; x <= s + 900; x += 100) {
      if (kindAt(x) != kind) return false;
    }
    for (final t in tolls) {
      if (s > t.plazaStart - 1600 && s < t.plazaEnd + 700) return false;
    }
    return !gates.any((g) => (g.s - s).abs() < 3000);
  }

  for (final c in crossings) {
    final range = c.stretches == open.length && c.stretch >= 0 && c.stretch < open.length ? open[c.stretch] : null;
    // Lệch khỏi chính giữa theo tên tỉnh (cố định cho từng cặp tỉnh).
    final jitter = ((c.from.hashCode ^ (c.to.hashCode * 31)) & 0xff) / 255;
    final lo = range?.$1 ?? startS, hi = range?.$2 ?? endS;
    final target = range != null ? lo + (hi - lo) * (0.42 + 0.18 * jitter) : startS + (endS - startS) * c.fraction;
    double? at;
    for (var k = 0; k < 120 && at == null; k++) {
      for (final sign in const [1, -1]) {
        final s = target + sign * k * 150;
        if (s >= lo && s <= hi && fits(s)) {
          at = s;
          break;
        }
      }
    }
    if (at != null) gates.add(BorderGate(s: at, from: c.from, to: c.to));
  }
  gates.sort((a, b) => a.s.compareTo(b.s));
  return gates;
}
