import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../common/game_panel.dart';
import '../../common/lixi_icon.dart';
import '../../game/game_config.dart';
import '../../game/logic/trip_clock.dart';
import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';

/// Công an tới sau va chạm: chọn nộp phạt hoặc bỏ chạy.
class IncidentOverlay extends StatelessWidget {
  const IncidentOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final lixi = controller.hud.value?.lixi ?? 0;
    final enough = lixi >= GameConfig.fineLixi;
    final minutes = (GameConfig.fineMinutes + (enough ? 0 : GameConfig.fineExtraMinutesIfBroke)).round();
    return GamePanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.manrope('Công an tới!', fontSize: 24.h, fontWeight: FontWeight.w800, color: AppColors.ffD62828),
          SizedBox(height: 8.h),
          AppText.manrope(
            controller.incidentKind.value == IncidentKind.redLight
                ? 'Bạn vừa vượt đèn đỏ! Dừng lại nộp phạt, hay liều bỏ chạy?'
                : 'Bạn vừa va chạm. Dừng lại nộp phạt, hay liều bỏ chạy?',
            fontSize: 14.h,
            maxLines: 3,
            textAlign: TextAlign.center,
            color: AppColors.ff1B1D22,
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: _Choice(
                  title: 'Nộp phạt',
                  detail: enough
                      ? '−${GameConfig.fineLixi} lì xì · bị giữ $minutes phút'
                      : 'Không đủ lì xì · nộp hết, bị giữ $minutes phút',
                  button: AppButton(label: 'Nộp phạt', color: AppColors.ff5B6169, onPressed: controller.payFine),
                ),
              ),
              SizedBox(width: 14.h),
              Expanded(
                child: _Choice(
                  title: 'Bỏ chạy',
                  detail: 'Chạy nhanh thì thoát · chậm là bị bắt, hết chuyến',
                  button: AppButton(label: 'Chạy!', onPressed: controller.flee),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, required this.detail, required this.button});

  final String title;
  final String detail;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText.manrope(detail, fontSize: 12.h, maxLines: 2, textAlign: TextAlign.center, color: AppColors.ff5B6169),
        SizedBox(height: 8.h),
        button,
      ],
    );
  }
}

/// Đang bị công an đuổi: thanh khoảng cách + thời gian cầm cự.
class ChaseBar extends StatelessWidget {
  const ChaseBar({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final progress = controller.chaseProgress.value;
      final timeLeft = controller.chaseTimeLeft.value;
      return Container(
        width: 300.h,
        padding: EdgeInsets.fromLTRB(14.h, 8.h, 14.h, 10.h),
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14.h),
          border: Border.all(color: AppColors.ffD62828, width: 2.h),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppText.manrope(
                    'CHẠY ĐI! Công an đang đuổi',
                    fontSize: 13.h,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ffFFFFFF,
                  ),
                ),
                AppText.manrope(
                  '${timeLeft.ceil()}s',
                  fontSize: 13.h,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ffFFD166,
                ),
              ],
            ),
            SizedBox(height: 6.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.h),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8.h,
                backgroundColor: AppColors.ffD62828.withValues(alpha: 0.35),
                color: progress < 0.25 ? AppColors.ffD62828 : AppColors.ff4ADE80,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      width: 320.h,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText.manrope(
            'Tạm dừng',
            fontSize: 24.h,
            fontWeight: FontWeight.w800,
            textAlign: TextAlign.center,
            color: AppColors.ff1B1D22,
          ),
          SizedBox(height: 16.h),
          AppButton(label: 'Đi tiếp', icon: Img.icPlay, onPressed: controller.resume),
          SizedBox(height: 10.h),
          AppButton(label: 'Chơi lại chặng này', icon: Img.icRetry, color: AppColors.ff5B6169, onPressed: controller.retry),
          SizedBox(height: 10.h),
          AppButton(label: 'Về menu', icon: Img.icMenu, color: AppColors.ff5B6169, onPressed: controller.exitToMenu),
        ],
      ),
    );
  }
}

