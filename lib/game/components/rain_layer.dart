import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../game_config.dart';
import '../logic/road_path.dart';
import '../logic/weather.dart';

/// Bụi nước bắn lên sau một xe đang chạy trên đường ướt (toạ độ thế giới).
class Spray {
  const Spray(this.rear, this.heading, this.strength, this.width);

  /// Đuôi xe, hướng chạy, độ mạnh (0..1 theo tốc độ), bề ngang xe.
  final Offset rear;
  final double heading;
  final double strength;
  final double width;
}

/// Mặt đường ướt: đường sẫm màu, loang bóng sáng; hạt mưa rơi toé vòng tròn
/// trên mặt đất; xe chạy nhanh bắn bụi nước phía sau.
class RainGroundLayer extends Component {
  RainGroundLayer({required this.road}) : super(priority: 3);

  final RoadPath road;
  double fromS = 0, toS = 0;

  /// Độ nặng hạt đang rơi, độ ướt mặt đường (0..1), loại mưa.
  double rain = 0;
  double wet = 0;
  RainKind kind = RainKind.drizzle;

  /// Khung thế giới đang nhìn thấy (để rải vòng toé).
  Rect view = Rect.zero;
  final List<Spray> sprays = [];

  final Random _random = Random(5);
  final List<_Ripple> _ripples = [];

  static final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1;

  @override
  void update(double dt) {
    for (final r in _ripples) {
      r.age += dt;
    }
    _ripples.removeWhere((r) => r.age >= r.life);
    if (rain <= 0.02 || view.isEmpty) return;
    // Mưa rào toé nhiều vòng to, mưa phùn lấm tấm vòng nhỏ.
    final perSecond = (kind == RainKind.shower ? 520 : 260) * rain;
    var n = perSecond * dt;
    while (n > 0) {
      if (n < 1 && _random.nextDouble() > n) break;
      n -= 1;
      _ripples.add(_Ripple(
        Offset(view.left + _random.nextDouble() * view.width, view.top + _random.nextDouble() * view.height),
        kind == RainKind.shower ? 5 + _random.nextDouble() * 4 : 2.5 + _random.nextDouble() * 2,
        kind == RainKind.shower ? 0.42 : 0.3,
      ));
    }
  }

  @override
  void render(Canvas canvas) {
    if (wet > 0.02) _wetRoad(canvas);
    for (final r in _ripples) {
      final k = r.age / r.life;
      _ring.color = Color.fromRGBO(225, 235, 245, 0.55 * (1 - k) * min(1, rain * 2));
      canvas.drawOval(Rect.fromCenter(center: r.at, width: r.size * (0.3 + k) * 2, height: r.size * (0.3 + k) * 1.5), _ring);
    }
    if (wet > 0.15) {
      for (final s in sprays) {
        _spray(canvas, s);
      }
    }
  }

  /// Mặt nhựa ướt sẫm lại, loang ánh trời xám dọc theo làn xe.
  void _wetRoad(Canvas canvas) {
    const half = GameConfig.roadHalfWidth;
    final left = <Offset>[], right = <Offset>[];
    for (var s = fromS; s <= toS + 40; s += 40) {
      final (lx, ly) = road.worldAt(s, -half);
      final (rx, ry) = road.worldAt(s, half);
      left.add(Offset(lx, ly));
      right.add(Offset(rx, ry));
    }
    if (left.length < 2) return;
    final band = Path()..addPolygon([...left, ...right.reversed], true);
    canvas.drawPath(band, Paint()..color = Color.fromRGBO(18, 26, 38, 0.24 * wet));
    // Vệt sáng loang dọc theo vệt bánh xe.
    final sheen = Paint()
      ..color = Color.fromRGBO(200, 214, 230, 0.07 * wet)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    for (final d in const <double>[-74, -46, 46, 74]) {
      final path = Path();
      var first = true;
      for (var s = fromS; s <= toS + 40; s += 40) {
        final (x, y) = road.worldAt(s, d);
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, sheen);
    }
  }

