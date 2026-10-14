import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/lixi_icon.dart';
import '../../game/logic/road_layout.dart';
import '../../game/stage.dart';
import '../../game/vehicle_spec.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';

/// Thanh trên cùng: tiến trình chặng, đồng hồ giao thừa, lì xì, nút chat và
/// tạm dừng. Các ô nền tối bán trong suốt để không che đường quá nhiều.
class GameHud extends StatelessWidget {
  const GameHud({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.h, 8.h, 12.h, 0),
      child: Obx(() {
        final hud = controller.hud.value;
        if (hud == null) return const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RouteProgress(from: controller.setup.fromName, to: controller.setup.toName, hud: hud),
            SizedBox(width: 10.h),
            _Pill(child: _Clock(hud: hud)),
            SizedBox(width: 10.h),
            _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LixiIcon(height: 20.h),
                  SizedBox(width: 6.h),
                  AppText.manrope('${hud.lixi}', fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                ],
              ),
            ),
            SizedBox(width: 10.h),
            _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    controller.setup.vehicle == VehicleKind.bus ? Img.people.first : Img.cargo.first,
                    width: 24.h,
                    height: 24.h,
                  ),
                  SizedBox(width: 4.h),
                  AppText.manrope(
                    controller.setup.vehicle == VehicleKind.bus ? '${hud.cargo} khách' : '${hud.cargo}',
                    fontSize: 15.h,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ffFFFFFF,
                  ),
                ],
              ),
            ),
            if (hud.light != null) ...[SizedBox(width: 10.h), _LightPill(light: hud.light!)],
            if (hud.curve != null) ...[SizedBox(width: 10.h), _CurvePill(curve: hud.curve!)],
            const Spacer(),
            _IconPill(icon: Img.icChat, onPressed: controller.openChat),
            SizedBox(width: 8.h),
            _IconPill(icon: Img.icPause, onPressed: controller.pause),
          ],
        );
      }),
    );
  }
}

/// Đèn giao thông phía trước: màu đang sáng, số giây còn lại, khoảng cách.
class _LightPill extends StatelessWidget {
  const _LightPill({required this.light});

  final LightHud light;

  static Color colorOf(LightColor c) => switch (c) {
        LightColor.red => const Color(0xffFF3B30),
        LightColor.yellow => const Color(0xffFFC800),
        LightColor.green => const Color(0xff34E06A),
      };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(light.color);
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in LightColor.values.reversed)
            Container(
              width: 10.h,
              height: 10.h,
              margin: EdgeInsets.only(right: 3.h),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c == light.color ? color : AppColors.ffFFFFFF.withValues(alpha: 0.15),
                boxShadow: c == light.color ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)] : null,
              ),
            ),
          SizedBox(width: 5.h),
          AppText.manrope('${light.seconds}s', fontSize: 15.h, fontWeight: FontWeight.w800, color: color),
          SizedBox(width: 6.h),
          AppText.manrope('${light.meters}m', fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ffB8BCC4),
        ],
      ),
    );
  }
}

/// Khúc cua gắt phía trước: mũi tên hướng cua, khoảng cách, biển tốc độ
/// khuyên dùng. Đang chạy nhanh hơn mức khuyên thì nền chuyển đỏ.
class _CurvePill extends StatelessWidget {
  const _CurvePill({required this.curve});

  final CurveHud curve;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38.h,
      padding: EdgeInsets.only(left: 10.h, right: 6.h),
      decoration: BoxDecoration(
        color: curve.tooFast ? AppColors.ffD62828.withValues(alpha: 0.85) : AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(19.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22.h,
            height: 22.h,
            child: CustomPaint(painter: _CurveArrowPainter(right: curve.right)),
          ),
          SizedBox(width: 6.h),
          AppText.manrope(
            curve.meters > 0 ? '${curve.meters}m' : 'Cua',
            fontSize: 14.h,
            fontWeight: FontWeight.w800,
            color: AppColors.ffFFFFFF,
          ),
          SizedBox(width: 6.h),
          Container(
            width: 28.h,
            height: 28.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ffFFFFFF,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ffD62828, width: 3.h),
            ),
            child: AppText.manrope('${curve.adviseKmh}', fontSize: 10.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ),
        ],
      ),
    );
  }
}

