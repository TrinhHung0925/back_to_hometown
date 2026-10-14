import 'dart:math';

import 'package:flutter/widgets.dart';

import 'map_geometry.dart';

/// Camera của bản đồ: tâm (toạ độ bản đồ) + tỉ lệ (điểm ảnh / đơn vị bản đồ).
///
/// [padding] là phần màn hình bị bảng điều khiển che: tâm camera nằm giữa vùng
/// còn lại, và các phép "vừa khung" chỉ dùng vùng đó.
class MapCamera extends ChangeNotifier {
  Offset center = MapProjection.vietnam.center;
  double scale = 20;
  Size viewport = Size.zero;
  EdgeInsets padding = EdgeInsets.zero;
  bool _ready = false;

  static const double maxScale = 460;

  Rect get _free => padding.deflateRect(Offset.zero & viewport);

  Offset get focal => _free.center;

  /// Thu nhỏ nhất: vừa cả nước Việt Nam theo chiều cao vùng nhìn.
  double get minScale {
    final vn = MapProjection.vietnam;
    return min(_free.height / vn.height, _free.width / vn.width * 1.6);
  }

  Offset toScreen(Offset p) => (p - center) * scale + focal;

  Offset toMap(Offset s) => (s - focal) / scale + center;

  /// Vùng bản đồ đang nhìn thấy (cả phần dưới bảng điều khiển).
  Rect get visible => Rect.fromPoints(toMap(Offset.zero), toMap(viewport.bottomRight(Offset.zero)));

  /// Cập nhật kích thước màn hình (gọi trong lúc build, không báo thay đổi).
  void configure(Size size, EdgeInsets pad) {
    viewport = size;
    padding = pad;
    if (!_ready && size.width > 0 && size.height > 0) {
      _ready = true;
      final fit = this.fit(MapProjection.vietnam, margin: 0);
      center = fit.$1;
      scale = fit.$2;
    }
    final clamped = _clamp(center, scale);
    center = clamped.$1;
    scale = clamped.$2;
  }

  void moveTo(Offset c, double s) {
    final clamped = _clamp(c, s);
    center = clamped.$1;
    scale = clamped.$2;
    notifyListeners();
  }

  /// Tâm + tỉ lệ để [rect] vừa trong vùng nhìn, chừa lề [margin] điểm ảnh.
  (Offset, double) fit(Rect rect, {double margin = 40}) {
    final free = _free.deflate(margin);
    final s = min(free.width / max(rect.width, 1e-3), free.height / max(rect.height, 1e-3));
    return _clamp(rect.center, s);
  }

  (Offset, double) _clamp(Offset c, double s) {
    final sc = s.clamp(minScale, maxScale).toDouble();
    final world = MapProjection.world;
    final f = focal;
    double axis(double v, double lo, double hi) => lo > hi ? (lo + hi) / 2 : v.clamp(lo, hi).toDouble();
    return (
      Offset(
        axis(c.dx, world.left + f.dx / sc, world.right - (viewport.width - f.dx) / sc),
        axis(c.dy, world.top + f.dy / sc, world.bottom - (viewport.height - f.dy) / sc),
      ),
      sc,
    );
  }
}
