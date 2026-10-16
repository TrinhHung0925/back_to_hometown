import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../common/game_panel.dart';
import '../../common/lixi_icon.dart';
import '../../dialog/map_picker_dialog.dart';
import '../../game/game_config.dart';
import '../../game/logic/trip_clock.dart';
import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';
import 'game_controller.dart';
import 'mission_panels.dart';
import 'road_icons.dart';

/// Công an tới (va chạm, vượt đèn đỏ, quá tốc độ, quay đầu sai): biên bản
/// vi phạm ghi lỗi, nơi vi phạm, mức phạt; chọn nộp phạt hoặc bỏ chạy.
class IncidentOverlay extends StatelessWidget {
  const IncidentOverlay({super.key, required this.controller});

  final GameController controller;

  static String offence(IncidentKind kind) => switch (kind) {
        IncidentKind.collision => 'Gây va chạm giao thông',
        IncidentKind.redLight => 'Không chấp hành tín hiệu đèn đỏ',
        IncidentKind.speeding => 'Chạy quá tốc độ quy định',
        IncidentKind.illegalUTurn => 'Quay đầu xe ở nơi có biển cấm',
        IncidentKind.crash => 'Gây tai nạn giao thông',
        IncidentKind.phone => 'Sử dụng điện thoại khi đang điều khiển xe',
      };

