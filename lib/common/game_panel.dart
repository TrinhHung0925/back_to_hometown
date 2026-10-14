import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../resource/app_colors.dart';

/// Lớp phủ tối + thẻ ở giữa màn hình (bảng công an, tạm dừng, kết quả).
class GamePanel extends StatelessWidget {
  const GamePanel({super.key, required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ff1B1D22.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Container(
        width: width ?? 420.h,
        padding: EdgeInsets.fromLTRB(24.h, 20.h, 24.h, 20.h),
        decoration: BoxDecoration(
          color: AppColors.ffFFFFFF,
          borderRadius: BorderRadius.circular(18.h),
          border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
        ),
        child: child,
      ),
    );
  }
}
