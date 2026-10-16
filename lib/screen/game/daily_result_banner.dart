import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/daily_service.dart';

/// Điểm viết kiểu Việt Nam: 12.340.
String formatScore(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Bảng kết quả thử thách hôm nay: kỷ lục trong ngày (mới hay cũ) và chuỗi
/// ngày liên tiếp về tới nơi.
class DailyResultBanner extends StatelessWidget {
  const DailyResultBanner({super.key, required this.result});

  final DailyResult result;

  @override
  Widget build(BuildContext context) {
    final fresh = result.newBest;
    return Container(
      padding: EdgeInsets.fromLTRB(12.h, 8.h, 12.h, 8.h),
      decoration: BoxDecoration(
        color: fresh ? AppColors.ffFFD166.withValues(alpha: 0.35) : AppColors.ffF2F3F5,
        borderRadius: BorderRadius.circular(12.h),
        border: fresh ? Border.all(color: AppColors.ffFFB020, width: 1.5.h) : null,
      ),
      child: Row(
        children: [
          Image.asset(Img.icStar, width: 26.h, height: 26.h, color: fresh ? AppColors.ffFFB020 : AppColors.ffB8BCC4),
          SizedBox(width: 10.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope(
                  fresh ? 'KỶ LỤC HÔM NAY · MỚI!' : 'KỶ LỤC HÔM NAY',
                  fontSize: 10.h,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.h,
                  color: fresh ? AppColors.ffB4231E : AppColors.ff6B7280,
                ),
                AppText.manrope(
                  result.best > 0 ? '${formatScore(result.best)} điểm' : 'Chưa có — về tới nơi mới tính điểm',
                  fontSize: result.best > 0 ? 17.h : 12.h,
                  fontWeight: FontWeight.w800,
                  maxLines: 1,
                  color: AppColors.ff1B1D22,
                ),
              ],
            ),
          ),
          if (result.streak > 0) ...[
            SizedBox(width: 8.h),
            StreakBadge(days: result.streak),
          ],
        ],
      ),
    );
  }
}

/// Ngọn lửa nhỏ + số ngày liên tiếp.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.days, this.dark = false});

  final int days;

  /// Nền tối (thẻ ở màn chính) thì chữ sáng.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(6.h, 3.h, 8.h, 3.h),
      decoration: BoxDecoration(
        color: dark ? AppColors.ff1B1D22.withValues(alpha: 0.35) : AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(10.h),
        border: Border.all(color: AppColors.ffFF6B3D.withValues(alpha: 0.7), width: 1.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 12.h, height: 15.h, child: const CustomPaint(painter: _FlamePainter())),
          SizedBox(width: 4.h),
          AppText.manrope(
            '$days ngày',
            fontSize: 11.h,
            fontWeight: FontWeight.w800,
            color: dark ? AppColors.ffFFE3A1 : AppColors.ffB4231E,
          ),
        ],
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Path flame(double k) => Path()
      ..moveTo(w * 0.5, h * (1 - 0.98 * k))
      ..cubicTo(w * (0.5 + 0.55 * k), h * (1 - 0.6 * k), w * (0.5 + 0.5 * k), h, w * 0.5, h)
      ..cubicTo(w * (0.5 - 0.5 * k), h, w * (0.5 - 0.55 * k), h * (1 - 0.5 * k), w * 0.5, h * (1 - 0.98 * k))
      ..close();
    canvas.drawPath(flame(1), Paint()..color = AppColors.ffFF6B3D);
    canvas.drawPath(flame(0.55), Paint()..color = AppColors.ffFFD166);
  }

  @override
  bool shouldRepaint(covariant _FlamePainter oldDelegate) => false;
}
