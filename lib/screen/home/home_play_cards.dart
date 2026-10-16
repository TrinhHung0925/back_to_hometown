import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../game/logic/tutorial.dart';
import '../../game/vehicle_spec.dart';
import '../../model/difficulty.dart';
import '../../model/map_theme.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../route.dart';
import '../../service/audio_service.dart';
import '../../service/daily_service.dart';
import '../../service/local_service.dart';
import '../../service/route_service.dart';
import '../game/daily_result_banner.dart';
import '../game/road_icons.dart';

/// Hai lối chơi nhanh ở màn chính: tập lái và thử thách hôm nay.
class HomePlayController extends GetxController {
  final tutorialDone = LocalService.shared.getTutorialDone().obs;
  final challenge = DailyService.shared.today.obs;
  final best = RxnInt();
  final streak = 0.obs;

  /// Chiều dài chặng thử thách (km).
  final dailyKm = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    refreshStatus();
  }

  void refreshStatus() {
    if (isClosed) return;
    tutorialDone.value = LocalService.shared.getTutorialDone();
    challenge.value = DailyService.shared.today;
    dailyKm.value = DailyService.stageOf(challenge.value.route).km;
    best.value = DailyService.shared.bestToday;
    streak.value = DailyService.shared.streak;
  }

  Future<void> startTutorial() async {
    await Get.toNamed(AppPage.game.routeName, arguments: TutorialPlan.setup());
    refreshStatus();
  }

  Future<void> startDaily() async {
    // Mở bản đồ lộ trình trước (chọn bản đồ, trời) rồi mới xuất phát.
    await Get.toNamed(AppPage.planTrip.routeName, arguments: challenge.value);
    refreshStatus();
  }
}

/// Cột thẻ bên phải màn chính: "Tập lái" (lần đầu chơi thì sáng nhấp nháy
/// mời tập) và "Thử thách hôm nay".
class HomePlayCards extends StatefulWidget {
  const HomePlayCards({super.key});

  /// Hiện thẻ "Thử thách hôm nay" trên màn chính (đang tắt theo ý người dùng).
  static const bool showDaily = false;

  @override
  State<HomePlayCards> createState() => _HomePlayCardsState();
}

class _HomePlayCardsState extends State<HomePlayCards> {
  late final HomePlayController controller = Get.put(HomePlayController());

  @override
  void dispose() {
    Get.delete<HomePlayController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 292.h,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() => _TutorialCard(done: controller.tutorialDone.value, onPressed: controller.startTutorial)),
          // Thử thách hôm nay: người dùng muốn màn chính chỉ có "Về quê" —
          // thẻ tạm ẩn, bật lại bằng cờ này.
          if (HomePlayCards.showDaily) ...[
            SizedBox(height: 10.h),
            Obx(() => _DailyCard(
                  challenge: controller.challenge.value,
                  km: controller.dailyKm.value,
                  best: controller.best.value,
                  streak: controller.streak.value,
                  onPressed: controller.startDaily,
                )),
          ],
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: 0.8,
        onPressed: () {
          AudioService.shared.click();
          onPressed();
        },
        child: child,
      );
}

/// Thẻ "Tập lái": vô-lăng, một dòng giới thiệu; chưa tập thì viền vàng nhấp
/// nháy và nhãn mời "Mới chơi?".
class _TutorialCard extends StatefulWidget {
  const _TutorialCard({required this.done, required this.onPressed});

  final bool done;
  final VoidCallback onPressed;

  @override
  State<_TutorialCard> createState() => _TutorialCardState();
}

