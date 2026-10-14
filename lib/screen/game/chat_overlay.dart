import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';
import 'game_controller.dart';

/// Ô gõ chat: game tạm dừng, ô nhập nằm phía trên bàn phím. Có vài câu
/// gợi ý để bấm nhanh.
class ChatInputOverlay extends StatefulWidget {
  const ChatInputOverlay({super.key, required this.controller});

  final GameController controller;

  static const List<String> quickLines = [
    'Sắp về tới nhà rồi mẹ ơi!',
    'Kẹt xe quá trời 😩',
    'Chúc mừng năm mới! 🧧',
    'Ai đi cùng đường không?',
  ];

  @override
  State<ChatInputOverlay> createState() => _ChatInputOverlayState();
}

class _ChatInputOverlayState extends State<ChatInputOverlay> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? value]) {
    AudioService.shared.click();
    widget.controller.sendChat(value ?? _text.text);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return GestureDetector(
      onTap: widget.controller.closeChat,
      child: Container(
        color: AppColors.ff1B1D22.withValues(alpha: 0.55),
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.only(bottom: keyboard + 10.h, left: 60.h, right: 60.h),
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ChatInputOverlay.quickLines.length,
                  separatorBuilder: (_, _) => SizedBox(width: 8.h),
                  itemBuilder: (context, i) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => _send(ChatInputOverlay.quickLines[i]),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.h),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.ffFFFFFF.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(17.h),
                      ),
                      child: AppText.manrope(
                        ChatInputOverlay.quickLines[i],
                        fontSize: 12.h,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ff1B1D22,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              Container(
                height: 46.h,
                padding: EdgeInsets.only(left: 14.h, right: 4.h),
                decoration: BoxDecoration(
                  color: AppColors.ffFFFFFF,
                  borderRadius: BorderRadius.circular(23.h),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        type: MaterialType.transparency,
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          maxLength: 80,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          style: TextStyle(fontFamily: 'Manrope', fontSize: 15.h, fontWeight: FontWeight.w600, color: AppColors.ff1B1D22),
                          decoration: InputDecoration(
                            hintText: 'Nhắn gì đó…',
                            hintStyle: TextStyle(fontFamily: 'Manrope', fontSize: 15.h, color: AppColors.ff6B7280),
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _send,
                      child: Container(
                        width: 38.h,
                        height: 38.h,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.ffD62828, shape: BoxShape.circle),
                        child: Image.asset(Img.icArrow, width: 18.h, height: 18.h),
                      ),
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

/// Tin chat vừa gửi: hiện phía trên màn hình, ngay dưới HUD, rồi mờ dần.
class ChatFeed extends StatelessWidget {
  const ChatFeed({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final messages = controller.chatMessages.toList();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in messages)
            Padding(
              key: ObjectKey(m),
              padding: EdgeInsets.only(bottom: 6.h),
              child: _FadeOut(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.h, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: AppColors.ff1B1D22.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16.h),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText.manrope('Bạn: ', fontSize: 13.h, fontWeight: FontWeight.w800, color: AppColors.ffFFD166),
                      Flexible(
                        child: AppText.manrope(m.text, fontSize: 13.h, fontWeight: FontWeight.w600, color: AppColors.ffFFFFFF),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Hiện rõ rồi mờ dần trong ~4,5 giây.
class _FadeOut extends StatefulWidget {
  const _FadeOut({required this.child});

  final Widget child;

  @override
  State<_FadeOut> createState() => _FadeOutState();
}

class _FadeOutState extends State<_FadeOut> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))
    ..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim.drive(TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 6),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 74),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
      ])),
      child: widget.child,
    );
  }
}
