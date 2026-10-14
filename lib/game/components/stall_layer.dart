import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, TextDirection;

import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/road_path.dart';
import '../logic/roadside.dart';
import 'road_signs.dart';
import 'scenery_layer.dart';
import 'world_paints.dart';

/// Một món đồ trong quán: ảnh, vị trí (toạ độ riêng của quán), cỡ, góc.
class StallProp {
  const StallProp(this.path, this.x, this.y, this.w, this.h, {this.angle = 0});

  final String path;
  final double x;
  final double y;
  final double w;
  final double h;
  final double angle;
}

/// Bố cục một quán, dựng một lần theo [Stall.seed].
///
/// Toạ độ riêng: x dọc theo chiều đi của phía quán (bên phải chiều đó), y từ
/// mép trong khu quán ([Stall.plotFrom]) ra xa đường; y âm là lề dựng xe.
class StallPlan {
  StallPlan(this.stall) {
    final r = Random(stall.seed);
    String stoolPath() => Img.stools[r.nextInt(Img.stools.length)];
    String person() => Img.people[r.nextInt(Img.people.length)];

    void table(double x, double y, {bool guestSeat = false, int guests = 1}) {
      props.add(StallProp(Img.tables[r.nextInt(Img.tables.length)], x, y, 32, 32));
      // Ghế quanh bàn: trước (sát đường), sau, trái, phải.
      final seats = [(x, y - 26, 0.0), (x, y + 26, pi), (x - 26, y, pi / 2), (x + 26, y, -pi / 2)];
      for (var i = 0; i < seats.length; i++) {
        final (sx, sy, face) = seats[i];
        props.add(StallProp(stoolPath(), sx, sy, 20, 20));
        if (guestSeat && i == 0) {
          seat = Offset(sx, sy);
          seatAngle = face;
        } else if (guests > 0 && r.nextDouble() < 0.55) {
          guests--;
          people.add(StallProp(person(), sx, sy, 24, 24, angle: face + (r.nextDouble() - 0.5) * 0.4));
        } else {
          // Ghế trống: trời mưa thì có người vào trú.
          rainPeople.add(StallProp(person(), sx, sy, 24, 24, angle: face + (r.nextDouble() - 0.5) * 0.4));
        }
      }
    }

    switch (stall.kind) {
      case StallKind.traDa:
        table(-24, 34, guestSeat: true);
        table(36, 92, guests: 2);
        props.add(StallProp(Img.imgTeaJug, 70, 24, 24, 24));
        props.add(StallProp(Img.imgCooler, -62, 124, 40, 27));
        overhead.add(StallProp(Img.umbrellas[r.nextInt(Img.umbrellas.length)], 36, 92, 96, 96, angle: r.nextDouble() * pi));
        if (r.nextBool()) overhead.add(StallProp(Img.umbrellas[r.nextInt(Img.umbrellas.length)], -50, 114, 80, 80, angle: r.nextDouble() * pi));
      case StallKind.nuocMia:
        tarp = Rect.fromLTRB(-74, 74, 74, 144);
        props.add(StallProp(Img.imgCanePress, -38, 40, 50, 36));
        props.add(StallProp(Img.imgCaneBundle, -40, 92, 76, 27, angle: 0.15));
        props.add(StallProp(Img.imgCooler, 64, 110, 36, 24));
        table(34, 36, guestSeat: true);
        for (final x in const <double>[-50, 10, 50]) {
          rainPeople.add(StallProp(person(), x, 120, 24, 24, angle: r.nextDouble() * pi * 2));
        }
      case StallKind.caPheVong:
        tarp = Rect.fromLTRB(-84, 104, 84, 150);
        for (var i = 0; i < 5; i++) {
          final x = -64.0 + i * 32;
          if (i == 2) {
            hammock = Offset(x, 56);
            seat = Offset(x, 56);
            seatAngle = 0;
            props.add(StallProp(Img.hammocks[0], x, 56, 28, 80));
          } else {
            props.add(StallProp(Img.hammocks[r.nextDouble() < 0.6 ? 1 + r.nextInt(2) : 0], x, 56, 28, 80));
          }
        }
        props.add(StallProp(Img.imgTeaJug, 74, 12, 22, 22));
        for (final x in const <double>[-60, -20, 30, 66]) {
          rainPeople.add(StallProp(person(), x, 126, 24, 24, angle: pi + (r.nextDouble() - 0.5)));
        }
      case StallKind.banhMi:
        props.add(StallProp(Img.imgBreadCart, -30, 30, 58, 35));
        overhead.add(StallProp(Img.umbrellas[r.nextInt(Img.umbrellas.length)], -30, 84, 80, 80, angle: r.nextDouble() * pi));
        table(40, 34, guestSeat: true);
        rainPeople.add(StallProp(person(), -40, 80, 24, 24, angle: r.nextDouble() * pi * 2));
      case StallKind.com:
        tarp = Rect.fromLTRB(-82, 70, 82, 146);
        props.add(StallProp(Img.imgFoodTray, -42, 32, 62, 35));
        table(36, 34, guestSeat: true, guests: 2);
        table(-30, 104, guests: 3);
        table(44, 110, guests: 2);
      case StallKind.vaXe:
        props.add(StallProp(Img.imgTireStack, -40, 30, 40, 40));
        props.add(StallProp(Img.imgTireStack, -62, 62, 34, 34, angle: 1.1));
        props.add(StallProp(Img.imgCompressor, -20, 74, 44, 29));
        props.add(StallProp(Img.imgWaterBasin, 22, 22, 26, 26));
        props.add(StallProp(Img.imgCooler, 66, 116, 34, 23));
        tarp = Rect.fromLTRB(-80, 96, 30, 146);
        table(46, 72, guestSeat: true);
        worker = StallProp(Img.imgMechanic, 0, 26, 26, 26);
      case StallKind.xang:
        // Hai đảo bơm dưới mái che (cột bơm vẽ bằng code), xe vào đỗ cạnh
        // đảo phía sát đường.
        for (final x in const <double>[-48, 48]) {
          islands.add(Offset(x, 66));
        }
        // Khách đang đổ ở phía trong đảo: xe máy, có khi cả ô tô.
        if (r.nextDouble() < 0.75) {
          bikes.add(StallProp(Img.scootersParked[r.nextInt(Img.scootersParked.length)], -48, 92, 24, 56, angle: pi / 2));
        }
        if (r.nextDouble() < 0.45) {
          bikes.add(StallProp(Img.sedansAi[r.nextInt(Img.sedansAi.length)], 48, 100, 42, 88, angle: pi / 2));
        }
        for (var i = 0; i < 5; i++) {
          stains.add((Offset(-80 + r.nextDouble() * 160, 20 + r.nextDouble() * 90), 4 + r.nextDouble() * 9));
        }
        worker = StallProp(Img.imgAttendant, -48, 44, 26, 26);
      case StallKind.xangLe:
        // Kệ chai xăng sát mép đất, phễu, can; người bán ngồi ghế dưới ô.
        props.add(StallProp(Img.imgBottleShelf, 6, 12, 58, 31));
        props.add(StallProp(Img.imgFunnel, 40, 4, 12, 12));
        props.add(StallProp(Img.imgJerrycan, 42, 24, 14, 18, angle: 0.3));
        props.add(StallProp(stoolPath(), -30, 40, 18, 18));
        overhead.add(StallProp(Img.umbrellas[r.nextInt(Img.umbrellas.length)], -30, 46, 62, 62, angle: r.nextDouble() * pi));
        worker = StallProp(Img.imgSeller, -30, 40, 24, 24);
    }
    // Xe máy của khách dựng ở lề trước quán, mũi xe chĩa vào quán.
    if (stall.kind.canSit) {
      for (final x in [52.0, 76.0]) {
        if (r.nextDouble() < 0.6) {
          bikes.add(StallProp(Img.scootersParked[r.nextInt(Img.scootersParked.length)], x, -28, 24, 56, angle: pi + (r.nextDouble() - 0.5) * 0.3));
        } else {
          rainBikes.add(StallProp(Img.scootersParked[r.nextInt(Img.scootersParked.length)], x, -28, 24, 56, angle: pi + (r.nextDouble() - 0.5) * 0.3));
        }
      }
      rainBikes.add(StallProp(Img.scootersParked[r.nextInt(Img.scootersParked.length)], -66, -28, 24, 56, angle: pi + (r.nextDouble() - 0.5) * 0.3));
    }
  }