class _TutorialCardState extends State<_TutorialCard> with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (!widget.done) _glow.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TutorialCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done) {
      _glow.stop();
    } else if (!_glow.isAnimating) {
      _glow.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fresh = !widget.done;
    return _Tap(
      onPressed: widget.onPressed,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, child) {
          final k = fresh ? Curves.easeInOut.transform(_glow.value) : 0.0;
          return Container(
            padding: EdgeInsets.fromLTRB(10.h, 9.h, 12.h, 9.h),
            decoration: BoxDecoration(
              color: AppColors.ff1B1D22.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16.h),
              border: Border.all(
                color: fresh ? AppColors.ffFFD166.withValues(alpha: 0.55 + 0.45 * k) : AppColors.ffFFFFFF.withValues(alpha: 0.14),
                width: fresh ? 2.h : 1.h,
              ),
              boxShadow: [
                BoxShadow(color: AppColors.shadowSoft, blurRadius: 10.h, offset: Offset(0, 3.h)),
                if (fresh) BoxShadow(color: AppColors.ffFFD166.withValues(alpha: 0.18 + 0.3 * k), blurRadius: 10.h + 10.h * k),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            Container(
              width: 40.h,
              height: 40.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fresh ? AppColors.ffFFD166 : AppColors.ffFFFFFF.withValues(alpha: 0.12),
              ),
              child: RoadIcon(RoadGlyph.steering, size: 24.h, color: fresh ? AppColors.ff1B1D22 : AppColors.ffFFD166),
            ),
            SizedBox(width: 10.h),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppText.manrope('Tập lái', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                      SizedBox(width: 6.h),
                      if (fresh)
                        Container(
                          padding: EdgeInsets.fromLTRB(6.h, 1.h, 6.h, 1.h),
                          decoration: BoxDecoration(color: AppColors.ffD62828, borderRadius: BorderRadius.circular(6.h)),
                          child: AppText.manrope('MỚI CHƠI?', fontSize: 8.5.h, fontWeight: FontWeight.w800, letterSpacing: 0.8.h, color: AppColors.ffFFFFFF),
                        ),
                    ],
                  ),
                  SizedBox(height: 1.h),
                  AppText.manrope(
                    fresh ? 'Làm quen ga, phanh, cần lái · 2 phút' : 'Đã tập · lái lại cho quen tay',
                    fontSize: 11.h,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    color: AppColors.ffB8BCC4,
                  ),
                ],
              ),
            ),
            SizedBox(width: 6.h),
            SizedBox(width: 8.h, height: 13.h, child: CustomPaint(painter: _ChevronPainter(fresh ? AppColors.ffFFD166 : AppColors.ffB8BCC4))),
          ],
        ),
      ),
    );
  }
}

