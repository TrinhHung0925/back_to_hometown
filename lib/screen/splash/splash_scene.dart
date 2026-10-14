import 'dart:math';

import 'package:flutter/material.dart';

import '../../resource/app_colors.dart';

/// Đường chân trời (tỉ lệ chiều cao) và điểm tụ của con đường về làng.
const double _horizon = 0.62;
const double _vanishX = 0.72;

/// Cảnh tĩnh của màn splash: chiều cuối năm, mặt trời lặn sau cổng làng,
/// con đường uốn lượn từ chân màn hình về làng, cành đào góc trên.
class SplashScenePainter extends CustomPainter {
  const SplashScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizonY = h * _horizon;
    _sky(canvas, w, h, horizonY);
    _sun(canvas, w, h, horizonY);
    _mountains(canvas, w, h, horizonY);
    _ground(canvas, w, h, horizonY);
    _road(canvas, w, h, horizonY);
    _village(canvas, w, h, horizonY);
    _peachBranch(canvas, w, h);
  }

  void _sky(Canvas canvas, double w, double h, double horizonY) {
    final rect = Rect.fromLTWH(0, 0, w, horizonY + 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [AppColors.ff4A0716, AppColors.ff8E1428, AppColors.ffD9452B, AppColors.ffF7A440],
          stops: const [0, 0.42, 0.78, 1],
        ).createShader(rect),
    );
  }

  void _sun(Canvas canvas, double w, double h, double horizonY) {
    final c = Offset(w * _vanishX, horizonY - h * 0.05);
    canvas.drawCircle(
      c,
      h * 0.62,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.ffFFE3A1.withValues(alpha: 0.75),
          AppColors.ffFFB55E.withValues(alpha: 0.28),
          AppColors.ffFFB55E.withValues(alpha: 0),
        ], stops: const [0, 0.32, 1]).createShader(Rect.fromCircle(center: c, radius: h * 0.62)),
    );
    canvas.drawCircle(c, h * 0.105, Paint()..color = AppColors.ffFFE3A1);
  }

  void _mountains(Canvas canvas, double w, double h, double horizonY) {
    Path ridge(double Function(double u) height) {
      final path = Path()..moveTo(0, horizonY + 1);
      for (var x = 0.0; x <= w + 4; x += 4) {
        path.lineTo(x, horizonY - h * height(x / w));
      }
      return path
        ..lineTo(w, horizonY + 1)
        ..close();
    }

    canvas.drawPath(
      ridge((u) => 0.14 + 0.05 * sin(u * 6 + 0.7) + 0.035 * sin(u * 15 + 2.1) + 0.015 * sin(u * 37 + 0.3)),
      Paint()..color = AppColors.ffC2412F.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      ridge((u) => 0.06 + 0.03 * sin(u * 4.2 + 2) + 0.018 * sin(u * 11 + 0.4) + 0.008 * sin(u * 29)),
      Paint()..color = AppColors.ff8E2233.withValues(alpha: 0.9),
    );
    // Hàng cây lô nhô ở chân trời (chừa chỗ cho làng).
    final trees = Paint()..color = AppColors.ff5E1626;
    final r = Random(7);
    for (var x = 0.0; x < w; x += h * 0.035) {
      final rad = h * (0.012 + r.nextDouble() * 0.018);
      if ((x - w * _vanishX).abs() < w * 0.13) continue;
      canvas.drawCircle(Offset(x + r.nextDouble() * 6, horizonY - rad * 0.35), rad, trees);
    }
  }

  void _ground(Canvas canvas, double w, double h, double horizonY) {
    final rect = Rect.fromLTWH(0, horizonY, w, h - horizonY);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff5E1626, AppColors.ff1F070D],
        ).createShader(rect),
    );
    // Luống ruộng chụm về điểm tụ.
    final rows = Paint()
      ..color = AppColors.ffFFFFFF.withValues(alpha: 0.045)
      ..strokeWidth = 1.2;
    final vp = Offset(w * _vanishX, horizonY);
    for (var i = -14; i <= 14; i++) {
      canvas.drawLine(vp, Offset(vp.dx + i * w * 0.16, h), rows);
    }
    for (var k = 1; k < 7; k++) {
      final y = horizonY + (h - horizonY) * pow(k / 7, 2.2);
      canvas.drawLine(Offset(0, y), Offset(w, y), rows);
    }
  }

  /// Tim đường và bề rộng theo t (0 = chân màn hình, 1 = chân trời): thu nhỏ
  /// theo phối cảnh, uốn trái phải như khúc cua trong game.
  (Offset, double) _roadAt(double t, double w, double h, double horizonY) {
    final k = pow(1 - t, 2).toDouble();
    final y = horizonY + (h * 1.04 - horizonY) * k;
    final lateral = (w * 0.47 - w * _vanishX) + w * 0.3 * sin(t * pi * 2.3 + 0.4);
    return (Offset(w * _vanishX + lateral * k, y), w * 0.17 * k + h * 0.006);
  }

  void _road(Canvas canvas, double w, double h, double horizonY) {
    const n = 90;
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final (c, hw) = _roadAt(i / n, w, h, horizonY);
      left.add(c - Offset(hw, 0));
      right.add(c + Offset(hw, 0));
    }
    final bounds = Rect.fromLTRB(0, horizonY, w, h);
    canvas.drawPath(
      Path()..addPolygon([...left, ...right.reversed], true),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.ff3A2B31, AppColors.ff8A4F48],
        ).createShader(bounds),
    );
    final edge = Paint()
      ..color = AppColors.ffF4E3C9.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(Path()..addPolygon(left, false), edge);
    canvas.drawPath(Path()..addPolygon(right, false), edge);
    // Vạch giữa đứt đoạn, nhỏ dần về xa.
    final dash = Paint()..color = AppColors.ffFFD166.withValues(alpha: 0.85);
    for (var i = 0; i < 26; i++) {
      final t0 = i / 26, t1 = t0 + 0.45 / 26;
      final (a, wa) = _roadAt(t0, w, h, horizonY);
      final (b, wb) = _roadAt(t1, w, h, horizonY);
      final ta = wa * 0.035, tb = wb * 0.035;
      canvas.drawPath(
        Path()..addPolygon([a - Offset(ta, 0), b - Offset(tb, 0), b + Offset(tb, 0), a + Offset(ta, 0)], true),
        dash,
      );
    }
  }

  /// Cổng làng ở cuối đường, nhà mái cong, cau cao, cửa sổ sáng đèn.
  void _village(Canvas canvas, double w, double h, double horizonY) {
    final dark = Paint()..color = AppColors.ff2E0A12;
    final glow = Paint()
      ..color = AppColors.ffFFD166
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final window = Paint()..color = AppColors.ffFFD166;
    final cx = w * _vanishX;
    final u = h * 0.01;

    // Cau: thân mảnh, tàu lá xoè.
    final trunk = Paint()
      ..color = AppColors.ff2E0A12
      ..strokeWidth = u * 0.5
      ..strokeCap = StrokeCap.round;
    for (final (dx, tall) in [(-11.5, 7.5), (-9.8, 6.2), (9.6, 7.8), (12.2, 6.0)]) {
      final base = Offset(cx + dx * u, horizonY);
      final top = base - Offset(-u * 0.4, tall * u);
      canvas.drawLine(base, top, trunk);
      for (var k = 0; k < 7; k++) {
        final a = -pi / 2 + (k - 3) * 0.48;
        final tip = top + Offset(cos(a) * u * 2.6, sin(a) * u * 1.6 + u * 1.1);
        canvas.drawLine(top, tip, trunk..strokeWidth = u * 0.35);
      }
      trunk.strokeWidth = u * 0.5;
    }

    // Nhà hai bên cổng.
    for (final (dx, bw, bh) in [(-8.0, 3.6, 2.2), (-4.6, 2.6, 1.7), (5.0, 3.0, 2.0), (8.6, 3.8, 2.4)]) {
      final x = cx + dx * u;
      final body = Rect.fromLTWH(x - bw * u / 2, horizonY - bh * u, bw * u, bh * u);
      canvas.drawRect(body, dark);
      final roof = Path()
        ..moveTo(body.left - u * 0.7, body.top + u * 0.2)
        ..quadraticBezierTo(body.left, body.top - u * 0.2, body.left + u * 0.5, body.top - u * 1.2)
        ..lineTo(body.right - u * 0.5, body.top - u * 1.2)
        ..quadraticBezierTo(body.right, body.top - u * 0.2, body.right + u * 0.7, body.top + u * 0.2)
        ..close();
      canvas.drawPath(roof, dark);
      final win = Rect.fromCenter(center: Offset(x, horizonY - bh * u * 0.5), width: u * 0.7, height: u * 0.6);
      canvas.drawRect(win.inflate(u * 0.3), glow);
      canvas.drawRect(win, window);
    }

    // Cổng làng: hai trụ, mái cong hai tầng, lối vào giữa.
    final gw = u * 4.6, gh = u * 4.4;
    for (final side in [-1.0, 1.0]) {
      canvas.drawRect(Rect.fromLTWH(cx + side * gw / 2 - u * 0.6, horizonY - gh, u * 1.2, gh), dark);
    }
    canvas.drawRect(Rect.fromLTWH(cx - gw / 2, horizonY - gh, gw, u * 1.2), dark);
    for (final (y, half) in [(horizonY - gh, gw * 0.7), (horizonY - gh - u * 1.3, gw * 0.48)]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - half - u, y + u * 0.2)
          ..quadraticBezierTo(cx - half, y - u * 0.3, cx - half + u * 0.6, y - u * 1.1)
          ..lineTo(cx + half - u * 0.6, y - u * 1.1)
          ..quadraticBezierTo(cx + half, y - u * 0.3, cx + half + u, y + u * 0.2)
          ..close(),
        dark,
      );
    }
  }

  void _peachBranch(Canvas canvas, double w, double h) {
    final u = h / 100;
    final main = Path()
      ..moveTo(-2 * u, 19 * u)
      ..cubicTo(8 * u, 13 * u, 15 * u, 12 * u, 24 * u, 8 * u)
      ..cubicTo(32 * u, 4.5 * u, 40 * u, 4 * u, 52 * u, 1.5 * u);
    final subA = Path()
      ..moveTo(18 * u, 10.5 * u)
      ..quadraticBezierTo(24 * u, 14 * u, 31 * u, 19 * u);
    final subB = Path()
      ..moveTo(34 * u, 4.4 * u)
      ..quadraticBezierTo(39 * u, 9 * u, 46 * u, 10 * u);
    final subC = Path()
      ..moveTo(8 * u, 14.5 * u)
      ..quadraticBezierTo(10 * u, 7 * u, 15 * u, 2 * u);
    final bark = Paint()
      ..color = AppColors.ff4A2C21
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..color = AppColors.ff7A4A35.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(main, bark..strokeWidth = 2.6 * u);
    canvas.drawPath(main.shift(Offset(-0.4 * u, -0.5 * u)), shine..strokeWidth = 0.8 * u);
    for (final p in [subA, subB, subC]) {
      canvas.drawPath(p, bark..strokeWidth = 1.3 * u);
    }

    final r = Random(3);
    void bloom(Path path, int count, double size) {
      for (final metric in path.computeMetrics()) {
        for (var i = 0; i < count; i++) {
          final at = metric.length * (0.12 + 0.86 * i / max(1, count - 1));
          final tangent = metric.getTangentForOffset(at)!;
          final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
          final side = i.isEven ? 1.0 : -1.0;
          final p = tangent.position + normal * side * size * u * (0.6 + r.nextDouble() * 0.5);
          if (r.nextDouble() < 0.22) {
            _bud(canvas, p, size * 0.45 * u, r.nextDouble() * pi);
          } else {
            _flower(canvas, p, size * u * (0.8 + r.nextDouble() * 0.35), r.nextDouble() * pi);
          }
        }
      }
    }

    bloom(main, 9, 3.2);
    bloom(subA, 4, 2.7);
    bloom(subB, 4, 2.7);
    bloom(subC, 3, 2.5);
  }

  static void _flower(Canvas canvas, Offset c, double r, double rotation) {
    final petal = Paint()
      ..shader = const RadialGradient(colors: [AppColors.ffFFD3DE, AppColors.ffF7A8BC], stops: [0.25, 1])
          .createShader(Rect.fromCircle(center: c, radius: r * 1.2));
    for (var i = 0; i < 5; i++) {
      final a = rotation + i * 2 * pi / 5;
      canvas.save();
      canvas.translate(c.dx + cos(a) * r * 0.52, c.dy + sin(a) * r * 0.52);
      canvas.rotate(a);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 1.1, height: r * 0.92), petal);
      canvas.restore();
    }
    canvas.drawCircle(c, r * 0.24, Paint()..color = AppColors.ffD94A72);
    final stamen = Paint()..color = AppColors.ffFFD166;
    for (var i = 0; i < 6; i++) {
      final a = rotation + i * pi / 3;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * r * 0.36, r * 0.07, stamen);
    }
  }

  static void _bud(Canvas canvas, Offset c, double r, double rotation) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 1.5, height: r * 2.1), Paint()..color = AppColors.ffE8768F);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SplashScenePainter oldDelegate) => false;
}

