import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../logic/road_path.dart';
import 'scenery_layer.dart';

/// Một hình vẽ tạm bên lề: biển tam giác, lốp dự phòng, con đội, người ngồi
/// sửa xe, xe máy người mang xăng tới. Toạ độ đường (s, d), [angle] là góc
/// tuyệt đối trong thế giới (đầu ảnh hướng theo góc này).
class CrewItem {
  const CrewItem(this.path, this.s, this.d, this.angle, this.w, this.h, {this.shadow = true});

  final String path;
  final double s;
  final double d;
  final double angle;
  final double w;
  final double h;
  final bool shadow;
}

/// Lớp vẽ những thứ game bày ra quanh xe mình khi dừng bên lề (thay lốp,
/// chờ xăng, thợ vá lưu động). Game điền lại [items] mỗi khung hình.
class CrewLayer extends Component {
  CrewLayer({required this.road, required this.images}) : super(priority: 7);

  final RoadPath road;
  final Images images;
  final List<CrewItem> items = [];

  static final Paint _shadow = Paint()
    ..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn)
    ..filterQuality = FilterQuality.low;
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;

  @override
  void render(Canvas canvas) {
    for (final item in items) {
      final img = images.fromCache(item.path);
      final (x, y) = road.worldAt(item.s, item.d);
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final dst = Rect.fromCenter(center: Offset.zero, width: item.w, height: item.h);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(item.angle);
      if (item.shadow) canvas.drawImageRect(img, src, dst.shift(toLocal(sunShadow * 0.4, item.angle)), _shadow);
      canvas.drawImageRect(img, src, dst, _image);
      canvas.restore();
    }
  }
}
