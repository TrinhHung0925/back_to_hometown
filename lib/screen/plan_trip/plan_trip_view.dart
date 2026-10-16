import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../dialog/map_picker_dialog.dart';
import '../../game/logic/trip_clock.dart';
import '../../game/vehicle_spec.dart';
import '../../model/trip.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';
import '../../service/local_service.dart';
import '../../service/route_service.dart';
import 'family_toggle.dart';
import 'plan_trip_controller.dart';
import 'trip_map.dart';

class PlanTripView extends StatefulWidget {
  PlanTripView({super.key}) {
    if (!Get.isRegistered<PlanTripController>()) {
      Get.put(PlanTripController());
    }
  }

  @override
  State<PlanTripView> createState() => _PlanTripViewState();
}

class _PlanTripViewState extends State<PlanTripView> {
  var controller = Get.find<PlanTripController>();
  final _mapKey = GlobalKey<TripMapState>();

  @override
  void dispose() {
    Get.delete<PlanTripController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final gap = 12.h;
    final left = max(insets.left, gap);
    final right = max(insets.right, gap);
    final top = max(insets.top, gap);
    final bottom = max(insets.bottom, gap);
    final panelW = 296.h;
    return Scaffold(
      backgroundColor: AppColors.ff4B86BE,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Obx(
              () => TripMap(
                key: _mapKey,
                places: controller.routes.places,
                fromId: controller.fromId.value,
                toId: controller.toId.value,
                plan: controller.plan.value,
                vehicle: controller.vehicle.value,
                padding: EdgeInsets.fromLTRB(left, top + 44.h, right + panelW + gap, bottom),
                onTapPlace: (id) {
                  AudioService.shared.click();
                  controller.tapPlace(id);
                },
              ),
            ),
          ),
          Positioned(left: left, top: top, child: _BackChip(onBack: controller.onBack)),
          Positioned(
            left: left + 150.h,
            right: right + panelW + gap,
            top: top,
            child: Center(
              child: Obx(() => _HintChip(hasFrom: controller.fromId.value != null, hasTo: controller.toId.value != null)),
            ),
          ),
          Positioned(
            left: left,
            bottom: bottom,
            child: Obx(
              () => _MapTools(
                hasRoute: controller.plan.value != null,
                onShowAll: () => _mapKey.currentState?.showAll(),
                onShowRoute: () => _mapKey.currentState?.showRoute(),
              ),
            ),
          ),
          Positioned(
            right: right,
            top: top,
            bottom: bottom,
            width: panelW,
            child: _Panel(controller: controller),
          ),
        ],
      ),
    );
  }
}

/// Nút quay lại + tên màn, nền tối trong mờ nổi trên bản đồ.
class _BackChip extends StatelessWidget {
  const _BackChip({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        AudioService.shared.click();
        onBack();
      },
      child: Container(
        height: 40.h,
        padding: EdgeInsets.only(left: 6.h, right: 16.h),
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20.h),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30.h,
              height: 30.h,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.ffD62828, shape: BoxShape.circle),
              child: RotatedBox(quarterTurns: 2, child: Image.asset(Img.icPlay, width: 14.h, height: 14.h)),
            ),
            SizedBox(width: 10.h),
            AppText.manrope('Lên lộ trình', fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
          ],
        ),
      ),
    );
  }
}

/// Gợi ý bước tiếp theo, nằm giữa phía trên bản đồ.
class _HintChip extends StatelessWidget {
  const _HintChip({required this.hasFrom, required this.hasTo});

  final bool hasFrom;
  final bool hasTo;

  @override
  Widget build(BuildContext context) {
    final (String text, Color dot) = !hasFrom
        ? ('Chạm thành phố để chọn nơi đi', AppColors.ff1E9C53)
        : !hasTo
            ? ('Giờ chạm vào quê bạn', AppColors.ffD62828)
            : ('Chụm 2 ngón để xem kỹ đường đi', AppColors.ffFFD166);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.h, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFFFF.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20.h),
        boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10.h, height: 10.h, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          SizedBox(width: 8.h),
          Flexible(
            child: AppText.manrope(text, fontSize: 12.h, fontWeight: FontWeight.w700, color: AppColors.ff1B1D22),
          ),
        ],
      ),
    );
  }
}

