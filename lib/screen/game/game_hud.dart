import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/lixi_icon.dart';
import '../../game/logic/road_layout.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../game/stage.dart';
import '../../game/vehicle_spec.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Thanh trên cùng: tiến trình chặng, đồng hồ giao thừa, lì xì + hàng chở,
/// cụm tình trạng xe (xăng, tỉnh táo, lốp, mưa), nút chat và tạm dừng. Các ô
/// nền tối bán trong suốt để không che đường quá nhiều.
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
        final bus = controller.setup.vehicle == VehicleKind.bus;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RouteProgress(from: controller.setup.fromName, to: controller.setup.toName, hud: hud),
            SizedBox(width: 8.h),
            _Pill(child: _Clock(hud: hud)),
            SizedBox(width: 8.h),
            _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LixiIcon(height: 19.h),
                  SizedBox(width: 5.h),
                  AppText.manrope('${hud.lixi}', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                  const _Divider(),
                  Image.asset(bus ? Img.people.first : Img.cargo.first, width: 22.h, height: 22.h),
                  SizedBox(width: 3.h),
                  AppText.manrope(
                    '${hud.cargo}',
                    fontSize: 15.h,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ffFFFFFF,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.h),
            // Nhiều chuyện cùng lúc (lốp xẹp, mưa, ướt) thì thu nhỏ cho vừa.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(hud: hud, motorbike: controller.setup.vehicle == VehicleKind.motorbike),
                ),
              ),
            ),
            SizedBox(width: 8.h),
            _ViewToggle(controller: controller),
            SizedBox(width: 8.h),
            _IconPill(icon: Img.icChat, onPressed: controller.openChat),
            SizedBox(width: 8.h),
            _IconPill(icon: Img.icPause, onPressed: controller.pause),
          ],
        );
      }),
    );
  }
}

/// Vạch chia mảnh giữa các mục trong một ô.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18.h,
      margin: EdgeInsets.symmetric(horizontal: 8.h),
      color: AppColors.ffFFFFFF.withValues(alpha: 0.18),
    );
  }
}

/// Cụm tình trạng xe: đồng hồ xăng, tỉnh táo; lốp hỏng, trời mưa (xe máy:
/// có áo mưa chưa, ướt bao nhiêu) chỉ hiện khi có chuyện.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.hud, required this.motorbike});

  final HudData hud;
  final bool motorbike;

  static Color levelColor(double v, {double low = 0.12, double mid = 0.35}) => v < low
      ? AppColors.ffFF5A4E
      : v < mid
          ? AppColors.ffFFD166
          : AppColors.ff4ADE80;

  @override
  Widget build(BuildContext context) {
    final fuelColor = levelColor(hud.fuel);
    final alertColor = levelColor(hud.alert / 100, low: 0.25, mid: 0.45);
    return Container(
      height: 38.h,
      padding: EdgeInsets.symmetric(horizontal: 12.h),
      decoration: BoxDecoration(
        color: hud.outOfFuel || hud.alert < 25 ? AppColors.ff8E1428.withValues(alpha: 0.82) : AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(19.h),
      ),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Blink(
              on: hud.fuel < 0.12,
              child: _Gauge(glyph: RoadGlyph.pump, value: hud.fuel, color: fuelColor, label: hud.outOfFuel ? 'Hết' : '${(hud.fuel * 100).round()}'),
            ),
            const _Divider(),
            _Blink(
              on: hud.alert < 25,
              child: _Gauge(glyph: RoadGlyph.cup, value: hud.alert / 100, color: alertColor, label: '${hud.alert}'),
            ),
            if (hud.tire != TireState.ok) ...[
              const _Divider(),
              _Blink(
                on: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoadIcon(RoadGlyph.tireFlat, size: 18.h, color: AppColors.ffFF5A4E, accent: AppColors.ff1B1D22),
                    SizedBox(width: 4.h),
                    AppText.manrope(
                      hud.tire == TireState.ruined ? 'Nát' : 'Xẹp',
                      fontSize: 12.h,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ffFF8FAB,
                    ),
                  ],
                ),
              ),
            ],
            if (hud.rain > 0) ...[
              const _Divider(),
              RoadIcon(RoadGlyph.rain, size: 19.h, color: AppColors.ffE3E5E9, accent: AppColors.ff4B86BE),
              if (motorbike) ...[
                SizedBox(width: 5.h),
                if (hud.raincoat)
                  RoadIcon(RoadGlyph.raincoat, size: 17.h, color: AppColors.ff4B86BE, accent: AppColors.ffFFFFFF)
                else ...[
                  RoadIcon(RoadGlyph.drop, size: 15.h, color: AppColors.ff4B86BE, accent: AppColors.ffFFFFFF),
                  SizedBox(width: 2.h),
                  AppText.manrope('${(hud.soaked * 100).round()}%', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff9FC6EA),
                ],
              ],
            ],
          ],
        ),
    );
  }
}

