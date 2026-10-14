import 'dart:math';

import '../game/game_config.dart';
import '../game/vehicle_spec.dart';
import '../model/place.dart';
import '../model/trip.dart';
import '../resource/vn_route_data.dart';

/// Tìm lộ trình trên mạng lưới điểm/đoạn nối của [VnRouteData] và chia thành
/// các chặng chơi.
class RouteService {
  RouteService({List<Place>? places, List<RoadLink>? links})
      : places = places ?? VnRouteData.places,
        links = links ?? VnRouteData.links;

  static final RouteService shared = RouteService();

  final List<Place> places;
  final List<RoadLink> links;

  late final Map<String, Place> _byId = {for (final p in places) p.id: p};
  late final Map<String, List<RoadLink>> _adjacent = () {
    final map = <String, List<RoadLink>>{};
    for (final l in links) {
      map.putIfAbsent(l.a, () => []).add(l);
      map.putIfAbsent(l.b, () => []).add(l);
    }
    return map;
  }();

  Place place(String id) => _byId[id]!;

  /// Giờ lái thực tế của một đoạn nối với loại xe đã chọn.
  double linkHours(RoadLink link, VehicleKind vehicle) => switch (vehicle) {
        VehicleKind.car => link.carHours,
        VehicleKind.bus => link.carHours * GameConfig.busHoursFactor,
        VehicleKind.motorbike => link.km / GameConfig.motorbikeRealKmh,
      };

  /// Lộ trình nhanh nhất, null nếu không có đường (hoặc trùng điểm).
  TripPlan? plan(String fromId, String toId, VehicleKind vehicle) {
    if (fromId == toId || !_byId.containsKey(fromId) || !_byId.containsKey(toId)) return null;
    final path = _shortestPath(fromId, toId, vehicle);
    if (path == null) return null;

    final hops = <RoadLink>[];
    for (var i = 0; i + 1 < path.length; i++) {
      hops.add(_adjacent[path[i]]!.firstWhere((l) => l.other(path[i]) == path[i + 1]));
    }
    final stages = _stages(path, hops, vehicle);
    final km = hops.fold<double>(0, (sum, l) => sum + l.km);
    final expresswayKm =
        vehicle.fourWheels ? hops.fold<double>(0, (sum, l) => sum + l.expresswayKm) : 0.0;
    return TripPlan(
      vehicle: vehicle,
      placeIds: path,
      stages: stages,
      km: km,
      expresswayKm: expresswayKm,
      realHours: hops.fold<double>(0, (sum, l) => sum + linkHours(l, vehicle)),
      tollBooths: stages.fold(0, (sum, s) => sum + s.tollBooths),
    );
  }

  List<String>? _shortestPath(String from, String to, VehicleKind vehicle) {
    final dist = <String, double>{from: 0};
    final prev = <String, String>{};
    final open = <String>{from};
    final done = <String>{};
    while (open.isNotEmpty) {
      final u = open.reduce((a, b) => dist[a]! <= dist[b]! ? a : b);
      open.remove(u);
      if (u == to) break;
      done.add(u);
      for (final link in _adjacent[u] ?? const <RoadLink>[]) {
        final v = link.other(u);
        if (done.contains(v)) continue;
        final alt = dist[u]! + linkHours(link, vehicle);
        if (alt < (dist[v] ?? double.infinity)) {
          dist[v] = alt;
          prev[v] = u;
          open.add(v);
        }
      }
    }
    if (!dist.containsKey(to)) return null;
    final path = <String>[to];
    while (path.last != from) {
      path.add(prev[path.last]!);
    }
    return path.reversed.toList();
  }

