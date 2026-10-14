import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/lixi_icon.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'splash_controller.dart';
import 'splash_scene.dart';

class SplashView extends StatefulWidget {
  SplashView({super.key}) {
    if (!Get.isRegistered<SplashController>()) {
      Get.put(SplashController());
    }
  }

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  var controller = Get.find<SplashController>();

  /// Màn mở đầu: tiêu đề bật vào, chữ phụ và thanh tải hiện dần.
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Đồng hồ cho pháo hoa, đèn lồng, cánh đào.
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6);

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _intro.dispose();
    _time.dispose();
    Get.delete<SplashController>();
    super.dispose();
  }

  Animation<double> _phase(double from, double to, [Curve curve = Curves.easeOut]) =>
      CurvedAnimation(parent: _intro, curve: Interval(from, to, curve: curve));

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final title = _phase(0.05, 0.75, Curves.elasticOut);
    final fade = _phase(0.05, 0.35);
    final subtitle = _phase(0.4, 0.8);
    final loading = _phase(0.6, 1);
    return Scaffold(
      backgroundColor: AppColors.ff4A0716,
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: SplashScenePainter())),
          ),
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: SplashFestivePainter(_time))),
          ),
          // Nền tối mờ sau chữ cho dễ đọc trên trời chiều.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.1),
                  radius: 0.9,
                  colors: [AppColors.ff1F070D.withValues(alpha: 0.5), AppColors.ff1F070D.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned(
            left: max(insets.left, 24.h) + 24.h,
            top: 0,
            bottom: 70.h,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeTransition(
                  opacity: fade,
                  child: Row(
                    children: [
                      LixiIcon(height: 30.h),
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
                ),
                SizedBox(height: 4.h),
                FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.6, end: 1.0).animate(title),
                    alignment: Alignment.centerLeft,
                    child: AppText.paytone(
                      'Về Quê Thôi!',
                      fontSize: 62.h,
                      color: AppColors.ffFFD166,
                      shadow: [
                        const Shadow(color: AppColors.ffB4231E, offset: Offset(0, 4)),
                        Shadow(color: AppColors.ff1F070D.withValues(alpha: 0.6), offset: const Offset(0, 9), blurRadius: 14),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 2.h),
                FadeTransition(
                  opacity: subtitle,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(subtitle),
                    child: AppText.manrope(
                      'Đường xa mấy cũng về kịp giao thừa.',
                      fontSize: 16.h,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ffFFF4D6,
                      shadow: [Shadow(color: AppColors.ff1F070D.withValues(alpha: 0.7), blurRadius: 8)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: max(insets.bottom, 14.h) + 4.h,
            child: FadeTransition(
              opacity: loading,
              child: Center(child: _LoadingRoad(controller: controller)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh tải dạng con đường: xe máy chạy dần tới đích theo tiến độ nạp.
class _LoadingRoad extends StatelessWidget {
  const _LoadingRoad({required this.controller});

  final SplashController controller;

  @override
  Widget build(BuildContext context) {
    final width = 340.h;
    final bike = 44.h;
    return Obx(() {
      final p = controller.progress.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width + bike,
            height: 30.h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: bike / 2,
                  right: bike / 2,
                  bottom: 0,
                  child: Container(
                    height: 10.h,
                    decoration: BoxDecoration(
                      color: AppColors.ff1F070D.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(5.h),
                      border: Border.all(color: AppColors.ffFFD166.withValues(alpha: 0.45), width: 1.h),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: max(0.02, p),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5.h),
                          gradient: const LinearGradient(colors: [AppColors.ffF7A440, AppColors.ffFFD166]),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: width * p,
                  bottom: 3.h,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Image.asset(Img.imgScooterPlayer, width: bike * 0.43, height: bike),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 6.h),
          AppText.manrope(
            '${controller.tip}  ${(p * 100).round()}%',
            fontSize: 12.h,
            fontWeight: FontWeight.w700,
            color: AppColors.ffFFF4D6.withValues(alpha: 0.85),
          ),
        ],
      );
    });
  }
}
