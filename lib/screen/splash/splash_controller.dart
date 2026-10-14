import 'dart:async';
import 'dart:math';

import 'package:flame/flame.dart';
import 'package:get/get.dart';

import '../../game/debug/autopilot.dart';
import '../../game/debug/debug_launch.dart';
import '../../resource/app_resource.dart';
import '../../route.dart';
import '../../service/audio_service.dart';

class SplashController extends GetxController {
  /// Tiến độ hiện trên thanh tải (0..1): theo việc nạp thật, nhưng chạy
  /// đủ [_minShow] để cảnh mở màn kịp diễn.
  final progress = 0.0.obs;

  static const Duration _minShow = Duration(milliseconds: 2800);

  /// Câu vui đổi theo tiến độ tải.
  static const List<String> tips = [
    'Đang xếp quà Tết lên xe…',
    'Đang đổ đầy bình xăng…',
    'Đang đếm lì xì…',
    'Đang dò đường về quê…',
    'Lên đường thôi!',
  ];

  String get tip => tips[min(tips.length - 1, (progress.value * (tips.length - 1)).floor())];

  final Stopwatch _clock = Stopwatch();
  double _loaded = 0;
  Timer? _ticker;

  @override
  void onInit() {
    super.onInit();
    _clock.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
    _load();
  }

  /// Nạp sẵn âm thanh và toàn bộ hình trong game để vào menu, vào chặng
  /// không phải chờ.
  Future<void> _load() async {
    try {
      await AudioService.shared.init();
    } catch (_) {
      // Không có âm thanh vẫn chơi được.
    }
    _loaded = 0.15;
    // Game dùng chung bộ nhớ ảnh Flame.images, đường dẫn đầy đủ trong Img.
    Flame.images.prefix = '';
    final images = [...Img.vehicles, ...Img.worldArt];
    const chunk = 8;
    for (var i = 0; i < images.length; i += chunk) {
      try {
        await Flame.images.loadAll(images.sublist(i, min(images.length, i + chunk)));
      } catch (_) {
        // Thiếu ảnh nào thì game tự nạp lại lúc cần.
      }
      _loaded = 0.15 + 0.85 * min(images.length, i + chunk) / images.length;
    }
  }

  void _tick() {
    final byTime = _clock.elapsedMilliseconds / _minShow.inMilliseconds;
    final shown = min(_loaded, byTime).clamp(0.0, 1.0);
    if (shown > progress.value) progress.value = shown;
    if (progress.value >= 1) {
      _ticker?.cancel();
      Timer(const Duration(milliseconds: 450), _next);
    }
  }

  void _next() {
    // Chế độ phát triển: tự lái vào thẳng màn chơi, hoặc mở thẳng một màn.
    if (Autopilot.enabled) {
      Get.offAllNamed(AppPage.game.routeName);
    } else if (DebugLaunch.screen.isNotEmpty) {
      Get.offAllNamed(AppPage.values.byName(DebugLaunch.screen).routeName);
    } else {
      Get.offAllNamed(AppPage.home.routeName);
    }
  }

  @override
  void onClose() {
    _ticker?.cancel();
    super.onClose();
  }

  onBack() {
    Get.back();
  }
}
