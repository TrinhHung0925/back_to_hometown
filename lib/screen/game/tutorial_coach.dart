import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../game/logic/tutorial.dart';
import '../../game/stage.dart';
import '../../game/tutorial_director.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../route.dart';
import '../../service/audio_service.dart';
import '../../service/local_service.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Chặng tập lái kết thúc vì tập xong hết hay vì đã về tới thị trấn.
enum TutorialEnd { complete, arrived }

/// Huấn luyện viên của chặng tập lái: chấm từng bước theo số liệu thật của
/// xe (qua [TutorialDirector] chạy trong vòng lặp game), chúc mừng mỗi bước
/// xong, cuối cùng hiện bảng tổng kết.
class TutorialCoachController extends GetxController {
  TutorialCoachController(this.host);

  final GameController host;

  late TutorialTracker tracker;

  /// Bước đang hướng dẫn (null khi đã xong hết).
  final step = Rxn<TutorialStep>();

  /// Bước vừa xong, đang hiện dấu tích (thẻ giữ bước này thêm một nhịp).
  final cheered = Rxn<TutorialStep>();
  final progress = 0.0.obs;
  final cue = ''.obs;

  /// Kết quả từng bước (chấm tiến độ, bảng tổng kết).
  final outcomes = <TutorialOutcome?>[].obs;

  /// Bảng kết thúc đang hiện (null = đang tập).
  final end = Rxn<TutorialEnd>();

  Worker? _gameWorker;
  Timer? _cheerTimer;
  Timer? _endTimer;
  bool _ending = false;

  static const _cheers = ['Tuyệt!', 'Chuẩn rồi!', 'Giỏi lắm!', 'Đúng rồi!', 'Ngon lành!'];

  /// Lời khen cho bước vừa xong.
  String get cheer => _cheers[(cheered.value?.index ?? 0) % _cheers.length];

  @override
  void onInit() {
    super.onInit();
    _attach();
    // Chơi lại / đổi bản đồ thì GameController dựng game mới: tập lại từ đầu.
    _gameWorker = ever(host.gameKey, (_) => _attach());
  }

  void _attach() {
    _cheerTimer?.cancel();
    _endTimer?.cancel();
    _ending = false;
    final game = host.game;
    tracker = TutorialTracker();
    // Tập từ lúc xe còn đứng yên ở bãi tập, đường thưa xe.
    game.player
      ..speed = 0
      ..cruise = 0;
    game.traffic.density = TutorialPlan.trafficDensity;
    game.add(TutorialDirector(game: game, tracker: tracker, honks: () => host.hornTick.value, onStep: _onStep, onTick: _onTick));
    step.value = tracker.step;
    cheered.value = null;
    progress.value = 0;
    cue.value = '';
    outcomes.assignAll(tracker.outcomes);
    end.value = null;
  }

  void _onStep(TutorialStep done) {
    outcomes.assignAll(tracker.outcomes);
    cheered.value = done;
    AudioService.shared.play(AppAudio.sfxConfirm, volume: 0.7);
    if (host.haptics.value) HapticFeedback.lightImpact();
    _cheerTimer?.cancel();
    _cheerTimer = Timer(const Duration(milliseconds: 1100), _afterCheer);
  }

  void _afterCheer() {
    cheered.value = null;
    step.value = tracker.step;
    if (tracker.finished) _finish(TutorialEnd.complete);
  }

  void _onTick() {
    final p = (tracker.progress * 50).round() / 50;
    if (p != progress.value) progress.value = p;
    if (cue.value != tracker.cue) cue.value = tracker.cue;
    if (host.game.phase == GamePhase.finished) _finish(TutorialEnd.arrived);
  }

  /// Bỏ qua bước đang tập (đang chúc mừng thì chưa bỏ được).
  void skip() {
    if (_ending || cheered.value != null || tracker.finished) return;
    tracker.skip();
    outcomes.assignAll(tracker.outcomes);
    step.value = tracker.step;
    if (tracker.finished) _finish(TutorialEnd.complete);
  }

  void _finish(TutorialEnd kind) {
    if (_ending) return;
    _ending = true;
    _cheerTimer?.cancel();
    LocalService.shared.saveTutorialDone();
    // Đã tập rồi thì khỏi hiện thẻ "Cách lái" ở chặng thật.
    LocalService.shared.saveCruiseTipShown();
    host
      ..onThrottle(false)
      ..onBrake(false);
    _endTimer = Timer(Duration(milliseconds: kind == TutorialEnd.complete ? 500 : 1200), () {
      cheered.value = null;
      step.value = tracker.step;
      end.value = tracker.finished && tracker.skippedCount == 0 ? TutorialEnd.complete : kind;
      host.game.pauseEngine();
      final audio = AudioService.shared;
      if (audio.enabled) {
        audio
          ..pauseLoops()
          ..play(AppAudio.jingleWin, volume: 0.8);
      }
    });
  }

