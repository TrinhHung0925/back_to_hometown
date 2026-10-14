import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../../resource/app_resource.dart';
import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/road_path.dart';
import '../logic/roadside.dart';
import '../logic/traffic_system.dart';
import 'road_signs.dart';
import 'scenery_layer.dart';
import 'world_paints.dart';

const double _half = GameConfig.roadHalfWidth;

/// Chốt CSGT bên lề phải chiều về quê: bãi đất, lều bạt xanh, bàn làm việc,
/// xe máy CSGT dựng, hàng cọc tiêu, người đứng bắn tốc độ, người vẫy gậy.
/// Biển hạn chế tốc độ và cấm quay đầu đặt trước chốt ở cả hai chiều.
class CheckpointLayer extends Component {
  CheckpointLayer({required this.road, required this.layout, required this.paints, required this.images}) : super(priority: 5);

  final RoadPath road;
  final RoadLayout layout;
  final WorldPaints paints;
  final Images images;
  double fromS = 0, toS = 0;

  /// Chốt đang vẫy xe mình vào (người vẫy bước ra mép đường, vung gậy).
  Checkpoint? waving;
  int wavingDir = 1;

  double _t = 0;
  final RoadSigns _signs = RoadSigns();

  static final Paint _shadow = Paint()
    ..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn)
    ..filterQuality = FilterQuality.low;
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _tentShadow = Paint()..color = const Color(0x38000000);
  static final Paint _tentBlue = Paint()..color = const Color(0xff1F5FAF);
  static final Paint _tentWhite = Paint()..color = const Color(0xffF2F4F6);
  static final Paint _pole = Paint()..color = const Color(0xff9BA2AA);

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    for (final c in layout.checkpointsBetween(fromS - 200, toS + 200)) {
      _signsFor(canvas, c);
      if (c.s < fromS - 260 || c.s > toS + 260) continue;
      final p = road.at(c.s);
      final (x, y) = road.worldAt(c.s, 0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      _post(canvas, c, p.heading);
      canvas.restore();
    }
  }

  /// Hệ toạ độ riêng: x dọc chiều về quê, y sang phải (lề có chốt).
  void _post(Canvas canvas, Checkpoint c, double angle) {
    // Bãi đất nện bên lề.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(-150, _half + 4, 150, _half + 96), const Radius.circular(8)),
      paints.laterite,
    );
    // Hàng cọc tiêu sát mép đường, dồn xe vào làn.
    for (var x = -130.0; x <= 130; x += 38) {
      _sprite(canvas, Img.imgTrafficCone, Offset(x, _half - 4), 15, 15, 0, angle);
    }
    // Xe máy CSGT dựng.
    _sprite(canvas, Img.imgScooterPoliceParked, const Offset(70, _half + 46), 26, 61, -pi / 2 + 0.2, angle);
    _sprite(canvas, Img.imgScooterPoliceParked, const Offset(102, _half + 50), 26, 61, -pi / 2 + 0.35, angle);
    // Bàn làm việc, cán bộ ngồi ghi biên bản.
    _sprite(canvas, Img.imgPoliceTable, const Offset(0, _half + 52), 46, 26, 0, angle);
    _sprite(canvas, Img.imgPoliceOfficer, const Offset(4, _half + 74), 30, 30, pi, angle);
    // Người bắn tốc độ đứng trước chốt, súng chĩa về phía xe đang tới.
    for (final dir in [1, -1]) {
      final rx = -dir * GameConfig.radarAhead;
      final ry = dir > 0 ? _half + 22 : -_half - 22;
      _sprite(canvas, Img.imgRadarTripod, Offset(rx + dir * 10, ry + (dir > 0 ? 14 : -14)), 20, 20, 0, angle);
      _sprite(canvas, Img.imgPoliceOfficerRadar, Offset(rx, ry), 34, 34, dir > 0 ? -pi / 2 : pi / 2, angle);
    }
    // Người chỉ huy: bình thường đứng cạnh lều; vẫy xe thì bước ra mép đường.
    final calling = identical(waving, c);
    if (calling) {
      final wave = sin(_t * 9) * 0.35;
      final at = wavingDir > 0 ? const Offset(-60, _half - 14) : const Offset(60, -_half + 14);
      _sprite(canvas, Img.imgPoliceOfficerWave, at, 46, 46, (wavingDir > 0 ? -pi / 2 : pi / 2) + wave, angle);
    } else {
      _sprite(canvas, Img.imgPoliceOfficer, const Offset(-44, _half + 20), 34, 34, -pi / 2, angle);
    }
    _tent(canvas, angle);
  }

  /// Lều bạt sọc xanh trắng che bàn làm việc, chữ CSGT trên nóc.
  void _tent(Canvas canvas, double angle) {
    const rect = Rect.fromLTRB(-34, _half + 30, 34, _half + 92);
    canvas.drawRect(rect.shift(toLocal(sunShadow * 1.8, angle)), _tentShadow);
    canvas.drawRect(rect, _tentWhite);
    for (var x = rect.left; x < rect.right; x += 17) {
      canvas.drawRect(Rect.fromLTWH(x, rect.top, 8.5, rect.height), _tentBlue);
    }
    canvas.drawRect(
      rect,
      Paint()..shader = Gradient.linear(rect.topCenter, rect.bottomCenter, const [Color(0x30FFFFFF), Color(0x00000000), Color(0x40000000)], const [0, 0.45, 1]),
    );
    final band = Rect.fromCenter(center: rect.center, width: 46, height: 15);
    canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(3)), Paint()..color = const Color(0xffC62828));
    final label = _signs.label('CSGT', 10, const Color(0xffFFE08A));
    label.paint(canvas, band.center - Offset(label.width / 2, label.height / 2));
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(c, 2.6, _pole);
    }
  }

  /// Biển hạn chế tốc độ và cấm quay đầu bên phải của mỗi chiều, mặt biển đọc
  /// xuôi theo người lái chiều đó.
  void _signsFor(Canvas canvas, Checkpoint c) {
    for (final forward in [true, false]) {
      final dir = forward ? 1 : -1;
      final signS = forward ? c.signS : c.oncomingSignS;
      final noTurnS = c.s - dir * (GameConfig.noUTurnReach - 120);
      for (final (s, speed) in [(signS, true), (noTurnS, false)]) {
        if (s < fromS - 60 || s > toS + 60) continue;
        final p = road.at(s);
        final (x, y) = road.worldAt(s, 0);
        final angle = p.heading + (forward ? 0 : pi);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(angle);
        if (speed) {
          _signs.speedLimit(canvas, const Offset(0, _half + 22), c.limitKmh, angle);
          // Biển phụ: có chốt kiểm soát phía trước.
          _signs.handwritten(canvas, const Offset(-30, _half + 22), 'KIỂM SOÁT', angle, paper: const Color(0xffF6F6F4));
        } else {
          _signs.noUTurn(canvas, const Offset(0, _half + 22), angle);
        }
        canvas.restore();
      }
    }
  }

  void _sprite(Canvas canvas, String path, Offset at, double w, double h, double rotation, double layerAngle) {
    final img = images.fromCache(path);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotation + pi / 2);
    final dst = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawImageRect(img, src, dst.shift(toLocal(sunShadow * 0.35, layerAngle + rotation + pi / 2)), _shadow);
    canvas.drawImageRect(img, src, dst, _image);
    canvas.restore();
  }

  @override
  void onRemove() {
    _signs.dispose();
    super.onRemove();
  }
}

