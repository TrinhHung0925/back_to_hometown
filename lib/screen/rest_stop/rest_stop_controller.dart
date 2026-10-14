import 'package:get/get.dart';

import '../../game/game_config.dart';
import '../../model/trip.dart';
import '../../route.dart';
import '../../service/trip_service.dart';

class RestStopController extends GetxController {
  TripProgress? progress;

  @override
  void onInit() {
    super.onInit();
    progress = TripService.shared.current;
  }

  /// Chặng vừa xong (null nếu đang ở đầu chuyến).
  TripStage? get previousStage {
    final p = progress;
    if (p == null || p.stageIndex == 0) return null;
    return p.plan.stages[p.stageIndex - 1];
  }

  TripStage? get nextStage {
    final p = progress;
    if (p == null || p.finished) return null;
    return p.plan.stages[p.stageIndex];
  }

  /// Đang chậm so với giờ giao thừa: thời gian chơi còn lại (ước tính ở tốc
  /// độ thường) dài hơn thời gian còn lại.
  bool get behindSchedule {
    final p = progress;
    if (p == null) return false;
    final neededMinutes = TripService.playSecondsLeft(p) * GameConfig.gameSecondsPerPlaySecond / 60;
    return neededMinutes > TripService.minutesLeft(p);
  }

  void goOn() {
    final p = progress;
    if (p == null || p.finished) {
      Get.offAllNamed(AppPage.home.routeName);
      return;
    }
    Get.offNamed(AppPage.game.routeName, arguments: TripService.shared.stageSetup(p));
  }

  void restLater() {
    Get.offAllNamed(AppPage.home.routeName);
  }

  onBack() {
    restLater();
  }
}
