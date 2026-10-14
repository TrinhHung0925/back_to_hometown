import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Một hạt hiệu ứng trong toạ độ thế giới.
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.r0,
    required this.r1,
    required this.color,
    required this.alpha,
    this.drag = 0,
  });

  double x, y, vx, vy;
  double age = 0;
  final double life;
  final double r0, r1;
  final Color color;
  final double alpha;

  /// Hãm vận tốc (1/giây): khói, bụi nước chậm dần rồi lơ lửng.
  final double drag;

  double get t => age / life;
  double get radius => r0 + (r1 - r0) * t;

  void step(double dt) {
    age += dt;
    final k = exp(-drag * dt);
    vx *= k;
    vy *= k;
    x += vx * dt;
    y += vy * dt;
  }
}

/// Vệt lốp in trên mặt đường (phanh gấp, quệt lề), mờ dần rồi mất.
class _Mark {
  _Mark(this.x0, this.y0, this.x1, this.y1, this.width, this.alpha);

  final double x0, y0, x1, y1, width, alpha;
  double age = 0;
}

/// Mảnh vỡ văng ra khi va chạm: trượt trên đường rồi nằm yên một lúc.
class _Shard {
  _Shard(this.x, this.y, this.vx, this.vy, this.size, this.angle, this.spin, this.color);

  double x, y, vx, vy;
  final double size;
  double angle;
  double spin;
  final Color color;
  double age = 0;
}

/// Ảnh đốm tròn mềm (trắng ở giữa, trong suốt dần ra mép) dùng chung cho khói,
/// bụi nước, quầng sáng.
ui.Image _softBlob() {
  const size = 64.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(size / 2, size / 2),
        size / 2,
        const [Color(0xffFFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
        const [0, 0.45, 1],
      ),
  );
  return recorder.endRecording().toImageSync(size.toInt(), size.toInt());
}

/// Hiệu ứng sát mặt đất, dưới gầm xe: vệt phanh, mảnh vỡ.
class GroundEffects extends Component {
  GroundEffects() : super(priority: 3);

  final List<_Mark> _marks = [];
  final List<_Shard> _shards = [];

  static const double _markHold = 14;
  static const double _markFade = 10;
  static const int _maxMarks = 700;

  final Paint _markPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _shardPaint = Paint();

  /// Một đoạn vệt lốp từ (x0, y0) tới (x1, y1).
  void skid(double x0, double y0, double x1, double y1, {double width = 3.4, double alpha = 0.3}) {
    if ((x1 - x0).abs() + (y1 - y0).abs() < 0.5) return;
    _marks.add(_Mark(x0, y0, x1, y1, width, alpha));
    if (_marks.length > _maxMarks) _marks.removeRange(0, _marks.length - _maxMarks);
  }

  /// Văng mảnh vỡ (kính đèn, nhựa ốp) quanh chỗ va chạm, theo hướng xe đang lao.
  void shatter(Random random, double x, double y, double vx, double vy, {int count = 14}) {
    const colors = [Color(0xffDDE8EE), Color(0xffB9CED8), Color(0xff2A2C30), Color(0xffC8231B), Color(0xffF0B030)];
    for (var i = 0; i < count; i++) {
      final a = random.nextDouble() * 2 * pi;
      final sp = 30 + random.nextDouble() * 120;
      _shards.add(_Shard(
        x,
        y,
        vx * 0.35 + cos(a) * sp,
        vy * 0.35 + sin(a) * sp,
        1.6 + random.nextDouble() * 2.8,
        random.nextDouble() * pi,
        (random.nextDouble() - 0.5) * 18,
        colors[random.nextInt(colors.length)],
      ));
    }
    if (_shards.length > 120) _shards.removeRange(0, _shards.length - 120);
  }

  @override
  void update(double dt) {
    for (final m in _marks) {
      m.age += dt;
    }
    _marks.removeWhere((m) => m.age > _markHold + _markFade);
    for (final s in _shards) {
      s.age += dt;
      final k = exp(-4 * dt);
      s.vx *= k;
      s.vy *= k;
      s.spin *= k;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.angle += s.spin * dt;
    }
    _shards.removeWhere((s) => s.age > 30);
  }

