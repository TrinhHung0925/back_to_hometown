import 'dart:math';

import '../../model/trip.dart';
import '../game_config.dart';
import 'border_gate.dart';
import 'road_path.dart';
import 'roadside.dart';

/// Một đoạn liên tục cùng loại đường, tính theo quãng s của chặng.
class RoadZone {
  const RoadZone(this.kind, this.startS, this.endS);

  final RoadKind kind;
  final double startS;
  final double endS;

  bool contains(double s) => s >= startS && s < endS;
}

enum LightColor { green, yellow, red }

/// Ngã tư có đèn giao thông. Thời gian tính bằng giây chơi kể từ lúc vào chặng.
class TrafficLight {
  const TrafficLight({required this.s, required this.offset, this.noUTurn = false});

  /// Tim đường cắt ngang.
  final double s;

  /// Lệch pha của chu kỳ đèn (giây).
  final double offset;

  /// Có biển cấm quay đầu (camera phạt nguội ghi hình).
  final bool noUTurn;

  static const double green = GameConfig.lightGreenSeconds;
  static const double yellow = GameConfig.lightYellowSeconds;
  static const double red = GameConfig.lightRedSeconds;
  static const double cycle = green + yellow + red;

  /// Giây đã trôi trong chu kỳ tại thời điểm [t].
  double _phase(double t) => (t + offset) % cycle;

  /// Đèn cho xe chạy dọc đường (cả chiều mình lẫn chiều ngược lại).
  LightColor colorAt(double t) {
    final p = _phase(t);
    if (p < green) return LightColor.green;
    if (p < green + yellow) return LightColor.yellow;
    return LightColor.red;
  }

  /// Số giây còn lại của màu đang sáng (để hiện đếm ngược như đèn thật).
  double remainingAt(double t) {
    final p = _phase(t);
    if (p < green) return green - p;
    if (p < green + yellow) return green + yellow - p;
    return cycle - p;
  }

  /// Đèn cho đường cắt ngang: xanh khi chiều dọc đỏ, chừa 1 giây "đỏ cả hai"
  /// ở đầu và cuối để xe trong ngã tư kịp đi hết.
  bool crossGreenAt(double t) {
    final p = _phase(t);
    return p > green + yellow + GameConfig.lightAllRedSeconds && p < cycle - GameConfig.lightAllRedSeconds;
  }

  double get halfWidth => GameConfig.crossRoadWidth / 2;

  /// Vạch dừng của chiều mình (xe dừng trước vạch này, tính theo đầu xe).
  double get stopLine => s - halfWidth - GameConfig.stopLineGap;

  /// Vạch dừng của chiều ngược lại.
  double get oncomingStopLine => s + halfWidth + GameConfig.stopLineGap;
}

/// Trạm thu phí. [s] là chỗ đặt barrier của chiều mình.
class TollPlaza {
  const TollPlaza(this.s);

  final double s;

  /// Đoạn mặt đường mở rộng (thêm làn xe máy sát lề).
  double get plazaStart => s - GameConfig.tollPlazaBefore;
  double get plazaEnd => s + GameConfig.tollPlazaAfter;

  /// Đảo phân làn: bắt đầu (mũi đảo) và kết thúc theo s.
  double get islandStart => s - GameConfig.tollIslandBefore;
  double get islandEnd => s + GameConfig.tollIslandAfter;

  bool contains(double s) => s >= plazaStart && s <= plazaEnd;

  /// Lệch ngang tối đa của xe ở quãng [at] (vào trạm thì được ra làn xe máy,
  /// qua trạm thì mép đường thu hẹp dần về như cũ).
  double maxEdge(double at) {
    const wide = GameConfig.tollMotoLaneOuter;
    const normal = GameConfig.roadHalfWidth;
    final widenEnd = plazaStart + GameConfig.tollTaper;
    final narrowStart = plazaEnd - GameConfig.tollTaper;
    if (at < plazaStart || at > plazaEnd) return normal;
    if (at < widenEnd) return normal + (wide - normal) * (at - plazaStart) / GameConfig.tollTaper;
    if (at > narrowStart) return wide - (wide - normal) * (at - narrowStart) / GameConfig.tollTaper;
    return wide;
  }
}

