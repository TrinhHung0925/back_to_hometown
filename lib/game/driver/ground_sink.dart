import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'driver_camera.dart';

/// Nơi vẽ mặt đất (mặt đường, lề, ruộng, vạch kẻ, miếng vá…) theo toạ độ
/// thế giới. Bản đồ nhìn từ trên vẽ thẳng lên canvas; góc nhìn ghế lái chiếu
/// phối cảnh từng tam giác. Nhờ vậy hai góc nhìn dùng chung một cách dựng.
abstract class GroundSink {
  /// Vẽ phẳng từ trên xuống (được dùng lớp trộn saveLayer, đường nét canvas).
  bool get flat;

  /// Canvas gốc (chỉ dùng khi [flat]).
  Canvas get canvas;

  /// Dải nằm giữa hai mép [a] và [b] (cùng số điểm, theo thứ tự dọc đường).
  void band(List<Offset> a, List<Offset> b, Paint paint);

  /// Đa giác lồi (tứ giác vạch kẻ, ô bàn cờ…).
  void polygon(List<Offset> pts, Paint paint);

  /// Đường nét theo [pts], bề rộng là `paint.strokeWidth` (đơn vị thế giới).
  void polyline(List<Offset> pts, Paint paint);

  void segment(Offset a, Offset b, Paint paint);

  void circle(Offset c, double r, Paint paint);

  /// Ảnh nằm trên mặt đường, tâm [center], xoay [angle], cỡ [w] × [h].
  void image(Image img, Offset center, double angle, double w, double h, Paint paint);
}

/// Vẽ thẳng lên canvas của bản đồ nhìn từ trên.
class FlatGroundSink implements GroundSink {
  FlatGroundSink(this.canvas);

  @override
  final Canvas canvas;

  @override
  bool get flat => true;

  @override
  void band(List<Offset> a, List<Offset> b, Paint paint) =>
      canvas.drawPath(Path()..addPolygon([...a, ...b.reversed], true), paint);

  @override
  void polygon(List<Offset> pts, Paint paint) => canvas.drawPath(Path()..addPolygon(pts, true), paint);

  @override
  void polyline(List<Offset> pts, Paint paint) => canvas.drawPath(Path()..addPolygon(pts, false), paint);

  @override
  void segment(Offset a, Offset b, Paint paint) => canvas.drawLine(a, b, paint);

  @override
  void circle(Offset c, double r, Paint paint) => canvas.drawCircle(c, r, paint);

  @override
  void image(Image img, Offset center, double angle, double w, double h, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      paint,
    );
    canvas.restore();
  }
}

/// Chiếu mặt đất lên màn hình theo camera ghế lái: mỗi dải cắt thành tam
/// giác, bỏ phần sau lưng mắt, dán vân theo toạ độ thế giới (vân ảnh của
/// [WorldPaints] dùng thẳng được). Xa thì thưa điểm cho nhẹ.
class PerspectiveGroundSink implements GroundSink {
  PerspectiveGroundSink(this.canvas, this.cam);

  @override
  final Canvas canvas;
  final DriverCamera cam;

  @override
  bool get flat => false;

  final List<double> _pos = [];
  final List<double> _tex = [];
  final Map<Image, Paint> _imagePaints = {};

  /// Bước thưa điểm theo độ sâu.
  static int _stride(double z) => z < 450 ? 1 : z < 1200 ? 2 : z < 2400 ? 4 : 8;

  @override
  void band(List<Offset> a, List<Offset> b, Paint paint) {
    final n = min(a.length, b.length);
    if (n < 2) return;
    final keep = <int>[0];
    var last = 0;
    for (var i = 1; i < n; i++) {
      final m = (a[i] + b[i]) / 2;
      final z = cam.depthOf(m.dx, m.dy);
      if (i == n - 1 || i - last >= _stride(z)) {
        keep.add(i);
        last = i;
      }
    }
    final ca = [for (final i in keep) cam.toCam(a[i].dx, a[i].dy, 0, a[i].dx, a[i].dy)];
    final cb = [for (final i in keep) cam.toCam(b[i].dx, b[i].dy, 0, b[i].dx, b[i].dy)];
    for (var k = 0; k + 1 < ca.length; k++) {
      _quad(ca[k], ca[k + 1], cb[k + 1], cb[k]);
    }
    _flush(paint);
  }