  /// Tập lại từ đầu (đường mới).
  void again() => host.retry();

  /// Lên đường thật: sang màn chọn cách về quê.
  void goHome() => Get.offNamed(AppPage.chooseMode.routeName);

  @override
  void onClose() {
    _gameWorker?.dispose();
    _cheerTimer?.cancel();
    _endTimer?.cancel();
    super.onClose();
  }
}

/// Lớp hướng dẫn của chặng tập lái: thẻ huấn luyện góc trên bên trái, vòng
/// sáng chỉ nút cần bấm, bảng tổng kết khi xong.
class TutorialCoach extends StatefulWidget {
  const TutorialCoach({super.key, required this.controller});

  final GameController controller;

  @override
  State<TutorialCoach> createState() => _TutorialCoachState();
}

class _TutorialCoachState extends State<TutorialCoach> {
  late final TutorialCoachController coach = Get.put(TutorialCoachController(widget.controller));

  @override
  void dispose() {
    Get.delete<TutorialCoachController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.controller;
    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: Obx(() {
              final cheered = coach.cheered.value;
              final step = cheered ?? coach.step.value;
              final hidden =
                  coach.end.value != null ||
                  host.isPaused.value ||
                  host.chatOpen.value ||
                  host.phase.value == GamePhase.resting ||
                  host.phase.value == GamePhase.finished;
              if (hidden || step == null) return const SizedBox.shrink();
              final horizontal = host.driverView.value;
              return Stack(
                children: [
                  if (cheered == null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _Spotlight(step: step, horizontal: horizontal),
                      ),
                    ),
                  Positioned(
                    left: 12.h,
                    top: 58.h,
                    child: _CoachCard(coach: coach, step: step, horizontal: horizontal, assist: host.driveAssist.value),
                  ),
                ],
              );
            }),
          ),
        ),
        Obx(() {
          final end = coach.end.value;
          if (end == null) return const SizedBox.shrink();
          return Positioned.fill(
            child: TutorialFinishCard(end: end, outcomes: coach.outcomes.toList(), onHome: coach.goHome, onAgain: coach.again),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------- Thẻ
/// Thẻ huấn luyện gọn (chỉ nằm trên phần làn ngược chiều, không che làn
/// mình): minh hoạ, tên bước, lời chỉ dẫn, dòng nhắc theo tình trạng xe,
/// chấm tiến độ; thanh tiến độ chạy dọc mép dưới thẻ.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.coach, required this.step, required this.horizontal, required this.assist});

  final TutorialCoachController coach;
  final TutorialStep step;
  final bool horizontal;
  final bool assist;

  @override
  Widget build(BuildContext context) {
    final cheering = coach.cheered.value != null;
    final accent = cheering ? AppColors.ff4ADE80 : AppColors.ffFFB020;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 300.h,
      decoration: BoxDecoration(
        color: AppColors.ff1B1D22.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14.h),
        border: Border.all(color: accent.withValues(alpha: 0.85), width: 1.5.h),
        boxShadow: [
          BoxShadow(color: AppColors.shadowSoft, blurRadius: 12.h, offset: Offset(0, 4.h)),
          if (cheering) BoxShadow(color: AppColors.ff4ADE80.withValues(alpha: 0.35), blurRadius: 16.h),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8.h, 7.h, 10.h, 9.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.1, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  child: Row(
                    key: ValueKey(step),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StepArt(step: step, done: cheering),
                      SizedBox(width: 9.h),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText.manrope(
                              'TẬP LÁI · BƯỚC ${step.index + 1}/${TutorialStep.values.length}',
                              fontSize: 8.5.h,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.h,
                              lineHeight: 1.25,
                              color: AppColors.ffFFB020,
                            ),
                            AppText.manrope(
                              step.title,
                              fontSize: 14.h,
                              fontWeight: FontWeight.w800,
                              lineHeight: 1.2,
                              maxLines: 1,
                              color: cheering ? AppColors.ff4ADE80 : AppColors.ffFFFFFF,
                            ),
                            SizedBox(height: 1.h),
                            AppText.manrope(
                              step.detail(horizontal: horizontal, assist: assist),
                              fontSize: 10.h,
                              fontWeight: FontWeight.w600,
                              lineHeight: 1.25,
                              maxLines: 2,
                              color: AppColors.ffB8BCC4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 5.h),
                Row(
                  children: [
                    Expanded(
                      child: Obx(() {
                        final cue = coach.cue.value;
                        return AppText.manrope(
                          cheering ? coach.cheer : cue,
                          fontSize: 10.5.h,
                          fontWeight: FontWeight.w800,
                          maxLines: 1,
                          color: cheering ? AppColors.ff4ADE80 : AppColors.ffFFD166,
                        );
                      }),
                    ),
                    SizedBox(width: 8.h),
                    Obx(() => _StepDots(outcomes: coach.outcomes.toList(), current: step.index)),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 5.h,
            right: 6.h,
            child: _SkipButton(enabled: !cheering, onPressed: coach.skip),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Obx(() {
              final value = coach.progress.value;
              return _ProgressBar(value: cheering ? 1.0 : value, color: cheering ? AppColors.ff4ADE80 : AppColors.ffFFD166);
            }),
          ),
        ],
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.enabled, required this.onPressed});

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
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          padding: EdgeInsets.fromLTRB(8.h, 3.h, 6.h, 3.h),
          decoration: BoxDecoration(color: AppColors.ffFFFFFF.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8.h)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText.manrope('Bỏ qua', fontSize: 10.h, fontWeight: FontWeight.w800, color: AppColors.ffE3E5E9),
              SizedBox(width: 4.h),
              SizedBox(
                width: 5.h,
                height: 8.h,
                child: CustomPaint(painter: _ChevronPainter(AppColors.ffE3E5E9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh tiến độ mảnh dọc mép dưới thẻ.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 200),
      builder: (context, v, _) => Container(
        height: 3.h,
        color: AppColors.ffFFFFFF.withValues(alpha: 0.1),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(2.h)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chấm tiến độ: xong (vàng), bỏ qua (vòng rỗng), đang tập (vạch dài),
/// chưa tới (mờ).
class _StepDots extends StatelessWidget {
  const _StepDots({required this.outcomes, required this.current});

  final List<TutorialOutcome?> outcomes;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < outcomes.length; i++) ...[
          if (i > 0) SizedBox(width: 4.h),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            width: i == current && outcomes[i] == null ? 14.h : 6.h,
            height: 6.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3.h),
              color: switch (outcomes[i]) {
                TutorialOutcome.done => AppColors.ffFFD166,
                TutorialOutcome.skipped => AppColors.ff1B1D22,
                null => i == current ? AppColors.ffFFB020 : AppColors.ffFFFFFF.withValues(alpha: 0.2),
              },
              border: outcomes[i] == TutorialOutcome.skipped
                  ? Border.all(color: AppColors.ffB8BCC4.withValues(alpha: 0.7), width: 1.2.h)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------- Minh hoạ
/// Ô minh hoạ bước đang tập (nút ga nhấp nháy, xe đổi làn, đèn giao thông…);
/// xong bước thì hiện dấu tích xanh.
class _StepArt extends StatefulWidget {
  const _StepArt({required this.step, required this.done});

  final TutorialStep step;
  final bool done;

  @override
  State<_StepArt> createState() => _StepArtState();
}

class _StepArtState extends State<_StepArt> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final AnimationController _check = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.done ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _StepArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done && !oldWidget.done) _check.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 50.h;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff2B3038, AppColors.ff121418],
        ),
        borderRadius: BorderRadius.circular(12.h),
        border: Border.all(color: AppColors.ffFFFFFF.withValues(alpha: 0.08), width: 1.h),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _check]),
        builder: (context, _) {
          if (widget.done) return CustomPaint(painter: _CheckPainter(Curves.easeOutBack.transform(_check.value.clamp(0.0, 1.0))));
          final t = _loop.value;
          return switch (widget.step) {
            TutorialStep.tapGas => _ButtonArt(icon: Img.icPedalGas, t: t, tap: true, label: '+5', labelColor: AppColors.ff4ADE80),
            TutorialStep.holdGas => _ButtonArt(icon: Img.icPedalGas, t: t, tap: false, label: 'GIỮ', labelColor: AppColors.ffFFD166),
            TutorialStep.tapBrake => _ButtonArt(icon: Img.icPedalBrake, t: t, tap: true, label: '−5', labelColor: AppColors.ffFFB020),
            TutorialStep.horn => _ButtonArt(icon: Img.icHorn, t: t, tap: true, waves: true),
            TutorialStep.headlights => _ButtonArt(icon: Img.icHeadlight, t: t, tap: true, beams: true),
            TutorialStep.laneInner => CustomPaint(painter: _LanePainter(t, inner: true)),
            TutorialStep.laneOuter => CustomPaint(painter: _LanePainter(t, inner: false)),
            TutorialStep.redLight => CustomPaint(painter: _SignalPainter(t, red: true)),
            TutorialStep.greenGo => CustomPaint(painter: _SignalPainter(t, red: false)),
          };
        },
      ),
    );
  }
}

