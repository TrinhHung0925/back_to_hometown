import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_text.dart';

/// Đồng hồ tốc độ kiểu công-tơ-mét xe máy: mặt kính tối, vạch chia, kim đỏ,
/// số điện tử ở giữa. Vạch hổ phách ngoài vành là mức ga đang giữ (buông tay
/// xe tự giữ tốc độ này); có chốt CSGT phía trước thì phần quá tốc độ cho
/// phép tô đỏ.
class Speedometer extends StatelessWidget {
  const Speedometer({
    super.key,
    required this.speedKmh,
    required this.cruiseKmh,
    required this.maxKmh,
    this.limitKmh,
  });

  final int speedKmh;
  final int cruiseKmh;

  /// Tốc độ tối đa của xe — mặt đồng hồ chia tới bội số 10 kế tiếp.
  final double maxKmh;

  /// Biển hạn chế tốc độ ở chốt phía trước (null nếu không có).
  final int? limitKmh;

  static double get width => 108.h;
  static double get height => 92.h;

  @override
  Widget build(BuildContext context) {
    final scaleMax = (maxKmh / 10).ceil() * 10.0;
    final over = limitKmh != null && speedKmh > limitKmh!;
    return SizedBox(
      width: width,
      height: height,
      child: TweenAnimationBuilder<double>(
        // Kim lướt mềm giữa hai lần HUD cập nhật.
        tween: Tween(end: speedKmh.toDouble()),
        duration: const Duration(milliseconds: 140),
        builder: (context, needle, _) => CustomPaint(
          painter: _GaugePainter(
            needle: needle,
            cruise: cruiseKmh.toDouble(),
            scaleMax: scaleMax,
            limit: limitKmh?.toDouble(),
            unit: 1.h,
          ),
          child: Align(
            alignment: const Alignment(0, 0.78),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText.manrope(
                  '$speedKmh',
                  fontSize: 21.h,
                  fontWeight: FontWeight.w800,
                  lineHeight: 1,
                  color: over ? AppColors.ffFF5A4E : AppColors.ffFFFFFF,
                  shadow: const [Shadow(color: AppColors.shadowSoft, blurRadius: 4)],
                ),
                AppText.manrope('km/h', fontSize: 8.h, fontWeight: FontWeight.w700, lineHeight: 1.1, color: AppColors.ffB8BCC4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.needle, required this.cruise, required this.scaleMax, required this.limit, required this.unit});

  final double needle;
  final double cruise;
  final double scaleMax;
  final double? limit;
  final double unit;

  /// Mặt đồng hồ quét 240° từ dưới-trái qua đỉnh xuống dưới-phải.
  static const double _start = 150 * pi / 180;
  static const double _sweep = 240 * pi / 180;

  double _angle(double kmh) => _start + _sweep * (kmh / scaleMax).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final u = unit;
    final r = size.width / 2 - 9 * u;
    final c = Offset(size.width / 2, 9 * u + r);

    // Vỏ đồng hồ: nửa trên tròn, đáy bo — kính tối, viền sáng mảnh.
    final pod = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: Radius.circular(size.width / 2),
      topRight: Radius.circular(size.width / 2),
      bottomLeft: Radius.circular(18 * u),
      bottomRight: Radius.circular(18 * u),
    );
    canvas.drawRRect(
      pod.shift(Offset(0, 2 * u)),
      Paint()
        ..color = AppColors.shadowSoft
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * u),
    );
    canvas.drawRRect(
      pod,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff2B3038.withValues(alpha: 0.9), AppColors.ff121418.withValues(alpha: 0.92)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      pod.deflate(0.75 * u),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * u
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ffFFFFFF.withValues(alpha: 0.28), AppColors.ffFFFFFF.withValues(alpha: 0.04)],
        ).createShader(Offset.zero & size),
    );

    final arcRect = Rect.fromCircle(center: c, radius: r);
    // Rãnh vành.
    canvas.drawArc(
      arcRect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * u
        ..color = AppColors.ffFFFFFF.withValues(alpha: 0.1),
    );