  @override
  void polygon(List<Offset> pts, Paint paint) {
    if (pts.length < 3) return;
    _fan([for (final p in pts) cam.toCam(p.dx, p.dy, 0, p.dx, p.dy)]);
    _flush(paint);
  }

  @override
  void polyline(List<Offset> pts, Paint paint) {
    if (pts.length < 2) return;
    final half = paint.strokeWidth / 2;
    final a = <Offset>[], b = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final p0 = pts[max(0, i - 1)], p1 = pts[min(pts.length - 1, i + 1)];
      final d = p1 - p0;
      final len = d.distance;
      if (len == 0) continue;
      final nrm = Offset(-d.dy / len, d.dx / len) * half;
      a.add(pts[i] + nrm);
      b.add(pts[i] - nrm);
    }
    band(a, b, paint);
  }

  @override
  void segment(Offset a, Offset b, Paint paint) => polyline([a, b], paint);

  @override
  void circle(Offset c, double r, Paint paint) {
    final z = cam.depthOf(c.dx, c.dy);
    if (z < DriverCamera.near || r / z * cam.focal < 0.7) return;
    polygon([for (var i = 0; i < 8; i++) c + Offset(cos(i * pi / 4), sin(i * pi / 4)) * r], paint);
  }

  @override
  void image(Image img, Offset center, double angle, double w, double h, Paint paint) {
    final z = cam.depthOf(center.dx, center.dy);
    if (z < DriverCamera.near - max(w, h) || z > cam.far) return;
    final c = cos(angle), s = sin(angle);
    Offset corner(double lx, double ly) => center + Offset(lx * c - ly * s, lx * s + ly * c);
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final pts = [corner(-w / 2, -h / 2), corner(w / 2, -h / 2), corner(w / 2, h / 2), corner(-w / 2, h / 2)];
    final uv = [Offset.zero, Offset(iw, 0), Offset(iw, ih), Offset(0, ih)];
    _fan([for (var i = 0; i < 4; i++) cam.toCam(pts[i].dx, pts[i].dy, 0, uv[i].dx, uv[i].dy)]);
    _flush(_imagePaints.putIfAbsent(
        img, () => Paint()..shader = ImageShader(img, TileMode.clamp, TileMode.clamp, Float64List.fromList(_identity), filterQuality: FilterQuality.medium)));
  }

  /// Mặt phẳng đứng (tường, mặt tiền nhà, hộ lan): bốn góc toạ độ camera đã
  /// có toạ độ vân, vẽ bằng [paint].
  void wall(List<CamPoint> quad, Paint paint) {
    _fan(quad);
    _flush(paint);
  }

  static const List<double> _identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  void _quad(CamPoint p0, CamPoint p1, CamPoint p2, CamPoint p3) {
    final far = cam.far;
    if (p0.z < DriverCamera.near && p1.z < DriverCamera.near && p2.z < DriverCamera.near && p3.z < DriverCamera.near) return;
    if (p0.z > far && p1.z > far && p2.z > far && p3.z > far) return;
    _fan([p0, p1, p2, p3]);
  }

  void _fan(List<CamPoint> poly) {
    var clipped = poly;
    if (poly.any((p) => p.z < DriverCamera.near)) {
      clipped = DriverCamera.clipNear(poly);
      if (clipped.length < 3) return;
    }
    final scr = [for (final p in clipped) cam.project(p)];
    // Nằm hẳn ngoài khung hình thì bỏ.
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity;
    for (final o in scr) {
      minX = min(minX, o.dx);
      maxX = max(maxX, o.dx);
      minY = min(minY, o.dy);
    }
    if (maxX < -cam.width * 0.2 || minX > cam.width * 1.2 || minY > cam.height * 1.2) return;
    for (var i = 1; i + 1 < scr.length; i++) {
      for (final k in [0, i, i + 1]) {
        _pos
          ..add(scr[k].dx)
          ..add(scr[k].dy);
        _tex
          ..add(clipped[k].tu)
          ..add(clipped[k].tv);
      }
    }
  }

  void _flush(Paint paint) {
    if (_pos.isEmpty) return;
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.fromList(_pos),
      textureCoordinates: Float32List.fromList(_tex),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
    _pos.clear();
    _tex.clear();
  }
}
