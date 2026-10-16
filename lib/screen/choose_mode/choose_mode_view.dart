import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/screen_header.dart';
import '../../model/difficulty.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';
import 'choose_mode_controller.dart';

class ChooseModeView extends StatefulWidget {
  ChooseModeView({super.key}) {
    if (!Get.isRegistered<ChooseModeController>()) {
      Get.put(ChooseModeController());
    }
  }

  @override
  State<ChooseModeView> createState() => _ChooseModeViewState();
}

class _ChooseModeViewState extends State<ChooseModeView> {
  var controller = Get.find<ChooseModeController>();

  @override
  void dispose() {
    Get.delete<ChooseModeController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ffD62828,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.h, 12.h, 24.h, 20.h),
          child: Column(
            children: [
              ScreenHeader(title: 'Bạn về quê bằng gì?', onBack: controller.onBack),
              SizedBox(height: 16.h),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeCard(
                        title: 'Tự lái xe',
                        subtitle: 'Tự chạy xe máy hoặc ô tô, tự chọn đường về.',
                        images: [Img.imgScooterPlayer, Img.imgCarPlayer],
                        onPressed: controller.selfDrive,
                      ),
                    ),
                    SizedBox(width: 20.h),
                    Expanded(
                      child: _ModeCard(
                        title: 'Lái xe khách',
                        subtitle: 'Cầm lái xe khách, đón người dọc đường về quê ăn Tết.',
                        images: [Img.imgBusPlayer],
                        badge: 'Mới',
                        onPressed: controller.coach,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Obx(() => _DifficultyBar(value: controller.difficulty.value, onChanged: controller.setDifficulty)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chọn độ khó: ba ô Dễ / Thường / Khó kèm một dòng mô tả.
class _DifficultyBar extends StatelessWidget {
  const _DifficultyBar({required this.value, required this.onChanged});

  final Difficulty value;
  final ValueChanged<Difficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(5.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(16.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.h),
            child: AppText.manrope('Độ khó', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ),
          for (final d in Difficulty.values)
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  AudioService.shared.click();
                  onChanged(d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: double.infinity,
                  margin: EdgeInsets.only(left: 5.h),
                  padding: EdgeInsets.symmetric(horizontal: 10.h, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: d == value ? AppColors.ffD62828 : AppColors.ffF2F3F5,
                    borderRadius: BorderRadius.circular(11.h),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.manrope(d.title, fontSize: 14.h, fontWeight: FontWeight.w800, color: d == value ? AppColors.ffFFFFFF : AppColors.ff1B1D22),
                      AppText.manrope(
                        d.subtitle,
                        fontSize: 9.5.h,
                        fontWeight: FontWeight.w600,
                        maxLines: 1,
                        color: d == value ? AppColors.ffFFFFFF.withValues(alpha: 0.85) : AppColors.ff6B7280,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.images,
    required this.onPressed,
    this.badge,
  });

  final String title;
  final String subtitle;
  final List<String> images;
  final VoidCallback? onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: enabled
          ? () {
              AudioService.shared.click();
              onPressed!();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.ffFFFFFF,
            borderRadius: BorderRadius.circular(20.h),
            border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.all(10.h),
                      decoration: BoxDecoration(
                        color: AppColors.ff5B6169,
                        borderRadius: BorderRadius.circular(14.h),
                        // Mặt đường nhựa thật làm nền cho hình xe.
                        image: const DecorationImage(
                          image: AssetImage(Img.texAsphalt),
                          repeat: ImageRepeat.repeat,
                          scale: 2.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final image in images)
                            Transform.rotate(angle: pi / 2, child: Image.asset(image, height: image == Img.imgScooterPlayer ? 76.h : 110.h)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.h, 2.h, 16.h, 16.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.manrope(title, fontSize: 22.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                        SizedBox(height: 4.h),
                        AppText.manrope(subtitle, fontSize: 13.h, maxLines: 2, color: AppColors.ff5B6169),
                      ],
                    ),
                  ),
                ],
              ),
              if (badge != null)
                Positioned(
                  top: 18.h,
                  right: 18.h,
                  child: AppText.manrope(
                    badge!,
                    fontSize: 12.h,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ff1B1D22,
                    padding: EdgeInsets.symmetric(horizontal: 10.h, vertical: 4.h),
                    boxDecoration: BoxDecoration(
                      color: AppColors.ffFFD166,
                      borderRadius: BorderRadius.circular(10.h),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