    // Quá tốc độ cho phép ở chốt phía trước: tô đỏ phần vượt.
    final lim = limit;
    if (lim != null && lim < scaleMax) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2.5 * u),
        _angle(lim),
        _sweep * (1 - lim / scaleMax),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * u
          ..color = AppColors.ffD62828.withValues(alpha: 0.85),
      );
    }

    // Mức ga đang giữ: cung hổ phách sát ngoài vành + mũi tam giác.
    if (cruise > 0.5) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 4 * u),
        _start,
        _angle(cruise) - _start,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 * u
          ..strokeCap = StrokeCap.round
          ..color = AppColors.ffFFB020.withValues(alpha: 0.9),
      );
      final a = _angle(cruise);
      final dirOut = Offset(cos(a), sin(a));
      final side = Offset(-dirOut.dy, dirOut.dx);
      final tip = c + dirOut * (r + 1.5 * u);
      final base = c + dirOut * (r + 8.5 * u);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + side.dx * 4 * u, base.dy + side.dy * 4 * u)
          ..lineTo(base.dx - side.dx * 4 * u, base.dy - side.dy * 4 * u)
          ..close(),
        Paint()..color = AppColors.ffFFB020,
      );
    }

    // Vạch chia: 5 km/h một vạch nhỏ, 10 vạch vừa, số mỗi 20.
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var v = 0; v <= scaleMax; v += 5) {
      final a = _angle(v.toDouble());
      final d = Offset(cos(a), sin(a));
      final major = v % 10 == 0;
      final over = lim != null && v > lim;
      tick
        ..strokeWidth = (major ? 2 : 1.2) * u
        ..color = over
            ? AppColors.ffFF8A80.withValues(alpha: major ? 1 : 0.8)
            : AppColors.ffFFFFFF.withValues(alpha: major ? 0.9 : 0.45);
      canvas.drawLine(c + d * (r - (major ? 7.5 : 4.5) * u), c + d * (r - 1 * u), tick);
      if (v % 20 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: '$v',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 8 * u,
              fontWeight: FontWeight.w700,
              color: AppColors.ffFFFFFF.withValues(alpha: 0.72),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final at = c + d * (r - 15 * u);
        label.paint(canvas, at - Offset(label.width / 2, label.height / 2));
      }
    }

    // Kim: thon dần, đỏ cam phát sáng, đuôi ngắn.
    final a = _angle(needle);
    final d = Offset(cos(a), sin(a));
    final n = Offset(-d.dy, d.dx);
    final tip = c + d * (r - 3 * u);
    final tail = c - d * 7 * u;
    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(c.dx + n.dx * 2.4 * u, c.dy + n.dy * 2.4 * u)
      ..lineTo(tail.dx + n.dx * 1.4 * u, tail.dy + n.dy * 1.4 * u)
      ..lineTo(tail.dx - n.dx * 1.4 * u, tail.dy - n.dy * 1.4 * u)
      ..lineTo(c.dx - n.dx * 2.4 * u, c.dy - n.dy * 2.4 * u)
      ..close();
    canvas.drawPath(
      needlePath,
      Paint()
        ..color = AppColors.ffFF5A4E.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * u),
    );
    canvas.drawPath(needlePath, Paint()..color = AppColors.ffFF5A4E);
    canvas.drawCircle(c, 5 * u, Paint()..color = AppColors.ff1B1D22);
    canvas.drawCircle(
      c,
      5 * u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * u
        ..color = AppColors.ffB8BCC4,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.needle != needle || old.cruise != cruise || old.scaleMax != scaleMax || old.limit != limit || old.unit != unit;
}

/// Chỉ cách dùng ga giữ mức (hiện một lần, lần đầu vào chơi): thẻ nhỏ cạnh
/// cụm nút ga/phanh.
class CruiseTip extends StatelessWidget {
  const CruiseTip({super.key, required this.assist});

  /// Đang bật hỗ trợ lái (thêm dòng chỉ cách thả cần lái).
  final bool assist;

  @override
  Widget build(BuildContext context) {
    Widget row(String key, Color color, String text) => Padding(
          padding: EdgeInsets.only(top: 5.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70.h,
                padding: EdgeInsets.symmetric(vertical: 2.h),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6.h)),
                child: AppText.manrope(key, fontSize: 9.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
              ),
              SizedBox(width: 8.h),
              AppText.manrope(text, fontSize: 11.5.h, fontWeight: FontWeight.w700, color: AppColors.ffFFFFFF),
            ],
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(12.h, 9.h, 14.h, 10.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14.h),
        border: Border.all(color: AppColors.ffFFB020.withValues(alpha: 0.85), width: 1.5.h),
        boxShadow: [BoxShadow(color: AppColors.shadowSoft, blurRadius: 10.h)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.manrope('Cách lái', fontSize: 13.h, fontWeight: FontWeight.w800, color: AppColors.ffFFB020),
          row('CHẠM GA', AppColors.ff4ADE80, '+5 km/h · giữ Ga: tăng tốc dần'),
          row('BUÔNG GA', AppColors.ffE3E5E9, 'xe tự giữ tốc độ đã đặt'),
          row('CHẠM PHANH', AppColors.ffFFB020, '−5 km/h · giữ Phanh: phanh mạnh dần'),
          if (assist) row('THẢ CẦN LÁI', AppColors.ff7FB2E5, 'xe tự về giữa làn, tự chậm khi vào cua'),
        ],
      ),
    );
  }
}

/// Mức ga đang đặt ("Giữ 50 km/h") ngay trên đồng hồ; hỗ trợ lái đang tự
/// giảm tốc thì ghi thêm vì sao.
class CruiseChip extends StatelessWidget {
  const CruiseChip({super.key, required this.cruiseKmh, required this.assist});

  final int cruiseKmh;
  final AssistState assist;

  @override
  Widget build(BuildContext context) {
    final note = switch (assist) {
      AssistState.none => null,
      AssistState.following => 'bám xe trước',
      AssistState.curve => 'chậm vào cua',
    };
    return Container(
      padding: EdgeInsets.fromLTRB(9.h, 3.h, 9.h, 3.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10.h),
        border: Border.all(color: AppColors.ffFFB020.withValues(alpha: 0.7), width: 1.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.manrope('Giữ ', fontSize: 10.5.h, fontWeight: FontWeight.w700, color: AppColors.ffB8BCC4),
          AppText.manrope('$cruiseKmh', fontSize: 13.h, fontWeight: FontWeight.w800, color: AppColors.ffFFB020),
          AppText.manrope(' km/h', fontSize: 10.5.h, fontWeight: FontWeight.w700, color: AppColors.ffB8BCC4),
          if (note != null) ...[
            Container(width: 1.h, height: 12.h, margin: EdgeInsets.symmetric(horizontal: 6.h), color: AppColors.ffFFFFFF.withValues(alpha: 0.25)),
            AppText.manrope(note, fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ff7FB2E5),
          ],
        ],
      ),
    );
  }
}

/// Nút "i" nhỏ góc trên bên trái: chạm thì hiện thẻ [CruiseTip], vài giây sau tự ẩn.
class CruiseTipButton extends StatelessWidget {
  const CruiseTipButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        width: 28.h,
        height: 28.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.ffFFB020.withValues(alpha: 0.85), width: 1.5.h),
        ),
        child: AppText.manrope('i', fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ffFFB020),
      ),
    );
  }
}