/// Thẻ "Thử thách hôm nay": nền đỏ Tết viền vàng, cung đường của ngày, xe,
/// cảnh, trời, độ khó, kỷ lục hôm nay và chuỗi ngày.
class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.challenge, required this.km, required this.best, required this.streak, required this.onPressed});

  final DailyChallenge challenge;
  final double km;
  final int? best;
  final int streak;
  final VoidCallback onPressed;

  static const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

  String get _dateLabel {
    final parts = challenge.dateKey.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    return '${_weekdays[date.weekday - 1]}, ${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final route = challenge.route;
    final from = RouteService.shared.place(route.fromId).name, to = RouteService.shared.place(route.toId).name;
    return _Tap(
      onPressed: onPressed,
      child: Container(
        padding: EdgeInsets.fromLTRB(14.h, 11.h, 12.h, 12.h),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.ffB4231E, AppColors.ff7F0A14],
          ),
          borderRadius: BorderRadius.circular(18.h),
          border: Border.all(color: AppColors.ffFFD166.withValues(alpha: 0.75), width: 1.5.h),
          boxShadow: [BoxShadow(color: AppColors.shadowSoft, blurRadius: 14.h, offset: Offset(0, 5.h))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset(Img.icStar, width: 14.h, height: 14.h, color: AppColors.ffFFD166),
                SizedBox(width: 5.h),
                AppText.manrope('THỬ THÁCH HÔM NAY', fontSize: 10.h, fontWeight: FontWeight.w800, letterSpacing: 1.2.h, color: AppColors.ffFFD166),
                const Spacer(),
                AppText.manrope(_dateLabel, fontSize: 10.h, fontWeight: FontWeight.w700, color: AppColors.ffFFE3A1.withValues(alpha: 0.8)),
              ],
            ),
            SizedBox(height: 6.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Chữ Paytone không có mũi tên "→": vẽ mũi tên riêng giữa hai tên.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _placeTitle(from),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7.h),
                          child: SizedBox(width: 16.h, height: 12.h, child: CustomPaint(painter: _RouteArrowPainter())),
                        ),
                        _placeTitle(to),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8.h),
                AppText.manrope('${km.round()} km', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFE3A1),
              ],
            ),
            SizedBox(height: 1.h),
            AppText.manrope(route.blurb, fontSize: 11.h, fontWeight: FontWeight.w600, maxLines: 1, color: AppColors.ffFFE3A1),
            SizedBox(height: 8.h),
            Wrap(
              spacing: 5.h,
              runSpacing: 5.h,
              children: [
                _Chip(route.vehicle == VehicleKind.motorbike ? 'Xe máy' : 'Ô tô', glyph: route.vehicle == VehicleKind.motorbike ? RoadGlyph.scooter : null),
                _Chip(route.theme.title),
                _Chip(_skyLabel(challenge.sky)),
                _Chip(challenge.difficulty.title, color: _difficultyColor(challenge.difficulty)),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.manrope('Kỷ lục hôm nay', fontSize: 9.5.h, fontWeight: FontWeight.w700, color: AppColors.ffFFE3A1.withValues(alpha: 0.75)),
                      AppText.manrope(
                        best == null ? 'Chưa chơi' : '${formatScore(best!)} điểm',
                        fontSize: 14.h,
                        fontWeight: FontWeight.w800,
                        color: best == null ? AppColors.ffFFE3A1.withValues(alpha: 0.85) : AppColors.ffFFFFFF,
                      ),
                    ],
                  ),
                ),
                if (streak > 0) ...[StreakBadge(days: streak, dark: true), SizedBox(width: 8.h)],
                Container(
                  height: 34.h,
                  padding: EdgeInsets.fromLTRB(12.h, 0, 14.h, 0),
                  decoration: BoxDecoration(
                    color: AppColors.ffFFD166,
                    borderRadius: BorderRadius.circular(11.h),
                    border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: 0.35), width: 2.h),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(Img.icPlay, width: 15.h, height: 15.h, color: AppColors.ff7F0A14),
                      SizedBox(width: 5.h),
                      AppText.manrope(best == null ? 'Lên đường' : 'Chơi lại', fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ff7F0A14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _placeTitle(String name) => AppText.paytone(
        name,
        fontSize: 19.h,
        maxLines: 1,
        color: AppColors.ffFFFFFF,
        shadow: const [Shadow(color: AppColors.ff4A0716, offset: Offset(0, 2))],
      );

  static String _skyLabel(SkyMode sky) => switch (sky) {
        SkyMode.clock => 'Chiều tối',
        SkyMode.day => 'Ban ngày',
        SkyMode.night => 'Ban đêm',
      };

  static Color _difficultyColor(Difficulty d) => switch (d) {
        Difficulty.easy => AppColors.ff4ADE80,
        Difficulty.normal => AppColors.ffFFFFFF,
        Difficulty.hard => AppColors.ffFF8A80,
      };
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color = AppColors.ffFFFFFF, this.glyph});

  final String label;
  final Color color;
  final RoadGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(glyph == null ? 7.h : 5.h, 2.h, 7.h, 2.h),
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(7.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[RoadIcon(glyph!, size: 13.h, color: color), SizedBox(width: 3.h)],
          AppText.manrope(label, fontSize: 10.h, fontWeight: FontWeight.w800, color: color),
        ],
      ),
    );
  }
}

/// Mũi tên vàng nối điểm đi → điểm đến.
class _RouteArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.ffFFD166;
    canvas.drawLine(Offset(w * 0.08, h / 2), Offset(w * 0.9, h / 2), paint);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.58, h * 0.14)
        ..lineTo(w * 0.92, h / 2)
        ..lineTo(w * 0.58, h * 0.86),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteArrowPainter oldDelegate) => false;
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.2, size.height * 0.1)
        ..lineTo(size.width * 0.8, size.height / 2)
        ..lineTo(size.width * 0.2, size.height * 0.9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.color != color;
}
