import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/app_button.dart';
import '../../common/lixi_icon.dart';
import '../../game/logic/alcohol.dart';
import '../../game/ve_que_game.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Các bước ở bảng thổi: CSGT chào, chờ thổi, đang thổi, máy phân tích,
/// có kết quả, đã bấm đi tiếp.
enum _Stage { intro, ready, blowing, analyzing, result, closing }

/// Chốt kiểm tra nồng độ cồn đêm 30 Tết: CSGT đứng cạnh cửa xe cầm máy đo,
/// người chơi giữ nút "Thổi" chừng 2 giây cho thanh hơi đầy, máy phân tích
/// rồi ra số. Âm tính: chúc về quê an toàn; dương tính: biên bản, nộp phạt,
/// ngồi chờ tỉnh rượu.
class BreathTestOverlay extends StatefulWidget {
  const BreathTestOverlay({super.key, required this.controller, required this.check});

  final GameController controller;
  final BreathCheck check;

  @override
  State<BreathTestOverlay> createState() => _BreathTestOverlayState();
}

class _BreathTestOverlayState extends State<BreathTestOverlay> with TickerProviderStateMixin {
  /// Thổi đủ chừng này thì máy kêu bíp.
  static const Duration _blowTime = Duration(milliseconds: 2000);

  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  late final AnimationController _blow = AnimationController(vsync: this, duration: _blowTime);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  _Stage _stage = _Stage.intro;
  BreathReading? _reading;
  bool _short = false;
  int? _pointer;
  final List<Timer> _timers = [];
  Timer? _blowSound;

  AudioService get _audio => AudioService.shared;

  @override
  void initState() {
    super.initState();
    _blow.addStatusListener((status) {
      if (status == AnimationStatus.completed && _stage == _Stage.blowing) _analyze();
    });
    _after(1000, () {
      setState(() => _stage = _Stage.ready);
      _audio.play(AppAudio.sfxBreathBeep, volume: 0.6);
    });
  }

  void _after(int ms, VoidCallback fn) => _timers.add(Timer(Duration(milliseconds: ms), () {
        if (mounted) fn();
      }));

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _blowSound?.cancel();
    _enter.dispose();
    _blow.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _down(int pointer) {
    if (_pointer != null || _stage != _Stage.ready) return;
    setState(() {
      _pointer = pointer;
      _stage = _Stage.blowing;
      _short = false;
    });
    _blow.forward();
    _audio.play(AppAudio.sfxBreathBlow, volume: 0.8);
    _blowSound = Timer.periodic(const Duration(milliseconds: 480), (_) => _audio.play(AppAudio.sfxBreathBlow, volume: 0.8));
  }

