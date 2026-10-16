import 'package:get/get.dart';

import '../../game/vehicle_spec.dart';
import '../../model/difficulty.dart';
import '../../route.dart';
import '../../service/local_service.dart';

class ChooseModeController extends GetxController {
  /// Độ khó cho chuyến sắp đi (lưu lại cho lần sau).
  final difficulty = LocalService.shared.getDifficulty().obs;

  void setDifficulty(Difficulty value) {
    LocalService.shared.saveDifficulty(value);
    difficulty.value = value;
  }

  void selfDrive() {
    Get.toNamed(AppPage.planTrip.routeName);
  }

  /// Lái xe khách: lên lộ trình như ô tô, dọc đường dừng đón khách.
  void coach() {
    Get.toNamed(AppPage.planTrip.routeName, arguments: VehicleKind.bus);
  }

  onBack() {
    Get.back();
  }
}