/// Bãi đinh tặc trên mặt đường: đinh nằm rải rác, thỉnh thoảng loé sáng dưới
/// nắng (đèn pha). Có bãi người dân dựng biển viết tay cảnh báo phía trước.
class NailLayer extends Component {
  NailLayer({required this.road, required this.layout}) : super(priority: 3);

  final RoadPath road;
  final RoadLayout layout;
  double fromS = 0, toS = 0;

  double _t = 0;
  final RoadSigns _signs = RoadSigns();
  final Map<NailPatch, List<(Offset, double, double)>> _nails = {};

  static final Paint _nail = Paint()
    ..color = const Color(0xff9AA0A8)
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  static final Paint _nailShadow = Paint()
    ..color = const Color(0x55000000)
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;
  static final Paint _head = Paint()..color = const Color(0xffD8DCE0);

  @override
  void update(double dt) => _t += dt;

  List<(Offset, double, double)> _scatter(NailPatch n) => _nails.putIfAbsent(n, () {
        final r = Random(n.seed);
        return [
          for (var i = 0; i < 34; i++)
            (
              Offset((r.nextDouble() - 0.5) * NailPatch.length, (r.nextDouble() - 0.5) * NailPatch.width),
              r.nextDouble() * pi,
              r.nextDouble() * 6,
            ),
        ];
      });

  @override
  void render(Canvas canvas) {
    for (final n in layout.nailsBetween(fromS - 400, toS + 100)) {
      if (n.warned && n.s - 260 > fromS - 60 && n.s - 260 < toS + 60) {
        final p = road.at(n.s - 260);
        final (x, y) = road.worldAt(n.s - 260, 0);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(p.heading);
        _signs.handwritten(canvas, const Offset(0, _half + 18), 'CÓ ĐINH! ĐI CHẬM', p.heading);
        canvas.restore();
      }
      if (n.s < fromS - 60 || n.s > toS + 60) continue;
      final p = road.at(n.s);
      final (x, y) = road.worldAt(n.s, 0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      canvas.translate(0, Lanes.center(n.lane));
      for (final (o, a, phase) in _scatter(n)) {
        final d = Offset(cos(a), sin(a)) * 3;
        canvas.drawLine(o - d + const Offset(1, 1.2), o + d + const Offset(1, 1.2), _nailShadow);
        canvas.drawLine(o - d, o + d, _nail);
        canvas.drawCircle(o - d, 1.2, _head);
        // Loé sáng: vài chiếc đinh lấp lánh theo nhịp riêng.
        final glint = pow(max(0.0, sin(_t * 2.4 + phase * 3)), 12).toDouble();
        if (glint > 0.05) {
          final g = Paint()..color = Color.fromRGBO(255, 255, 255, 0.95 * glint);
          final c = o - d;
          canvas.drawLine(c - const Offset(4, 0), c + const Offset(4, 0), g..strokeWidth = 1);
          canvas.drawLine(c - const Offset(0, 4), c + const Offset(0, 4), g);
        }
      }
      canvas.restore();
    }
  }

  @override
  void onRemove() {
    _signs.dispose();
    super.onRemove();
  }
}