  final Stall stall;
  final List<StallProp> props = [];
  final List<StallProp> people = [];
  final List<StallProp> overhead = [];
  final List<StallProp> bikes = [];

  /// Trời mưa: người vào trú, xe dựng thêm ở lề.
  final List<StallProp> rainPeople = [];
  final List<StallProp> rainBikes = [];

  /// Người làm ở quán (nhân viên cây xăng, thợ vá xe, người bán xăng lẻ):
  /// chỗ đứng mặc định (ra phục vụ thì game dời đi).
  StallProp? worker;

  /// Cây xăng: tâm các đảo bơm, vết dầu loang trên sân.
  final List<Offset> islands = [];
  final List<(Offset, double)> stains = [];

  /// Mái bạt (toạ độ riêng), null nếu quán không có.
  Rect? tarp;

  /// Chỗ người chơi ngồi (ghế sát đường, hoặc võng trống) và hướng mặt.
  Offset seat = Offset.zero;
  double seatAngle = 0;

  /// Võng dành cho người chơi (cà phê võng): nằm lên thì đổi sang võng có người.
  Offset? hammock;

  /// Đổi toạ độ riêng của quán sang toạ độ đường (s, d).
  (double, double) toRoad(Offset local) => (stall.s + stall.side * local.dx, stall.side * (Stall.plotFrom + local.dy));