  /// Chia lộ trình thành các chặng 60–110 km. Đoạn nối dài bị cắt thành
  /// nhiều khúc; khúc ngắn được gộp tới khi đủ dài.
  List<TripStage> _stages(List<String> path, List<RoadLink> hops, VehicleKind vehicle) {
    // Khúc = một phần của đoạn nối, nhớ xem đầu/cuối khúc có phải thành phố.
    final pieces = <_Piece>[];
    for (var i = 0; i < hops.length; i++) {
      final link = hops[i];
      final parts = max(1, (link.km / GameConfig.stageMaxKm).ceil());
      final ctShare = vehicle.fourWheels ? link.expresswayKm / link.km : 0.0;
      for (var p = 0; p < parts; p++) {
        pieces.add(_Piece(
          km: link.km / parts,
          expresswayShare: ctShare,
          startsAtCity: p == 0,
          endsAtCity: p == parts - 1,
          startName: p == 0 ? place(path[i]).name : 'Trạm nghỉ trên đường tới ${place(path[i + 1]).name}',
          endName: p == parts - 1 ? place(path[i + 1]).name : 'Trạm nghỉ trên đường tới ${place(path[i + 1]).name}',
        ));
      }
    }

    final stages = <TripStage>[];
    var group = <_Piece>[];
    double groupKm() => group.fold(0, (sum, p) => sum + p.km);
    for (var i = 0; i < pieces.length; i++) {
      group.add(pieces[i]);
      final remaining = pieces.skip(i + 1).fold<double>(0, (sum, p) => sum + p.km);
      final next = i + 1 < pieces.length ? pieces[i + 1].km : 0.0;
      // Đóng chặng khi đã đủ dài, hoặc thêm khúc sau thì quá dài; khúc còn
      // lại ngắn quá thì gộp nốt vào chặng cuối.
      final longEnough = groupKm() >= GameConfig.stageMinKm;
      final wouldOverflow = groupKm() + next > GameConfig.stageMaxKm;
      final tailTooShort = remaining > 0 && remaining < GameConfig.stageMinKm / 2;
      if (i == pieces.length - 1 || ((longEnough || wouldOverflow) && !tailTooShort)) {
        stages.add(_toStage(group));
        group = [];
      }
    }
    return stages;
  }

  TripStage _toStage(List<_Piece> pieces) {
    final sections = <StageSection>[];
    void add(RoadKind kind, double km) {
      if (km <= 0.05) return;
      if (sections.isNotEmpty && sections.last.kind == kind) {
        sections[sections.length - 1] = StageSection(kind, sections.last.km + km);
      } else {
        sections.add(StageSection(kind, km));
      }
    }

    for (final p in pieces) {
      // Đầu/cuối khúc là thành phố thì có một đoạn đường phố (tối đa 1/4 khúc).
      final cityKm = min(GameConfig.cityKmPerSide, p.km / 4);
      final startCity = p.startsAtCity ? cityKm : 0.0;
      final endCity = p.endsAtCity ? cityKm : 0.0;
      final inner = p.km - startCity - endCity;
      add(RoadKind.city, startCity);
      final ct = inner * p.expresswayShare;
      final hw = inner - ct;
      add(RoadKind.highway, hw / 2);
      add(RoadKind.expressway, ct);
      add(RoadKind.highway, hw / 2);
      add(RoadKind.city, endCity);
    }

    double kmOf(RoadKind kind) => sections.where((s) => s.kind == kind).fold(0, (sum, s) => sum + s.km);
    final tolls = (kmOf(RoadKind.expressway) / GameConfig.expresswayKmPerToll +
            kmOf(RoadKind.highway) / GameConfig.highwayKmPerToll)
        .round();
    return TripStage(
      fromName: pieces.first.startName,
      toName: pieces.last.endName,
      sections: sections,
      tollBooths: tolls,
    );
  }

  /// Thời gian chơi ước tính (giây) của một chặng.
  static double stagePlaySeconds(TripStage stage) {
    var seconds = 0.0;
    for (final s in stage.sections) {
      final pace = switch (s.kind) {
        RoadKind.city => GameConfig.cityPaceFactor,
        RoadKind.highway => 1.0,
        RoadKind.expressway => GameConfig.expresswayPaceFactor,
      };
      seconds += s.km * GameConfig.playSecondsPerKm * pace;
    }
    return seconds;
  }

  static double planPlaySeconds(TripPlan plan) =>
      plan.stages.fold(0, (sum, s) => sum + stagePlaySeconds(s));
}

class _Piece {
  _Piece({
    required this.km,
    required this.expresswayShare,
    required this.startsAtCity,
    required this.endsAtCity,
    required this.startName,
    required this.endName,
  });

  final double km;
  final double expresswayShare;
  final bool startsAtCity;
  final bool endsAtCity;
  final String startName;
  final String endName;
}
