import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../game/logic/radio_bulletin.dart';
import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_text.dart';
import 'road_icons.dart';

/// Bản tin "Radio Giao thông" giữa phía trên màn hình: khung xanh đêm, đài
/// radio vẽ tay trên nền vàng, tên đài và mục bản tin, đèn đỏ đang phát,
/// cột sóng nhạc nhún nhảy.
class RadioNoticeBanner extends StatelessWidget {
  const RadioNoticeBanner({super.key, required this.notice});

  final GameNotice notice;

  @override
  Widget build(BuildContext context) {
    final value = notice;
    final segment = value is RadioBulletin ? value.segment.label : 'BẢN TIN';
    return Container(
      constraints: BoxConstraints(maxWidth: 560.h),
      padding: EdgeInsets.fromLTRB(7.h, 7.h, 16.h, 8.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ff243A6B, AppColors.ff16213E],
        ),
        borderRadius: BorderRadius.circular(16.h),
        border: Border.all(color: AppColors.ff4A6BB0.withValues(alpha: 0.85), width: 1.5.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.35), blurRadius: 12.h, offset: Offset(0, 4.h))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.h,
            height: 40.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.ffFFD166, AppColors.ffFFB020],
              ),
              borderRadius: BorderRadius.circular(11.h),
            ),
            child: RoadIcon(RoadGlyph.radio, size: 27.h, color: AppColors.ff16213E, accent: AppColors.ffFFD166),
          ),
          SizedBox(width: 10.h),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7.h,
                      height: 7.h,
                      decoration: BoxDecoration(
                        color: AppColors.ffFF5A5F,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.ffFF5A5F.withValues(alpha: 0.7), blurRadius: 5.h)],
                      ),
                    ),
                    SizedBox(width: 6.h),
                    Flexible(
                      child: AppText.manrope('RADIO GIAO THÔNG', fontSize: 10.h, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.ffFFD166),
                    ),
                    SizedBox(width: 6.h),
                    Flexible(
                      child: AppText.manrope('· $segment', fontSize: 10.h, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.ffB7C6E8),
                    ),
                    SizedBox(width: 8.h),
                    SizedBox(width: 18.h, height: 11.h, child: const _OnAirBars()),
                  ],
                ),
                SizedBox(height: 3.h),
                AppText.manrope(
                  notice.text,
                  fontSize: 13.h,
                  fontWeight: FontWeight.w700,
                  // Khung hẹp (đang có thẻ cuộc gọi bên trái) thì xuống dòng thứ ba.
                  maxLines: 3,
                  lineHeight: 1.3,
                  color: AppColors.ffFFFFFF,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bốn cột sóng nhạc nhún lên xuống (đài đang phát).
class _OnAirBars extends StatefulWidget {
  const _OnAirBars();

  @override
  State<_OnAirBars> createState() => _OnAirBarsState();
}

class _OnAirBarsState extends State<_OnAirBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _BarsPainter(_c.value)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ffB7C6E8;
    const count = 4;
    final w = size.width / (count * 1.6);
    for (var i = 0; i < count; i++) {
      final level = 0.3 + 0.7 * (0.5 + 0.5 * sin(2 * pi * t * (1 + i % 3) + i * 1.7));
      final h = size.height * level;
      final x = i * w * 1.6;
      canvas.drawRRect(RRect.fromLTRBR(x, size.height - h, x + w, size.height, Radius.circular(w / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) => oldDelegate.t != t;
}