class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.controller, required this.result});

  final GameController controller;
  final StageResult result;

  (String, String) get _texts => switch (result.reason) {
        StageEndReason.arrived when !controller.isLastStage => (
            'Tới ${controller.setup.toName}!',
            'Xong chặng ${controller.setup.stageNumber}/${controller.setup.stageCount}. Nghỉ chân một chút rồi đi tiếp.',
          ),
        StageEndReason.arrived => ('Về tới nhà rồi!', 'Kịp trước giao thừa. Cả nhà đang đợi!'),
        StageEndReason.timeUp => ('Không kịp giao thừa', 'Pháo hoa đã nổ mà bạn vẫn còn trên đường.'),
        StageEndReason.caught => ('Bị công an bắt', 'Chạy không thoát. Chuyến về quê dừng ở đây.'),
        StageEndReason.accident => ('Tai nạn!', 'Đâm mạnh quá. Chuyến về quê dừng ở đây.'),
      };

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _texts;
    final summary = controller.tripSummary.value;
    return GamePanel(
      width: 420.h,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.manrope(
            title,
            fontSize: 26.h,
            fontWeight: FontWeight.w800,
            color: result.won ? AppColors.ff27AE60 : AppColors.ffD62828,
          ),
          SizedBox(height: 4.h),
          AppText.manrope(subtitle, fontSize: 14.h, maxLines: 2, textAlign: TextAlign.center, color: AppColors.ff5B6169),
          if (result.won) ...[
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.h),
                    child: Image.asset(
                      Img.icStar,
                      width: 40.h,
                      height: 40.h,
                      color: i < result.stars ? AppColors.ffFFD166 : AppColors.ffB8BCC4,
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppText.manrope(
                'Giờ tới: ${TripClock(minutes: result.clockMinutes).label}',
                fontSize: 14.h,
                fontWeight: FontWeight.w700,
                color: AppColors.ff1B1D22,
              ),
              SizedBox(width: 18.h),
              LixiIcon(height: 18.h),
              SizedBox(width: 6.h),
              AppText.manrope('${result.lixi}', fontSize: 14.h, fontWeight: FontWeight.w700, color: AppColors.ff1B1D22),
              if (result.won) ...[
                SizedBox(width: 18.h),
                AppText.manrope('Điểm: ${result.score}', fontSize: 14.h, fontWeight: FontWeight.w700, color: AppColors.ff1B1D22),
              ],
            ],
          ),
          if (summary != null) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.h, vertical: 8.h),
              decoration: BoxDecoration(
                color: summary.newRecord ? AppColors.ffFFD166.withValues(alpha: 0.35) : AppColors.ffF2F3F5,
                borderRadius: BorderRadius.circular(12.h),
              ),
              child: AppText.manrope(
                summary.newRecord
                    ? 'Kỷ lục mới cho tuyến này: ${summary.record.score} điểm!'
                    : 'Cả chuyến: ${summary.record.score} điểm · kỷ lục ${summary.previousBest} điểm',
                fontSize: 14.h,
                fontWeight: FontWeight.w800,
                textAlign: TextAlign.center,
                maxLines: 2,
                color: AppColors.ff1B1D22,
              ),
            ),
          ],
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: result.won
                    ? AppButton(
                        label: controller.isLastStage ? 'Ăn Tết thôi!' : 'Tới trạm dừng nghỉ',
                        icon: Img.icPlay,
                        onPressed: controller.continueTrip,
                      )
                    : AppButton(label: 'Chơi lại chặng này', icon: Img.icRetry, onPressed: controller.retry),
              ),
              if (!(result.won && controller.isLastStage)) ...[
                SizedBox(width: 12.h),
                Expanded(
                  child: AppButton(
                    label: 'Về menu',
                    icon: Img.icMenu,
                    color: AppColors.ff5B6169,
                    onPressed: controller.exitToMenu,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