/// Chốt CSGT ven quốc lộ: lều, bàn, súng bắn tốc độ, cọc tiêu. Phía trước có
/// biển hạn chế tốc độ; quanh chốt cấm quay đầu.
class Checkpoint {
  const Checkpoint({required this.s, required this.limitKmh, required this.seed});

  /// Chỗ dựng lều (bên phải chiều về quê).
  final double s;
  final int limitKmh;
  final int seed;

  /// Biển hạn chế tốc độ (mỗi chiều một biển, đặt trước chốt).
  double get signS => s - GameConfig.speedSignAhead;
  double get oncomingSignS => s + GameConfig.speedSignAhead;

  /// Chỗ đứng bắn tốc độ theo chiều đi [dir].
  double radarS(int dir) => s - dir * GameConfig.radarAhead;

  bool inNoUTurnZone(double at) => (at - s).abs() < GameConfig.noUTurnReach;
}

/// Điểm đón khách (chế độ xe khách): nhà chờ ở lề phải, vài người đứng đợi.
class BusStop {
  BusStop({required this.s, required this.passengers, required this.seed});

  final double s;
  final int passengers;
  final int seed;

  /// Đã đón khách / đã chạy qua mà không dừng.
  bool served = false;
  bool missed = false;
}

/// Bố cục một chặng: các đoạn phố / quốc lộ / cao tốc nối nhau, ngã tư có
/// đèn ở đoạn phố, trạm thu phí ở quốc lộ và cao tốc.
class RoadLayout {
  RoadLayout._(
    this.zones,
    this.lights,
    this.tolls,
    this.startS,
    this.endS, {
    this.busStops = const [],
    this.stalls = const [],
    this.checkpoints = const [],
    this.nails = const [],
    this.gates = const [],
  });