  @override
  void render(Canvas canvas) {
    for (final m in _marks) {
      final fade = m.age < _markHold ? 1.0 : 1 - (m.age - _markHold) / _markFade;
      _markPaint
        ..strokeWidth = m.width
        ..color = Color.fromRGBO(18, 16, 14, m.alpha * fade);
      canvas.drawLine(Offset(m.x0, m.y0), Offset(m.x1, m.y1), _markPaint);
    }
    for (final s in _shards) {
      final fade = s.age < 24 ? 1.0 : 1 - (s.age - 24) / 6;
      _shardPaint.color = s.color.withValues(alpha: 0.95 * fade);
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(s.angle);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s.size, height: s.size * 0.6), _shardPaint);
      canvas.restore();
    }
  }
}

/// Hiệu ứng lơ lửng trên xe: khói pô, bụi nước, tia lửa, chữ nổi (+1 lì xì).
class AirEffects extends Component {
  AirEffects() : super(priority: 10);

  final List<_Particle> _puffs = [];
  final List<_Particle> _sparks = [];
  final List<_Popup> _popups = [];
  late final ui.Image _blob = _softBlob();

  /// Góc xoay camera — chữ nổi luôn đứng thẳng trên màn hình.
  double cameraAngle = 0;

  final Paint _blobPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _sparkPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  /// Khói pô: xám nhạt, nở to rồi tan.
  void exhaust(Random random, double x, double y, double vx, double vy, {double strength = 1, bool diesel = false}) {
    _puffs.add(_Particle(
      x: x,
      y: y,
      vx: vx + (random.nextDouble() - 0.5) * 14,
      vy: vy + (random.nextDouble() - 0.5) * 14,
      life: (diesel ? 1.4 : 1.0) + random.nextDouble() * 0.6,
      r0: 3,
      r1: (diesel ? 20 : 13) * (0.7 + 0.3 * strength),
      color: diesel ? const Color(0xff2E2F31) : const Color(0xffD2D6DB),
      alpha: (diesel ? 0.5 : 0.42) * strength,
      drag: 2.2,
    ));
    _cap(_puffs, 160);
  }

  /// Bụi nước tung sau bánh xe trên đường ướt.
  void spray(Random random, double x, double y, double vx, double vy, {double strength = 1}) {
    _puffs.add(_Particle(
      x: x + (random.nextDouble() - 0.5) * 6,
      y: y + (random.nextDouble() - 0.5) * 6,
      vx: vx + (random.nextDouble() - 0.5) * 30,
      vy: vy + (random.nextDouble() - 0.5) * 30,
      life: 0.45 + random.nextDouble() * 0.3,
      r0: 3,
      r1: 13,
      color: const Color(0xffE8EEF2),
      alpha: 0.3 * strength,
      drag: 3,
    ));
    _cap(_puffs, 160);
  }

  /// Khói bụi bốc lên khi va chạm / phanh khét lốp.
  void dust(Random random, double x, double y, {int count = 6, Color color = const Color(0xffB8B2A6), double size = 16}) {
    for (var i = 0; i < count; i++) {
      final a = random.nextDouble() * 2 * pi;
      final sp = 10 + random.nextDouble() * 40;
      _puffs.add(_Particle(
        x: x,
        y: y,
        vx: cos(a) * sp,
        vy: sin(a) * sp,
        life: 0.8 + random.nextDouble() * 0.8,
        r0: size * 0.3,
        r1: size * (0.8 + random.nextDouble() * 0.5),
        color: color,
        alpha: 0.4,
        drag: 2.5,
      ));
    }
    _cap(_puffs, 160);
  }

  /// Tia lửa khi thân xe quệt vào mép đường / dải phân cách.
  void sparks(Random random, double x, double y, double vx, double vy, {int count = 3}) {
    for (var i = 0; i < count; i++) {
      final a = random.nextDouble() * 2 * pi;
      final sp = 60 + random.nextDouble() * 160;
      _sparks.add(_Particle(
        x: x,
        y: y,
        vx: vx * 0.6 + cos(a) * sp,
        vy: vy * 0.6 + sin(a) * sp,
        life: 0.18 + random.nextDouble() * 0.22,
        r0: 1.6,
        r1: 0.6,
        color: random.nextBool() ? const Color(0xffFFD27A) : const Color(0xffFF9A3C),
        alpha: 1,
        drag: 3,
      ));
    }
    _cap(_sparks, 120);
  }