  void _up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _blowSound?.cancel();
    if (_stage != _Stage.blowing) return;
    // Thổi chưa đủ hơi: thanh hơi tụt về, thổi lại.
    _blow.animateBack(0, duration: const Duration(milliseconds: 350));
    setState(() {
      _stage = _Stage.ready;
      _short = true;
    });
  }

  void _analyze() {
    _blowSound?.cancel();
    setState(() => _stage = _Stage.analyzing);
    _audio.play(AppAudio.sfxBreathBeep, volume: 0.6);
    _after(1300, () {
      final reading = widget.controller.game.blowBreath();
      setState(() {
        _reading = reading;
        _stage = _Stage.result;
      });
      _audio.play(AppAudio.sfxBreathBeep, volume: 0.7);
      if (reading.positive) _after(180, () => _audio.play(AppAudio.sfxBreathBeep, volume: 0.7));
    });
  }

  void _finish() {
    setState(() => _stage = _Stage.closing);
    widget.controller.game.finishBreathTest();
  }

  String get _line {
    final r = _reading;
    return switch (_stage) {
      _Stage.intro => 'Chào anh! Chốt kiểm tra nồng độ cồn đêm giao thừa — mời anh dừng xe, thổi vào máy đo.',
      _Stage.ready when _short => 'Thổi chưa đủ hơi rồi anh ơi — thổi lại, mạnh và dài hơi hơn nhé!',
      _Stage.ready => 'Anh ngậm ống thổi, thổi mạnh và đều cho tới khi máy kêu "bíp" nhé.',
      _Stage.blowing => 'Thổi tiếp… thổi tiếp… đều hơi…',
      _Stage.analyzing => 'Được rồi, anh chờ máy báo kết quả.',
      _Stage.result || _Stage.closing => r == null || !r.positive
          ? 'Không có nồng độ cồn. Cảm ơn anh đã chấp hành — chúc anh về quê ăn Tết an toàn!'
          : 'Máy báo ${r.display} mg/L — Tết vui chén rượu, nhưng đã uống rượu bia thì không lái xe anh nhé!',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.closing) return const SizedBox.shrink();
    final curve = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    return Container(
      color: AppColors.ff0B1020.withValues(alpha: 0.5),
      alignment: Alignment.center,
      child: FadeTransition(
        opacity: _enter,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curve),
          child: Container(
            width: 664.h,
            height: 314.h,
            decoration: BoxDecoration(
              color: AppColors.ffFBF6E9,
              borderRadius: BorderRadius.circular(16.h),
              border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
              boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.4), blurRadius: 24.h, offset: Offset(0, 8.h))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 196.h, child: _OfficerPanel(pulse: _pulse)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Band(clock: widget.check.clock),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(14.h, 10.h, 14.h, 12.h),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _Bubble(text: _line),
                                    SizedBox(height: 8.h),
                                    Expanded(child: _body()),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12.h),
                              AnimatedBuilder(
                                animation: Listenable.merge([_blow, _pulse]),
                                builder: (context, _) => CustomPaint(
                                  size: Size(112.h, 214.h),
                                  painter: _BreathalyzerPainter(
                                    stage: _stage,
                                    blow: _blow.value,
                                    pulse: _pulse.value,
                                    reading: _reading,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final r = _reading;
    switch (_stage) {
      case _Stage.intro:
      case _Stage.ready:
      case _Stage.blowing:
        return Row(
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _down(e.pointer),
              onPointerUp: (e) => _up(e.pointer),
              onPointerCancel: (e) => _up(e.pointer),
              child: AnimatedBuilder(
                animation: _blow,
                builder: (context, _) => _BlowButton(
                  size: 96.h,
                  progress: _blow.value,
                  pressed: _stage == _Stage.blowing,
                  enabled: _stage != _Stage.intro,
                ),
              ),
            ),
            SizedBox(width: 14.h),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(
                    _stage == _Stage.blowing ? 'Đang thổi…' : 'Giữ nút THỔI',
                    fontSize: 16.h,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ff1B1D22,
                  ),
                  SizedBox(height: 3.h),
                  AppText.manrope(
                    'Ngậm ống thổi mới bóc niêm phong, thổi đều chừng 2 giây cho tới khi máy kêu bíp.',
                    fontSize: 11.h,
                    fontWeight: FontWeight.w600,
                    maxLines: 3,
                    color: AppColors.ff6B7280,
                  ),
                  if (_short) ...[
                    SizedBox(height: 4.h),
                    AppText.manrope('Chưa đủ hơi — thổi lại nhé!', fontSize: 11.5.h, fontWeight: FontWeight.w800, color: AppColors.ffB4231E),
                  ],
                ],
              ),
            ),
          ],
        );
      case _Stage.analyzing:
        return Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 10.h,
                      height: 10.h,
                      margin: EdgeInsets.only(right: 6.h),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.ff23408E.withValues(alpha: 0.25 + 0.75 * (sin((_pulse.value - i * 0.18) * 2 * pi) * 0.5 + 0.5)),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8.h),
            Expanded(
              child: AppText.manrope('Máy đang phân tích hơi thở…', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ff23408E),
            ),
          ],
        );
      case _Stage.result:
      case _Stage.closing:
        return r != null && r.positive ? _positive(r) : _negative();
    }
  }

  Widget _negative() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44.h,
              height: 44.h,
              decoration: const BoxDecoration(color: AppColors.ff1E9C53, shape: BoxShape.circle),
              child: CustomPaint(painter: _CheckPainter()),
            ),
            SizedBox(width: 10.h),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope('0,00 mg/L khí thở', fontSize: 17.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53),
                  AppText.manrope('Không có nồng độ cồn — đạt, được đi tiếp', fontSize: 11.5.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        AppButton(label: 'Cảm ơn anh, đi tiếp', icon: Img.icPlay, color: AppColors.ff1E9C53, width: double.infinity, onPressed: _finish),
      ],
    );
  }

  Widget _positive(BreathReading r) {
    final fine = r.tier.fineLixi;
    final minutes = r.minutes.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Field(label: 'Lỗi vi phạm', value: 'Điều khiển xe mà trong hơi thở có nồng độ cồn', strong: true),
        _Field(label: 'Nồng độ đo', value: '${r.display} mg/L khí thở — ${r.tier.title}: ${r.tier.band}'),
        _Field(
          label: 'Mức phạt',
          value: r.enoughLixi ? '$fine lì xì · ngồi chờ tỉnh rượu $minutes phút' : 'Không đủ lì xì — nộp hết, chờ $minutes phút',
          lixi: true,
        ),
        const Spacer(),
        AppButton(label: 'Nộp phạt, ngồi chờ tỉnh rượu', color: AppColors.ff23408E, width: double.infinity, onPressed: _finish),
      ],
    );
  }
}

