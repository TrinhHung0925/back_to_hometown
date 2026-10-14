import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../game/stage.dart';
import '../../resource/app_colors.dart';
import 'action_buttons.dart';
import 'chat_overlay.dart';
import 'game_controller.dart';
import 'game_hud.dart';
import 'game_overlays.dart';
import 'steering_stick.dart';

class GameView extends StatefulWidget {
  GameView({super.key}) {
    if (!Get.isRegistered<GameController>()) {
      Get.put(GameController());
    }
  }

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  var controller = Get.find<GameController>();

  /// Ra khỏi app (cuộc gọi, vuốt về màn hình chính) thì tự tạm dừng.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onInactive: controller.pause);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    Get.delete<GameController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vuốt quay lại (iOS) / nút Back (Android) không thoát màn chơi mà tạm dừng.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.ff1B1D22,
        // Bàn phím chat không được bóp nhỏ màn chơi.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Obx(() => GameWidget(key: ValueKey(controller.gameKey.value), game: controller.game)),
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(top: 0, left: 0, right: 0, child: GameHud(controller: controller)),
                    Positioned(
                      top: 56.h,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          NoticeBanner(controller: controller),
                          SizedBox(height: 6.h),
                          ChatFeed(controller: controller),
                        ],
                      ),
                    ),
                    Obx(() {
                      if (controller.phase.value != GamePhase.chase) return const SizedBox.shrink();
                      return Positioned(
                        top: 58.h,
                        left: 0,
                        right: 0,
                        child: Center(child: ChaseBar(controller: controller)),
                      );
                    }),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: MediaQuery.sizeOf(context).width * 0.34,
                      height: MediaQuery.sizeOf(context).height * 0.62,
                      child: SteeringStick(onChanged: controller.onSteer),
                    ),
                    Positioned(
                      right: 14.h,
                      bottom: 18.h,
                      child: Obx(() {
                        final hud = controller.hud.value;
                        return ActionButtons(
                          onThrottle: controller.onThrottle,
                          onBrake: controller.onBrake,
                          onHorn: controller.honk,
                          onHeadlight: controller.toggleHeadlights,
                          headlightOn: hud?.headlightsOn ?? false,
                          hornTick: controller.hornTick.value,
                          speedFraction: hud == null ? 0 : hud.speedKmh / controller.maxSpeedKmh,
                          danger: hud?.danger ?? false,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Obx(() {
              if (controller.phase.value != GamePhase.incident) return const SizedBox.shrink();
              return Positioned.fill(child: IncidentOverlay(controller: controller));
            }),
            Obx(() {
              if (!controller.chatOpen.value) return const SizedBox.shrink();
              return Positioned.fill(child: ChatInputOverlay(controller: controller));
            }),
            Obx(() {
              if (!controller.isPaused.value) return const SizedBox.shrink();
              return Positioned.fill(child: PauseOverlay(controller: controller));
            }),
            Obx(() {
              final result = controller.result.value;
              if (result == null) return const SizedBox.shrink();
              return Positioned.fill(
                child: ResultOverlay(controller: controller, result: result),
              );
            }),
          ],
        ),
      ),
    );
  }
}