  /// Chữ nổi lên rồi mờ dần tại chỗ (x, y): "+1", "−2 lì xì"…
  void popup(double x, double y, String text, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: color,
          shadows: const [Shadow(color: Color(0xcc000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _popups.add(_Popup(x, y, painter));
    if (_popups.length > 8) _popups.removeAt(0);
  }

  static void _cap(List<_Particle> list, int max) {
    if (list.length > max) list.removeRange(0, list.length - max);
  }

  @override
  void update(double dt) {
    for (final p in _puffs) {
      p.step(dt);
    }
    _puffs.removeWhere((p) => p.age >= p.life);
    for (final p in _sparks) {
      p.step(dt);
    }
    _sparks.removeWhere((p) => p.age >= p.life);
    for (final p in _popups) {
      p.age += dt;
    }
    _popups.removeWhere((p) => p.age >= _Popup.life);
  }

  @override
  void render(Canvas canvas) {
    final src = Rect.fromLTWH(0, 0, _blob.width.toDouble(), _blob.height.toDouble());
    for (final p in _puffs) {
      final r = p.radius;
      final fade = pow(1 - p.t, 1.4).toDouble();
      _blobPaint
        ..colorFilter = ColorFilter.mode(p.color, BlendMode.srcIn)
        ..color = Color.fromRGBO(0, 0, 0, (p.alpha * fade).clamp(0.0, 1.0));
      canvas.drawImageRect(_blob, src, Rect.fromCircle(center: Offset(p.x, p.y), radius: r), _blobPaint);
    }
    for (final p in _sparks) {
      final fade = 1 - p.t;
      _sparkPaint
        ..strokeWidth = p.radius
        ..color = p.color.withValues(alpha: fade);
      canvas.drawLine(Offset(p.x, p.y), Offset(p.x - p.vx * 0.04, p.y - p.vy * 0.04), _sparkPaint);
    }
    for (final p in _popups) {
      final t = p.age / _Popup.life;
      final rise = 46 * (1 - pow(1 - t, 2.2).toDouble());
      final alpha = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
      final scale = t < 0.12 ? 0.6 + 0.4 * (t / 0.12) * 1.15 : 1.0;
      canvas.save();
      canvas.translate(p.x, p.y);
      // Chữ đứng thẳng theo màn hình, bay lên phía trên màn hình.
      canvas.rotate(cameraAngle);
      canvas.translate(0, -rise);
      canvas.scale(scale);
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      p.painter.paint(canvas, Offset(-p.painter.width / 2, -p.painter.height / 2));
      canvas.restore();
      canvas.restore();
    }
  }
}

class _Popup {
  _Popup(this.x, this.y, this.painter);

  static const double life = 1.25;

  final double x, y;
  final TextPainter painter;
  double age = 0;
}

/// Pháo hoa giao thừa nhìn từ trên xuống: chùm sao nở tròn, đuôi sáng, quầng
/// sáng hắt xuống mặt đất. Vẽ trên lớp màn đêm (cộng sáng).
class Fireworks extends Component {
  Fireworks() : super(priority: 21);

  final List<_Burst> _bursts = [];
  late final ui.Image _blob = _softBlob();

  final Paint _trail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final Paint _glow = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  static const List<List<Color>> _palettes = [
    [Color(0xffFF3B30), Color(0xffFFD166)],
    [Color(0xffFFD166), Color(0xffFFF3C4)],
    [Color(0xff4ADE80), Color(0xffD9FFE6)],
    [Color(0xffFF5FA2), Color(0xffFFD1E6)],
    [Color(0xff5AC8FA), Color(0xffE3F6FF)],
    [Color(0xffB57BFF), Color(0xffFFD166)],
  ];

  bool get active => _bursts.isNotEmpty;

  /// Bắn một quả pháo nở tại (x, y), bán kính chừng [radius].
  void burst(Random random, double x, double y, {double radius = 120}) {
    final palette = _palettes[random.nextInt(_palettes.length)];
    final n = 34 + random.nextInt(20);
    final rays = [
      for (var i = 0; i < n; i++)
        (
          angle: i * 2 * pi / n + (random.nextDouble() - 0.5) * 0.18,
          reach: radius * (0.75 + random.nextDouble() * 0.35),
          color: random.nextDouble() < 0.7 ? palette[0] : palette[1],
        ),
    ];
    _bursts.add(_Burst(x, y, radius, rays, palette[0], ring: random.nextDouble() < 0.35));
    if (_bursts.length > 10) _bursts.removeAt(0);
  }

  @override
  void update(double dt) {
    for (final b in _bursts) {
      b.age += dt;
    }
    _bursts.removeWhere((b) => b.age >= _Burst.life);
  }

  @override
  void render(Canvas canvas) {
    final src = Rect.fromLTWH(0, 0, _blob.width.toDouble(), _blob.height.toDouble());
    for (final b in _bursts) {
      final t = b.age;
      // Sao bay ra nhanh rồi chậm dần (sức cản không khí).
      double reachAt(double time) => 1 - exp(-4.2 * time);
      final fade = t < 0.15 ? 1.0 : pow(1 - (t - 0.15) / (_Burst.life - 0.15), 1.6).toDouble();
      // Quầng sáng hắt xuống đất: loé lên rồi tắt dần.
      final flash = t < 0.12 ? t / 0.12 : exp(-(t - 0.12) * 2.4);
      _glow.colorFilter = ColorFilter.mode(b.glow, BlendMode.srcIn);
      _glow.color = Color.fromRGBO(0, 0, 0, 0.42 * flash);
      canvas.drawImageRect(_blob, src, Rect.fromCircle(center: Offset(b.x, b.y), radius: b.radius * 1.9), _glow);
      final k1 = reachAt(t);
      final k0 = reachAt(max(0, t - 0.16));
      for (final r in b.rays) {
        final dx = cos(r.angle), dy = sin(r.angle);
        // Sao rơi lả tả cuối đời: lấp lánh.
        final twinkle = t > 1.1 ? (0.55 + 0.45 * sin(t * 40 + r.angle * 7)) : 1.0;
        _trail
          ..strokeWidth = 2.6 - 1.2 * (t / _Burst.life)
          ..color = r.color.withValues(alpha: (fade * twinkle).clamp(0.0, 1.0));
        canvas.drawLine(
          Offset(b.x + dx * r.reach * k0, b.y + dy * r.reach * k0),
          Offset(b.x + dx * r.reach * k1, b.y + dy * r.reach * k1),
          _trail,
        );
        if (b.ring) {
          _trail.strokeWidth = 1.6;
          canvas.drawLine(
            Offset(b.x + dx * r.reach * k1 * 0.55, b.y + dy * r.reach * k1 * 0.55),
            Offset(b.x + dx * r.reach * k1 * 0.6, b.y + dy * r.reach * k1 * 0.6),
            _trail,
          );
        }
      }
      // Lõi loé trắng lúc vừa nổ.
      if (t < 0.25) {
        _glow.colorFilter = const ColorFilter.mode(Color(0xffFFFFFF), BlendMode.srcIn);
        _glow.color = Color.fromRGBO(0, 0, 0, 1 - t / 0.25);
        canvas.drawImageRect(_blob, src, Rect.fromCircle(center: Offset(b.x, b.y), radius: 26), _glow);
      }
    }
  }
}

class _Burst {
  _Burst(this.x, this.y, this.radius, this.rays, this.glow, {required this.ring});

  static const double life = 2.2;

  final double x, y, radius;
  final List<({double angle, double reach, Color color})> rays;
  final Color glow;
  final bool ring;
  double age = 0;
}

/// Một câu thoại đang hiện.
class _Bubble {
  _Bubble(this.anchor, this.name, this.text, this.life, {required this.mine});

  final (double, double) Function() anchor;
  final String name;
  final String text;
  final double life;
  final bool mine;
  double age = 0;
  int _shown = -1;
  TextPainter? _body;
  late final TextPainter _name = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(fontFamily: 'Manrope', fontSize: 10, fontWeight: FontWeight.w800, color: mine ? const Color(0xff2F6FB2) : const Color(0xffC8231B)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static const double maxWidth = 168;

  /// Chữ hiện dần (khoảng 40 ký tự / giây) như đang nói.
  TextPainter get body {
    final n = min(text.length, (age * 40).floor() + 1);
    if (n != _shown || _body == null) {
      _shown = n;
      // Giữ chỗ cho cả câu (phần chưa nói trong suốt) để bong bóng không co giãn.
      _body = TextPainter(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Manrope', fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xff1B1D22), height: 1.25),
          children: [
            TextSpan(text: text.substring(0, n)),
            TextSpan(text: text.substring(n), style: const TextStyle(color: Color(0x00000000))),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
    }
    return _body!;
  }
}

/// Bong bóng thoại phía trên người nói (thợ sửa xe, người bán, chính mình):
/// tên người nói, chữ hiện dần; đứng thẳng theo màn hình, nổi trên màn đêm.
class SpeechLayer extends Component {
  SpeechLayer() : super(priority: 22);

  /// Góc xoay camera — bong bóng luôn đứng thẳng trên màn hình.
  double cameraAngle = 0;

  final Map<String, _Bubble> _bubbles = {};

  static final Paint _fill = Paint();
  static final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = const Color(0xff1B1D22);
  static final Paint _shade = Paint()
    ..color = const Color(0x55000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  /// [who] nói câu [text] (thay câu đang nói dở của chính người đó). [anchor]
  /// trả về chỗ người nói trong thế giới (bám theo khi người đó di chuyển).
  void say(String who, (double, double) Function() anchor, String text, {required String name, bool mine = false, double? seconds}) {
    _bubbles[who] = _Bubble(anchor, name, text, seconds ?? (1.6 + text.length * 0.045), mine: mine);
  }

  void clear() => _bubbles.clear();

  @override
  void update(double dt) {
    for (final b in _bubbles.values) {
      b.age += dt;
    }
    _bubbles.removeWhere((_, b) => b.age >= b.life);
  }

  @override
  void render(Canvas canvas) {
    for (final b in _bubbles.values) {
      final (x, y) = b.anchor();
      final body = b.body;
      final w = max(body.width, b._name.width) + 18;
      final h = body.height + b._name.height + 12;
      final appear = (b.age / 0.16).clamp(0.0, 1.0);
      final fade = ((b.life - b.age) / 0.3).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(cameraAngle);
      // Mọc lên từ đầu người nói: phóng to dần, hơi nảy.
      final scale = 0.7 + 0.3 * Curves.easeOutBack.transform(appear);
      canvas.scale(scale);
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, min(appear * 1.4, 1) * fade));
      const lift = 36.0;
      // Bong bóng của mình chìa sang phải, của người kia sang trái — hai
      // người đứng gần nhau vẫn không đè chữ lên nhau.
      final left = b.mine ? -18.0 : 18 - w;
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, -lift - h, w, h), const Radius.circular(10));
      final tail = Path()
        ..moveTo(-7, -lift - 1)
        ..lineTo(7, -lift - 1)
        ..lineTo(-2, -lift + 11)
        ..close();
      canvas.drawRRect(box.shift(const Offset(0, 3)), _shade);
      _fill.color = b.mine ? const Color(0xffEAF4FF) : const Color(0xffFFFDF6);
      final shape = Path()
        ..addRRect(box)
        ..addPath(tail, Offset.zero);
      canvas.drawPath(shape, _fill);
      canvas.drawRRect(box, _edge);
      canvas.drawLine(const Offset(-7, -lift), const Offset(-2, -lift + 11), _edge);
      canvas.drawLine(const Offset(7, -lift), const Offset(-2, -lift + 11), _edge);
      canvas.drawLine(const Offset(-6.2, -lift), const Offset(6.2, -lift), Paint()
        ..color = _fill.color
        ..strokeWidth = 2.2);
      b._name.paint(canvas, Offset(left + 9, -lift - h + 5));
      body.paint(canvas, Offset(left + 9, -lift - h + 5 + b._name.height + 1));
      canvas.restore();
      canvas.restore();
    }
  }
}