/// Băng phản quang vàng chanh: tên chốt và giờ kiểm tra.
class _Band extends StatelessWidget {
  const _Band({required this.clock});

  final String clock;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34.h,
      padding: EdgeInsets.symmetric(horizontal: 14.h),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ffC4D23E, AppColors.ffC4D23E, AppColors.ffE3E5E9, AppColors.ffC4D23E],
          stops: [0, 0.62, 0.7, 0.78],
        ),
      ),
      child: Row(
        children: [
          RoadIcon(RoadGlyph.breathalyzer, size: 19.h, color: AppColors.ff1B1D22, accent: AppColors.ffC4D23E),
          SizedBox(width: 8.h),
          Expanded(
            child: AppText.manrope('KIỂM TRA NỒNG ĐỘ CỒN', fontSize: 14.h, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.ff1B1D22),
          ),
          AppText.manrope('$clock · 30 Tết', fontSize: 11.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
        ],
      ),
    );
  }
}

/// Lời CSGT: bong bóng nền trắng, đuôi chỉ về phía người CSGT bên trái.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(11.h, 8.h, 11.h, 8.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(12.h),
        border: Border.all(color: AppColors.ffE9DFC6, width: 1.5.h),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Align(
          key: ValueKey(text),
          alignment: Alignment.centerLeft,
          child: AppText.manrope(text, fontSize: 12.h, fontWeight: FontWeight.w700, maxLines: 2, color: AppColors.ff23408E),
        ),
      ),
    );
  }
}

/// Một dòng biên bản: nhãn xám, nội dung mực xanh (lỗi in đỏ).
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.strong = false, this.lixi = false});

  final String label;
  final String value;
  final bool strong;
  final bool lixi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.5.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78.h,
            child: AppText.manrope('$label:', fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
          ),
          if (lixi) ...[LixiIcon(height: 15.h), SizedBox(width: 5.h)],
          Expanded(
            child: AppText.manrope(
              value,
              fontSize: strong ? 12.5.h : 11.5.h,
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

/// Bên trái bảng: CSGT đứng cạnh cửa xe trong đêm, đèn xanh đỏ xe tuần tra
/// hắt lên nhấp nháy.
class _OfficerPanel extends StatelessWidget {
  const _OfficerPanel({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => CustomPaint(painter: _NightPainter(pulse.value)),
            ),
          ),
          Positioned(
            left: -40.h,
            right: -40.h,
            bottom: -h * 0.52,
            height: h * 1.5,
            child: Image.asset(Img.imgOfficerBreath, fit: BoxFit.contain, alignment: Alignment.bottomCenter, filterQuality: FilterQuality.medium),
          ),
          Positioned(
            left: 10.h,
            bottom: 10.h,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.h, vertical: 3.h),
              decoration: BoxDecoration(color: AppColors.ff0E1626.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8.h)),
              child: AppText.manrope('CSGT · Tổ công tác', fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ffC4D23E),
            ),
          ),
        ],
      );
    });
  }
}

