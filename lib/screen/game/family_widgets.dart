import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/lixi_icon.dart';
import '../../game/logic/family.dart';
import '../../game/logic/roadside.dart';
import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Ảnh mặt bé theo tâm trạng.
String kidPortrait(KidMood mood) => switch (mood) {
      KidMood.happy => Img.imgPortraitKidHappy,
      KidMood.ok || KidMood.fussy => Img.imgPortraitKid,
      KidMood.crying => Img.imgPortraitKidCry,
      KidMood.asleep => Img.imgPortraitKidSleep,
    };

/// Màu mức kiên nhẫn: xanh vui, vàng bình thường, cam quấy, đỏ khóc, xanh
/// đêm khi ngủ.
Color kidMoodColor(KidMood mood) => switch (mood) {
      KidMood.happy => AppColors.ff4ADE80,
      KidMood.ok => AppColors.ffFFD166,
      KidMood.fussy => AppColors.ffFF8A3D,
      KidMood.crying => AppColors.ffFF5A4E,
      KidMood.asleep => AppColors.ff9FC6EA,
    };

/// Nhãn kiên nhẫn của bé (cột nhãn góc trái, cạnh nhãn cành đào): mặt bé
/// theo tâm trạng, tâm trạng bằng chữ, thanh mức, số; bé buồn tè thì thêm
/// nhãn còn bao nhiêu km phải dừng.
class FamilyChip extends StatelessWidget {
  const FamilyChip({super.key, required this.family});

  final FamilyHud family;

  @override
  Widget build(BuildContext context) {
    final color = kidMoodColor(family.mood);
    final crying = family.mood == KidMood.crying;
    final wc = family.bathroomKm;
    final label = switch (family.mood) {
      KidMood.happy => 'Bé Bin vui',
      KidMood.ok => 'Bé Bin',
      KidMood.fussy => 'Bé quấy',
      KidMood.crying => 'Bé khóc!',
      KidMood.asleep => 'Bé ngủ',
    };
    return Container(
      height: 30.h,
      padding: EdgeInsets.only(left: 3.h, right: wc == null ? 10.h : 4.h),
      decoration: BoxDecoration(
        color: crying ? AppColors.ff8E1428.withValues(alpha: 0.9) : AppColors.ff1B1D22.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(15.h),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Shake(
            on: crying,
            child: Container(
              width: 24.h,
              height: 24.h,
              padding: EdgeInsets.all(1.5.h),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: ClipOval(child: Image.asset(kidPortrait(family.mood), fit: BoxFit.cover, gaplessPlayback: true)),
            ),
          ),
          SizedBox(width: 6.h),
          AppText.manrope(label, fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
          SizedBox(width: 6.h),
          Container(
            width: 34.h,
            height: 7.h,
            decoration: BoxDecoration(color: AppColors.ffFFFFFF.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4.h)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (family.patience / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4.h),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4.h)],
                ),
              ),
            ),
          ),
          SizedBox(width: 5.h),
          AppText.manrope('${family.patience}', fontSize: 12.h, fontWeight: FontWeight.w800, color: color),
          if (wc != null) ...[
            SizedBox(width: 6.h),
            Container(
              height: 22.h,
              padding: EdgeInsets.symmetric(horizontal: 7.h),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: wc <= 1 ? AppColors.ffFF5A4E : AppColors.ffFFD166,
                borderRadius: BorderRadius.circular(11.h),
              ),
              child: AppText.manrope('Buồn tè · $wc km', fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rung nhẹ khi bé khóc (mặt bé lắc qua lắc lại).
class _Shake extends StatefulWidget {
  const _Shake({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  @override
  void initState() {
    super.initState();
    if (widget.on) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !_anim.isAnimating) _anim.repeat(reverse: true);
    if (!widget.on && _anim.isAnimating) {
      _anim
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.rotate(angle: widget.on ? (_anim.value - 0.5) * 0.35 : 0, child: child),
      child: widget.child,
    );
  }
}

/// Thẻ lời nói trên xe (góc trên bên trái): ảnh người nói, tên, câu nói. Câu
/// của mình thì nền xanh, ảnh vô-lăng.
class FamilyTalkCard extends StatelessWidget {
  const FamilyTalkCard({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final line = controller.familyLine.value;
      final hidden = line == null ||
          controller.call.value != null ||
          controller.phase.value == GamePhase.incident ||
          controller.phase.value == GamePhase.finished ||
          controller.cruiseTip.value;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(position: Tween(begin: const Offset(-0.06, 0), end: Offset.zero).animate(anim), child: child),
        ),
        child: hidden ? const SizedBox.shrink() : _TalkBubble(key: ValueKey(line.text), line: line),
      );
    });
  }
}

class _TalkBubble extends StatelessWidget {
  const _TalkBubble({super.key, required this.line});

  final FamilyLine line;

