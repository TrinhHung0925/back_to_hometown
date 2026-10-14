import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../resource/app_colors.dart';
import '../resource/app_resource.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';

/// Tiêu đề màn hình + nút quay lại (dùng icon PNG, không dùng Material Icons).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.onBack, this.color = AppColors.ffFFFFFF});

  final String title;
  final VoidCallback? onBack;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () {
              AudioService.shared.click();
              onBack!();
            },
            child: Container(
              width: 40.h,
              height: 40.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.ff1B1D22.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: RotatedBox(
                quarterTurns: 2,
                child: Image.asset(Img.icPlay, width: 18.h, height: 18.h, color: color),
              ),
            ),
          ),
        if (onBack != null) SizedBox(width: 12.h),
        Expanded(
          child: AppText.manrope(title, fontSize: 24.h, fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}