/// Lớp chuyển động: đèn lồng đung đưa, pháo hoa nổ trên trời, cánh đào rơi.
class SplashFestivePainter extends CustomPainter {
  SplashFestivePainter(this.time) : super(repaint: time);

  /// Số giây kể từ lúc mở màn.
  final ValueNotifier<double> time;

  static const List<Color> _fireworks = [
    AppColors.ffFFD166,
    AppColors.ffFF8FAB,
    AppColors.ffFFF4D6,
    AppColors.ffFF6B3D,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    _fireworksAt(canvas, t, w, h);
    _lantern(canvas, t, Offset(w * 0.86, 0), h * 0.17, h * 0.13, 0);
    _lantern(canvas, t, Offset(w * 0.95, 0), h * 0.08, h * 0.105, 1.9);
    _petals(canvas, t, w, h);
  }

  void _fireworksAt(Canvas canvas, double t, double w, double h) {
    const period = 1.15, life = 1.6, rise = 0.5;
    final horizonY = h * _horizon;
    final now = (t / period).floor();
    for (var i = now - 2; i <= now + 1; i++) {
      if (i < 0) continue;
      final r = Random(i * 7919 + 13);
      final burstAt = i * period + 0.6;
      final cx = w * (0.36 + r.nextDouble() * 0.42);
      final cy = h * (0.08 + r.nextDouble() * 0.24);
      final color = _fireworks[i % _fireworks.length];
      final spark = Paint()
        ..blendMode = BlendMode.plus
        ..strokeCap = StrokeCap.round;

      // Pháo bay lên trước khi nổ.
      final pr = (t - (burstAt - rise)) / rise;
      if (pr >= 0 && pr < 1) {
        final y = horizonY + (cy - horizonY) * Curves.easeOut.transform(pr);
        spark
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = h * 0.006;
        canvas.drawLine(Offset(cx, y), Offset(cx, y + h * 0.05), spark..color = color.withValues(alpha: 0.35));
        canvas.drawCircle(Offset(cx, y), h * 0.006, spark..color = color);
      }

      final p = (t - burstAt) / life;
      if (p < 0 || p >= 1) continue;
      final radius = h * (0.1 + r.nextDouble() * 0.07);
      final spread = 1 - pow(1 - p, 3).toDouble();
      final alpha = pow(1 - p, 1.4).toDouble();
      final fall = h * 0.06 * p * p;
      final n = 26 + r.nextInt(10);
      spark.strokeWidth = h * 0.006 * (1 - p * 0.5);
      for (var k = 0; k < n; k++) {
        final a = k * 2 * pi / n + r.nextDouble() * 0.12;
        final dist = radius * spread * (0.82 + r.nextDouble() * 0.18);
        final dir = Offset(cos(a), sin(a));
        final head = Offset(cx, cy + fall) + dir * dist;
        final tail = Offset(cx, cy + fall * 0.8) + dir * dist * 0.72;
        canvas.drawLine(tail, head, spark..color = color.withValues(alpha: alpha * 0.55));
        canvas.drawCircle(head, h * 0.0045, spark..color = color.withValues(alpha: alpha));
      }
      if (p < 0.12) {
        canvas.drawCircle(Offset(cx, cy), h * 0.035, spark..color = AppColors.ffFFF4D6.withValues(alpha: 1 - p / 0.12));
      }
    }
  }