/// Một đồng hồ nhỏ: icon, thanh mức, số.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.glyph, required this.value, required this.color, required this.label});

  final RoadGlyph glyph;
  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoadIcon(glyph, size: 18.h, color: color, accent: AppColors.ff1B1D22.withValues(alpha: 0.7)),
        SizedBox(width: 5.h),
        Container(
          width: 24.h,
          height: 7.h,
          decoration: BoxDecoration(
            color: AppColors.ffFFFFFF.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(4.h),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4.h),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4.h)],
              ),
            ),
          ),
        ),
        SizedBox(width: 5.h),
        AppText.manrope(label, fontSize: 12.h, fontWeight: FontWeight.w800, color: color),
      ],
    );
  }
}

/// Nháy chậm khi [on] (đèn báo).
class _Blink extends StatefulWidget {
  const _Blink({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void initState() {
    super.initState();
    if (widget.on) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Blink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !_anim.isAnimating) _anim.repeat(reverse: true);
    if (!widget.on && _anim.isAnimating) {
      _anim
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(opacity: 1 - 0.65 * _anim.value, child: child),
      child: widget.child,
    );
  }
}

/// Cột bên phải dưới nút tạm dừng: những gì sắp gặp phía trước — CSGT vẫy
/// vào, đèn giao thông, khúc cua gắt, biển hạn chế tốc độ, chỗ đổ xăng / vá
/// xe gần nhất khi đang cần.
class RoadAheadColumn extends StatelessWidget {
  const RoadAheadColumn({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hud = controller.hud.value;
      if (hud == null || controller.phase.value == GamePhase.resting) return const SizedBox.shrink();
      final items = <Widget>[
        if (hud.pullOver != null) _PullOverBanner(meters: hud.pullOver!),
        if (hud.light != null) _LightPill(light: hud.light!),
        if (hud.curve != null) _CurvePill(curve: hud.curve!),
        if (hud.speedLimit != null) _SpeedLimitPill(limit: hud.speedLimit!, speedKmh: hud.speedKmh),
        if (hud.fuelAhead != null) _ServiceChip(glyph: RoadGlyph.pump, label: hud.fuelAhead!, color: AppColors.ffEE9B2F),
        if (hud.repairAhead != null) _ServiceChip(glyph: RoadGlyph.wrench, label: hud.repairAhead!, color: AppColors.ff3A78A8),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in items) Padding(padding: EdgeInsets.only(bottom: 6.h), child: item),
        ],
      );
    });
  }
}

/// CSGT vẫy vào: băng đỏ nháy, còi, còn bao nhiêu mét phải dừng.
class _PullOverBanner extends StatelessWidget {
  const _PullOverBanner({required this.meters});

  final int meters;

  @override
  Widget build(BuildContext context) {
    return _Blink(
      on: true,
      child: Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 12.h),
        decoration: BoxDecoration(
          color: AppColors.ffD62828,
          borderRadius: BorderRadius.circular(20.h),
          border: Border.all(color: AppColors.ffFFD166, width: 2.h),
          boxShadow: [BoxShadow(color: AppColors.ffD62828.withValues(alpha: 0.6), blurRadius: 12.h)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoadIcon(RoadGlyph.whistle, size: 20.h, color: AppColors.ffFFFFFF, accent: AppColors.ffD62828),
            SizedBox(width: 8.h),
            AppText.manrope('CSGT vẫy — DỪNG XE!', fontSize: 13.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
            SizedBox(width: 8.h),
            AppText.manrope('${meters}m', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFE3A1),
          ],
        ),
      ),
    );
  }
}

/// Biển hạn chế tốc độ ở chốt phía trước: biển tròn viền đỏ + khoảng cách;
/// đang quá tốc độ thì nền đỏ.
class _SpeedLimitPill extends StatelessWidget {
  const _SpeedLimitPill({required this.limit, required this.speedKmh});

