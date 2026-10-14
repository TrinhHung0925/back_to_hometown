import 'package:get/get.dart';

import '../../game/game_config.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../resource/app_resource.dart';
import '../../service/audio_service.dart';
import '../../model/trip.dart';
import '../../route.dart';
import '../../service/trip_service.dart';

class RestStopController extends GetxController {
  TripProgress? progress;

  /// Lì xì, xăng hiện tại (đổi khi đổ xăng ở trạm).
  final lixi = 0.obs;
  final fuel = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    progress = TripService.shared.current;
    _sync();
  }

  void _sync() {
    lixi.value = progress?.lixi ?? 0;
    fuel.value = progress?.fuel ?? 0;
  }

  /// Giá đổ đầy bình (lì xì).
  int get fullPrice {
    final p = progress;
    if (p == null) return 0;
    return FuelTank(p.plan.vehicle, level: fuel.value).fullPrice;
  }

  double get rangeKm {
    final p = progress;
    if (p == null) return 0;
    return FuelTank(p.plan.vehicle, level: fuel.value).kmLeft;
  }

  void refuel() {
    final p = progress;
    if (p == null) return;
    if (TripService.shared.refuelAtRestStop(p)) {
      AudioService.shared.play(AppAudio.sfxFuelPump, volume: 0.7);
      _sync();
    }
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