/// Nút xem toàn cảnh / xem lộ trình + chú thích màu đường.
class _MapTools extends StatelessWidget {
  const _MapTools({required this.hasRoute, required this.onShowAll, required this.onShowRoute});

  final bool hasRoute;
  final VoidCallback onShowAll;
  final VoidCallback onShowRoute;

  Widget _round(String icon, VoidCallback onPressed) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () {
          AudioService.shared.click();
          onPressed();
        },
        child: Container(
          width: 40.h,
          height: 40.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.ff1B1D22.withValues(alpha: 0.72),
            shape: BoxShape.circle,
          ),
          child: Image.asset(icon, width: 20.h, height: 20.h),
        ),
      );

  Widget _legend(Color color, String label, {bool dot = false}) => Padding(
        padding: EdgeInsets.only(right: 10.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot
                ? Container(
                    width: 10.h,
                    height: 10.h,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.ff1B1D22, width: 1.5.h),
                    ),
                  )
                : Container(width: 16.h, height: 4.h, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.h))),
            SizedBox(width: 5.h),
            AppText.manrope(label, fontSize: 10.h, fontWeight: FontWeight.w700, color: AppColors.ff1B1D22),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _round(Img.icZoomOut, onShowAll),
        if (hasRoute) ...[SizedBox(width: 8.h), _round(Img.icTarget, onShowRoute)],
        SizedBox(width: 10.h),
        Container(
          height: 28.h,
          padding: EdgeInsets.only(left: 10.h),
          decoration: BoxDecoration(
            color: AppColors.ffFFFFFF.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14.h),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _legend(AppColors.ff1E9C53, 'Cao tốc'),
              _legend(AppColors.ffEE9B2F, 'Quốc lộ'),
              if (hasRoute) _legend(AppColors.ffD62828, 'Lộ trình'),
              if (hasRoute) _legend(AppColors.ffFFD166, 'Trạm nghỉ', dot: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.controller});

  final PlanTripController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.h, 12.h, 12.h, 12.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(20.h),
        boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Obx(() {
        final plan = controller.plan.value;
        final from = controller.fromId.value;
        final to = controller.toId.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _PlaceField(
                        tag: 'Từ',
                        hint: 'Chọn nơi xuất phát',
                        value: from == null ? null : controller.routes.place(from).name,
                        color: AppColors.ff1E9C53,
                        active: controller.activeField.value == TripField.from,
                        onPressed: () => controller.pickFromList(TripField.from),
                      ),
                      SizedBox(height: 6.h),
                      _PlaceField(
                        tag: 'Về',
                        hint: 'Chọn quê bạn',
                        value: to == null ? null : controller.routes.place(to).name,
                        color: AppColors.ffD62828,
                        active: controller.activeField.value == TripField.to,
                        onPressed: () => controller.pickFromList(TripField.to),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6.h),
                _SwapButton(enabled: from != null || to != null, onPressed: controller.swap),
              ],
            ),
            SizedBox(height: 8.h),
            controller.coachMode
                ? const _CoachInfo()
                : _VehicleSwitch(value: controller.vehicle.value, onChanged: controller.setVehicle),
            SizedBox(height: 6.h),
            MapSkyRow(theme: controller.mapTheme.value, sky: controller.sky.value, onPickMap: controller.pickMap, onSky: controller.setSky),
            SizedBox(height: 8.h),
            Container(height: 1.h, color: AppColors.ffE3E5E9),
            SizedBox(height: 8.h),
            Expanded(
              child: plan == null
                  ? _Steps(hasFrom: from != null, hasTo: to != null)
                  : _PlanSummary(plan: plan, departure: controller.departureMinutes!, family: controller.family.value),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                // Chở cả nhà: chọn ngay cạnh nút Xuất phát (đã có lộ trình).
                if (plan != null && !controller.coachMode) ...[
                  FamilyToggle(value: controller.family.value, onChanged: controller.setFamily),
                  SizedBox(width: 6.h),
                ],
                Expanded(
                  child: AppButton(
                    width: double.infinity,
                    label: plan == null ? 'Chọn điểm đi và điểm đến' : 'Xuất phát',
                    icon: plan == null ? null : Img.icPlay,
                    onPressed: plan == null ? null : controller.start,
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.tag,
    required this.hint,
    required this.value,
    required this.color,
    required this.active,
    required this.onPressed,
  });

  final String tag;
  final String hint;
  final String? value;
  final Color color;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        AudioService.shared.click();
        onPressed();
      },
      child: Container(
        height: 42.h,
        padding: EdgeInsets.only(left: 6.h, right: 10.h),
        decoration: BoxDecoration(
          color: active ? AppColors.ffFFD166.withValues(alpha: 0.22) : AppColors.ffF2F3F5,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: active ? AppColors.ffFFD166 : AppColors.ffF2F3F5, width: 2.h),
        ),
        child: Row(
          children: [
            Container(
              width: 30.h,
              height: 26.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8.h)),
              child: AppText.manrope(tag, fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
            ),
            SizedBox(width: 10.h),
            Expanded(
              child: AppText.manrope(
                value ?? hint,
                fontSize: value == null ? 13.h : 15.h,
                fontWeight: value == null ? FontWeight.w600 : FontWeight.w800,
                color: value == null ? AppColors.ff6B7280 : AppColors.ff1B1D22,
              ),
            ),
            Image.asset(Img.icSearch, width: 15.h, height: 15.h, color: AppColors.ff6B7280),
          ],
        ),
      ),
    );
  }
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: enabled
          ? () {
              AudioService.shared.click();
              onPressed();
            }
          : null,
      child: Container(
        width: 34.h,
        height: 34.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.ff1B1D22 : AppColors.ffE3E5E9,
          shape: BoxShape.circle,
        ),
        child: Image.asset(Img.icSwap, width: 18.h, height: 18.h),
      ),
    );
  }
}