/// Nút điều khiển thu nhỏ (đúng ảnh nút trong game) với gợn chạm / vòng giữ.
class _ButtonArt extends StatelessWidget {
  const _ButtonArt({
    required this.icon,
    required this.t,
    required this.tap,
    this.label,
    this.labelColor = AppColors.ffFFFFFF,
    this.waves = false,
    this.beams = false,
  });

  final String icon;
  final double t;
  final bool tap;
  final String? label;
  final Color labelColor;
  final bool waves;
  final bool beams;

  @override
  Widget build(BuildContext context) {
    // Chạm: nút nhún xuống ở đầu mỗi nhịp; giữ: nút ấn suốt lúc vòng chạy.
    final pressed = tap ? (t % 0.5) < 0.12 && t < 0.62 : t < 0.72;
    final shift = beams || waves ? -5.h : 0.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PressPainter(t, tap: tap, waves: waves, beams: beams, shift: shift),
          ),
        ),
        Transform.translate(
          offset: Offset(shift, 0),
          child: AnimatedScale(
            scale: pressed ? 0.88 : 1,
            duration: const Duration(milliseconds: 70),
            child: SizedBox(
              width: 32.h,
              height: 32.h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(Img.icButtonCircle, width: 32.h, height: 32.h),
                  Image.asset(icon, width: 15.h, height: 15.h),
                ],
              ),
            ),
          ),
        ),
        if (label != null)
          Positioned(
            right: 3.h,
            bottom: 3.h,
            child: Container(
              padding: EdgeInsets.fromLTRB(4.h, 1.h, 4.h, 1.h),
              decoration: BoxDecoration(color: AppColors.ff1B1D22, borderRadius: BorderRadius.circular(5.h)),
              child: AppText.manrope(label!, fontSize: 9.h, fontWeight: FontWeight.w800, lineHeight: 1.1, color: labelColor),
            ),
          ),
      ],
    );
  }
}

