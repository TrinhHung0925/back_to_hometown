import 'dart:async';

import 'package:get/get.dart';

import '../../route.dart';

class SplashController extends GetxController {
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer(const Duration(seconds: 2), () {
      Get.offAllNamed(AppPage.home.routeName);
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
