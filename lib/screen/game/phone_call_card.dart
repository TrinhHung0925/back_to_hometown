import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'game_controller.dart';
import 'road_icons.dart';

/// Điện thoại từ nhà: chuông reo thì chọn tấp vào nghe / nghe luôn (vừa lái
/// vừa nghe, dễ bị CSGT phạt) / để lát gọi lại; đang nói thì hiện từng câu.
class PhoneCallCard extends StatelessWidget {
  const PhoneCallCard({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final call = controller.call.value;
      if (call == null) return const SizedBox.shrink();
      return Container(
        width: 292.h,
        padding: EdgeInsets.fromLTRB(10.h, 10.h, 10.h, 10.h),
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18.h),
          border: Border.all(color: call.driving ? AppColors.ffD62828 : AppColors.ffFFFFFF.withValues(alpha: 0.18), width: 2.h),
          boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.3), blurRadius: 12.h, offset: Offset(0, 4.h))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(call: call),
            SizedBox(height: 8.h),
            if (call.stage == CallStage.ringing) _Choices(controller: controller),
            if (call.stage == CallStage.pullingOver)
              AppText.manrope('Đang tấp vào lề để nghe…', fontSize: 12.h, fontWeight: FontWeight.w700, color: AppColors.ffFFFFFF.withValues(alpha: 0.8)),
            if (call.stage == CallStage.talking && call.line != null) _Line(text: call.line!, mine: call.mine, caller: call.caller),
          ],
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.call});

  final PhoneCallState call;

  @override
  Widget build(BuildContext context) {
    final status = switch (call.stage) {
      CallStage.ringing => call.attempt > 1 ? 'gọi lại lần ${call.attempt}…' : 'đang gọi…',
      CallStage.pullingOver => 'chờ chút…',
      CallStage.talking => call.driving ? 'vừa lái vừa nghe!' : 'đang nói chuyện',
    };
    return Row(
      children: [
        _Avatar(caller: call.caller, ringing: call.stage == CallStage.ringing),
        SizedBox(width: 10.h),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText.manrope(call.caller, fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
              AppText.manrope(
                status,
                fontSize: 11.5.h,
                fontWeight: FontWeight.w700,
                color: call.driving ? AppColors.ffFF8A80 : AppColors.ffFFFFFF.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        RoadIcon(RoadGlyph.phone, size: 22.h, color: AppColors.ff47D16C, accent: AppColors.ff1B1D22),
      ],
    );
  }
}

/// Ảnh người gọi; chuông reo thì vòng sáng nhấp nháy.
class _Avatar extends StatefulWidget {
  const _Avatar({required this.caller, required this.ringing});

  final String caller;
  final bool ringing;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mom = widget.caller == 'Mẹ';
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        width: 46.h,
        height: 46.h,
        padding: EdgeInsets.all(2.5.h),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.ringing ? Color.lerp(AppColors.ff47D16C, AppColors.ffFFFFFF, _pulse.value * 0.5) : AppColors.ffFFFFFF.withValues(alpha: 0.3),
        ),
        child: child,
      ),
      child: ClipOval(
        child: mom
            ? Image.asset(Img.imgPortraitMom, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initial())
            : _initial(),
      ),
    );
  }

  Widget _initial() => Container(
        color: AppColors.ff3A78A8,
        alignment: Alignment.center,
        child: AppText.manrope(widget.caller, fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
      );
}

class _Choices extends StatelessWidget {
  const _Choices({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Choice(
            label: 'Tấp vào nghe',
            caption: 'mất ~3 phút',
            color: AppColors.ff1E9C53,
            onPressed: () => controller.answerCall(pullOver: true),
          ),
        ),
        SizedBox(width: 6.h),
        Expanded(
          child: _Choice(
            label: 'Nghe luôn',
            caption: 'gặp CSGT là phạt',
            color: AppColors.ffEE9B2F,
            onPressed: () => controller.answerCall(pullOver: false),
          ),
        ),
        SizedBox(width: 6.h),
        Expanded(
          child: _Choice(label: 'Lát gọi lại', caption: 'mẹ sẽ lo', color: AppColors.ff5B6169, onPressed: controller.declineCall),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.caption, required this.color, required this.onPressed});

  final String label;
  final String caption;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 4.h),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12.h)),
        child: Column(
          children: [
            AppText.manrope(label, fontSize: 11.5.h, fontWeight: FontWeight.w800, maxLines: 1, color: AppColors.ffFFFFFF),
            AppText.manrope(caption, fontSize: 9.h, fontWeight: FontWeight.w600, maxLines: 1, color: AppColors.ffFFFFFF.withValues(alpha: 0.85)),
          ],
        ),
      ),
    );
  }
}

/// Một câu đang nói (của mình bên phải, của người gọi bên trái).
class _Line extends StatelessWidget {
  const _Line({required this.text, required this.mine, required this.caller});

  final String text;
  final bool mine;
  final String caller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.h, vertical: 7.h),
        decoration: BoxDecoration(
          color: mine ? AppColors.ff3A78A8 : AppColors.ffFBF6E9,
          borderRadius: BorderRadius.circular(12.h),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText.manrope(
              mine ? 'Mình' : caller,
              fontSize: 10.h,
              fontWeight: FontWeight.w800,
              color: mine ? AppColors.ffFFFFFF.withValues(alpha: 0.8) : AppColors.ffD62828,
            ),
            AppText.manrope(text, fontSize: 12.5.h, fontWeight: FontWeight.w700, maxLines: 3, color: mine ? AppColors.ffFFFFFF : AppColors.ff1B1D22),
          ],
        ),
      ),
    );
  }
}