/// Gợn tròn lúc chạm, vòng sáng chạy quanh nút lúc giữ, sóng còi, tia đèn.
class _PressPainter extends CustomPainter {
  _PressPainter(this.t, {required this.tap, required this.waves, required this.beams, required this.shift});

  final double t;
  final bool tap;
  final bool waves;
  final bool beams;
  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset(shift, 0));
    final r = size.width * 0.31;
    if (waves) {
      // Sóng âm loang ra bên phải.
      for (var i = 0; i < 3; i++) {
        final k = (t * 1.6 - i * 0.22) % 1.0;
        if (k < 0 || k > 0.85) continue;
        final rr = r + 4 + k * size.width * 0.32;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: rr),
          -0.6,
          1.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.04
            ..strokeCap = StrokeCap.round
            ..color = AppColors.ffFFD166.withValues(alpha: (1 - k / 0.85) * 0.9),
        );
      }
      return;
    }
    if (beams) {
      // Đèn pha bật tắt: chùm tia vàng hắt sang phải.
      final on = (t % 1.0) < 0.6;
      if (!on) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.045
        ..strokeCap = StrokeCap.round
        ..color = AppColors.ffFFD166.withValues(alpha: 0.9);
      for (final a in [-0.32, 0.0, 0.32]) {
        final from = c + Offset(cos(a), sin(a)) * (r + 3);
        final to = c + Offset(cos(a), sin(a)) * (r + size.width * 0.24);
        canvas.drawLine(from, to, paint);
      }
      return;
    }
    if (tap) {
      // Hai lần chạm mỗi nhịp: vòng gợn nở ra rồi mờ đi.
      for (final start in [0.0, 0.5]) {
        final k = (t - start) / 0.42;
        if (k < 0 || k > 1) continue;
        canvas.drawCircle(
          c,
          r + k * size.width * 0.16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.035 * (1 - k * 0.6)
            ..color = AppColors.ffFFFFFF.withValues(alpha: (1 - k) * 0.8),
        );
      }
      return;
    }
    // Giữ: vòng xanh chạy dần quanh nút rồi bắt đầu lại.
    final k = (t / 0.72).clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: c, radius: r + 4.5);
    canvas.drawCircle(
      c,
      r + 4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..color = AppColors.ffFFFFFF.withValues(alpha: 0.12),
    );
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * k,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round
        ..color = AppColors.ff4ADE80.withValues(alpha: t < 0.86 ? 1 : (1 - (t - 0.86) / 0.14)),
    );
  }

  @override
  bool shouldRepaint(covariant _PressPainter old) => old.t != t || old.tap != tap || old.waves != waves || old.beams != beams;
}

/// Hai làn chiều mình nhìn từ trên (vạch vàng giữa đường ở trên, lề ở dưới),
/// xe nhỏ chạy sang làn trong / về làn ngoài.
class _LanePainter extends CustomPainter {
  _LanePainter(this.t, {required this.inner});