/// Nền đêm xanh thẫm, đèn xe tuần tra xanh / đỏ loé luân phiên, đèn chiếu
/// dã chiến hắt sáng trắng từ trên.
class _NightPainter extends CustomPainter {
  _NightPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff16233A, AppColors.ff0E1626],
        ).createShader(rect),
    );
    final red = t < 0.5;
    final flash = sin(t * 2 * pi * 2).abs();
    void glow(Offset c, double r, Color color, double a) => canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [color.withValues(alpha: a), color.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: r)),
        );
    glow(Offset(size.width * 0.08, size.height * 0.1), size.width * 0.8, AppColors.ffD62828, red ? 0.55 * flash : 0.1);
    glow(Offset(size.width * 0.92, size.height * 0.12), size.width * 0.8, AppColors.ff2F6BFF, red ? 0.1 : 0.55 * flash);
    glow(Offset(size.width * 0.55, -size.height * 0.05), size.width * 0.9, AppColors.ffFFF4D6, 0.16);
  }

  @override
  bool shouldRepaint(_NightPainter oldDelegate) => oldDelegate.t != t;
}

/// Nút THỔI: nút tròn đỏ, vòng thanh hơi quanh nút đầy dần khi giữ.
class _BlowButton extends StatelessWidget {
  const _BlowButton({required this.size, required this.progress, required this.pressed, required this.enabled});

  final double size;
  final double progress;
  final bool pressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: AnimatedScale(
        scale: pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(progress: progress, stroke: 7.h),
            child: Center(
              child: Container(
                width: size * 0.74,
                height: size * 0.74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: pressed ? [AppColors.ffB4231E, AppColors.ff8E1428] : [AppColors.ffFF5A4E, AppColors.ffD62828],
                  ),
                  border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: 0.35), width: 2.h),
                  boxShadow: [BoxShadow(color: AppColors.ffD62828.withValues(alpha: pressed ? 0.6 : 0.3), blurRadius: 12.h)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RoadIcon(RoadGlyph.breathalyzer, size: 24.h, color: AppColors.ffFFFFFF, accent: AppColors.ffD62828),
                    AppText.manrope('THỔI', fontSize: 14.h, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.ffFFFFFF),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.stroke});

  final double progress;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * pi,
      false,
      Paint()
        ..color = AppColors.ff1B1D22.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0.005) return;
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = Color.lerp(AppColors.ffFFB020, AppColors.ff1E9C53, progress)!
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.stroke != stroke;
}

/// Dấu tích trắng trong huy hiệu "đạt".
class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.27, w * 0.52)
        ..lineTo(w * 0.44, w * 0.68)
        ..lineTo(w * 0.74, w * 0.34),
      Paint()
        ..color = AppColors.ffFFFFFF
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Máy đo nồng độ cồn cầm tay vẽ bằng code: ống thổi trắng cắm trên đỉnh,
/// thân than chì viền cao su vàng, màn LCD xanh số 7 vạch, đèn báo, phím.
class _BreathalyzerPainter extends CustomPainter {
  _BreathalyzerPainter({required this.stage, required this.blow, required this.pulse, required this.reading});

