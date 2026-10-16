import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/lixi_icon.dart';
import '../../common/mission_row.dart';
import '../../common/shop_glyphs.dart';
import '../../game/logic/missions.dart';
import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';

/// Nhiệm vụ phụ trong menu tạm dừng: hai cột, trạng thái đang làm / xong / hỏng.
class PauseMissions extends StatelessWidget {
  const PauseMissions({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final checks = controller.missions.toList();
      if (checks.isEmpty) return const SizedBox.shrink();
      // Khung kem có nhãn nằm vắt trên viền (như nhãn khung biểu mẫu) cho gọn chiều cao.
      return Padding(
        padding: EdgeInsets.only(top: 14.h),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(10.h, 11.h, 10.h, 7.h),
              decoration: BoxDecoration(
                color: AppColors.ffFFFBF2,
                borderRadius: BorderRadius.circular(12.h),
                border: Border.all(color: AppColors.ffF1E7D2, width: 1.5.h),
              ),
              child: Row(
                children: [
                  for (final c in checks) ...[
                    if (c != checks.first) Container(width: 1.h, height: 26.h, margin: EdgeInsets.symmetric(horizontal: 10.h), color: AppColors.ffE9DFC6),
                    Expanded(child: MissionRow(mission: c.mission, check: c)),
                  ],
                  if (checks.length == 1) const Spacer(),
                ],
              ),
            ),
            Positioned(
              left: 10.h,
              top: -8.h,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.h),
                color: AppColors.ffFFFFFF,
                child: const SectionLabel('NHIỆM VỤ PHỤ · TỚI NƠI MỚI NHẬN THƯỞNG'),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Bảng kết quả chặng: từng nhiệm vụ phụ xong / hỏng và lì xì thưởng.
class ResultMissions extends StatelessWidget {
  const ResultMissions({super.key, required this.result, this.compact = false});

  final StageResult result;

  /// Gọn một hàng (chặng cuối còn dòng tổng kết cả chuyến bên dưới).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final checks = result.missions;
    if (checks.isEmpty) return const SizedBox.shrink();
    final bonus = result.missionLixi;
    if (compact) {
      return Padding(
        padding: EdgeInsets.only(top: 8.h),
        child: Row(
          children: [
            for (final c in checks) ...[
              if (c != checks.first) SizedBox(width: 8.h),
              Expanded(child: _MissionChip(check: c)),
            ],
          ],
        ),
      );
    }
    return Container(
      margin: EdgeInsets.only(top: 10.h),
      padding: EdgeInsets.fromLTRB(10.h, 8.h, 10.h, 8.h),
      decoration: BoxDecoration(color: AppColors.ffFFFBF2, borderRadius: BorderRadius.circular(12.h), border: Border.all(color: AppColors.ffF1E7D2, width: 1.5.h)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'NHIỆM VỤ PHỤ',
            trailing: bonus > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText.manrope('Thưởng ', fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ff7A4A35),
                      LixiIcon(height: 14.h),
                      AppText.manrope(' +$bonus', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53),
                    ],
                  )
                : AppText.manrope(
                    checks.every((c) => c.state == MissionState.failed) ? 'Chặng sau cố lên nhé!' : '',
                    fontSize: 11.h,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ff9A9385,
                  ),
          ),
          for (final c in checks) ...[
            SizedBox(height: 6.h),
            MissionRow(mission: c.mission, check: c),
          ],
        ],
      ),
    );
  }
}

/// Nhiệm vụ gọn trong một ô: icon, tên, thưởng, dấu xong / hỏng.
class _MissionChip extends StatelessWidget {
  const _MissionChip({required this.check});

  final MissionCheck check;

  @override
  Widget build(BuildContext context) {
    final done = check.done;
    return Container(
      height: 34.h,
      padding: EdgeInsets.symmetric(horizontal: 6.h),
      decoration: BoxDecoration(
        color: done ? AppColors.ffE6F4EC : AppColors.ffF2F3F5,
        borderRadius: BorderRadius.circular(10.h),
        border: Border.all(color: done ? AppColors.ff1E9C53.withValues(alpha: 0.5) : AppColors.ffE3E5E9, width: 1.5.h),
      ),
      child: Row(
        children: [
          MissionIcon(check.mission.kind, size: 17.h, color: done ? AppColors.ff1B1D22 : AppColors.ff9A9385),
          SizedBox(width: 5.h),
          Expanded(
            child: AppText.manrope(
              check.mission.title,
              fontSize: 11.5.h,
              fontWeight: FontWeight.w800,
              maxLines: 1,
              color: done ? AppColors.ff1B1D22 : AppColors.ff9A9385,
              decoration: done ? null : TextDecoration.lineThrough,
            ),
          ),
          if (done) ...[
            LixiIcon(height: 13.h),
            AppText.manrope(' +${check.mission.reward}', fontSize: 11.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53),
            SizedBox(width: 4.h),
          ],
          Container(
            width: 18.h,
            height: 18.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: done ? AppColors.ff1E9C53 : AppColors.ffB4231E, shape: BoxShape.circle),
            child: ShopIcon(done ? ShopGlyph.check : ShopGlyph.cross, size: 11.h, color: AppColors.ffFFFFFF),
          ),
        ],
      ),
    );
  }
}