class _VehicleSwitch extends StatelessWidget {
  const _VehicleSwitch({required this.value, required this.onChanged});

  final VehicleKind value;
  final ValueChanged<VehicleKind> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(VehicleKind kind, String label, String sub, String image, double length) {
      final selected = kind == value;
      return Expanded(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () {
            AudioService.shared.click();
            onChanged(kind);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 46.h,
            padding: EdgeInsets.symmetric(horizontal: 8.h),
            decoration: BoxDecoration(
              color: selected ? AppColors.ffD62828 : AppColors.ffF2F3F5,
              borderRadius: BorderRadius.circular(12.h),
            ),
            child: Row(
              children: [
                // Hình xe gốc quay đầu lên trên: xoay cho chạy sang phải.
                SizedBox(
                  width: 40.h,
                  child: Center(child: RotatedBox(quarterTurns: 1, child: Image.asset(image, height: length))),
                ),
                SizedBox(width: 6.h),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.manrope(label, fontSize: 14.h, fontWeight: FontWeight.w800, color: selected ? AppColors.ffFFFFFF : AppColors.ff1B1D22),
                      AppText.manrope(sub, fontSize: 9.5.h, fontWeight: FontWeight.w600, color: selected ? AppColors.ffFFFFFF.withValues(alpha: 0.85) : AppColors.ff6B7280),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(VehicleKind.motorbike, 'Xe máy', 'Lách giỏi', Img.imgScooterPlayer, 34.h),
        SizedBox(width: 6.h),
        option(VehicleKind.car, 'Ô tô', 'Đi cao tốc', Img.imgCarPlayer, 40.h),
      ],
    );
  }
}

/// Chế độ xe khách: thay cho nút chọn loại xe.
class _CoachInfo extends StatelessWidget {
  const _CoachInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46.h,
      padding: EdgeInsets.symmetric(horizontal: 8.h),
      decoration: BoxDecoration(color: AppColors.ffD62828, borderRadius: BorderRadius.circular(12.h)),
      child: Row(
        children: [
          SizedBox(
            width: 70.h,
            child: Center(child: RotatedBox(quarterTurns: 1, child: Image.asset(Img.imgBusPlayer, height: 64.h))),
          ),
          SizedBox(width: 6.h),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope('Xe khách Tết', fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                AppText.manrope(
                  'Dừng ở điểm đón để đón khách',
                  fontSize: 9.5.h,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ffFFFFFF.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Các bước còn thiếu trước khi xuất phát.
class _Steps extends StatelessWidget {
  const _Steps({required this.hasFrom, required this.hasTo});

  final bool hasFrom;
  final bool hasTo;

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String text, bool done) => Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Row(
            children: [
              Container(
                width: 22.h,
                height: 22.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? AppColors.ff1E9C53 : AppColors.ffF2F3F5,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? Image.asset(Img.icCheck, width: 12.h, height: 12.h)
                    : AppText.manrope('$n', fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ff6B7280),
              ),
              SizedBox(width: 10.h),
              Expanded(
                child: AppText.manrope(
                  text,
                  fontSize: 12.5.h,
                  fontWeight: FontWeight.w700,
                  maxLines: 2,
                  color: done ? AppColors.ff1B1D22 : AppColors.ff6B7280,
                ),
              ),
            ],
          ),
        );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step(1, 'Chọn nơi xuất phát (chạm bản đồ hoặc tìm tên)', hasFrom),
          step(2, 'Chọn quê bạn — nơi đón giao thừa', hasTo),
          step(3, 'Chọn xe (xe máy, ô tô hoặc xe khách)', true),
          AppText.manrope(
            '100 km quốc lộ ≈ 5 phút chơi. Đường càng xa càng nhiều chặng, '
            'nghỉ giữa các chặng và chơi tiếp sau cũng được.',
            fontSize: 10.5.h,
            maxLines: 4,
            color: AppColors.ff6B7280,
          ),
        ],
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan, required this.departure, this.family = false});

  final TripPlan plan;
  final double departure;

  /// Chở cả nhà (vợ + bé) về quê.
  final bool family;

  static String hours(double h) {
    final total = (h * 60).round();
    return total >= 60 ? '${total ~/ 60} giờ ${(total % 60).toString().padLeft(2, '0')}' : '$total phút';
  }

  @override
  Widget build(BuildContext context) {
    final playMinutes = (RouteService.planPlaySeconds(plan) / 60).ceil();
    final cityKm = plan.stages
        .expand((s) => s.sections)
        .where((s) => s.kind == RoadKind.city)
        .fold<double>(0, (sum, s) => sum + s.km);
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              AppText.manrope(value, fontSize: 17.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
              AppText.manrope(label, fontSize: 9.5.h, fontWeight: FontWeight.w600, color: AppColors.ff6B7280),
            ],
          ),
        );
    Widget fact(String label, String value) => Container(
          padding: EdgeInsets.symmetric(horizontal: 7.h, vertical: 4.h),
          decoration: BoxDecoration(color: AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(8.h)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText.manrope('$label ', fontSize: 10.h, fontWeight: FontWeight.w600, color: AppColors.ff6B7280),
              AppText.manrope(value, fontSize: 10.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
            ],
          ),
        );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              stat('${plan.km.round()} km', 'quãng đường'),
              stat('~$playMinutes', 'phút chơi'),
              stat('${plan.stages.length}', 'chặng'),
            ],
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 4.h,
            runSpacing: 4.h,
            children: [
              fact('Độ khó', LocalService.shared.getDifficulty().title),
              if (family) fact('Đi cùng', 'vợ + bé Bin'),
              fact('Lái thật', hours(plan.realHours)),
              fact('Xuất phát', '${TripClock(minutes: departure).label} · ${TripClock(minutes: departure).dayLabel}'),
              if (plan.expresswayKm > 0) fact('Cao tốc', '${plan.expresswayKm.round()} km'),
              fact('Phố đèn đỏ', '${cityKm.round()} km'),
              fact('Thu phí', '${plan.tollBooths} trạm'),
            ],
          ),
          SizedBox(height: 6.h),
          AppText.manrope(
            switch (plan.vehicle) {
              VehicleKind.motorbike => 'Xe máy không vào cao tốc. Về tới nhà trước giao thừa!',
              VehicleKind.car => 'Cao tốc nhanh nhưng mất phí. Về tới nhà trước giao thừa!',
              VehicleKind.bus => 'Dừng sát lề phải ở điểm đón để đón khách (+lì xì). Về trước giao thừa!',
            },
            fontSize: 10.h,
            maxLines: 3,
            color: AppColors.ff6B7280,
          ),
        ],
      ),
    );
  }
}