  factory RoadLayout.build({
    required List<StageSection> sections,
    required double startS,
    required int tollBooths,
    required Random random,
    bool withBusStops = false,
    double checkpointFactor = 1,
    List<BorderCrossing> borders = const [],
  }) {
    final zones = <RoadZone>[];
    var s = startS;
    for (final section in sections) {
      final length = section.km * GameConfig.unitsPerKm;
      if (length <= 0) continue;
      if (zones.isNotEmpty && zones.last.kind == section.kind) {
        final last = zones.removeLast();
        zones.add(RoadZone(section.kind, last.startS, s + length));
      } else {
        zones.add(RoadZone(section.kind, s, s + length));
      }
      s += length;
    }
    if (zones.isEmpty) zones.add(RoadZone(RoadKind.highway, startS, startS + GameConfig.unitsPerKm));
    final endS = zones.last.endS;

    // Ngã tư: rải đều trong đoạn phố, chừa đầu và cuối đoạn.
    final lights = <TrafficLight>[];
    for (final zone in zones.where((z) => z.kind == RoadKind.city)) {
      var at = max(zone.startS, startS + GameConfig.firstLightAfterStart) + GameConfig.lightZoneMargin;
      while (at < zone.endS - GameConfig.lightZoneMargin) {
        lights.add(TrafficLight(
          s: at,
          offset: random.nextDouble() * TrafficLight.cycle,
          noUTurn: random.nextDouble() < GameConfig.noUTurnJunctionChance,
        ));
        at += GameConfig.lightSpacingMin + random.nextDouble() * (GameConfig.lightSpacingMax - GameConfig.lightSpacingMin);
      }
    }

    // Trạm thu phí: chia đều theo tổng chiều dài quốc lộ + cao tốc.
    final tolls = <TollPlaza>[];
    final open = zones.where((z) => z.kind != RoadKind.city).toList();
    final openLength = open.fold<double>(0, (a, z) => a + z.endS - z.startS);
    if (tollBooths > 0 && openLength > 0) {
      for (var i = 0; i < tollBooths; i++) {
        var target = openLength * (i + 0.5) / tollBooths;
        for (final zone in open) {
          final length = zone.endS - zone.startS;
          if (target <= length) {
            final margin = min(GameConfig.tollZoneMargin, length / 2);
            tolls.add(TollPlaza((zone.startS + target).clamp(zone.startS + margin, zone.endS - margin)));
            break;
          }
          target -= length;
        }
      }
    }
    // Cổng chào ở ranh giới tỉnh (đoạn thẳng, không vướng phố, trạm thu phí).
    final gates = placeBorderGates(crossings: borders, zones: zones, tolls: tolls, startS: startS, endS: endS);
    // Chốt CSGT: giữa các đoạn quốc lộ đủ dài, tránh trạm thu phí.
    final checkpoints = <Checkpoint>[];
    final plain = RoadLayout._(zones, lights, tolls, startS, endS, gates: gates);
    for (final zone in zones.where((z) => z.kind == RoadKind.highway)) {
      final km = (zone.endS - zone.startS) / GameConfig.unitsPerKm;
      final count = (km * checkpointFactor / GameConfig.checkpointEveryKm + random.nextDouble() * 0.6).floor();
      for (var i = 0; i < count; i++) {
        var at = zone.startS + (zone.endS - zone.startS) * (i + 0.3 + random.nextDouble() * 0.4) / count;
        while (plain.nearFeature(at, margin: GameConfig.speedSignAhead + 200) && at < zone.endS - 1500) {
          at += 300;
        }
        if (at < startS + 3000 || at > zone.endS - 1500 || at > endS - 2000) continue;
        checkpoints.add(Checkpoint(s: at, limitKmh: random.nextBool() ? 60 : 50, seed: random.nextInt(1 << 20)));
      }
    }
    final layout = RoadLayout._(zones, lights, tolls, startS, endS, checkpoints: checkpoints, gates: gates);

    // Điểm đón khách: rải đều trên phố và quốc lộ (cao tốc không đón khách),
    // tránh ngã tư và trạm thu phí.
    final stops = <BusStop>[];
    final eligible = withBusStops ? zones.where((z) => z.kind != RoadKind.expressway).toList() : <RoadZone>[];
    final total = eligible.fold<double>(0, (a, z) => a + z.endS - z.startS);
    final count = (total / GameConfig.unitsPerKm / GameConfig.busStopEveryKm).round().clamp(2, 6);
    for (var i = 0; i < count && total > 0; i++) {
      var target = total * (i + 0.5) / count;
      for (final zone in eligible) {
        final length = zone.endS - zone.startS;
        if (target > length) {
          target -= length;
          continue;
        }
        var at = max(zone.startS + target, startS + GameConfig.firstBusStopAfterStart);
        while (layout.nearFeature(at, margin: 260) && at < zone.endS - 300) {
          at += 200;
        }
        if (at < zone.endS - 300 && at < endS - 800) {
          stops.add(BusStop(s: at, passengers: 2 + random.nextInt(5), seed: random.nextInt(1 << 20)));
        }
        break;
      }
    }
    // Quán ven đường, cây xăng, bãi đinh: tránh ngã tư, trạm thu phí, chốt
    // CSGT, điểm đón khách.
    final roadside = placeRoadside(
      zones: [for (final z in zones) (kind: z.kind, startS: z.startS, endS: z.endS)],
      startS: startS,
      endS: endS,
      // Quán không chắn biển báo của chốt CSGT (biển tốc độ, cấm quay đầu).
      blocked: (s) =>
          layout.nearFeature(s, margin: 260) ||
          stops.any((b) => (b.s - s).abs() < 320) ||
          checkpoints.any((c) => (c.s - s).abs() < GameConfig.speedSignAhead + 140),
      random: Random(random.nextInt(1 << 30)),
    );
    return RoadLayout._(
      zones,
      lights,
      tolls,
      startS,
      endS,
      busStops: stops,
      stalls: roadside.stalls,
      checkpoints: checkpoints,
      nails: roadside.nails,
      gates: gates,
    );
  }

  final List<RoadZone> zones;
  final List<TrafficLight> lights;
  final List<TollPlaza> tolls;
  final List<BusStop> busStops;
  final List<Stall> stalls;
  final List<Checkpoint> checkpoints;
  final List<NailPatch> nails;

  /// Cổng chào tỉnh (theo s tăng dần).
  final List<BorderGate> gates;
  final double startS;
  final double endS;

  RoadZone zoneAt(double s) {
    if (s < zones.first.startS) return zones.first;
    for (final z in zones) {
      if (z.contains(s)) return z;
    }
    return zones.last;
  }

  RoadKind kindAt(double s) => zoneAt(s).kind;