  final _Stage stage;
  final double blow;
  final double pulse;
  final BreathReading? reading;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Ống thổi (nhựa trắng, đầu ống còn mảnh niêm phong trong).
    final tube = Path()
      ..moveTo(w * 0.40, h * 0.17)
      ..lineTo(w * 0.27, h * 0.015)
      ..lineTo(w * 0.42, h * 0.0)
      ..lineTo(w * 0.58, h * 0.16)
      ..close();
    canvas.drawPath(
      tube,
      Paint()
        ..shader = const LinearGradient(colors: [AppColors.ffE3E5E9, AppColors.ffFFFFFF, AppColors.ffC9CDD3]).createShader(Rect.fromLTWH(w * 0.27, 0, w * 0.31, h * 0.17)),
    );
    canvas.drawPath(tube, Paint()
      ..color = AppColors.ff9A9385
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    if (stage == _Stage.blowing) {
      // Hơi thở phả vào ống.
      final breath = Paint()
        ..color = AppColors.ff7FB2E5.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final k = (pulse * 2 + i / 3) % 1;
        final x = w * (0.02 + 0.2 * k), y = h * (0.01 + i * 0.03);
        canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: w * 0.16, height: h * 0.04), pi * 0.1, pi * 0.8, false, breath..color = breath.color.withValues(alpha: 0.6 * (1 - k)));
      }
    }
    // Thân máy.
    final body = RRect.fromLTRBR(w * 0.06, h * 0.15, w * 0.94, h * 0.995, Radius.circular(w * 0.16));
    canvas.drawRRect(body.shift(const Offset(2, 3)), Paint()..color = AppColors.ff000000.withValues(alpha: 0.25));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(colors: [AppColors.ff3A3E46, AppColors.ff23262C, AppColors.ff1B1D22]).createShader(body.outerRect),
    );
    final yellow = Paint()..color = AppColors.ffE8B81E;
    canvas.drawRRect(RRect.fromLTRBR(w * 0.06, h * 0.22, w * 0.15, h * 0.93, Radius.circular(w * 0.05)), yellow);
    canvas.drawRRect(RRect.fromLTRBR(w * 0.85, h * 0.22, w * 0.94, h * 0.93, Radius.circular(w * 0.05)), yellow);
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.12, h * 0.16, w * 0.88, h * 0.19, Radius.circular(w * 0.04)),
      Paint()..color = AppColors.ffFFFFFF.withValues(alpha: 0.12),
    );
    // Màn LCD.
    final bezel = RRect.fromLTRBR(w * 0.19, h * 0.23, w * 0.81, h * 0.50, Radius.circular(w * 0.05));
    canvas.drawRRect(bezel, Paint()..color = AppColors.ff121418);
    final lcd = RRect.fromLTRBR(w * 0.23, h * 0.255, w * 0.77, h * 0.475, Radius.circular(w * 0.025));
    final lit = stage != _Stage.intro;
    canvas.drawRRect(
      lcd,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: lit ? const [AppColors.ffA8D88C, AppColors.ff7FB46A] : [AppColors.ff7FB46A.withValues(alpha: 0.55), AppColors.ff1E2A1A],
        ).createShader(lcd.outerRect),
    );
    _lcd(canvas, lcd.outerRect, lit);
    // Đèn báo: xanh sẵn sàng / âm tính, vàng nháy lúc thổi và đo, đỏ dương tính.
    final r = reading;
    final ledColor = switch (stage) {
      _Stage.blowing || _Stage.analyzing => AppColors.ffFFB020,
      _Stage.result || _Stage.closing => r != null && r.positive ? AppColors.ffD62828 : AppColors.ff4ADE80,
      _ => AppColors.ff4ADE80,
    };
    final ledOn = stage == _Stage.intro ? 0.25 : (stage == _Stage.blowing || stage == _Stage.analyzing || (r?.positive ?? false)) ? (pulse < 0.5 ? 1.0 : 0.35) : 1.0;
    final led = Offset(w * 0.5, h * 0.555);
    canvas.drawCircle(led, w * 0.1, Paint()..shader = RadialGradient(colors: [ledColor.withValues(alpha: 0.5 * ledOn), ledColor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: led, radius: w * 0.1)));
    canvas.drawCircle(led, w * 0.035, Paint()..color = ledColor.withValues(alpha: 0.3 + 0.7 * ledOn));
    // Phím bấm.
    final key = Paint()
      ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.ff5B6169, AppColors.ff2B3038])
          .createShader(Rect.fromLTWH(0, h * 0.6, w, h * 0.2));
    for (final x in [0.34, 0.66]) {
      canvas.drawCircle(Offset(w * x, h * 0.665), w * 0.085, key);
      canvas.drawCircle(Offset(w * x - w * 0.02, h * 0.655), w * 0.03, Paint()..color = AppColors.ffFFFFFF.withValues(alpha: 0.18));
    }
    canvas.drawRRect(RRect.fromLTRBR(w * 0.36, h * 0.745, w * 0.64, h * 0.785, Radius.circular(w * 0.03)), key);
    // Lỗ loa.
    final grille = Paint()..color = AppColors.ff000000.withValues(alpha: 0.45);
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(RRect.fromLTRBR(w * 0.33, h * (0.85 + i * 0.03), w * 0.67, h * (0.862 + i * 0.03), Radius.circular(w * 0.01)), grille);
    }
  }

  /// Nội dung màn hình theo bước: chữ trạng thái nhỏ phía trên, số 7 vạch.
  void _lcd(Canvas canvas, Rect r, bool lit) {
    if (!lit) return;
    final ink = Paint()..color = AppColors.ff1E2A1A;
    final ghost = Paint()..color = AppColors.ff1E2A1A.withValues(alpha: 0.08);
    final status = switch (stage) {
      _Stage.ready => 'SẴN SÀNG',
      _Stage.blowing => 'ĐANG THỔI',
      _Stage.analyzing => 'ĐANG ĐO',
      _Stage.result || _Stage.closing => (reading?.positive ?? false) ? 'CÓ CỒN!' : 'ĐẠT',
      _Stage.intro => '',
    };
    final tp = TextPainter(
      text: TextSpan(text: status, style: TextStyle(fontFamily: 'Manrope', fontSize: r.height * 0.17, fontWeight: FontWeight.w800, color: AppColors.ff1E2A1A)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r.left + r.width * 0.07, r.top + r.height * 0.06));
    tp.dispose();
    final digitsTop = r.top + r.height * 0.34;
    final dh = r.height * 0.46;
    if (stage == _Stage.blowing) {
      // Thanh hơi: mười vạch đầy dần.
      final n = (blow * 10).floor();
      final bw = r.width * 0.075;
      for (var i = 0; i < 10; i++) {
        final x = r.left + r.width * 0.08 + i * bw * 1.12;
        canvas.drawRect(Rect.fromLTWH(x, digitsTop + dh * 0.2, bw, dh * 0.6), i < n ? ink : ghost);
      }
      return;
    }
    final text = switch (stage) {
      _Stage.result || _Stage.closing => (reading?.value ?? 0).toStringAsFixed(2),
      _Stage.analyzing => pulse < 0.5 ? '-.--' : ' .  ',
      _ => '-.--',
    };
    _sevenSeg(canvas, Offset(r.left + r.width * 0.1, digitsTop), dh, text, ink, ghost);
    final unit = TextPainter(
      text: TextSpan(text: 'mg/L', style: TextStyle(fontFamily: 'Manrope', fontSize: r.height * 0.15, fontWeight: FontWeight.w800, color: AppColors.ff1E2A1A)),
      textDirection: TextDirection.ltr,
    )..layout();
    unit.paint(canvas, Offset(r.right - unit.width - r.width * 0.05, r.bottom - unit.height - r.height * 0.06));
    unit.dispose();
  }

  /// Số kiểu đồng hồ LCD 7 vạch (vạch tắt hiện mờ như màn thật).
  static void _sevenSeg(Canvas canvas, Offset at, double h, String text, Paint on, Paint off) {
    const map = {
      '0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc', '5': 'afgcd', '6': 'afgedc', '7': 'abc', //
      '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': '',
    };
    final w = h * 0.52, t = h * 0.12;
    var x = at.dx;
    for (final ch in text.split('')) {
      if (ch == '.') {
        canvas.drawRect(Rect.fromLTWH(x - w * 0.12, at.dy + h - t, t, t), on);
        x += w * 0.18;
        continue;
      }
      final segs = map[ch] ?? '';
      Rect seg(String s) => switch (s) {
            'a' => Rect.fromLTWH(x + t * 0.6, at.dy, w - t * 1.2, t),
            'b' => Rect.fromLTWH(x + w - t, at.dy + t * 0.6, t, h / 2 - t * 0.9),
            'c' => Rect.fromLTWH(x + w - t, at.dy + h / 2 + t * 0.3, t, h / 2 - t * 0.9),
            'd' => Rect.fromLTWH(x + t * 0.6, at.dy + h - t, w - t * 1.2, t),
            'e' => Rect.fromLTWH(x, at.dy + h / 2 + t * 0.3, t, h / 2 - t * 0.9),
            'f' => Rect.fromLTWH(x, at.dy + t * 0.6, t, h / 2 - t * 0.9),
            _ => Rect.fromLTWH(x + t * 0.6, at.dy + h / 2 - t / 2, w - t * 1.2, t),
          };
      for (final s in 'abcdefg'.split('')) {
        canvas.drawRRect(RRect.fromRectAndRadius(seg(s), Radius.circular(t * 0.35)), segs.contains(s) ? on : off);
      }
      x += w + t * 1.1;
    }
  }

  @override
  bool shouldRepaint(_BreathalyzerPainter oldDelegate) =>
      oldDelegate.stage != stage || oldDelegate.blow != blow || oldDelegate.pulse != pulse || oldDelegate.reading != reading;
}