  final double t;
  final bool inner;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.16, bottom = h * 0.84;
    final mid = (top + bottom) / 2;
    canvas.drawRect(Rect.fromLTRB(0, top, w, bottom), Paint()..color = AppColors.ff5B6169);
    // Lề cỏ hai bên.
    canvas.drawRect(Rect.fromLTRB(0, 0, w, top), Paint()..color = AppColors.ff1E9C53.withValues(alpha: 0.75));
    canvas.drawRect(Rect.fromLTRB(0, bottom, w, h), Paint()..color = AppColors.ff1E9C53.withValues(alpha: 0.75));
    final line = Paint()..strokeWidth = h * 0.035;
    canvas.drawLine(Offset(0, top + h * 0.03), Offset(w, top + h * 0.03), line..color = AppColors.ffF2C12E);
    canvas.drawLine(Offset(0, bottom - h * 0.03), Offset(w, bottom - h * 0.03), line..color = AppColors.ffFFFFFF.withValues(alpha: 0.8));
    // Vạch đứt chia làn, trôi sang trái như xe đang chạy.
    final dash = w * 0.2, gap = w * 0.14;
    final scroll = (t * (dash + gap) * 2) % (dash + gap);
    final dashPaint = Paint()
      ..color = AppColors.ffFFFFFF.withValues(alpha: 0.85)
      ..strokeWidth = h * 0.03;
    for (var x = -scroll; x < w; x += dash + gap) {
      canvas.drawLine(Offset(x, mid), Offset(x + dash, mid), dashPaint);
    }
    // Xe: nằm yên ở làn cũ, gạt sang làn mới, đứng ở làn mới rồi lặp lại.
    final innerY = (top + mid) / 2, outerY = (mid + bottom) / 2;
    final fromY = inner ? outerY : innerY, toY = inner ? innerY : outerY;
    final k = Curves.easeInOutCubic.transform(((t - 0.2) / 0.45).clamp(0.0, 1.0));
    final y = fromY + (toY - fromY) * k;
    final yaw = sin(k * pi) * (toY < fromY ? -0.32 : 0.32);
    final car = Offset(w * 0.46, y);
    // Mũi tên cong chỉ hướng đổi làn.
    if (t < 0.25) {
      final arrow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.035
        ..strokeCap = StrokeCap.round
        ..color = AppColors.ffFFD166;
      final start = Offset(w * 0.64, fromY);
      final end = Offset(w * 0.86, toY);
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(end.dx - w * 0.04, fromY, end.dx, end.dy),
        arrow,
      );
      final dirY = toY < fromY ? -1.0 : 1.0;
      canvas.drawPath(
        Path()
          ..moveTo(end.dx - w * 0.06, end.dy - dirY * h * 0.02)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx + w * 0.045, end.dy - dirY * h * 0.06),
        arrow,
      );
    }
    canvas.save();
    canvas.translate(car.dx, car.dy);
    canvas.rotate(yaw);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w * 0.3, height: h * 0.15), Radius.circular(h * 0.05));
    canvas.drawRRect(body.shift(Offset(0, h * 0.02)), Paint()..color = AppColors.shadowSoft);
    canvas.drawRRect(body, Paint()..color = AppColors.ffD62828);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.045, 0), width: w * 0.07, height: h * 0.11), Radius.circular(h * 0.02)),
      Paint()..color = AppColors.ff121418.withValues(alpha: 0.75),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LanePainter old) => old.t != t || old.inner != inner;
}

/// Cột đèn giao thông: đèn đỏ sáng rực (xe dừng trước vạch) hoặc đèn xanh
/// (mũi tên đi tiếp).
class _SignalPainter extends CustomPainter {
  _SignalPainter(this.t, {required this.red});

  final double t;
  final bool red;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final housing = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.12, w * 0.3, h * 0.76), Radius.circular(w * 0.08));
    canvas.drawRRect(housing, Paint()..color = AppColors.ff0E1216);
    canvas.drawRRect(
      housing,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025
        ..color = AppColors.ffFFFFFF.withValues(alpha: 0.18),
    );
    final lit = red ? 0 : 2;
    final colors = [AppColors.ffFF5A4E, AppColors.ffFFB020, AppColors.ff4ADE80];
    final pulse = 0.75 + 0.25 * sin(t * 2 * pi);
    for (var i = 0; i < 3; i++) {
      final c = Offset(w * 0.29, h * (0.25 + i * 0.25));
      final r = w * 0.085;
      if (i == lit) {
        canvas.drawCircle(
          c,
          r * 2.1,
          Paint()
            ..color = colors[i].withValues(alpha: 0.32 * pulse)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
        );
        canvas.drawCircle(c, r, Paint()..color = colors[i]);
      } else {
        canvas.drawCircle(c, r, Paint()..color = AppColors.ff2B3038);
      }
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (red) {
      // Vạch dừng và chữ "dừng" dạng bàn tay giơ: hai vạch ngang song song.
      canvas.drawLine(Offset(w * 0.78, h * 0.18), Offset(w * 0.78, h * 0.82), stroke..color = AppColors.ffFFFFFF.withValues(alpha: 0.9));
      final bob = sin(t * 2 * pi) * h * 0.02;
      final car = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.62, h * 0.5 + bob * 0), width: w * 0.13, height: h * 0.26),
        Radius.circular(w * 0.04),
      );
      canvas.drawRRect(car, Paint()..color = AppColors.ffD62828);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * 0.62, h * 0.43), width: w * 0.09, height: h * 0.07),
          Radius.circular(w * 0.015),
        ),
        Paint()..color = AppColors.ff121418.withValues(alpha: 0.75),
      );
      // Đèn phanh đỏ sau xe.
      final brakeGlow = Paint()..color = AppColors.ffFF5A4E.withValues(alpha: pulse);
      canvas.drawCircle(Offset(w * 0.575, h * 0.625), w * 0.018, brakeGlow);
      canvas.drawCircle(Offset(w * 0.665, h * 0.625), w * 0.018, brakeGlow);
    } else {
      final k = (t * 1.4) % 1.0;
      final x = w * (0.56 + 0.14 * k);
      final arrow = stroke..color = AppColors.ff4ADE80.withValues(alpha: 1 - k * 0.6);
      canvas.drawLine(Offset(x, h * 0.5), Offset(x + w * 0.2, h * 0.5), arrow);
      canvas.drawPath(
        Path()
          ..moveTo(x + w * 0.12, h * 0.4)
          ..lineTo(x + w * 0.2, h * 0.5)
          ..lineTo(x + w * 0.12, h * 0.6),
        arrow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter old) => old.t != t || old.red != red;
}

