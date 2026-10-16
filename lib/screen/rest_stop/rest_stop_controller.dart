import 'package:get/get.dart';

import '../../dialog/map_picker_dialog.dart';
import '../../dialog/shop_dialog.dart';
import '../../game/game_config.dart';
import '../../game/logic/missions.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../resource/app_resource.dart';
import '../../service/audio_service.dart';
import '../../model/map_theme.dart';
import '../../model/shop.dart';
import '../../model/trip.dart';
import '../../route.dart';
import '../../service/local_service.dart';
import '../../service/trip_service.dart';

class RestStopController extends GetxController {
  TripProgress? progress;

  /// Lì xì, xăng hiện tại (đổi khi đổ xăng ở trạm).
  final lixi = 0.obs;
  final fuel = 0.0.obs;

  /// Bản đồ, trời cho chặng sắp đi (đổi được trước khi lên đường).
  final mapTheme = LocalService.shared.getMapTheme().obs;
  final sky = LocalService.shared.getSkyMode().obs;

  Future<void> pickMap() async {
    await MapPickerDialog.open();
    mapTheme.value = LocalService.shared.getMapTheme();
    sky.value = LocalService.shared.getSkyMode();
  }

  void setSky(SkyMode value) {
    LocalService.shared.saveSkyMode(value);
    sky.value = value;
  }

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
    return FuelTank(p.plan.vehicle, level: fuel.value, capacity: Perks.of(p.upgrades).fuelCapacity).fullPrice;
  }

  double get rangeKm {
    final p = progress;
    if (p == null) return 0;
    return FuelTank(p.plan.vehicle, level: fuel.value, capacity: Perks.of(p.upgrades).fuelCapacity).kmLeft;
  }

  void refuel() {
    final p = progress;
    if (p == null) return;
    if (TripService.shared.refuelAtRestStop(p)) {
      AudioService.shared.play(AppAudio.sfxFuelPump, volume: 0.7);
      _sync();
    }
  }

  /// Đồ đã mua ở cửa hàng (đổi sau mỗi lần mua — vẽ lại hàng đồ trong thẻ chuyến).
  final shopTick = 0.obs;

  /// Mở cửa hàng: nâng cấp xe, quà Tết cho cả nhà.
  Future<void> openShop() async {
    final p = progress;
    if (p == null) return;
    await ShopDialog.open(p, onChanged: () {
      _sync();
      shopTick.value++;
    });
    _sync();
    shopTick.value++;
  }

  /// Nhiệm vụ phụ của chặng sắp đi.
  List<Mission> get missions {
    final p = progress;
    return p == null ? const [] : TripService.missionsFor(p);
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
