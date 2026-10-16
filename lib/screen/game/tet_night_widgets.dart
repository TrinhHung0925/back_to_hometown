import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/lixi_icon.dart';
import '../../game/logic/cold_weather.dart';
import '../../game/ve_que_game.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Chip trời rét, máy nguội, hơi men cho cột chip bên trái (cùng kiểu chip
/// sương mù, cành đào).
abstract class NightColdChips {
  static List<Widget> of(NightColdHud? cold) {
    if (cold == null) return const [];
    return [
      if (cold.label != null)
        _ColdChip(
          glyph: RoadGlyph.thermometer,
          text: cold.numb ? '${cold.label} · tay cóng — mua găng tay' : cold.label!,
          color: cold.severe ? AppColors.ff2C5D8A : AppColors.ff3E6A92,
        ),
      if (cold.kicksLeft != null)
        const _ColdChip(glyph: RoadGlyph.scooter, text: 'Máy nguội — bấm Ga để đạp nổ máy', color: AppColors.ffB4231E, blink: true),
      if (cold.alcohol != null)
        _ColdChip(
          glyph: RoadGlyph.breathalyzer,
          text: 'Hơi men ${(cold.alcohol! / 100).toStringAsFixed(2).replaceAll('.', ',')} mg/L · còn ~${_duration(cold.soberMinutes ?? 0)} — đã uống đừng lái!',
          color: AppColors.ff8E1428,
        ),
    ];
  }

  /// 40 phút, 1 giờ 40.
  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes phút';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h giờ' : '$h giờ ${m.toString().padLeft(2, '0')}';
  }
}

class _ColdChip extends StatefulWidget {
  const _ColdChip({required this.glyph, required this.text, required this.color, this.blink = false});

  final RoadGlyph glyph;
  final String text;
  final Color color;
  final bool blink;

  @override
  State<_ColdChip> createState() => _ColdChipState();
}

class _ColdChipState extends State<_ColdChip> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.blink) _anim.repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 30.h,
      padding: EdgeInsets.symmetric(horizontal: 10.h),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(15.h),
        border: widget.blink ? Border.all(color: AppColors.ffFFD166, width: 1.5.h) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoadIcon(widget.glyph, size: 16.h, color: AppColors.ffFFFFFF, accent: widget.color),
          SizedBox(width: 6.h),
          AppText.manrope(widget.text, fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
        ],
      ),
    );
    if (!widget.blink) return chip;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(opacity: 1 - 0.45 * _anim.value, child: child),
      child: chip,
    );
  }
}

/// Món theo mùa ở quán, gọn trên một hàng (bảng quán đã dài): ngày 29, 30
/// Tết quán mời chén rượu mừng xuân; trời rét thì bán găng tay len.
class SeasonalOffers extends StatelessWidget {
  const SeasonalOffers({super.key, required this.controller, required this.lixi});

  final GameController controller;
  final int lixi;

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    final toasts = game.toastsLeft;
    final gloves = game.glovesOffer;
    if (toasts <= 0 && !gloves) return const SizedBox.shrink();
    final toast = game.toastItem;
    return Padding(
      padding: EdgeInsets.only(top: 3.h),
      child: Row(
        children: [
          if (toasts > 0)
            Expanded(
              child: _SeasonTile(
                art: Img.imgItemToast,
                title: 'Chén rượu Tết',
                caption: 'quán mời',
                price: toast.price,
                button: 'Uống',
                accent: AppColors.ffB4231E,
                enabled: true,
                onPressed: () => controller.order(toast),
              ),
            ),
          if (toasts > 0 && gloves) SizedBox(width: 8.h),
          if (gloves)
            Expanded(
              child: _SeasonTile(
                art: Img.imgItemGloves,
                title: 'Găng tay len',
                caption: 'đỡ cóng tay',
                price: 1,
                button: 'Mua',
                accent: AppColors.ff3E6A92,
                enabled: lixi >= 1,
                onPressed: game.buyGloves,
              ),
            ),
        ],
      ),
    );
  }
}

/// Một món theo mùa: ảnh, tên, giá, nút (cùng màu với dòng món trong bảng quán).
class _SeasonTile extends StatelessWidget {
  const _SeasonTile({
    required this.art,
    required this.title,
    required this.caption,
    required this.price,
    required this.button,
    required this.enabled,
    required this.onPressed,
    required this.accent,
  });

  final String art;
  final String title;
  final String caption;
  final int price;
  final String button;
  final bool enabled;
  final VoidCallback onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4.h, 3.h, 4.h, 3.h),
      decoration: BoxDecoration(
        color: AppColors.ffF1E7D2.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10.h),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2.h),
      ),
      child: Row(
        children: [
          SizedBox(width: 30.h, height: 30.h, child: Image.asset(art)),
          SizedBox(width: 5.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope(title, fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                Row(
                  children: [
                    if (price == 0)
                      AppText.manrope('Miễn phí · ', fontSize: 9.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53)
                    else ...[
                      LixiIcon(height: 11.h),
                      AppText.manrope(' $price · ', fontSize: 9.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                    ],
                    Flexible(child: AppText.manrope(caption, fontSize: 9.5.h, fontWeight: FontWeight.w600, color: AppColors.ff6B7280)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 4.h),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: enabled ? onPressed : null,
            child: Container(
              width: 46.h,
              height: 28.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? accent : AppColors.ffE3E5E9,
                borderRadius: BorderRadius.circular(9.h),
                border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: enabled ? 0.3 : 0.08), width: 1.5.h),
              ),
              child: AppText.manrope(button, fontSize: 12.h, fontWeight: FontWeight.w800, color: enabled ? AppColors.ffFFFFFF : AppColors.ff9A9385),
            ),
          ),
        ],
      ),
    );
  }
}