/// Mũi tên biển "chỗ ngoặt nguy hiểm": đi thẳng lên rồi bẻ sang phía cua.
class _CurveArrowPainter extends CustomPainter {
  const _CurveArrowPainter({required this.right});

  final bool right;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (!right) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    final stroke = Paint()
      ..color = AppColors.ffFFD166
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.3, h * 0.95)
        ..lineTo(w * 0.3, h * 0.55)
        ..quadraticBezierTo(w * 0.3, h * 0.3, w * 0.6, h * 0.3),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.98, h * 0.3)
        ..lineTo(w * 0.58, h * 0.04)
        ..lineTo(w * 0.58, h * 0.56)
        ..close(),
      Paint()..color = AppColors.ffFFD166,
    );
  }

  @override
  bool shouldRepaint(_CurveArrowPainter oldDelegate) => oldDelegate.right != right;
}

/// Thông báo ngắn giữa phía trên màn hình (tự ẩn).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final notice = controller.notice.value;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: notice == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(notice),
                constraints: BoxConstraints(maxWidth: 520.h),
                padding: EdgeInsets.symmetric(horizontal: 16.h, vertical: 8.h),
                decoration: BoxDecoration(
                  color: switch (notice.kind) {
                    NoticeKind.warning => const Color(0xE6B4231E),
                    NoticeKind.money => const Color(0xE6976A12),
                    NoticeKind.info => AppColors.ff1B1D22.withValues(alpha: 0.8),
                  },
                  borderRadius: BorderRadius.circular(18.h),
                ),
                child: AppText.manrope(
                  notice.text,
                  fontSize: 13.h,
                  fontWeight: FontWeight.w800,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  color: AppColors.ffFFFFFF,
                ),
              ),
      );
    });
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38.h,
      padding: EdgeInsets.symmetric(horizontal: 12.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(19.h),
      ),
      child: child,
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onPressed});

  final String icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: Opacity(
        opacity: onPressed == null ? 0.35 : 1,
        child: Container(
          width: 38.h,
          height: 38.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.ff1B1D22.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: Image.asset(icon, width: 20.h, height: 20.h),
        ),
      ),
    );
  }
}

class _RouteProgress extends StatelessWidget {
  const _RouteProgress({required this.from, required this.to, required this.hud});

  final String from;
  final String to;
  final HudData hud;

  @override
  Widget build(BuildContext context) {
    final fraction = hud.kmTotal == 0 ? 0.0 : hud.kmDone / hud.kmTotal;
    return Container(
      width: 230.h,
      padding: EdgeInsets.fromLTRB(12.h, 6.h, 12.h, 6.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14.h),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: AppText.manrope(from, fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ffB8BCC4)),
              AppText.manrope(
                'còn ${hud.kmTotal - hud.kmDone} km',
                fontSize: 11.h,
                fontWeight: FontWeight.w800,
                color: AppColors.ffFFFFFF,
              ),
              Expanded(
                child: AppText.manrope(
                  to,
                  fontSize: 11.h,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ffB8BCC4,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          SizedBox(height: 5.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(3.h),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6.h,
              backgroundColor: AppColors.ffFFFFFF.withValues(alpha: 0.2),
              color: AppColors.ffFFD166,
            ),
          ),
        ],
      ),
    );
  }
}

/// Giờ hiện tại trong game + còn bao lâu tới giao thừa (đỏ khi sắp hết giờ).
class _Clock extends StatelessWidget {
  const _Clock({required this.hud});

  final HudData hud;

  @override
  Widget build(BuildContext context) {
    final left = hud.minutesLeft;
    final urgent = left <= 15;
    final leftLabel = left >= 60 ? '${left ~/ 60}g${(left % 60).toString().padLeft(2, '0')}' : '$left phút';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        AppText.manrope(hud.clockLabel, fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
        SizedBox(width: 6.h),
        AppText.manrope(
          'còn $leftLabel',
          fontSize: 11.h,
          fontWeight: FontWeight.w700,
          color: urgent ? AppColors.ffD62828 : AppColors.ffB8BCC4,
        ),
      ],
    );
  }
}