/// Vòng tròn xanh nở ra, dấu tích vẽ dần.
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.k);

  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.3 * k.clamp(0.0, 1.2);
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..color = AppColors.ff4ADE80.withValues(alpha: 0.25 * k.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.08),
    );
    canvas.drawCircle(c, r, Paint()..color = AppColors.ff27AE60);
    final draw = ((k - 0.35) / 0.65).clamp(0.0, 1.0);
    if (draw <= 0) return;
    final a = c + Offset(-size.width * 0.13, 0);
    final b = c + Offset(-size.width * 0.03, size.width * 0.1);
    final e = c + Offset(size.width * 0.15, -size.width * 0.11);
    final path = Path()..moveTo(a.dx, a.dy);
    if (draw < 0.4) {
      final p = Offset.lerp(a, b, draw / 0.4)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, e, (draw - 0.4) / 0.6)!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.ffFFFFFF,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.k != k;
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.15, 0)
        ..lineTo(size.width * 0.85, size.height / 2)
        ..lineTo(size.width * 0.15, size.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.32
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.color != color;
}

// --------------------------------------------------- Chỉ nút cần bấm
/// Vòng sáng nhấp nháy quanh nút cần bấm (ga, phanh, còi, đèn); hai bước đổi
/// làn thì cần lái "tự gạt" mẫu cho xem.
class _Spotlight extends StatefulWidget {
  const _Spotlight({required this.step, required this.horizontal});

  final TutorialStep step;
  final bool horizontal;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Tâm và bán kính các nút trong cụm [ActionButtons] (cùng cách tính: cụm
  /// cách mép phải 14, mép dưới 18; nút ga to ở góc, các nút khác xếp vòng
  /// cung bán kính 112 quanh nó).
  static (Offset, double) _button(Size area, double degrees, double size) {
    final ring = 118.h, radius = 112.h;
    final gas = Offset(area.width - 14.h - ring / 2, area.height - 18.h - ring / 2);
    if (degrees.isNaN) return (gas, ring / 2);
    final a = degrees * pi / 180;
    return (gas + Offset(cos(a) * radius, -sin(a) * radius), size / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final target = switch (widget.step) {
          TutorialStep.tapGas || TutorialStep.holdGas || TutorialStep.greenGo => _button(area, double.nan, 0),
          TutorialStep.tapBrake || TutorialStep.redLight => _button(area, 176, 74.h),
          TutorialStep.horn => _button(area, 133, 62.h),
          TutorialStep.headlights => _button(area, 92, 62.h),
          TutorialStep.laneInner || TutorialStep.laneOuter => null,
        };
        // Đế cần lái lúc chưa chạm (xem SteeringStick: cách trái 18 + nửa đế,
        // cách đáy 10 + nửa đế).
        final stick = Offset(18.h + 62.h, area.height - 10.h - 62.h);
        return AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => CustomPaint(
            size: area,
            painter: target != null
                ? _PulsePainter(
                    _anim.value,
                    center: target.$1,
                    radius: target.$2 + 3.h,
                    hold: widget.step == TutorialStep.holdGas || widget.step == TutorialStep.redLight,
                  )
                : _GhostStickPainter(
                    _anim.value,
                    center: stick,
                    pad: 62.h,
                    travel: 34.h,
                    up: widget.step == TutorialStep.laneInner,
                    horizontal: widget.horizontal,
                  ),
          ),
        );
      },
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, {required this.center, required this.radius, required this.hold});

  final double t;
  final Offset center;
  final double radius;

  /// Nút phải giữ: thêm cung sáng chạy vòng quanh.
  final bool hold;

