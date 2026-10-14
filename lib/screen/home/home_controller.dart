import 'package:get/get.dart';

import '../../dialog/records_dialog.dart';
import '../../route.dart';
import '../../resource/app_resource.dart';
import '../../service/audio_service.dart';
import '../../service/trip_service.dart';

class HomeController extends GetxController {
  final hasTrip = false.obs;
  final soundOn = true.obs;

  @override
  void onInit() {
    super.onInit();
    hasTrip.value = TripService.shared.hasTrip;
    soundOn.value = AudioService.shared.enabled;
    AudioService.shared.playMusic(AppAudio.musicMain);
  }

  void startTrip() {
    Get.toNamed(AppPage.chooseMode.routeName);
  }

  void continueTrip() {
    Get.toNamed(AppPage.restStop.routeName);
  }

  void showRecords() {
    Get.dialog(RecordsDialog(records: TripService.shared.records));
  }

  void toggleSound() {
    soundOn.value = !soundOn.value;
    AudioService.shared.setEnabled(soundOn.value);
  }

  onBack() {
    Get.back();
  }
}
