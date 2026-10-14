import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../game/game_config.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';

/// Cụm nút kiểu game MOBA ở góc dưới bên phải: nút ga to sát góc, phanh,
/// còi, đèn xếp vòng cung quanh nó.
///
/// Không dùng CupertinoButton: nút game phải ăn ngay lúc chạm xuống, còn
/// CupertinoButton chỉ chạy khi nhấc tay ra (ngoại lệ cố ý, xem plan).
class ActionButtons extends StatelessWidget {
  const ActionButtons({
    super.key,
    required this.onThrottle,
    required this.onBrake,
    required this.speedFraction,
    required this.danger,
    this.onHorn,
    this.onHeadlight,
    this.headlightOn = false,
    this.hornTick = 0,
  });

  final ValueChanged<bool> onThrottle;
  final ValueChanged<bool> onBrake;

  /// null = nút chưa dùng được (mờ đi).
  final VoidCallback? onHorn;
  final VoidCallback? onHeadlight;
  final bool headlightOn;

  /// Đổi giá trị mỗi lần bóp còi thành công — nút còi chạy vòng hồi chiêu.
  final int hornTick;

  /// 0..1 để vẽ vòng tốc độ quanh nút ga.
  final double speedFraction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ring = 118.h;
    final gas = 92.h;
    final radius = 112.h;
    final clusterW = ring / 2 + radius + 40.h;
    final clusterH = ring / 2 + radius + 44.h;
    // Tâm nút ga tính từ góc dưới-phải của cụm.
    final c = Offset(clusterW - ring / 2, clusterH - ring / 2);

    Offset around(double degrees) {
      final a = degrees * pi / 180;
      return c + Offset(cos(a) * radius, -sin(a) * radius);
    }

    Widget at(Offset center, double size, Widget child) =>
        Positioned(left: center.dx - size / 2, top: center.dy - size / 2, child: child);

    return SizedBox(
      width: clusterW,
      height: clusterH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          at(
            c,
            ring,
            _SpeedRing(
              size: ring,
              fraction: speedFraction,
              danger: danger,
              child: _HoldButton(size: gas, icon: Img.icPedalGas, label: 'Ga', onChanged: onThrottle),
            ),
          ),
          at(around(176), 74.h, _HoldButton(size: 74.h, icon: Img.icPedalBrake, label: 'Phanh', onChanged: onBrake)),
          at(
            around(133),
            62.h,
            _Cooldown(
              tick: hornTick,
              size: 62.h,
              child: _TapButton(size: 62.h, icon: Img.icHorn, label: 'Còi', onTap: onHorn),
            ),
          ),
          at(
            around(92),
            62.h,
            _TapButton(size: 62.h, icon: Img.icHeadlight, label: 'Đèn', onTap: onHeadlight, highlighted: headlightOn),
          ),
        ],
      ),
    );
  }
}

/// Nền tròn bán trong suốt + icon + chữ nhỏ phía dưới.
class _ButtonFace extends StatelessWidget {
  const _ButtonFace({
    required this.size,
    required this.icon,
    required this.label,
    required this.pressed,
    this.enabled = true,
    this.highlighted = false,
  });

  final double size;
  final String icon;
  final String label;
  final bool pressed;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: AnimatedScale(
        scale: pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 60),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Image.asset(Img.icButtonCircle, width: size, height: size),
              if (pressed || highlighted)
                Container(
                  width: size * 0.84,
                  height: size * 0.84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (highlighted ? AppColors.ffFFD166 : AppColors.ffFFFFFF).withValues(alpha: 0.22),
                  ),
                ),
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  highlighted ? AppColors.ffFFD166 : AppColors.ffFFFFFF,
                  BlendMode.modulate,
                ),
                child: Image.asset(icon, width: size * 0.46, height: size * 0.46),
              ),
              Positioned(
                bottom: -15.h,
                child: AppText.manrope(
                  label,
                  fontSize: 11.h,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ffFFFFFF,
                  shadow: const [Shadow(color: AppColors.shadowSoft, blurRadius: 3)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút giữ (ga, phanh): báo true khi chạm xuống, false khi nhấc tay.
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.size, required this.icon, required this.label, required this.onChanged});

  final double size;
  final String icon;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  int? _pointer;

  void _set(int? pointer) {
    setState(() => _pointer = pointer);
    widget.onChanged(pointer != null);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer == null) _set(e.pointer);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _set(null);
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _set(null);
      },
      child: _ButtonFace(size: widget.size, icon: widget.icon, label: widget.label, pressed: _pointer != null),
    );
  }
}

/// Nút bấm một lần (còi, đèn): chạy ngay lúc chạm xuống.
class _TapButton extends StatefulWidget {
  const _TapButton({required this.size, required this.icon, required this.label, this.onTap, this.highlighted = false});

  final double size;
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  State<_TapButton> createState() => _TapButtonState();
}

class _TapButtonState extends State<_TapButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (!enabled) return;
        setState(() => _pressed = true);
        widget.onTap!();
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: _ButtonFace(
        size: widget.size,
        icon: widget.icon,
        label: widget.label,
        pressed: _pressed,
        enabled: enabled,
        highlighted: widget.highlighted,
      ),
    );
  }
}

/// Vòng hồi chiêu kiểu skill MOBA: phủ tối rồi quét tròn mở dần.
class _Cooldown extends StatefulWidget {
  const _Cooldown({required this.tick, required this.size, required this.child});

  final int tick;
  final double size;
  final Widget child;

  @override
  State<_Cooldown> createState() => _CooldownState();
}

class _CooldownState extends State<_Cooldown> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (GameConfig.hornCooldown * 1000).round()),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _Cooldown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => _anim.value >= 1
                ? const SizedBox.shrink()
                : CustomPaint(size: Size.square(widget.size), painter: _SweepPainter(_anim.value)),
          ),
        ),
      ],
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * 0.06);
    canvas.drawArc(
      rect,
      -pi / 2 + 2 * pi * progress,
      2 * pi * (1 - progress),
      true,
      Paint()..color = AppColors.ff1B1D22.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) => old.progress != progress;
}

/// Vòng tốc độ quanh nút ga: xanh khi an toàn, đỏ khi đâm vào là tai nạn.
class _SpeedRing extends StatelessWidget {
  const _SpeedRing({required this.size, required this.fraction, required this.danger, required this.child});

  final double size;
  final double fraction;
  final bool danger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, danger: danger, stroke: 7.h),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.danger, required this.stroke});

  final double fraction;
  final bool danger;
  final double stroke;

  static const double _start = 135 * pi / 180;
  static const double _sweep = 270 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..color = AppColors.ff1B1D22.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final value = Paint()
      ..color = danger ? AppColors.ffD62828 : AppColors.ff4ADE80
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, base);
    if (fraction > 0.01) canvas.drawArc(rect, _start, _sweep * fraction.clamp(0.0, 1.0), false, value);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.danger != danger || old.stroke != stroke;
}
