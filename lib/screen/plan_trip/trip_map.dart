import 'dart:math';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../game/vehicle_spec.dart';
import '../../model/place.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import 'map/map_camera.dart';
import 'map/map_geometry.dart';
import 'map/map_tile_cache.dart';
import 'map/trip_map_painter.dart';

/// Bản đồ lên lộ trình: kéo, chụm hai ngón để phóng to, chạm đúp để phóng to
/// nhanh, chạm vào thành phố để chọn. Có lộ trình thì camera bay tới vừa khung
/// và một chiếc xe nhỏ chạy dọc đường đi.
class TripMap extends StatefulWidget {
  const TripMap({
    super.key,
    required this.places,
    required this.fromId,
    required this.toId,
    required this.plan,
    required this.vehicle,
    required this.onTapPlace,
    this.padding = EdgeInsets.zero,
  });

  final List<Place> places;
  final String? fromId;
  final String? toId;
  final TripPlan? plan;
  final VehicleKind vehicle;
  final ValueChanged<String> onTapPlace;

  /// Phần bản đồ bị các bảng khác che (camera căn giữa vùng còn lại).
  final EdgeInsets padding;

  /// Luôn hiện tên các thành phố lớn; điểm khác chỉ hiện khi phóng to.
  /// Thứ tự = ưu tiên khi hai nhãn tranh chỗ.
  static const Set<String> majorPlaces = {
    'ha_noi',
    'tp_hcm',
    'da_nang',
    'hue',
    'hai_phong',
    'can_tho',
    'nha_trang',
    'vinh',
    'thanh_hoa',
    'quy_nhon',
    'da_lat',
    'buon_ma_thuot',
    'lao_cai',
    'ca_mau',
  };

  @override
  State<TripMap> createState() => TripMapState();
}

class TripMapState extends State<TripMap> with TickerProviderStateMixin {
  final camera = MapCamera();
  final _tiles = MapTileCache();
  final _text = MapTextCache();
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
  late final AnimationController _fling = AnimationController.unbounded(vsync: this);
  late final AnimationController _drive = AnimationController(vsync: this);
  RouteGeometry? _route;

  // Gesture
  double _startScale = 1;
  Offset _startFocalMap = Offset.zero;
  Offset? _doubleTapAt;
  bool _pinched = false;

  // Bay camera
  Offset _flyFromCenter = Offset.zero, _flyToCenter = Offset.zero;
  double _flyFromScale = 1, _flyToScale = 1;

  // Trượt quán tính
  FrictionSimulation? _flingX, _flingY;

  @override
  void initState() {
    super.initState();
    _route = RouteGeometry.of(widget.plan);
    _fly.addListener(_onFly);
    _fling.addListener(_onFling);
    _restartDrive();
    if (_route != null) WidgetsBinding.instance.addPostFrameCallback((_) => _flyToRoute());
  }