  @override
  Widget build(BuildContext context) {
    final kind = controller.incidentKind.value;
    final violation = controller.violation.value;
    final lixi = controller.hud.value?.lixi ?? 0;
    final fine = kind.fineLixi;
    final enough = lixi >= fine;
    final minutes = (kind.fineMinutes + (enough ? 0 : GameConfig.fineExtraMinutesIfBroke)).round();
    final clock = controller.hud.value?.clockLabel ?? '';
    return Container(
      color: AppColors.ff1B1D22.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Container(
        width: 450.h,
        decoration: BoxDecoration(
          color: AppColors.ffFBF6E9,
          borderRadius: BorderRadius.circular(14.h),
          border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
          boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.35), blurRadius: 20.h, offset: Offset(0, 8.h))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _PaperLinesPainter())),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ReflectiveBand(),
                Padding(
                  padding: EdgeInsets.fromLTRB(20.h, 10.h, 20.h, 16.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText.manrope(
                        'BIÊN BẢN VI PHẠM',
                        fontSize: 21.h,
                        fontWeight: FontWeight.w800,
                        textAlign: TextAlign.center,
                        letterSpacing: 1.2,
                        color: AppColors.ff23408E,
                      ),
                      AppText.manrope(
                        'Lập lúc $clock · giao thông dịp Tết',
                        fontSize: 11.h,
                        fontWeight: FontWeight.w600,
                        textAlign: TextAlign.center,
                        color: AppColors.ff9A9385,
                      ),
                      SizedBox(height: 10.h),
                      _TicketField(label: 'Lỗi vi phạm', value: offence(kind), strong: true),
                      if (kind == IncidentKind.speeding && violation != null && violation.measuredKmh > 0)
                        _TicketField(label: 'Tốc độ đo được', value: '${violation.measuredKmh} km/h  (tối đa ${violation.limitKmh} km/h)'),
                      if (violation != null && violation.place.isNotEmpty) _TicketField(label: 'Địa điểm', value: violation.place),
                      if (kind == IncidentKind.crash)
                        const _TicketField(label: 'Thiệt hại', value: 'Xe móp, vỡ đèn — chờ giám định, gọi thợ sửa'),
                      _TicketField(
                        label: 'Mức phạt',
                        value: enough ? '$fine lì xì · tạm giữ $minutes phút' : 'Không đủ lì xì — nộp hết, giữ $minutes phút',
                        lixi: true,
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Expanded(
                            child: _TicketChoice(
                              caption: enough ? '−$fine lì xì · $minutes phút' : 'Mất hết lì xì',
                              button: AppButton(label: 'Nộp phạt', color: AppColors.ff23408E, width: double.infinity, onPressed: controller.payFine),
                            ),
                          ),
                          SizedBox(width: 14.h),
                          Expanded(
                            child: _TicketChoice(
                              caption: kind == IncidentKind.crash ? 'Xe hỏng rồi, không chạy được' : 'Chạy nhanh thì thoát · chậm là hết chuyến',
                              button: AppButton(
                                label: 'Bỏ chạy!',
                                width: double.infinity,
                                onPressed: kind == IncidentKind.crash ? null : controller.flee,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 26.h,
              top: 96.h,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: -0.22,
                  child: SizedBox(width: 84.h, height: 84.h, child: CustomPaint(painter: _StampPainter())),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Băng phản quang vàng chanh, sọc bạc, chữ CẢNH SÁT GIAO THÔNG.
class _ReflectiveBand extends StatelessWidget {
  const _ReflectiveBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34.h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ffC4D23E, AppColors.ffC4D23E, AppColors.ffE3E5E9, AppColors.ffC4D23E],
          stops: [0, 0.62, 0.7, 0.78],
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RoadIcon(RoadGlyph.whistle, size: 18.h, color: AppColors.ff1B1D22, accent: AppColors.ffC4D23E),
          SizedBox(width: 8.h),
          AppText.manrope('CẢNH SÁT GIAO THÔNG', fontSize: 13.h, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.ff1B1D22),
        ],
      ),
    );
  }
}

/// Một dòng biên bản: nhãn xám, nội dung mực xanh, gạch chân chấm.
class _TicketField extends StatelessWidget {
  const _TicketField({required this.label, required this.value, this.strong = false, this.lixi = false});

  final String label;
  final String value;
  final bool strong;
  final bool lixi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104.h,
            child: AppText.manrope('$label:', fontSize: 12.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
          ),
          if (lixi) ...[LixiIcon(height: 16.h), SizedBox(width: 5.h)],
          Expanded(
            child: AppText.manrope(
              value,
              fontSize: strong ? 14.h : 13.h,
              fontWeight: FontWeight.w800,
              maxLines: 2,
              color: strong ? AppColors.ffB4231E : AppColors.ff23408E,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketChoice extends StatelessWidget {
  const _TicketChoice({required this.caption, required this.button});

  final String caption;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        SizedBox(height: 4.h),
        AppText.manrope(caption, fontSize: 11.h, fontWeight: FontWeight.w600, maxLines: 2, textAlign: TextAlign.center, color: AppColors.ff6B7280),
      ],
    );
  }
}

/// Dòng kẻ mờ của tờ giấy biên bản.
class _PaperLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.ffE9DFC6
      ..strokeWidth = 1;
    for (var y = 70.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(14, y), Offset(size.width - 14, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Con dấu đỏ tròn, mực loang (hơi trong).
class _StampPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ink = Paint()
      ..color = AppColors.ffD62828.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07;
    canvas.drawCircle(c, r * 0.94, ink);
    canvas.drawCircle(c, r * 0.72, ink..strokeWidth = r * 0.04);
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? r * 0.26 : r * 0.11;
      final p = c + Offset(cos(a), sin(a)) * rr;
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(star..close(), Paint()..color = AppColors.ffD62828.withValues(alpha: 0.55));
    final text = TextPainter(
      text: TextSpan(
        text: 'CSGT',
        style: TextStyle(fontFamily: 'Manrope', fontSize: r * 0.26, fontWeight: FontWeight.w800, color: AppColors.ffD62828.withValues(alpha: 0.6)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, c + Offset(-text.width / 2, r * 0.3));
    final top = TextPainter(
      text: TextSpan(
        text: 'ĐÃ GHI',
        style: TextStyle(fontFamily: 'Manrope', fontSize: r * 0.2, fontWeight: FontWeight.w800, color: AppColors.ffD62828.withValues(alpha: 0.6)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    top.paint(canvas, c + Offset(-top.width / 2, -r * 0.58));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

/// Tạm dừng: đi tiếp / chơi lại / về menu; bên phải đổi trời (ngay) và bản
/// đồ (chơi lại chặng với cảnh mới).
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      width: 600.h,
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
          SizedBox(height: 14.h),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(label: 'Đi tiếp', icon: Img.icPlay, width: double.infinity, onPressed: controller.resume),
                      SizedBox(height: 10.h),
                      AppButton(
                        label: 'Chơi lại chặng này',
                        icon: Img.icRetry,
                        width: double.infinity,
                        color: AppColors.ff5B6169,
                        onPressed: controller.retry,
                      ),
                      SizedBox(height: 10.h),
                      AppButton(label: 'Về menu', icon: Img.icMenu, width: double.infinity, color: AppColors.ff5B6169, onPressed: controller.exitToMenu),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.h),
                  child: Container(width: 1.h, color: AppColors.ffE3E5E9),
                ),
                Expanded(child: _ViewSettings(controller: controller)),
              ],
            ),
          ),
          PauseMissions(controller: controller),
        ],
      ),
    );
  }
}

