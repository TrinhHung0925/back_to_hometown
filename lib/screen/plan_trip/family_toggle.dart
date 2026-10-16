import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';

/// Nút gạt "Chở cả nhà" cạnh nút Xuất phát: ảnh vợ và bé chồng lên nhau, bật
/// thì nền vàng ấm kèm dấu tích xanh, tắt thì nhạt màu.
class FamilyToggle extends StatelessWidget {
  const FamilyToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final face = 26.h;
    Widget avatar(String path) => Container(
          width: face,
          height: face,
          padding: EdgeInsets.all(1.5.h),
          decoration: BoxDecoration(shape: BoxShape.circle, color: value ? AppColors.ffFFFFFF : AppColors.ffE3E5E9),
          child: ClipOval(
            child: Opacity(opacity: value ? 1 : 0.55, child: Image.asset(path, fit: BoxFit.cover)),
          ),
        );
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        AudioService.shared.click();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 112.h,
        height: 44.h,
        padding: EdgeInsets.only(left: 6.h, right: 9.h),
        decoration: BoxDecoration(
          color: value ? AppColors.ffFFF4D6 : AppColors.ffF2F3F5,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: value ? AppColors.ffEE9B2F : AppColors.ffE3E5E9, width: 2.h),
        ),
        child: Row(
          children: [
            SizedBox(
              width: face * 1.62,
              height: face + 6.h,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(left: 0, top: 0, child: avatar(Img.imgPortraitWife)),
                  Positioned(left: face * 0.62, bottom: 0, child: avatar(Img.imgPortraitKidHappy)),
                  if (value)
                    Positioned(
                      right: -3.h,
                      top: -2.h,
                      child: Container(
                        width: 14.h,
                        height: 14.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.ff1E9C53,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.ffFFFFFF, width: 1.5.h),
                        ),
                        child: Image.asset(Img.icCheck, width: 8.h, height: 8.h),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 6.h),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope('Cả nhà', fontSize: 13.h, fontWeight: FontWeight.w800, color: value ? AppColors.ff1B1D22 : AppColors.ff6B7280),
                AppText.manrope(
                  value ? 'vợ + bé Bin' : 'chở vợ con',
                  fontSize: 9.5.h,
                  fontWeight: FontWeight.w700,
                  color: value ? AppColors.ffC2412F : AppColors.ff6B7280,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