  @override
  Widget build(BuildContext context) {
    final me = line.speaker == FamilySpeaker.me;
    final kid = line.speaker == FamilySpeaker.kid;
    final ring = kid ? kidMoodColor(line.mood) : (me ? AppColors.ff7FB2E5 : AppColors.ffF7A8BC);
    return Container(
      constraints: BoxConstraints(maxWidth: 292.h),
      padding: EdgeInsets.fromLTRB(6.h, 5.h, 12.h, 5.h),
      decoration: BoxDecoration(
        color: me ? AppColors.ff2C5D8A.withValues(alpha: 0.92) : AppColors.ff1B1D22.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22.h),
        border: Border.all(color: ring.withValues(alpha: 0.7), width: 1.5.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.28), blurRadius: 10.h, offset: Offset(0, 3.h))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38.h,
            height: 38.h,
            padding: EdgeInsets.all(2.h),
            decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
            child: ClipOval(
              child: me
                  ? Container(
                      color: AppColors.ff3A78A8,
                      alignment: Alignment.center,
                      child: RoadIcon(RoadGlyph.steering, size: 22.h, color: AppColors.ffFFFFFF, accent: AppColors.ff3A78A8),
                    )
                  : Image.asset(kid ? kidPortrait(line.mood) : Img.imgPortraitWife, fit: BoxFit.cover),
            ),
          ),
          SizedBox(width: 9.h),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope(line.speaker.label, fontSize: 10.h, fontWeight: FontWeight.w800, color: ring),
                AppText.manrope(line.text, fontSize: 12.h, fontWeight: FontWeight.w700, maxLines: 2, color: AppColors.ffFFFFFF),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hàng "Cho bé" trong bảng quán: bim bim, hộp sữa — nút nhỏ gọn nằm chung
/// một hàng để bảng quán không dài thêm.
class FamilySnackRow extends StatelessWidget {
  const FamilySnackRow({super.key, required this.controller, required this.kind, required this.lixi});

  final GameController controller;
  final StallKind kind;
  final int lixi;

  @override
  Widget build(BuildContext context) {
    final menu = FamilySnack.menuFor(kind);
    if (menu.isEmpty || !controller.familyRide) return const SizedBox.shrink();
    final mood = controller.hud.value?.family?.mood ?? KidMood.ok;
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Container(
        padding: EdgeInsets.fromLTRB(6.h, 5.h, 6.h, 5.h),
        decoration: BoxDecoration(
          color: AppColors.ffFFF4D6,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: AppColors.ffF7A8BC, width: 1.5.h),
        ),
        child: Row(
          children: [
            Container(
              width: 30.h,
              height: 30.h,
              padding: EdgeInsets.all(1.5.h),
              decoration: BoxDecoration(shape: BoxShape.circle, color: kidMoodColor(mood)),
              child: ClipOval(child: Image.asset(kidPortrait(mood), fit: BoxFit.cover)),
            ),
            SizedBox(width: 6.h),
            AppText.manrope('Cho bé', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffC2412F),
            SizedBox(width: 6.h),
            for (final snack in menu) ...[
              Expanded(child: _SnackButton(snack: snack, enabled: lixi >= snack.price, onPressed: () => controller.orderSnack(snack))),
              if (snack != menu.last) SizedBox(width: 6.h),
            ],
          ],
        ),
      ),
    );
  }
}

class _SnackButton extends StatelessWidget {
  const _SnackButton({required this.snack, required this.enabled, required this.onPressed});

  final FamilySnack snack;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: enabled ? onPressed : null,
      child: Container(
        height: 32.h,
        padding: EdgeInsets.only(left: 3.h, right: 7.h),
        decoration: BoxDecoration(
          color: enabled ? AppColors.ffFFFFFF : AppColors.ffE3E5E9,
          borderRadius: BorderRadius.circular(9.h),
          border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: enabled ? 0.25 : 0.08), width: 1.5.h),
        ),
        child: Row(
          children: [
            Image.asset(Img.item(snack.art), width: 26.h, height: 26.h),
            SizedBox(width: 3.h),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(snack.name, fontSize: 11.5.h, fontWeight: FontWeight.w800, maxLines: 1, color: AppColors.ff1B1D22),
                  AppText.manrope('bé vui +${snack.patience.round()}', fontSize: 9.h, fontWeight: FontWeight.w700, maxLines: 1, color: AppColors.ff1E9C53),
                ],
              ),
            ),
            LixiIcon(height: 15.h),
            SizedBox(width: 2.h),
            AppText.manrope('${snack.price}', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ],
        ),
      ),
    );
  }
}

/// Dòng tổng kết chở cả nhà ở bảng kết quả chặng: mặt bé, điểm cả nhà.
class FamilyResultLine extends StatelessWidget {
  const FamilyResultLine({super.key, required this.score});

  /// Điểm cả nhà của chặng (thưởng bé còn vui trừ phạt tè dầm, khóc nhè).
  final int score;

  @override
  Widget build(BuildContext context) {
    final mood = score >= 150
        ? KidMood.happy
        : score >= 0
            ? KidMood.ok
            : KidMood.crying;
    final text = switch (mood) {
      KidMood.happy => 'Bé Bin tới nơi vẫn cười toe',
      KidMood.ok => 'Cả nhà tới nơi bình an',
      _ => 'Bé Bin quấy khóc dọc đường',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26.h,
          height: 26.h,
          padding: EdgeInsets.all(1.5.h),
          decoration: BoxDecoration(shape: BoxShape.circle, color: kidMoodColor(mood)),
          child: ClipOval(child: Image.asset(kidPortrait(mood), fit: BoxFit.cover)),
        ),
        SizedBox(width: 8.h),
        AppText.manrope(text, fontSize: 13.h, fontWeight: FontWeight.w700, color: AppColors.ff1B1D22),
        SizedBox(width: 8.h),
        AppText.manrope(
          score >= 0 ? '+$score điểm' : '−${-score} điểm',
          fontSize: 13.h,
          fontWeight: FontWeight.w800,
          color: score >= 0 ? AppColors.ff1E9C53 : AppColors.ffD62828,
        ),
      ],
    );
  }
}