  @override
  void paint(Canvas canvas, Size size) {
    for (final start in [0.0, 0.5]) {
      final k = (t - start) % 1.0;
      canvas.drawCircle(
        center,
        radius * (1 + 0.32 * k),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.07 * (1 - k * 0.5)
          ..color = AppColors.ffFFD166.withValues(alpha: (1 - k) * 0.85),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.06
        ..color = AppColors.ffFFD166.withValues(alpha: 0.9),
    );
    if (hold) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + radius * 0.12),
        -pi / 2,
        2 * pi * t,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.08
          ..strokeCap = StrokeCap.round
          ..color = AppColors.ff4ADE80,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.t != t || old.center != center || old.radius != radius || old.hold != hold;
}

/// Ngón tay ma gạt cần lái: núm lướt lên (hoặc sang trái ở ghế lái) rồi thả
/// về giữa, kèm mũi tên chỉ hướng.
class _GhostStickPainter extends CustomPainter {
  _GhostStickPainter(this.t, {required this.center, required this.pad, required this.travel, required this.up, required this.horizontal});

  final double t;
  final Offset center;
  final double pad;
  final double travel;
  final bool up;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    final sign = up ? -1.0 : 1.0;
    final axis = horizontal ? Offset(sign, 0) : Offset(0, sign);
    // 0–0.3 gạt ra, 0.3–0.55 giữ, 0.55–0.7 thả về, còn lại nghỉ.
    final k = t < 0.3
        ? Curves.easeOutCubic.transform(t / 0.3)
        : t < 0.55
        ? 1.0
        : t < 0.7
        ? 1 - Curves.easeInCubic.transform((t - 0.55) / 0.15)
        : 0.0;
    canvas.drawCircle(
      center,
      pad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pad * 0.05
        ..color = AppColors.ffFFD166.withValues(alpha: 0.55 + 0.35 * sin(t * 2 * pi).abs()),
    );
    // Mũi tên đôi chỉ hướng gạt, đặt cạnh đế (phía trên khi gạt ngang, bên
    // phải khi gạt dọc) để không lọt ra ngoài mép màn hình.
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = pad * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final side = Offset(-axis.dy, axis.dx);
    final anchor = center + (horizontal ? const Offset(0, -1) : const Offset(1, 0)) * (pad + pad * 0.3);
    for (final i in [0, 1]) {
      final tip = anchor + axis * (pad * 0.12 + i * pad * 0.24);
      final back = tip - axis * pad * 0.16;
      canvas.drawPath(
        Path()
          ..moveTo(back.dx + side.dx * pad * 0.2, back.dy + side.dy * pad * 0.2)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(back.dx - side.dx * pad * 0.2, back.dy - side.dy * pad * 0.2),
        arrow..color = AppColors.ffFFD166.withValues(alpha: i == 0 ? 0.55 : 0.95),
      );
    }
    final nub = center + axis * travel * k;
    canvas.drawCircle(nub, pad * 0.44, Paint()..color = AppColors.ffFFFFFF.withValues(alpha: 0.32));
    canvas.drawCircle(
      nub,
      pad * 0.44,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pad * 0.05
        ..color = AppColors.ffFFFFFF.withValues(alpha: 0.85),
    );
    // Đầu ngón tay ấn lên núm (chấm mờ), nhấc ra lúc thả.
    if (t < 0.6) canvas.drawCircle(nub, pad * 0.2, Paint()..color = AppColors.ffFFD166.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _GhostStickPainter old) =>
      old.t != t || old.center != center || old.up != up || old.horizontal != horizontal;
}

// ------------------------------------------------------- Bảng kết thúc
/// Bảng tổng kết chặng tập: các kỹ năng đã tập, "Về quê thôi" / "Tập lại".
class TutorialFinishCard extends StatefulWidget {
  const TutorialFinishCard({super.key, required this.end, required this.outcomes, required this.onHome, required this.onAgain});

  final TutorialEnd end;
  final List<TutorialOutcome?> outcomes;
  final VoidCallback onHome;
  final VoidCallback onAgain;

  @override
  State<TutorialFinishCard> createState() => _TutorialFinishCardState();
}

class _TutorialFinishCardState extends State<TutorialFinishCard> with TickerProviderStateMixin {
  late final AnimationController _petals = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();