/// Trời ngày / đêm đổi ngay; dòng bản đồ mở hộp chọn bản đồ; công tắc
/// hỗ trợ lái.
class _ViewSettings extends StatelessWidget {
  const _ViewSettings({required this.controller});

  final GameController controller;

  Widget _label(String text) =>
      AppText.manrope(text, fontSize: 11.h, fontWeight: FontWeight.w800, letterSpacing: 1.2.h, color: AppColors.ff9A9385);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final assist = controller.driveAssist.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('TRỜI'),
          SizedBox(height: 6.h),
          SkySwitch(value: controller.sky.value, onChanged: controller.setSky),
          SizedBox(height: 8.h),
          MapRow(summary: controller.setup.theme.title, onPressed: controller.pickMap),
          SizedBox(height: 12.h),
          _label('LÁI XE'),
          SizedBox(height: 6.h),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () {
              AudioService.shared.click();
              controller.setDriveAssist(!assist);
            },
            child: Container(
              padding: EdgeInsets.fromLTRB(10.h, 7.h, 8.h, 7.h),
              decoration: BoxDecoration(color: AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(10.h)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.manrope('Hỗ trợ lái', fontSize: 13.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                        AppText.manrope(
                          'Thả cần lái xe tự giữ làn, tự chậm sau xe trước và trước khúc cua',
                          fontSize: 9.5.h,
                          fontWeight: FontWeight.w600,
                          maxLines: 2,
                          color: AppColors.ff6B7280,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.h),
                  _Toggle(on: assist),
                ],
              ),
            ),
          ),
          SizedBox(height: 6.h),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () {
              AudioService.shared.click();
              controller.setHaptics(!controller.haptics.value);
            },
            child: Container(
              height: 36.h,
              padding: EdgeInsets.fromLTRB(10.h, 0, 8.h, 0),
              decoration: BoxDecoration(color: AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(10.h)),
              child: Row(
                children: [
                  Expanded(child: AppText.manrope('Rung máy khi va chạm, quệt lề', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22)),
                  _Toggle(on: controller.haptics.value),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Công tắc bật / tắt (đỏ khi bật).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 44.h,
      height: 26.h,
      padding: EdgeInsets.all(3.h),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: on ? AppColors.ffD62828 : AppColors.ffC9CDD3,
        borderRadius: BorderRadius.circular(13.h),
      ),
      child: Container(
        width: 20.h,
        height: 20.h,
        decoration: const BoxDecoration(color: AppColors.ffFFFFFF, shape: BoxShape.circle),
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
          if (result.won) ResultMissions(result: result, compact: summary != null),
          if (summary != null) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.h, vertical: 8.h),
              decoration: BoxDecoration(
                color: summary.newRecord ? AppColors.ffFFD166.withValues(alpha: 0.35) : AppColors.ffF2F3F5,
                borderRadius: BorderRadius.circular(12.h),
              ),
              child: AppText.manrope(
                '${summary.newRecord ? 'Kỷ lục mới cho tuyến này: ${summary.record.score} điểm!' : 'Cả chuyến: ${summary.record.score} điểm · kỷ lục ${summary.previousBest} điểm'}'
                '${summary.giftBonus > 0 ? '\nGồm +${summary.giftBonus} điểm quà Tết biếu cả nhà' : ''}',
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
                    : AppButton(label: 'Chơi lại', icon: Img.icRetry, onPressed: controller.retry),
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