  /// Chỗ xe vào đổ xăng: cạnh đảo bơm phía trước theo chiều đi (toạ độ riêng).
  Offset bayFor(double localX) {
    final ahead = islands.where((o) => o.dx > localX + 30).toList();
    final island = ahead.isEmpty ? islands.last : ahead.first;
    return Offset(island.dx, 30);
  }
}

/// Vẽ các quán ven đường đang thấy, cùng người lái đang đi bộ / ngồi quán.
class StallLayer extends Component {
  StallLayer({required this.road, required this.layout, required this.paints, required this.images}) : super(priority: 2);

  final RoadPath road;
  final RoadLayout layout;
  final WorldPaints paints;
  final Images images;
  double fromS = 0, toS = 0;

  /// Người lái đã xuống xe: quán đang ghé, vị trí (toạ độ đường), hướng,
  /// đang nằm võng (ẩn người, đổi võng).
  Stall? guestStall;
  double guestS = 0, guestD = 0, guestAngle = 0;
  bool guestInHammock = false;
  Sprite? guestSprite;

  /// Người làm của quán đang ra phục vụ xe mình (toạ độ đường), null nếu
  /// đứng chỗ cũ.
  Stall? servingStall;
  double workerS = 0, workerD = 0, workerAngle = 0;

  /// Độ nặng hạt mưa (quán đông người trú mưa).
  double rain = 0;

  /// Cây xăng xe mình đang đỗ dưới mái: mái che mờ đi để thấy cột bơm.
  Stall? underCanopy;
  double _canopyFade = 0;

  @override
  void update(double dt) {
    final target = underCanopy == null ? 0.0 : 1.0;
    _canopyFade += (target - _canopyFade) * min(1.0, dt * 4);
  }

  final Map<Stall, StallPlan> _plans = {};
  final Map<String, TextPainter> _text = {};
  final RoadSigns _signs = RoadSigns();

  StallPlan planOf(Stall stall) => _plans.putIfAbsent(stall, () => StallPlan(stall));

