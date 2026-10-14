import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../resource/app_colors.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';

/// Nút chữ dùng ở menu và các bảng (không phải nút lái xe).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.ffD62828,
    this.textColor = AppColors.ffFFFFFF,
    this.icon,
    this.width,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final String? icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final action = onPressed;
    return CupertinoButton(
      onPressed: action == null
          ? null
          : () {
              AudioService.shared.click();
              action();
            },
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: Container(
        width: width,
        height: 44.h,
        padding: EdgeInsets.symmetric(horizontal: 18.h),
        decoration: BoxDecoration(
          color: onPressed == null ? color.withValues(alpha: 0.4) : color,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: 0.35), width: 2.h),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Image.asset(icon!, width: 20.h, height: 20.h, color: textColor),
              SizedBox(width: 8.h),
            ],
            Flexible(child: AppText.manrope(label, fontSize: 15.h, fontWeight: FontWeight.w800, color: textColor)),
          ],
        ),
      ),
    );
  }
}