  @override
  void didUpdateWidget(covariant TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.plan != widget.plan) {
      _route = RouteGeometry.of(widget.plan);
      _restartDrive();
      if (_route != null) {
        _flyToRoute();
      }
    }
    // Chọn điểm từ danh sách: bay tới điểm đó nếu đang nằm ngoài màn hình.
    final picked = widget.plan == null && old.fromId != widget.fromId ? widget.fromId : null;
    if (picked != null) {
      final place = widget.places.firstWhere((p) => p.id == picked);
      final s = camera.toScreen(place.position);
      if (!(camera.padding.deflateRect(Offset.zero & camera.viewport)).contains(s)) {
        _flyTo(place.position, max(camera.scale, 60));
      }
    }
  }

  @override
  void dispose() {
    _fly.dispose();
    _fling.dispose();
    _drive.dispose();
    _tiles.dispose();
    _text.dispose();
    camera.dispose();
    super.dispose();
  }

  void _restartDrive() {
    final plan = widget.plan;
    if (plan == null) {
      _drive.stop();
      return;
    }
    final seconds = (plan.km / 90).clamp(3.0, 12.0);
    _drive
      ..duration = Duration(milliseconds: (seconds * 1000).round())
      ..repeat();
  }

  // ------------------------------------------------------------ Camera
  void _flyToRoute() {
    final r = _route;
    if (r == null) return;
    final fit = camera.fit(r.bounds, margin: 56.h);
    _flyTo(fit.$1, min(fit.$2, 260));
  }

  void _flyTo(Offset center, double scale) {
    _fling.stop();
    _flyFromCenter = camera.center;
    _flyFromScale = camera.scale;
    _flyToCenter = center;
    _flyToScale = scale;
    _fly.forward(from: 0);
  }

  void _onFly() {
    final t = Curves.easeInOutCubic.transform(_fly.value);
    // Nội suy tỉ lệ theo log cho cảm giác bay đều; hơi lùi ra giữa chừng khi
    // đi xa (như bản đồ thật).
    final dist = (_flyToCenter - _flyFromCenter).distance * min(_flyFromScale, _flyToScale);
    final bump = (dist / 900).clamp(0.0, 0.6) * sin(pi * t);
    final logScale = log(_flyFromScale) + (log(_flyToScale) - log(_flyFromScale)) * t - bump;
    camera.moveTo(Offset.lerp(_flyFromCenter, _flyToCenter, t)!, exp(logScale));
  }

  void _onFling() {
    final x = _flingX, y = _flingY;
    if (x == null || y == null) return;
    final t = _fling.value;
    camera.moveTo(Offset(x.x(t), y.x(t)), camera.scale);
    if (x.isDone(t) && y.isDone(t)) _fling.stop();
  }

  /// Thu nhỏ về toàn cảnh Việt Nam (nút ở góc bản đồ).
  void showAll() {
    final fit = camera.fit(MapProjection.vietnam, margin: 0);
    _flyTo(fit.$1, fit.$2);
  }

  void showRoute() => _flyToRoute();

  // ---------------------------------------------------------- Gesture
  void _onScaleStart(ScaleStartDetails d) {
    _fly.stop();
    _fling.stop();
    _startScale = camera.scale;
    _startFocalMap = camera.toMap(d.localFocalPoint);
    _pinched = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if ((d.scale - 1).abs() > 0.02) _pinched = true;
    final s = (_startScale * d.scale).clamp(camera.minScale, MapCamera.maxScale).toDouble();
    camera.moveTo(_startFocalMap - (d.localFocalPoint - camera.focal) / s, s);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (_pinched || v.distance < 120) return;
    // Vận tốc kéo (điểm ảnh/giây) đổi sang đơn vị bản đồ, trượt chậm dần.
    _flingX = FrictionSimulation(0.06, camera.center.dx, -v.dx / camera.scale);
    _flingY = FrictionSimulation(0.06, camera.center.dy, -v.dy / camera.scale);
    _fling.value = 0;
    _fling.animateWith(_FlingClock());
  }

  void _onTapUp(TapUpDetails d) {
    final hit = _placeAt(d.localPosition);
    if (hit != null) widget.onTapPlace(hit);
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null) return;
    final target = camera.toMap(at);
    final s = min(camera.scale * 2.2, MapCamera.maxScale);
    // Giữ điểm vừa chạm đứng yên trên màn hình khi phóng to.
    _flyTo(target - (at - camera.focal) / s, s);
  }

  String? _placeAt(Offset tap) {
    String? best;
    var bestD = 26.h;
    for (final p in widget.places) {
      final s = camera.toScreen(p.position);
      var d = (s - tap).distance;
      // Ghim điểm đi/đến: chạm vào đầu ghim cũng tính.
      if (p.id == widget.fromId || p.id == widget.toId) {
        d = min(d, (s.translate(0, -21.h) - tap).distance);
      }
      if (d < bestD) {
        bestD = d;
        best = p.id;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final unit = 1.h;
    final plan = widget.plan;
    return LayoutBuilder(builder: (context, constraints) {
      camera.configure(constraints.biggest, widget.padding);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onTapUp: _onTapUp,
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: _onDoubleTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: TripMapPainter(
                    camera: camera,
                    tiles: _tiles,
                    places: widget.places,
                    fromId: widget.fromId,
                    toId: widget.toId,
                    route: _route,
                    routeIds: plan?.placeIds.toSet() ?? const {},
                    majorIds: TripMap.majorPlaces,
                    unit: unit,
                    dpr: dpr,
                    text: _text,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: _tiles,
                    builder: (context, _) => CustomPaint(
                      painter: RouteVehiclePainter(
                        camera: camera,
                        route: _route,
                        progress: _drive,
                        image: _tiles.asset(Img.player(widget.vehicle)),
                        length: switch (widget.vehicle) {
                          VehicleKind.motorbike => 26.0,
                          VehicleKind.car => 32.0,
                          VehicleKind.bus => 44.0,
                        } *
                            unit,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Đồng hồ cho trượt quán tính: giá trị = số giây đã trôi.
class _FlingClock extends Simulation {
  @override
  double x(double time) => time;

  @override
  double dx(double time) => 1;

  @override
  bool isDone(double time) => time > 3;
}
