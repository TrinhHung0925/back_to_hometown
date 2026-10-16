import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../game/logic/family.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import 'action_buttons.dart';
import 'breath_test_overlay.dart';
import 'chat_overlay.dart';
import 'family_widgets.dart';
import 'game_controller.dart';
import 'game_hud.dart';
import 'game_overlays.dart';
import 'homecoming_overlay.dart';
import 'phone_call_card.dart';
import 'roadside_overlays.dart';
import 'speedometer.dart';
import 'steering_stick.dart';
import 'tutorial_coach.dart';

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ảnh minh hoạ món ở quán: nạp sẵn để bảng quán hiện ra là có hình ngay.
    for (final path in Img.items) {
      precacheImage(AssetImage(path), context);
    }
    // Chở cả nhà: ảnh vợ, bé (thẻ lời nói, nhãn kiên nhẫn) và món cho bé.
    if (controller.setup.family) {
      for (final path in [...Img.familyPortraits, Img.item(FamilySnack.bimBim.art), Img.item(FamilySnack.hopSua.art)]) {
        precacheImage(AssetImage(path), context);
      }
    }
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
            Positioned.fill(child: DrowsyOverlay(controller: controller)),
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(top: 0, left: 0, right: 0, child: GameHud(controller: controller)),
                    // Chở cả nhà: chừa chỗ cho thẻ lời nói hai dòng phía trên.
                    Positioned(top: controller.setup.family ? 126.h : 112.h, left: 12.h, child: ReversedChip(controller: controller)),
                    // Điện thoại từ nhà: góc trên bên trái, không che đường phía trước.
                    Positioned(top: 56.h, left: 12.h, child: PhoneCallCard(controller: controller)),
                    Positioned(top: 54.h, right: 12.h, child: RoadAheadColumn(controller: controller)),
                    // Thông báo nằm giữa khoảng trống phía trên: chừa cột "đường phía
                    // trước" bên phải; đang ghé quán thì dời sang phải bảng quán.
                    Obx(() {
                      final resting = controller.phase.value == GamePhase.resting && controller.stallVisit.value != null;
                      // Đang có điện thoại: thẻ cuộc gọi ở góc trái, thông báo dời sang phải.
                      final calling = controller.call.value != null || controller.familyLine.value != null;
                      return Positioned(
                        top: 56.h,
                        // Chặng tập lái: thẻ hướng dẫn chiếm góc trái như thẻ cuộc gọi.
                        left: resting ? 444.h : (calling || controller.setup.tutorial ? 312.h : 0),
                        right: resting ? 12.h : 214.h,
                        child: Column(
                          children: [
                            NoticeBanner(controller: controller),
                            SizedBox(height: 6.h),
                            ChatFeed(controller: controller),
                          ],
                        ),
                      );
                    }),
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
                      child: Obx(() => controller.phase.value == GamePhase.resting
                          ? const SizedBox.shrink()
                          : SteeringStick(onChanged: controller.onSteer, horizontal: controller.hud.value?.driverSeat ?? false)),
                    ),
                    // Đồng hồ tốc độ sát bên trái nút Phanh; nút theo tình huống
                    // xếp tiếp bên trái đồng hồ.
                    Positioned(
                      right: 14.h + 215.h,
                      bottom: 6.h,
                      child: Obx(() {
                        final hud = controller.hud.value;
                        if (hud == null || controller.phase.value == GamePhase.resting) return const SizedBox.shrink();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hud.cruiseKmh > 0 && controller.phase.value == GamePhase.driving) ...[
                              CruiseChip(cruiseKmh: hud.cruiseKmh, assist: hud.assist),
                              SizedBox(height: 4.h),
                            ],
                            Speedometer(
                              speedKmh: hud.speedKmh,
                              cruiseKmh: hud.cruiseKmh,
                              maxKmh: controller.maxSpeedKmh,
                              limitKmh: hud.speedLimit?.limit,
                            ),
                          ],
                        );
                      }),
                    ),
                    Positioned(
                      right: 14.h + 215.h + Speedometer.width + 10.h,
                      bottom: 22.h,
                      child: ContextActions(controller: controller),
                    ),
                    Obx(() {
                      if (!controller.cruiseTip.value || controller.phase.value != GamePhase.driving) {
                        return const SizedBox.shrink();
                      }
                      // Góc trên bên trái (phía làn ngược chiều) để không che xe mình.
                      return Positioned(left: 12.h, top: 58.h, child: CruiseTip(assist: controller.driveAssist.value));
                    }),
                    Obx(() {
                      final job = controller.job.value;
                      if (job == null) return const SizedBox.shrink();
                      // Lúc làm việc bên lề cụm nút lái ẩn đi: thẻ việc nằm góc phải dưới.
                      return Positioned(right: 14.h, bottom: 16.h, child: JobCard(state: job));
                    }),
                    Obx(() {
                      final visit = controller.stallVisit.value;
                      if (visit == null) return const SizedBox.shrink();
                      return Positioned(
                        left: 12.h,
                        top: 48.h,
                        child: StallSheet(key: ValueKey(visit.stall), controller: controller, visit: visit),
                      );
                    }),
                    Obx(() {
                      final visit = controller.stallVisit.value;
                      if (visit == null) return const SizedBox.shrink();
                      final chat = controller.gasChat.value;
                      return Positioned(
                        right: 20.h,
                        bottom: 18.h,
                        child: chat != null
                            ? GasChatPanel(key: ValueKey(chat.round), chat: chat, onAnswer: controller.answerChat, onMore: controller.nextChat)
                            : StallChatter(key: ValueKey(visit.stall), chatter: visit.chatter),
                      );
                    }),
                    // Chở cả nhà: vợ / con nói gì trên xe — góc trên bên trái (ẩn khi
                    // có điện thoại); đang ghé quán thì nằm bên phải bảng quán.
                    Obx(() {
                      final resting = controller.phase.value == GamePhase.resting && controller.stallVisit.value != null;
                      return Positioned(
                        top: resting ? 104.h : 56.h,
                        left: resting ? 444.h : 12.h,
                        child: FamilyTalkCard(controller: controller),
                      );
                    }),
                    Positioned(
                      right: 14.h,
                      bottom: 18.h,
                      child: Obx(() {
                        final hud = controller.hud.value;
                        if (controller.phase.value == GamePhase.resting) return const SizedBox.shrink();
                        return ActionButtons(
                          onThrottle: controller.onThrottle,
                          onBrake: controller.onBrake,
                          onHorn: controller.honk,
                          onHeadlight: controller.toggleHeadlights,
                          headlightOn: hud?.headlightsOn ?? false,
                          hornTick: controller.hornTick.value,
                          gasFraction: hud == null ? 0 : hud.cruiseKmh / controller.maxSpeedKmh,
                          danger: hud?.danger ?? false,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            // Chặng tập lái: thẻ hướng dẫn, vòng sáng chỉ nút, bảng tổng kết.
            if (controller.setup.tutorial) Positioned.fill(child: TutorialCoach(controller: controller)),
            Obx(() {
              if (controller.phase.value != GamePhase.incident) return const SizedBox.shrink();
              return Positioned.fill(child: IncidentOverlay(controller: controller));
            }),
            // Chốt kiểm tra nồng độ cồn đêm 30 Tết: bảng thổi.
            Obx(() {
              final check = controller.phase.value == GamePhase.resting ? controller.game.breathCheck : null;
              if (check == null) return const SizedBox.shrink();
              return Positioned.fill(child: BreathTestOverlay(key: ValueKey(check.clock), controller: controller, check: check));
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
              if (controller.homecoming.value) {
                return Positioned.fill(
                  child: HomecomingOverlay(
                    result: result,
                    vehicle: controller.setup.vehicle,
                    family: controller.setup.family,
                    onDone: () => controller.homecoming.value = false,
                  ),
                );
              }
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
