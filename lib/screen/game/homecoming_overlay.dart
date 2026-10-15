import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/app_button.dart';
import '../../game/logic/trip_clock.dart';
import '../../game/stage.dart';
import '../../game/vehicle_spec.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';

/// Về tới nhà (xong chặng cuối): xe chạy vào ngõ dừng trước cổng, cả nhà ra
/// đón; rồi đếm ngược đón giao thừa, pháo hoa nổ rộn trời.
class HomecomingOverlay extends StatefulWidget {
  const HomecomingOverlay({super.key, required this.result, required this.vehicle, required this.onDone});

  final StageResult result;
  final VehicleKind vehicle;
  final VoidCallback onDone;

  @override
  State<HomecomingOverlay> createState() => _HomecomingOverlayState();
}

/// Toạ độ trong khung ảnh cảnh nhà 2200 × 1000 (tool/asset_pipeline/build_home_scene.py).
abstract class _Scene {
  static const double width = 2200;
  static const double height = 1000;
  static const double groundY = 860;
  static const double pxPerM = 187.3;
  static const double vehicleStopX = 1092;
  static const double vehicleY = 950;
  static const double vehiclePxPerM = 243.9;
  static const Rect sky = Rect.fromLTWH(900, 0, 1300, 330);

  /// Mét → điểm ảnh ở chỗ chân chạm đất hàng [y].
  static double scaleAt(double y) => pxPerM + (y - groundY) * (vehiclePxPerM - pxPerM) / (vehicleY - groundY);
}

/// Một người (hay con chó) trong nhà ra đón: ảnh, cao bao nhiêu mét, đứng ở đâu.
class _Greeter {
  const _Greeter(this.art, this.heightM, this.x, this.y, this.phase);

  final String art;
  final double heightM;
  final double x;
  final double y;

  /// Lệch nhịp vẫy tay giữa mọi người.
  final double phase;
}

enum _Step { arriving, home, countdown, newYear }

class _HomecomingOverlayState extends State<HomecomingOverlay> with TickerProviderStateMixin {
  late final AnimationController _drive = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
  _Step _step = _Step.arriving;
  double _countdownAt = 0;
  final List<Timer> _timers = [];

  /// Tới nơi lúc tối muộn thì cảnh đã là đêm giao thừa.
  late final bool _lateArrival = widget.result.minutesLeft < 150;
  bool _night = false;

  static const List<_Greeter> _greeters = [
    _Greeter('family_grandma', 1.48, 1395, 788, 0.4),
    _Greeter('family_dad', 1.9, 1500, 795, 0.15),
    _Greeter('family_mom', 1.63, 1300, 800, 0),
    _Greeter('family_kid', 1.31, 1218, 818, 0.6),
  ];

