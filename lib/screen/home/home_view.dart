import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../common/lixi_icon.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'home_backdrop.dart';
import 'home_controller.dart';
import 'home_play_cards.dart';

class HomeView extends StatefulWidget {
  HomeView({super.key}) {
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController());
    }
  }

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  var controller = Get.find<HomeController>();

  @override
  void dispose() {
    Get.delete<HomeController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: AppColors.ff1B1D22,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeBackdrop()),
          // Phủ tối dần từ trái sang để chữ nổi trên nền đường.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.ff1B1D22.withValues(alpha: 0.88),
                    AppColors.ff1B1D22.withValues(alpha: 0.55),
                    AppColors.ff1B1D22.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 0.8],
                ),
              ),
            ),
          ),
          Positioned(
            left: max(insets.left, 24.h) + 12.h,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LixiIcon(height: 34.h),
                    SizedBox(width: 10.h),
                    AppText.manrope(
                      'TẾT 2027',
                      fontSize: 14.h,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4.h,
                      color: AppColors.ffFFD166,
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                AppText.paytone(
                  'Về Quê Thôi!',
                  fontSize: 54.h,
                  color: AppColors.ffFFD166,
                  shadow: const [
                    Shadow(color: AppColors.ffB4231E, offset: Offset(0, 4)),
                    Shadow(color: AppColors.shadowSoft, offset: Offset(0, 8), blurRadius: 10),
                  ],
                ),
                SizedBox(height: 4.h),
                AppText.manrope(
                  'Lái xe về quê, kịp đón giao thừa cùng gia đình.',
                  fontSize: 15.h,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ffFFFFFF,
                ),
                SizedBox(height: 22.h),
                AppButton(
                  label: 'Về quê',
                  icon: Img.icPlay,
                  width: 250.h,
                  color: AppColors.ffD62828,
                  onPressed: controller.startTrip,
                ),
                Obx(() {
                  if (!controller.hasTrip.value) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.only(top: 10.h),
                    child: AppButton(
                      label: 'Tiếp tục chuyến đi',
                      icon: Img.icRetry,
                      width: 250.h,
                      color: AppColors.ffFFD166,
                      textColor: AppColors.ff1B1D22,
                      onPressed: controller.continueTrip,
                    ),
                  );
                }),
                SizedBox(height: 10.h),
                AppButton(
                  label: 'Kỷ lục',
                  icon: Img.icStar,
                  width: 250.h,
                  color: AppColors.ff5B6169,
                  onPressed: controller.showRecords,
                ),
              ],
            ),
          ),
          // Tập lái, thử thách hôm nay: góc dưới bên phải.
          Positioned(
            right: max(insets.right, 16.h),
            bottom: max(insets.bottom, 14.h),
            child: const HomePlayCards(),
          ),
          Positioned(
            top: max(insets.top, 12.h),
            right: max(insets.right, 16.h),
            child: Obx(
              () => CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: controller.toggleSound,
                child: Container(
                  width: 44.h,
                  height: 44.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.ff1B1D22.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    controller.soundOn.value ? Img.icSoundOn : Img.icSoundOff,
                    width: 24.h,
                    height: 24.h,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