  void _spray(Canvas canvas, Spray s) {
    if (s.strength < 0.15) return;
    final back = Offset(-cos(s.heading), -sin(s.heading));
    for (var i = 0; i < 5; i++) {
      final c = s.rear + back * (6.0 + i * 12) * (0.6 + s.strength);
      final r = s.width * (0.34 + i * 0.15);
      final a = 0.38 * s.strength * wet * (1 - i / 5);
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = Gradient.radial(c, r, [Color.fromRGBO(235, 240, 245, a), const Color(0x00EBF0F5)]),
      );
    }
  }
}

class _Ripple {
  _Ripple(this.at, this.size, this.life);

  final Offset at;
  final double size;
  final double life;
  double age = 0;
}

/// Trời mưa: cả cảnh xám xịt (mưa rào tối hơn), mưa phùn thì mù mù sương.
class RainSkyLayer extends Component {
  RainSkyLayer() : super(priority: 19);

  double rain = 0;
  RainKind kind = RainKind.drizzle;
  Rect view = Rect.zero;

  @override
  void render(Canvas canvas) {
    if (rain <= 0.01 || view.isEmpty) return;
    final area = view.inflate(80);
    if (kind == RainKind.shower) {
      canvas.drawRect(area, Paint()..color = Color.fromRGBO(34, 46, 62, 0.26 * rain));
    } else {
      canvas.drawRect(area, Paint()..color = Color.fromRGBO(60, 70, 84, 0.14 * rain));
      canvas.drawRect(area, Paint()..color = Color.fromRGBO(214, 220, 226, 0.2 * rain));
    }
  }
}

/// Hạt mưa rơi xiên trước mắt (toạ độ màn hình). Xe chạy nhanh thì hạt mưa
/// như hắt ngược về phía sau.
class RainStreaks extends Component with HasGameReference<FlameGame> {
  RainStreaks() : super(priority: 1);

  double rain = 0;
  RainKind kind = RainKind.drizzle;

  /// Tốc độ cảnh trôi trên màn hình (px/s, dương = trôi sang trái).
  double flow = 0;

  final Random _random = Random(9);
  final List<_Drop> _drops = [];


  @override
  void update(double dt) {
    final size = game.size;
    if (size.x <= 0) return;
    final want = (rain * (kind == RainKind.shower ? 230 : 300)).round();
    while (_drops.length < want) {
      _drops.add(_Drop(Offset(_random.nextDouble() * size.x, _random.nextDouble() * size.y), 0.6 + _random.nextDouble() * 0.6));
    }
    if (_drops.length > want) _drops.removeRange(want, _drops.length);
    final v = _velocity;
    for (final d in _drops) {
      d.at += v * d.speed * dt;
      if (d.at.dy > size.y + 30 || d.at.dx < -60 || d.at.dx > size.x + 60) {
        d.at = Offset(_random.nextDouble() * (size.x + 120) - 60, -20 - _random.nextDouble() * 40);
      }
    }

  }

  Offset get _velocity =>
      kind == RainKind.shower ? Offset(-140 - flow * 0.55, 900) : Offset(-50 - flow * 0.45, 260);

  @override
  void render(Canvas canvas) {
    if (_drops.isEmpty) return;
    final v = _velocity;
    final dir = v / v.distance;
    final shower = kind == RainKind.shower;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = shower ? 1.4 : 1.0;
    for (final d in _drops) {
      final len = (shower ? 22.0 : 7.0) * d.speed;
      paint.color = Color.fromRGBO(226, 234, 244, (shower ? 0.42 : 0.5) * min(1.0, rain * 1.6) * d.speed);
      canvas.drawLine(d.at, d.at + dir * len, paint);
    }
  }
}

class _Drop {
  _Drop(this.at, this.speed);

  Offset at;
  final double speed;
}