  static final Paint _shadow = Paint()
    ..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn)
    ..filterQuality = FilterQuality.low;
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _pole = Paint()..color = const Color(0xff6B5A44);
  static final Paint _boardShadow = Paint()..color = const Color(0x40000000);
  static final Paint _boardEdge = Paint()
    ..color = const Color(0xffF4F4F0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _island = Paint()..color = const Color(0xffDCDAD2);
  static final Paint _hazardStripe = Paint()..color = const Color(0xffF2B705);
  static final Paint _lineWhite = Paint()
    ..color = const Color(0xccF4F4F0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  static const Map<StallKind, Color> _tarpColors = {
    StallKind.nuocMia: Color(0xff2F7FC4),
    StallKind.caPheVong: Color(0xff2E7D5B),
    StallKind.com: Color(0xffD9792B),
    StallKind.vaXe: Color(0xff3E6FA8),
  };

  static const Map<StallKind, Color> _boardColors = {
    StallKind.traDa: Color(0xffC8372D),
    StallKind.nuocMia: Color(0xff2E8B57),
    StallKind.caPheVong: Color(0xff5B3A29),
    StallKind.banhMi: Color(0xffE9822E),
    StallKind.com: Color(0xff2F6FB5),
    StallKind.vaXe: Color(0xff3A3D42),
    StallKind.xang: Color(0xffC8372D),
    StallKind.xangLe: Color(0xffC8372D),
  };

  TextPainter _label(String text, {double size = 9, Color color = const Color(0xffFFFFFF)}) => _text.putIfAbsent(
        '$text|$size|${color.toARGB32()}',
        () => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: 'Manrope', fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  @override
  void render(Canvas canvas) {
    final crowd = rain > 0.25;
    for (final stall in layout.stallsBetween(fromS - 260, toS + 260)) {
      final plan = planOf(stall);
      final p = road.at(stall.s);
      final (x, y) = road.worldAt(stall.s, stall.side * Stall.plotFrom);
      final angle = p.heading + (stall.side > 0 ? 0 : pi);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      _ground(canvas, stall, plan);
      for (final prop in [...plan.props, ...plan.bikes, if (crowd) ...plan.rainBikes]) {
        _sprite(canvas, prop, angle, shadow: true);
      }
      for (final prop in [...plan.people, if (crowd) ...plan.rainPeople]) {
        _sprite(canvas, prop, angle, shadow: false);
      }
      final worker = plan.worker;
      if (worker != null && !identical(servingStall, stall)) _sprite(canvas, worker, angle, shadow: false);
      if (identical(guestStall, stall) && guestInHammock && plan.hammock != null) {
        final h = plan.hammock!;
        _sprite(canvas, StallProp(Img.hammocks[2], h.dx, h.dy, 28, 80), angle, shadow: false);
      }
      canvas.restore();
      // Người lái / người làm vẽ theo toạ độ đường (đang đi lại), trên bàn
      // ghế nhưng dưới ô dù, mái bạt.
      if (identical(guestStall, stall) && !guestInHammock && guestSprite != null) {
        _person(canvas, guestSprite!, guestS, guestD, guestAngle, 26);
      }
      if (worker != null && identical(servingStall, stall)) {
        _person(canvas, Sprite(images.fromCache(worker.path)), workerS, workerD, workerAngle, worker.w);
      }
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      for (final prop in plan.overhead) {
        _sprite(canvas, prop, angle, shadow: true, shadowScale: 2.2);
      }
      final tarp = plan.tarp;
      if (tarp != null) _tarp(canvas, stall, tarp, angle);
      switch (stall.kind) {
        case StallKind.xang:
          _gasCanopy(canvas, angle, open: identical(underCanopy, stall) ? _canopyFade : 0);
          _pricePylon(canvas, angle);
        case StallKind.xangLe:
          _signs.handwritten(canvas, const Offset(-44, -12), 'XĂNG', angle);
        default:
          _signboard(canvas, stall, angle);
      }
      canvas.restore();
    }
  }

  void _person(Canvas canvas, Sprite sprite, double s, double d, double angle, double size) {
    final (gx, gy) = road.worldAt(s, d);
    canvas.save();
    canvas.translate(gx, gy);
    canvas.rotate(angle);
    sprite.render(canvas, position: Vector2.all(-size / 2), size: Vector2.all(size));
    canvas.restore();
  }

  void _ground(Canvas canvas, Stall stall, StallPlan plan) {
    final half = stall.halfLength;
    final city = layout.kindAt(stall.s) == RoadKind.city;
    switch (stall.kind) {
      case StallKind.xang:
        _gasYard(canvas, stall, plan);
      case StallKind.xangLe:
        canvas.drawRect(Rect.fromLTRB(-half, -GameConfig.stallPadWidth + 4, half, stall.depth), paints.laterite);
      default:
        if (!city) {
          canvas.drawRect(Rect.fromLTRB(-half, -GameConfig.stallPadWidth + 4, half, 0), paints.laterite);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(-half, 0, half, stall.depth), const Radius.circular(6)),
          city ? paints.concrete : paints.gravel,
        );
    }
  }

  /// Sân cây xăng: bê tông có đường ron, vết dầu, mũi tên lối vào / ra,
  /// bồn cây phía sau, đảo bơm có cột chắn vàng đen, cột bơm, cửa hàng.
  void _gasYard(Canvas canvas, Stall stall, StallPlan plan) {
    final half = stall.halfLength;
    final yard = Rect.fromLTRB(-half, -GameConfig.stallPadWidth + 2, half, stall.depth);
    canvas.drawRRect(RRect.fromRectAndRadius(yard, const Radius.circular(8)), paints.concrete);
    canvas.drawRRect(RRect.fromRectAndRadius(yard, const Radius.circular(8)), Paint()..color = const Color(0x0E000000));
    // Đường ron bê tông.
    final joint = Paint()
      ..color = const Color(0x1A000000)
      ..strokeWidth = 1;
    for (var x = -half + 40; x < half; x += 40) {
      canvas.drawLine(Offset(x, yard.top), Offset(x, yard.bottom), joint);
    }
    for (var y = yard.top + 36; y < yard.bottom; y += 36) {
      canvas.drawLine(Offset(-half, y), Offset(half, y), joint);
    }
    for (final (o, r) in plan.stains) {
      canvas.drawOval(
        Rect.fromCenter(center: o, width: r * 2.4, height: r * 1.6),
        Paint()..shader = Gradient.radial(o, r * 1.2, const [Color(0x40201A14), Color(0x00201A14)]),
      );
    }
    // Mũi tên sơn: vào ở đầu sân, ra ở cuối sân (theo chiều đi của phía này).
    for (final (x, inward) in [(-half + 30, true), (half - 30, false)]) {
      final y0 = inward ? -40.0 : 0.0, y1 = inward ? 0.0 : -40.0;
      canvas.drawLine(Offset(x, y0), Offset(x + (inward ? 10 : 10), y1), _lineWhite);
      final tip = Offset(x + 10, y1);
      final dir = inward ? 1.0 : -1.0;
      canvas.drawPath(
        Path()..addPolygon([tip + Offset(0, 6 * dir), tip + Offset(-6, -2 * dir), tip + Offset(6, -2 * dir)], true),
        Paint()..color = const Color(0xccF4F4F0),
      );
    }
    // Bồn cây sát cửa hàng.
    for (final x in [-100.0, 100.0]) {
      final bed = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, 160), width: 34, height: 40), const Radius.circular(4));
      canvas.drawRRect(bed, Paint()..color = const Color(0xffC9C4B8));
      canvas.drawRRect(bed.deflate(3), paints.grass);
      canvas.drawCircle(Offset(x, 156), 11, Paint()..shader = Gradient.radial(Offset(x - 3, 152), 13, const [Color(0xff5F9E48), Color(0xff2F6A2A)]));
    }
    for (final o in plan.islands) {
      final island = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 62, height: 16), const Radius.circular(6));
      canvas.drawRRect(island.shift(const Offset(2, 3)), _boardShadow);
      canvas.drawRRect(island, _island);
      canvas.drawRRect(island.deflate(2), Paint()..color = const Color(0xffE9E7E0));
      for (final end in [-1.0, 1.0]) {
        final b = o + Offset(end * 34, 0);
        canvas.drawCircle(b + const Offset(1.5, 2), 4, _boardShadow);
        canvas.drawCircle(b, 4, _hazardStripe);
        canvas.drawCircle(b, 2, Paint()..color = const Color(0xff1B1D22));
      }
      for (final dx in [-14.0, 14.0]) {
        _pump(canvas, o + Offset(dx, 0));
      }
    }
    _kiosk(canvas);
  }

  /// Cột bơm nhìn từ trên: thân trắng, nóc đỏ, màn hình hai mặt, vòi treo.
  void _pump(Canvas canvas, Offset c) {
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 18, height: 11), const Radius.circular(2));
    canvas.drawRRect(body.shift(const Offset(2.5, 3.5)), _boardShadow);
    canvas.drawRRect(body, Paint()..color = const Color(0xffF4F4F2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 18, height: 4), const Radius.circular(1)),
      Paint()..color = const Color(0xffC8372D),
    );
    for (final dy in [-4.0, 4.0]) {
      canvas.drawRect(Rect.fromCenter(center: c + Offset(0, dy), width: 8, height: 1.6), Paint()..color = const Color(0xff2A3540));
    }
    final hose = Paint()
      ..color = const Color(0xff1B1D22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawArc(Rect.fromCenter(center: c + const Offset(9, 0), width: 8, height: 12), -pi / 2, pi, false, hose);
  }

  /// Cửa hàng cây xăng: mái bằng có tường chắn mái, cục nóng điều hoà, mái
  /// hiên đỏ phía sân.
  void _kiosk(Canvas canvas) {
    const rect = Rect.fromLTRB(-62, 134, 62, 182);
    canvas.drawRect(rect.shift(const Offset(8, 11)), Paint()..color = const Color(0x44000000));
    canvas.drawRect(rect, Paint()..color = const Color(0xffDCD8CF));
    canvas.drawRect(rect.deflate(3), paints.roofFlat);
    canvas.drawRect(rect.deflate(3), Paint()..color = const Color(0x10000000));
    for (final x in [-38.0, 26.0]) {
      final unit = Rect.fromCenter(center: Offset(x, 162), width: 18, height: 12);
      canvas.drawRect(unit.shift(const Offset(2, 3)), _boardShadow);
      canvas.drawRect(unit, Paint()..color = const Color(0xffE8EAEC));
      canvas.drawCircle(unit.center + const Offset(2, 0), 4, Paint()..color = const Color(0xff7D848C));
      canvas.drawCircle(unit.center + const Offset(2, 0), 1.4, Paint()..color = const Color(0xffC6CBD0));
    }
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 6), Paint()..color = const Color(0xffC8372D));
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top + 6, rect.right, rect.top + 7.5), Paint()..color = const Color(0x40000000));
  }

  /// Mái che cây xăng (cao, đổ bóng dài): mái tôn trắng có đường ghép, viền
  /// đỏ xanh, chữ XĂNG DẦU trên viền phía đường. Xe mình đỗ bên dưới thì mái
  /// mờ đi ([open] 0..1) để thấy cột bơm.
  void _gasCanopy(Canvas canvas, double angle, {required double open}) {
    const rect = Rect.fromLTRB(-100, 10, 100, 120);
    final a = 1 - 0.72 * open;
    canvas.drawRect(rect.shift(toLocal(sunShadow * 3.4, angle)), Paint()..color = Color.fromRGBO(0, 0, 0, 0.22 * a));
    canvas.drawRect(rect, Paint()..color = Color.fromRGBO(240, 241, 242, a));
    final seam = Paint()
      ..color = Color.fromRGBO(0, 0, 0, 0.07 * a)
      ..strokeWidth = 1.2;
    for (var x = rect.left + 20; x < rect.right; x += 20) {
      canvas.drawLine(Offset(x, rect.top + 10), Offset(x, rect.bottom - 8), seam);
    }
    canvas.drawRect(
      rect,
      Paint()..shader = Gradient.linear(rect.topLeft, rect.bottomRight, [Color.fromRGBO(255, 255, 255, 0.25 * a), Color.fromRGBO(0, 0, 0, 0.1 * a)]),
    );
    // Viền mái: dải đỏ, chỉ xanh.
    final band = Paint()..color = Color.fromRGBO(200, 55, 45, a);
    final blue = Paint()..color = Color.fromRGBO(31, 78, 156, a);
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 9), band);
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.bottom - 7, rect.right, rect.bottom), band);
    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, rect.left + 6, rect.bottom), band);
    canvas.drawRect(Rect.fromLTRB(rect.right - 6, rect.top, rect.right, rect.bottom), band);
    canvas.drawRect(Rect.fromLTRB(rect.left + 6, rect.top + 9, rect.right - 6, rect.top + 11), blue);
    canvas.drawRect(Rect.fromLTRB(rect.left + 6, rect.bottom - 9, rect.right - 6, rect.bottom - 7), blue);
    if (a > 0.5) {
      final label = _label('XĂNG DẦU', size: 7);
      label.paint(canvas, Offset(-label.width / 2, rect.top + 4.5 - label.height / 2));
    }
    // Đèn trần soi xuống (ban đêm sáng).
    for (final o in const [Offset(-60, 40), Offset(0, 40), Offset(60, 40), Offset(-60, 92), Offset(0, 92), Offset(60, 92)]) {
      canvas.drawRect(Rect.fromCenter(center: o, width: 12, height: 3), Paint()..color = Color.fromRGBO(255, 255, 255, 0.45 * a));
    }
  }

  /// Trụ giá xăng cao sát mép đường: nhìn từ trên thấy đỉnh trụ hẹp và bóng
  /// tấm biển đổ dài trên mặt đất.
  void _pricePylon(Canvas canvas, double angle) {
    const top = Rect.fromLTRB(-126, -36, -96, -30);
    final shadow = toLocal(sunShadow * 1.0, angle);
    final along = toLocal(const Offset(1, 1.3), angle);
    final cast = Path()
      ..addPolygon([
        top.topLeft,
        top.topRight,
        top.topRight + shadow + along * 28,
        top.topLeft + shadow + along * 28,
      ], true);
    canvas.drawPath(cast, Paint()..color = const Color(0x33000000));
    canvas.drawRRect(RRect.fromRectAndRadius(top, const Radius.circular(1.5)), Paint()..color = const Color(0xff1F4E9C));
    canvas.drawRect(Rect.fromLTRB(top.left, top.top, top.right, top.top + 2.5), Paint()..color = const Color(0xffC8372D));
    final t = _label('RON95 · E5', size: 5.5, color: const Color(0xffFFB547));
    t.paint(canvas, Offset(top.center.dx - t.width / 2, top.bottom + 2));
  }

  void _sprite(Canvas canvas, StallProp prop, double layerAngle, {required bool shadow, double shadowScale = 1}) {
    final img = images.fromCache(prop.path);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.save();
    canvas.translate(prop.x, prop.y);
    canvas.rotate(prop.angle);
    final dst = Rect.fromCenter(center: Offset.zero, width: prop.w, height: prop.h);
    if (shadow) {
      final o = toLocal(sunShadow * 0.35 * shadowScale, layerAngle + prop.angle);
      canvas.drawImageRect(img, src, dst.shift(o), _shadow);
    }
    canvas.drawImageRect(img, src, dst, _image);
    canvas.restore();
  }

  /// Mái bạt căng trên cột tre: hơi trong để thấy bàn ghế bên dưới, võng
  /// xuống giữa (tối hơn ở mép ngoài).
  void _tarp(Canvas canvas, Stall stall, Rect rect, double angle) {
    final color = _tarpColors[stall.kind] ?? const Color(0xff2F7FC4);
    canvas.drawRect(rect.shift(toLocal(sunShadow * 1.8, angle)), _boardShadow);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.88));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(rect.topCenter, rect.bottomCenter, const [Color(0x30FFFFFF), Color(0x00000000), Color(0x38000000)], const [0, 0.5, 1]),
    );
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(c, 3, _pole);
    }
  }

  /// Biển hiệu quán dựng sát lề, chữ đọc xuôi theo chiều đi của phía quán.
  void _signboard(Canvas canvas, Stall stall, double angle) {
    final label = _label(stall.gouging ? 'VÁ XE 24H' : stall.kind.sign);
    final board = Rect.fromCenter(center: const Offset(-58, -8), width: label.width + 12, height: label.height + 8);
    canvas.drawRect(board.shift(toLocal(sunShadow * 0.8, angle)), _boardShadow);
    canvas.drawRect(board, Paint()..color = _boardColors[stall.kind]!);
    canvas.drawRect(board.deflate(1.5), _boardEdge);
    label.paint(canvas, board.center - Offset(label.width / 2, label.height / 2));
  }

  @override
  void onRemove() {
    for (final t in _text.values) {
      t.dispose();
    }
    _text.clear();
    _signs.dispose();
    super.onRemove();
  }
}
