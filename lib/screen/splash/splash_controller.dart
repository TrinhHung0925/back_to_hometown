import 'dart:async';

import 'package:get/get.dart';

import '../../game/debug/autopilot.dart';
import '../../game/debug/debug_launch.dart';
import '../../route.dart';

class SplashController extends GetxController {
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer(const Duration(seconds: 2), () {
      // Chế độ phát triển: tự lái vào thẳng màn chơi, hoặc mở thẳng một màn.
      if (Autopilot.enabled) {
        Get.offAllNamed(AppPage.game.routeName);
      } else if (DebugLaunch.screen.isNotEmpty) {
        Get.offAllNamed(AppPage.values.byName(DebugLaunch.screen).routeName);
      } else {
        Get.offAllNamed(AppPage.home.routeName);
      }
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  onBack() {
    Get.back();
  }
}
