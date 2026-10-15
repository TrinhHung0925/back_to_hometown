import 'dart:math';
import 'dart:ui';

/// Một điểm đã đổi sang toạ độ camera: [r] sang phải, [u] lên trên, [z] độ
/// sâu phía trước mắt; kèm toạ độ vân ([tu], [tv]) để dán ảnh.
class CamPoint {
  CamPoint(this.r, this.u, this.z, this.tu, this.tv);

  final double r;
  final double u;
  final double z;
  final double tu;
  final double tv;

  CamPoint lerp(CamPoint o, double t) =>
      CamPoint(r + (o.r - r) * t, u + (o.u - u) * t, z + (o.z - z) * t, tu + (o.tu - tu) * t, tv + (o.tv - tv) * t);
}

/// Camera góc nhìn ghế lái: đặt ở mắt người lái, nhìn theo hướng xe chạy.
/// Toạ độ thế giới (x, y) là mặt phẳng bản đồ của game (y hướng xuống dưới
/// màn hình bản đồ), z hướng lên trời, cùng đơn vị với bản đồ.
class DriverCamera {
  double x = 0;
  double y = 0;

  /// Mắt cao bao nhiêu so với mặt đường.
  double eye = 24;

  /// Hướng nhìn (radian) trong hệ thế giới.
  double heading = 0;

  /// Góc ngẩng (âm: cúi nhìn xuống) — tính từ chỗ muốn đặt đường chân trời.
  double pitch = -0.08;

  /// Góc nhìn ngang.
  double hfov = 75 * pi / 180;

  /// Gần hơn thì cắt bỏ; xa hơn thì không vẽ.
  static const double near = 6;
  double far = 4200;

  double width = 1;
  double height = 1;
  double focal = 1;
  double cx = 0;
  double cy = 0;
  double _c = 1, _s = 0, _cp = 1, _sp = 0;

  /// Chốt các thông số cho khung hình này: đường chân trời nằm ở [horizon]
  /// (tỉ lệ từ mép trên màn hình).
  void setup(Size size, {required double horizon}) {
    width = size.width;
    height = size.height;
    focal = width / 2 / tan(hfov / 2);
    cx = width / 2;
    cy = height / 2;
    pitch = atan((horizon * height - cy) / focal);
    _c = cos(heading);
    _s = sin(heading);
    _cp = cos(pitch);
    _sp = sin(pitch);
  }

  /// Hàng điểm ảnh của đường chân trời.
  double get horizonY => cy + focal * tan(pitch);

  /// Số điểm ảnh ứng với một radian quay đầu (bầu trời trôi theo).
  double get pixelsPerRadian => focal;

  CamPoint toCam(double wx, double wy, double wz, [double tu = 0, double tv = 0]) {
    final dx = wx - x, dy = wy - y, dz = wz - eye;
    final f = dx * _c + dy * _s;
    final r = -dx * _s + dy * _c;
    return CamPoint(r, dz * _cp - f * _sp, f * _cp + dz * _sp, tu, tv);
  }

  /// Độ sâu (dọc hướng nhìn, bỏ qua độ cao) của điểm thế giới.
  double depthOf(double wx, double wy) => (wx - x) * _c + (wy - y) * _s;

  /// Lệch ngang (sang phải) của điểm thế giới so với hướng nhìn.
  double sideOf(double wx, double wy) => -(wx - x) * _s + (wy - y) * _c;

  Offset project(CamPoint p) => Offset(cx + p.r / p.z * focal, cy - p.u / p.z * focal);

  /// Chiếu điểm thế giới; null nếu ở sau mặt cắt gần.
  Offset? projectWorld(double wx, double wy, double wz) {
    final p = toCam(wx, wy, wz);
    if (p.z < near) return null;
    return project(p);
  }

  /// Cắt đa giác (toạ độ camera) bỏ phần sau mặt cắt gần.
  static List<CamPoint> clipNear(List<CamPoint> poly) {
    final out = <CamPoint>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ina = a.z >= near, inb = b.z >= near;
      if (ina) out.add(a);
      if (ina != inb) out.add(a.lerp(b, (near - a.z) / (b.z - a.z)));
    }
    return out;
  }
}