  void _lantern(Canvas canvas, double t, Offset anchor, double string, double size, double phase) {
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(0.07 * sin(t * 1.5 + phase));
    final w = size * 0.95, hgt = size;
    final cy = string + size * 0.08 + hgt / 2;
    canvas.drawCircle(
      Offset(0, cy),
      size * 1.25,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.ffFF7A59.withValues(alpha: 0.35),
          AppColors.ffFF7A59.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(0, cy), radius: size * 1.25)),
    );
    canvas.drawLine(Offset.zero, Offset(0, string), Paint()
      ..color = AppColors.ff4A2C21
      ..strokeWidth = size * 0.03);
    final gold = Paint()..color = AppColors.ffFFD166;
    final cap = Rect.fromCenter(center: Offset(0, string + size * 0.05), width: w * 0.5, height: size * 0.1);
    canvas.drawRRect(RRect.fromRectAndRadius(cap, Radius.circular(size * 0.03)), gold);
    final body = Rect.fromCenter(center: Offset(0, cy), width: w, height: hgt * 0.92);
    canvas.drawOval(
      body,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [AppColors.ffFF5A4E, AppColors.ffC1121F, AppColors.ff7F0A14],
          stops: [0, 0.6, 1],
        ).createShader(body),
    );
    final rib = Paint()
      ..color = AppColors.ff7F0A14.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.025;
    for (final f in [0.32, 0.66]) {
      canvas.drawOval(Rect.fromCenter(center: body.center, width: w * f, height: body.height), rib);
    }
    canvas.drawLine(body.topCenter, body.bottomCenter, rib);
    final bottom = Rect.fromCenter(center: Offset(0, body.bottom + size * 0.02), width: w * 0.42, height: size * 0.09);
    canvas.drawRRect(RRect.fromRectAndRadius(bottom, Radius.circular(size * 0.03)), gold);
    final tassel = Paint()
      ..color = AppColors.ffF2C12E
      ..strokeWidth = size * 0.025;
    for (var k = -2; k <= 2; k++) {
      final x = k * size * 0.035;
      canvas.drawLine(Offset(x, bottom.bottom), Offset(x * 1.4, bottom.bottom + size * 0.32), tassel);
    }
    canvas.restore();
  }

  void _petals(Canvas canvas, double t, double w, double h) {
    final pink = Paint()..color = AppColors.ffF7A8BC.withValues(alpha: 0.9);
    final light = Paint()..color = AppColors.ffFFD3DE.withValues(alpha: 0.9);
    for (var i = 0; i < 26; i++) {
      final r = Random(i * 31 + 7);
      final speed = h * (0.07 + r.nextDouble() * 0.08);
      final span = h * 1.2;
      final y = (t * speed + r.nextDouble() * span) % span - h * 0.1;
      final x0 = r.nextDouble() * (w + 40);
      final phase = r.nextDouble() * pi * 2;
      final x = (x0 + t * w * 0.025 + sin(t * (0.8 + r.nextDouble()) + phase) * h * 0.05) % (w + 40) - 20;
      final s = h * (0.009 + r.nextDouble() * 0.008);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (1 + r.nextDouble() * 2) + phase);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 1.7, height: s), i.isEven ? pink : light);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SplashFestivePainter oldDelegate) => oldDelegate.time != time;
}
