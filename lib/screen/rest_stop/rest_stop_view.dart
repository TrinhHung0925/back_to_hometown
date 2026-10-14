import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../common/lixi_icon.dart';
import '../../common/screen_header.dart';
import '../../game/logic/trip_clock.dart';
import '../../model/trip.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/route_service.dart';
import '../../service/trip_service.dart';
import 'rest_stop_controller.dart';

class RestStopView extends StatefulWidget {
  RestStopView({super.key}) {
    if (!Get.isRegistered<RestStopController>()) {
      Get.put(RestStopController());
    }
  }

  @override
  State<RestStopView> createState() => _RestStopViewState();
}

class _RestStopViewState extends State<RestStopView> {
  var controller = Get.find<RestStopController>();

  @override
  void dispose() {
    Get.delete<RestStopController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;
    final next = controller.nextStage;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.ff27AE60,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.h, 12.h, 24.h, 16.h),
            child: progress == null || next == null
                ? Center(child: AppButton(label: 'Về menu', onPressed: controller.restLater))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScreenHeader(
                        title: controller.previousStage == null
                            ? 'Sẵn sàng lên đường'
                            : 'Trạm dừng nghỉ · ${controller.previousStage!.toName}',
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _TripCard(progress: progress, behind: controller.behindSchedule)),
                            SizedBox(width: 16.h),
                            Expanded(child: _NextStageCard(stage: next, number: progress.stageIndex + 1, total: progress.plan.stages.length)),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Nghỉ, chơi sau',
                              icon: Img.icMenu,
                              color: AppColors.ff5B6169,
                              onPressed: controller.restLater,
                            ),
                          ),
                          SizedBox(width: 16.h),
                          Expanded(
                            child: AppButton(
                              label: 'Đi tiếp',
                              icon: Img.icPlay,
                              color: AppColors.ffFFD166,
                              textColor: AppColors.ff1B1D22,
                              onPressed: controller.goOn,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(16.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
      ),
      child: child,
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.progress, required this.behind});

  final TripProgress progress;
  final bool behind;

  @override
  Widget build(BuildContext context) {
    final plan = progress.plan;
    final done = TripService.kmDone(progress);
    final left = TripService.minutesLeft(progress).round();
    final leftLabel = left >= 60 ? '${left ~/ 60} giờ ${(left % 60).toString().padLeft(2, '0')}' : '$left phút';
    final first = plan.stages.first.fromName;
    final last = plan.stages.last.toName;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText.manrope('$first → $last', fontSize: 17.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(5.h),
            child: LinearProgressIndicator(
              value: done / plan.km,
              minHeight: 10.h,
              backgroundColor: AppColors.ffB8BCC4.withValues(alpha: 0.4),
              color: AppColors.ffD62828,
            ),
          ),
          SizedBox(height: 4.h),
          AppText.manrope(
            'Đã đi ${done.round()} / ${plan.km.round()} km',
            fontSize: 12.h,
            color: AppColors.ff5B6169,
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppText.manrope(
                TripClock(minutes: progress.clockMinutes).label,
                fontSize: 34.h,
                fontWeight: FontWeight.w800,
                color: AppColors.ff1B1D22,
              ),
              SizedBox(width: 10.h),
              Expanded(
                child: AppText.manrope(
                  'còn $leftLabel tới giao thừa',
                  fontSize: 13.h,
                  maxLines: 2,
                  color: behind ? AppColors.ffD62828 : AppColors.ff5B6169,
                  padding: EdgeInsets.only(bottom: 6.h),
                ),
              ),
            ],
          ),
          if (behind)
            AppText.manrope(
              'Đang chậm giờ — phải chạy nhanh hơn mới kịp!',
              fontSize: 12.h,
              fontWeight: FontWeight.w700,
              color: AppColors.ffD62828,
            ),
          SizedBox(height: 8.h),
          Row(
            children: [
              LixiIcon(height: 22.h),
              SizedBox(width: 8.h),
              AppText.manrope('${progress.lixi} lì xì', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextStageCard extends StatelessWidget {
  const _NextStageCard({required this.stage, required this.number, required this.total});

  final TripStage stage;
  final int number;
  final int total;

  static String kindLabel(RoadKind kind) => switch (kind) {
        RoadKind.city => 'Đường phố',
        RoadKind.highway => 'Quốc lộ',
        RoadKind.expressway => 'Cao tốc',
      };

  static Color kindColor(RoadKind kind) => switch (kind) {
        RoadKind.city => AppColors.ffFFD166,
        RoadKind.highway => AppColors.ff5B6169,
        RoadKind.expressway => AppColors.ff27AE60,
      };

  @override
  Widget build(BuildContext context) {
    final minutes = (RouteService.stagePlaySeconds(stage) / 60).ceil();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText.manrope('Chặng $number / $total', fontSize: 12.h, fontWeight: FontWeight.w700, color: AppColors.ff5B6169),
          SizedBox(height: 2.h),
          AppText.manrope(
            '${stage.fromName} → ${stage.toName}',
            fontSize: 17.h,
            fontWeight: FontWeight.w800,
            maxLines: 2,
            color: AppColors.ff1B1D22,
          ),
          SizedBox(height: 10.h),
          // Dải màu tỉ lệ theo km từng loại đường.
          ClipRRect(
            borderRadius: BorderRadius.circular(5.h),
            child: SizedBox(
              height: 12.h,
              child: Row(
                children: [
                  for (final s in stage.sections)
                    Expanded(flex: (s.km * 10).round().clamp(1, 100000), child: ColoredBox(color: kindColor(s.kind))),
                ],
              ),
            ),
          ),
          SizedBox(height: 10.h),
          for (final kind in RoadKind.values)
            if (stage.sections.any((s) => s.kind == kind))
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Row(
                  children: [
                    Container(width: 12.h, height: 12.h, color: kindColor(kind)),
                    SizedBox(width: 8.h),
                    Expanded(child: AppText.manrope(kindLabel(kind), fontSize: 13.h, color: AppColors.ff1B1D22)),
                    AppText.manrope(
                      '${stage.sections.where((s) => s.kind == kind).fold<double>(0, (a, s) => a + s.km).round()} km',
                      fontSize: 13.h,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ff1B1D22,
                    ),
                  ],
                ),
              ),
          const Spacer(),
          AppText.manrope(
            '${stage.km.round()} km · ~$minutes phút chơi · ${stage.tollBooths} trạm thu phí',
            fontSize: 12.h,
            maxLines: 2,
            color: AppColors.ff5B6169,
          ),
        ],
      ),
    );
  }
}
