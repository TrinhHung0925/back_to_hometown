import 'package:get/get.dart';

import '../../game/vehicle_spec.dart';
import '../../route.dart';

class ChooseModeController extends GetxController {
  @override
  void onInit() {
    super.onInit();
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
