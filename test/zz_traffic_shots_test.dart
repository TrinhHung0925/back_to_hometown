import 'dart:io';
import 'dart:ui' as ui;

import 'package:back_to_hometown/game/game_config.dart';
import 'package:back_to_hometown/game/logic/road_layout.dart';
import 'package:back_to_hometown/game/logic/traffic_system.dart';
import 'package:back_to_hometown/game/stage.dart';
import 'package:back_to_hometown/game/vehicle_spec.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:back_to_hometown/route.dart';
import 'package:back_to_hometown/screen/game/game_controller.dart';
import 'package:back_to_hometown/service/local_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

const out = '/private/tmp/claude-501/-Users-hungtv-Documents-hungtv-back-to-hometown/757fd0bc-a5b2-43c0-ad52-da42435e3f2e/scratchpad/traffic';

void main() {
  testWidgets('traffic shots', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '/private/tmp/claude-501/-Users-hungtv-Documents-hungtv-back-to-hometown/757fd0bc-a5b2-43c0-ad52-da42435e3f2e/scratchpad/gs');
    await tester.runAsync(() async {
      await GetStorage.init();
      for (final w in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
        await (FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'))).load();
      }
      await (FontLoader('PaytoneOne')..addFont(rootBundle.load('assets/fonts/PaytoneOne-Regular.ttf'))).load();
    });
    LocalService.shared.saveSoundOn(false);
    tester.view.physicalSize = const Size(874 * 2, 402 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(left: 124, right: 124, bottom: 42);
    const clockMin = int.fromEnvironment('CLOCK', defaultValue: 900);
    final clockStart = clockMin * 1.0;
    const sections = [StageSection(RoadKind.city, 3), StageSection(RoadKind.highway, 110)];
    final setup = StageSetup(
      vehicle: VehicleKind.motorbike,
      fromName: 'Hà Nội',
      toName: 'Vinh',
      sections: sections,
      startClockMinutes: clockStart,
      startLixi: 30,
      startFuel: 0.8,
      seed: 3,
    );
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ScreenUtilInit(
        designSize: const Size(884, 390),
        builder: (_, _) => GetMaterialApp(debugShowCheckedModeBanner: false, onGenerateRoute: generateRoute, home: const SizedBox()),
      ),
    ));
    Get.toNamed(AppPage.game.routeName, arguments: setup);
    Future<void> run(double seconds) async {
      for (var t = 0.0; t < seconds; t += 1 / 30) {
        await tester.pump(const Duration(microseconds: 33333));
      }
    }

    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final c = Get.find<GameController>();
    final game = c.game;
    expect(game.isLoaded, isTrue);
    const tag = String.fromEnvironment('TAG');
    Future<void> shot(String name, {double ratio = 2}) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/$tag$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      print('SHOT $name s=${game.player.s.round()} vehicles=${game.traffic.vehicles.length}');
    }

    var id = 9000;
    Future<void> fleet(double s0, List<(TrafficType, int, int, double)> cars) async {
      game.traffic.vehicles.clear();
      game.player
        ..s = s0
        ..d = Lanes.center(1)
        ..speed = 0
        ..cruise = 0
        ..lateralVelocity = 0;
      await run(2.0);
      game.traffic.vehicles.clear();
      for (final (type, variant, lane, ds) in cars) {
        game.traffic.vehicles.add(TrafficVehicle(id: id++, type: type, lane: lane, s: s0 + ds, cruiseSpeed: 0, variant: variant));
      }
      await run(0.2);
    }

    const s0Units = int.fromEnvironment('S0', defaultValue: 14000);
    final s0 = s0Units * 1.0;
    await fleet(s0, [
      for (var i = 0; i < 10; i++) (TrafficType.motorbike, i, [0, 1, 2, 3][i % 4], -120.0 + i * 62),
    ]);
    await shot('01_bikes');
    await fleet(s0 + 3000, [
      for (var i = 0; i < 8; i++) (TrafficType.sedan, i, [0, 2, 3, 0][i % 4], -150.0 + i * 85 + (i % 4 == 0 ? 0 : 20)),
      (TrafficType.pickup, 0, 1, 180),
      (TrafficType.pickup, 1, 2, -60),
      (TrafficType.pickup, 2, 3, 330),
    ]);
    await shot('02_cars');
    await fleet(s0 + 6000, [
      (TrafficType.bus, 0, 0, -40),
      (TrafficType.truck, 0, 0, 220),
      (TrafficType.bus, 1, 2, 60),
      (TrafficType.truck, 1, 3, -120),
      (TrafficType.bus, 2, 3, 280),
      (TrafficType.truck, 2, 2, 380),
      (TrafficType.motorbike, 6, 1, 150),
      (TrafficType.motorbike, 8, 1, 260),
    ]);
    await shot('03_heavy');
  });
}