  @override
  void dispose() {
    _petals.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.outcomes.where((o) => o != TutorialOutcome.done).length;
    final (title, subtitle) = switch ((widget.end, missing)) {
      (TutorialEnd.complete, 0) => ('Lái vững rồi!', 'Ga, phanh, cần lái, còi, đèn — đủ cả. Lên đường về quê đón Tết thôi!'),
      (TutorialEnd.arrived, _) => ('Tới thị trấn rồi!', 'Còn $missing bước chưa tập — tập lại cho quen tay nhé.'),
      _ => ('Tập xong rồi!', 'Bỏ qua $missing bước — muốn chắc tay thì tập lại nhé.'),
    };
    return Container(
      color: AppColors.ff1B1D22.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final k = Curves.easeOutBack.transform(_enter.value);
          return Opacity(
            opacity: _enter.value,
            child: Transform.scale(scale: 0.9 + 0.1 * k, child: child),
          );
        },
        child: Container(
          width: 480.h,
          decoration: BoxDecoration(
            color: AppColors.ffFFFBF2,
            borderRadius: BorderRadius.circular(20.h),
            border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
            boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.35), blurRadius: 20.h, offset: Offset(0, 8.h))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _petals,
                    builder: (context, _) => CustomPaint(painter: _PetalPainter(_petals.value)),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(22.h, 18.h, 22.h, 18.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _Medal(),
                        SizedBox(width: 14.h),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText.paytone(
                                title,
                                fontSize: 26.h,
                                color: AppColors.ffD62828,
                                shadow: const [Shadow(color: AppColors.ffFFD166, offset: Offset(0, 2))],
                              ),
                              SizedBox(height: 2.h),
                              AppText.manrope(
                                subtitle,
                                fontSize: 13.h,
                                fontWeight: FontWeight.w600,
                                maxLines: 2,
                                color: AppColors.ff5B6169,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final gap = 8.h;
                        final chip = (constraints.maxWidth - 2 * gap) / 3;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final s in TutorialStep.values)
                              _SkillChip(width: chip, label: s.short, outcome: widget.outcomes.elementAtOrNull(s.index)),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppButton(label: 'Về quê thôi', icon: Img.icPlay, width: double.infinity, onPressed: widget.onHome),
                        ),
                        SizedBox(width: 12.h),
                        Expanded(
                          flex: 2,
                          child: AppButton(
                            label: 'Tập lại',
                            icon: Img.icRetry,
                            width: double.infinity,
                            color: AppColors.ff5B6169,
                            onPressed: widget.onAgain,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Huy hiệu vàng có vô-lăng.
class _Medal extends StatelessWidget {
  const _Medal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62.h,
      height: 62.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [AppColors.ffFFE3A1, AppColors.ffFFD166, AppColors.ffFFB020],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: AppColors.ff1B1D22, width: 2.5.h),
        boxShadow: [BoxShadow(color: AppColors.ffFFB020.withValues(alpha: 0.5), blurRadius: 12.h)],
      ),
      child: RoadIcon(RoadGlyph.steering, size: 34.h, color: AppColors.ff1B1D22),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.width, required this.label, required this.outcome});

  final double width;
  final String label;
  final TutorialOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final done = outcome == TutorialOutcome.done;
    return Container(
      width: width,
      height: 32.h,
      padding: EdgeInsets.symmetric(horizontal: 8.h),
      decoration: BoxDecoration(color: done ? AppColors.ffF1E7D2 : AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(10.h)),
      child: Row(
        children: [
          SizedBox(
            width: 18.h,
            height: 18.h,
            child: CustomPaint(painter: _MarkPainter(done)),
          ),
          SizedBox(width: 7.h),
          Expanded(
            child: AppText.manrope(
              label,
              fontSize: 12.h,
              fontWeight: FontWeight.w800,
              maxLines: 1,
              color: done ? AppColors.ff1B1D22 : AppColors.ff9A9385,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dấu tích xanh (đã tập) hoặc gạch ngang xám (bỏ qua).
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.done);

  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = done ? AppColors.ff27AE60 : AppColors.ffC9CDD3);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.ffFFFFFF;
    if (done) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.36)
          ..lineTo(c.dx + r * 0.48, c.dy - r * 0.32),
        stroke,
      );
    } else {
      canvas.drawLine(c + Offset(-r * 0.4, 0), c + Offset(r * 0.4, 0), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.done != done;
}

/// Cánh hoa đào, hoa mai rơi lả tả trên bảng tổng kết.
class _PetalPainter extends CustomPainter {
  _PetalPainter(this.t);

  final double t;

  static final List<(double, double, double, double, int)> _petals = () {
    final random = Random(27);
    return [
      for (var i = 0; i < 26; i++)
        (random.nextDouble(), random.nextDouble() * 0.45, 0.7 + random.nextDouble() * 0.6, 4 + random.nextDouble() * 4, random.nextInt(4)),
    ];
  }();

  static const _colors = [AppColors.ffF7A8BC, AppColors.ffFFD3DE, AppColors.ffFFD166, AppColors.ffE8768F];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
    if (fade <= 0) return;
    for (final (x0, delay, speed, petal, color) in _petals) {
      final k = (t - delay) / (1 - delay);
      if (k <= 0) continue;
      final y = -12 + k * size.height * 0.9 * speed;
      final x = x0 * size.width + sin(k * 6 + x0 * 9) * 14;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(k * 5 + x0 * 7);
      final s = petal * size.height / 260;
      canvas.drawPath(
        Path()
          ..moveTo(0, -s)
          ..quadraticBezierTo(s * 0.9, 0, 0, s)
          ..quadraticBezierTo(-s * 0.9, 0, 0, -s),
        Paint()..color = _colors[color].withValues(alpha: 0.85 * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) => old.t != t;
}