  @override
  void initState() {
    super.initState();
    _night = _lateArrival;
    _drive.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _step = _Step.home);
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _drive.dispose();
    _clock.dispose();
    super.dispose();
  }

  double get _seconds => _clock.lastElapsedDuration == null ? 0 : _clock.lastElapsedDuration!.inMilliseconds / 1000;

  void _celebrate() {
    AudioService.shared.click();
    setState(() {
      _step = _Step.countdown;
      _night = true;
      _countdownAt = _seconds;
    });
    _timers.add(Timer(const Duration(milliseconds: 5200), () {
      if (!mounted) return;
      setState(() => _step = _Step.newYear);
      AudioService.shared.play(AppAudio.sfxFirecrackers, volume: 0.7);
      final random = Random();
      _timers.add(Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (random.nextDouble() < 0.8) AudioService.shared.play(AppAudio.sfxFireworks, volume: 0.55 + random.nextDouble() * 0.3);
      }));
    }));
  }

  String get _vehicleArt => switch (widget.vehicle) {
        VehicleKind.motorbike => 'player_moto_side',
        VehicleKind.car => 'player_car_side',
        VehicleKind.bus => 'player_bus_side',
      };

  /// Cỡ ảnh xe nhìn ngang (80 điểm ảnh mỗi mét): cao (m), rộng / cao.
  (double, double) get _vehicleSize => switch (widget.vehicle) {
        VehicleKind.motorbike => (145 / 80, 188 / 145),
        VehicleKind.car => (129 / 80, 366 / 129),
        VehicleKind.bus => (297 / 80, 732 / 297),
      };

  String get _subtitle {
    final left = widget.result.minutesLeft.round();
    final arrive = TripClock(minutes: widget.result.clockMinutes).label;
    if (left <= 0) return 'Tới nhà lúc $arrive — vừa kịp giao thừa!';
    final h = left ~/ 60, m = left % 60;
    final span = [if (h > 0) '$h giờ', if (m > 0) '$m phút'].join(' ');
    return 'Tới nhà lúc $arrive · còn $span nữa là giao thừa';
  }

  String? get _peachLine {
    final p = widget.result.peach;
    if (p < 0) return null;
    if (p >= 70) return 'Cành đào còn đẹp nguyên — mẹ khen mãi, đem cắm ngay bàn thờ!';
    if (p > 0) return 'Cành đào rụng mất ít bông, vẫn đủ cắm cho có Tết.';
    return 'Cành đào gãy mất rồi… mẹ bảo thôi, người về là quý nhất.';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final scale = max(box.maxWidth / _Scene.width, box.maxHeight / _Scene.height);
      final ox = (box.maxWidth - _Scene.width * scale) / 2, oy = (box.maxHeight - _Scene.height * scale) / 2;
      Offset at(double x, double y) => Offset(ox + x * scale, oy + y * scale);
      return AnimatedBuilder(
        animation: Listenable.merge([_drive, _clock]),
        builder: (context, _) {
          final t = _seconds;
          final k = Curves.easeOutCubic.transform(_drive.value);
          final (heightM, aspect) = _vehicleSize;
          final vehicleH = heightM * _Scene.vehiclePxPerM * scale;
          final vehicleW = vehicleH * aspect;
          final vehicleX = -500 + (_Scene.vehicleStopX + 500) * k;
          final bounce = _drive.value < 1 ? sin(t * 26) * 1.2 * scale : 0.0;
          return Stack(
            children: [
              Positioned.fill(child: Container(color: AppColors.ff1B1D22)),
              Positioned(
                left: ox,
                top: oy,
                width: _Scene.width * scale,
                height: _Scene.height * scale,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(Img.imgHomeDay, fit: BoxFit.fill),
                    AnimatedOpacity(
                      opacity: _night ? 1 : 0,
                      duration: const Duration(milliseconds: 900),
                      child: Image.asset(Img.imgHomeNight, fit: BoxFit.fill),
                    ),
                  ],
                ),
              ),
              // Cả nhà đứng ở cổng (xa vẽ trước), con chó chạy ra ngõ đón.
              for (final g in [..._greeters]..sort((a, b) => a.y.compareTo(b.y)))
                _figure(at, scale, '${g.art}_${(t * 2.2 + g.phase).floor().isEven ? 1 : 2}', g.heightM, g.x, g.y, k),
              _figure(at, scale, 'family_dog_${(t * 5).floor().isEven ? 1 : 2}', 0.72, 1130 + 60 * sin(t * 1.3) * k, 836, k, flip: true),
              // Xe mình chạy vào từ đầu ngõ (ảnh đầu xe quay trái nên lật lại).
              Positioned(
                left: at(vehicleX, 0).dx - vehicleW / 2,
                top: at(0, _Scene.vehicleY).dy - vehicleH + bounce,
                width: vehicleW,
                height: vehicleH,
                child: Transform.flip(flipX: true, child: Image.asset(Img.driverArt(_vehicleArt), fit: BoxFit.fill)),
              ),
              if (!_night) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PetalsPainter(t)))),
              if (_step == _Step.newYear)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _FireworksPainter(
                        t - _countdownAt - 5.2,
                        Rect.fromLTWH(at(_Scene.sky.left, 0).dx, at(0, _Scene.sky.top).dy, _Scene.sky.width * scale, _Scene.sky.height * scale),
                      ),
                    ),
                  ),
                ),
              if (_step == _Step.home || _step == _Step.newYear) _caption(t),
              if (_step == _Step.countdown) _countdown(t - _countdownAt, at(_Scene.sky.center.dx, _Scene.sky.center.dy + 40)),
            ],
          );
        },
      );
    });
  }

  Widget _figure(Offset Function(double, double) at, double scale, String art, double heightM, double x, double y, double appear,
      {bool flip = false}) {
    final h = heightM * _Scene.scaleAt(y) * scale;
    final base = at(x, y);
    final image = Image.asset(Img.driverArt(art), height: h, fit: BoxFit.contain, gaplessPlayback: true);
    return Positioned(
      left: base.dx - h * 0.4,
      top: base.dy - h,
      width: h * 0.8,
      height: h,
      child: Opacity(
        opacity: ((appear - 0.55) / 0.45).clamp(0.0, 1.0),
        child: flip ? Transform.flip(flipX: true, child: image) : image,
      ),
    );
  }

  Widget _caption(double t) {
    final newYear = _step == _Step.newYear;
    final peach = _peachLine;
    return Positioned(
      left: 20.h,
      top: 16.h,
      child: Container(
        width: 360.h,
        padding: EdgeInsets.fromLTRB(16.h, 12.h, 16.h, 14.h),
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18.h),
          border: Border.all(color: AppColors.ffFFD166.withValues(alpha: 0.6), width: 1.5.h),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText.paytone(newYear ? 'Chúc Mừng Năm Mới!' : 'Về tới nhà rồi!', fontSize: 26.h, color: AppColors.ffFFD166),
            SizedBox(height: 4.h),
            AppText.manrope(
              newYear ? 'Cả nhà quây quần đón giao thừa. An khang thịnh vượng!' : _subtitle,
              fontSize: 13.h,
              fontWeight: FontWeight.w700,
              maxLines: 2,
              color: AppColors.ffFFFFFF,
            ),
            if (!newYear) ...[
              SizedBox(height: 4.h),
              AppText.manrope('Bố mẹ, bà và em ra tận cổng đón.', fontSize: 12.h, fontWeight: FontWeight.w600, color: AppColors.ffFFFFFF.withValues(alpha: 0.8)),
            ],
            if (peach != null && !newYear) ...[
              SizedBox(height: 4.h),
              AppText.manrope(peach, fontSize: 12.h, fontWeight: FontWeight.w700, maxLines: 2, color: AppColors.ffFFB3C7),
            ],
            SizedBox(height: 12.h),
            if (_step == _Step.home)
              AppButton(label: 'Đón giao thừa', icon: Img.icPlay, onPressed: _celebrate)
            else if (_step == _Step.newYear)
              AppButton(label: 'Xem kết quả', icon: Img.icPlay, color: AppColors.ff1E9C53, onPressed: widget.onDone),
          ],
        ),
      ),
    );
  }

  /// Đếm ngược 5 giây cuối năm cũ, giữa nền trời.
  Widget _countdown(double t, Offset center) {
    final n = (5 - t).ceil().clamp(1, 5);
    final k = 1 - (t % 1);
    return Positioned(
      left: center.dx - 120.h,
      top: max(6.h, center.dy - 90.h),
      width: 240.h,
      height: 220.h,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText.manrope('Đếm ngược giao thừa', fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
            Transform.scale(
              scale: 0.85 + 0.45 * k,
              child: AppText.paytone(
                '$n',
                fontSize: 130.h,
                color: AppColors.ffFFD166.withValues(alpha: 0.55 + 0.45 * k),
                shadow: [Shadow(color: AppColors.ffD62828, blurRadius: 28.h)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cánh hoa đào lả tả bay trong chiều cuối năm.
class _PetalsPainter extends CustomPainter {
  _PetalsPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 26; i++) {
      final speed = 0.04 + (i * 0.37 % 1) * 0.05;
      final y = ((i * 0.618 + t * speed) % 1) * (size.height + 40) - 20;
      final x = ((i * 0.382 + 0.1 * sin(t * 0.7 + i)) % 1) * size.width;
      paint.color = (i.isEven ? const Color(0xffF7B6C8) : const Color(0xffEE8FAA)).withValues(alpha: 0.85);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (1 + i % 3) + i);
      canvas.drawOval(const Rect.fromLTWH(-4, -2.5, 8, 5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PetalsPainter old) => old.t != t;
}

/// Pháo hoa: từng chùm nổ tung trên nền trời — tia sáng bay ra mỗi tia một
/// tốc độ, kéo vệt đuôi, rơi chậm dần rồi tắt; lúc nổ chớp sáng cả vùng trời.
class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.t, this.sky);

  final double t;
  final Rect sky;

  static const List<(Color, Color)> _palettes = [
    (Color(0xffFFD166), Color(0xffFF8A3D)),
    (Color(0xffFF5A5F), Color(0xffFFD166)),
    (Color(0xffFF8FD1), Color(0xffFFFFFF)),
    (Color(0xff7CF2B0), Color(0xffFFF3B0)),
    (Color(0xff8EC5FF), Color(0xffFFFFFF)),
    (Color(0xffFFFFFF), Color(0xffFFD166)),
  ];

  static const double _life = 2.6;
  static const double _every = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    if (t < 0) return;
    final dot = Paint()..blendMode = BlendMode.plus;
    final first = max(0, ((t - _life) / _every).floor());
    final last = (t / _every).floor();
    for (var i = first; i <= last; i++) {
      final age = t - i * _every;
      if (age < 0 || age > _life) continue;
      final r = Random(i * 7919 + 13);
      final center = Offset(sky.left + r.nextDouble() * sky.width, sky.top + sky.height * (0.2 + r.nextDouble() * 0.55));
      final (c1, c2) = _palettes[r.nextInt(_palettes.length)];
      final radius = sky.height * (0.4 + r.nextDouble() * 0.35);
      final fade = pow((1 - age / _life).clamp(0.0, 1.0), 1.4).toDouble();
      // Chớp sáng lúc nổ.
      if (age < 0.3) {
        final k = 1 - age / 0.3;
        dot.shader = RadialGradient(colors: [c1.withValues(alpha: 0.55 * k), c1.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius * 0.9));
        canvas.drawCircle(center, radius * 0.9, dot);
        dot.shader = null;
      }
      final n = 60 + r.nextInt(24);
      for (var j = 0; j < n; j++) {
        final a = r.nextDouble() * 2 * pi;
        final v = 0.55 + r.nextDouble() * 0.45;
        final color = r.nextDouble() < 0.7 ? c1 : c2;
        final twinkle = 0.75 + 0.25 * sin(age * 30 + j);
        // Vệt đuôi: mấy chấm ở các thời điểm trước, nhỏ và mờ dần.
        for (var k = 0; k < 5; k++) {
          final at = max(0.0, age - k * 0.035);
          final reach = radius * v * (1 - exp(-at * 3.0));
          final drop = 26.0 * at * at;
          final p = center + Offset(cos(a) * reach, sin(a) * reach + drop);
          final alpha = fade * twinkle * (1 - k / 5);
          dot.color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
          canvas.drawCircle(p, (3.2 - k * 0.45) * (0.6 + 0.4 * fade), dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => old.t != t;
}