  /// Cao tốc có dải phân cách cứng ở giữa (không lấn sang chiều ngược được).
  /// Dải bắt đầu/kết thúc hơi lùi vào trong đoạn để xe kịp về làn.
  bool hasMedian(double s) {
    final z = zoneAt(s);
    return z.kind == RoadKind.expressway &&
        s > z.startS + GameConfig.medianInset &&
        s < z.endS - GameConfig.medianInset;
  }

  Iterable<TrafficLight> lightsBetween(double a, double b) => lights.where((l) => l.s >= a && l.s <= b);

  Iterable<Stall> stallsBetween(double a, double b) => stalls.where((t) => t.s >= a && t.s <= b);

  /// Quãng [s] phía [side] có vướng khu quán nào (hoặc chốt CSGT) không,
  /// để cảnh vật né ra.
  bool nearStall(double s, int side, {double margin = 0}) =>
      stalls.any((t) => t.side == side && (t.s - s).abs() < t.halfLength + margin) ||
      (side > 0 && checkpoints.any((c) => (c.s - s).abs() < 120 + margin));

  Iterable<NailPatch> nailsBetween(double a, double b) => nails.where((n) => n.s >= a && n.s <= b);

  Iterable<Checkpoint> checkpointsBetween(double a, double b) =>
      checkpoints.where((c) => c.s + GameConfig.speedSignAhead >= a && c.s - GameConfig.speedSignAhead <= b);

  /// Chốt CSGT có vùng cấm quay đầu chứa [s] (null nếu không có).
  Checkpoint? checkpointNear(double s) {
    for (final c in checkpoints) {
      if (c.inNoUTurnZone(s)) return c;
    }
    return null;
  }

  Iterable<TollPlaza> tollsBetween(double a, double b) => tolls.where((t) => t.plazaEnd >= a && t.plazaStart <= b);

  TollPlaza? tollAt(double s) {
    for (final t in tolls) {
      if (t.contains(s)) return t;
    }
    return null;
  }

  /// Quãng [s] có nằm gần ngã tư hoặc trạm thu phí không (để giữ đường thẳng,
  /// không đặt ổ gà, lì xì, xe đỗ…).
  bool nearFeature(double s, {double margin = 0}) {
    for (final l in lights) {
      if ((l.s - s).abs() < GameConfig.crossRoadWidth / 2 + GameConfig.stopLineGap + 60 + margin) return true;
    }
    for (final t in tolls) {
      if (s > t.plazaStart - margin && s < t.plazaEnd + margin) return true;
    }
    for (final c in checkpoints) {
      if ((c.s - s).abs() < 220 + margin) return true;
    }
    for (final g in gates) {
      if (g.near(s, margin: margin)) return true;
    }
    return false;
  }

  /// Khoảng [a]..[b] có chạm vào vùng ngã tư / trạm thu phí (nới thêm
  /// [margin]) không — dùng để giữ đường thẳng ở các chỗ này.
  bool featureWithin(double a, double b, {double margin = 0}) {
    const lightReach = GameConfig.crossRoadWidth / 2 + GameConfig.stopLineGap + 80;
    for (final l in lights) {
      if (l.s + lightReach + margin > a && l.s - lightReach - margin < b) return true;
    }
    for (final t in tolls) {
      if (t.plazaEnd + margin > a && t.plazaStart - margin < b) return true;
    }
    // Chốt CSGT đứng ở đoạn thẳng, nhìn thấy từ xa.
    for (final c in checkpoints) {
      if (c.s + 400 + margin > a && c.s - 600 - margin < b) return true;
    }
    // Cổng chào tỉnh nhìn thấy từ xa trên đoạn thẳng.
    for (final g in gates) {
      if (g.within(a, b, margin: margin)) return true;
    }
    return false;
  }

  /// Kiểu uốn của đường ở quãng [s]: quốc lộ cua nhiều, phố và cao tốc cua
  /// rộng. Nhìn trước một đoạn để đường kịp nắn lại trước khi vào phố.
  CurveStyle curveStyleAt(double s) => _kindStyle(kindAt(s)).stricter(_kindStyle(kindAt(s + _lookAhead)));

  static const double _lookAhead = 3000;

  static CurveStyle _kindStyle(RoadKind kind) => switch (kind) {
        RoadKind.city => CurveStyle.city,
        RoadKind.expressway => CurveStyle.expressway,
        RoadKind.highway => CurveStyle.highway,
      };
}