  final SpeedLimitHud limit;
  final int speedKmh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38.h,
      padding: EdgeInsets.only(left: 5.h, right: 12.h),
      decoration: BoxDecoration(
        color: limit.over ? AppColors.ffD62828.withValues(alpha: 0.88) : AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(19.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30.h,
            height: 30.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ffFFFFFF,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ffD62828, width: 3.5.h),
            ),
            child: AppText.manrope('${limit.limit}', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ),
          SizedBox(width: 8.h),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText.manrope(
                limit.over ? 'Quá tốc độ!' : 'Chốt CSGT',
                fontSize: 11.h,
                fontWeight: FontWeight.w800,
                color: limit.over ? AppColors.ffFFFFFF : AppColors.ffFFD166,
              ),
              AppText.manrope(
                limit.meters > 0 ? 'bắn tốc độ ${limit.meters}m' : 'đang đo tốc độ',
                fontSize: 10.h,
                fontWeight: FontWeight.w700,
                color: AppColors.ffE3E5E9,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chỗ đổ xăng / vá xe gần nhất phía trước.
class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.glyph, required this.label, required this.color});

  final RoadGlyph glyph;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      padding: EdgeInsets.only(left: 4.h, right: 12.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16.h),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24.h,
            height: 24.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: RoadIcon(glyph, size: 15.h, color: AppColors.ffFFFFFF, accent: color),
          ),
          SizedBox(width: 7.h),
          AppText.manrope(label, fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
        ],
      ),
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

/// Đổi góc nhìn: bản đồ trên cao ↔ ghế lái. Đang nạp ảnh thì nút mờ đi.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final driver = controller.driverView.value;
      final loading = controller.viewLoading.value;
      return CupertinoButton(
        onPressed: loading ? null : controller.toggleView,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        child: Opacity(
          opacity: loading ? 0.5 : 1,
          child: Container(
            height: 38.h,
            padding: EdgeInsets.symmetric(horizontal: 11.h),
            decoration: BoxDecoration(
              color: AppColors.ff1B1D22.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(19.h),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoadIcon(driver ? RoadGlyph.aerial : RoadGlyph.steering, size: 19.h, color: AppColors.ffFFFFFF, accent: AppColors.ff5B6169),
                SizedBox(width: 6.h),
                AppText.manrope(loading ? 'Đang tải…' : (driver ? 'Trên cao' : 'Ghế lái'),
                    fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
              ],
            ),
          ),
        ),
      );
    });
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
      width: 186.h,
      padding: EdgeInsets.fromLTRB(12.h, 6.h, 12.h, 6.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14.h),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tên điểm đi → điểm đến (tên dài thì cắt bớt), dưới là thanh tiến
          // độ kèm số km còn lại.
          AppText.manrope('$from → $to', fontSize: 11.h, fontWeight: FontWeight.w700, maxLines: 1, color: AppColors.ffB8BCC4),
          SizedBox(height: 5.h),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3.h),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6.h,
                    backgroundColor: AppColors.ffFFFFFF.withValues(alpha: 0.2),
                    color: AppColors.ffFFD166,
                  ),
                ),
              ),
              SizedBox(width: 8.h),
              AppText.manrope('${hud.kmTotal - hud.kmDone} km', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
            ],
          ),
        ],
      ),
    );
  }
}

/// Giờ hiện tại trong game + đang dư / trễ bao nhiêu so với giao thừa (chạy
/// tiếp ở tốc độ thường tới hết chuyến): xanh khi dư, vàng khi sát nút, đỏ khi
/// trễ — biết lúc nào nên tăng ga, lúc nào ghé quán được.
class _Clock extends StatelessWidget {
  const _Clock({required this.hud});

  final HudData hud;

  static String _span(int minutes) => minutes >= 60 ? '${minutes ~/ 60}g${(minutes % 60).toString().padLeft(2, '0')}' : '$minutes phút';

  @override
  Widget build(BuildContext context) {
    final spare = hud.spareMinutes;
    // Chuyến dài xuất phát từ mấy hôm trước: ghi kèm ngày.
    final day = hud.day == 30 ? '' : '${hud.day} Tết · ';
    final (label, color) = spare < 0
        ? ('${day}trễ ${_span(-spare)}', AppColors.ffFF5A4E)
        : spare < 15
            ? ('${day}sát giờ · dư ${_span(spare)}', AppColors.ffFFD166)
            : ('${day}dư ${_span(spare)}', AppColors.ff4ADE80);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppText.manrope(hud.clockLabel, fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF, lineHeight: 1.05),
        AppText.manrope(label, fontSize: 9.5.h, fontWeight: FontWeight.w800, lineHeight: 1.1, color: color),
      ],
    );
  }
}
