import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../../game/debug/autopilot.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../game/vehicle_spec.dart';
import '../../model/trip.dart';

/// Nền màn menu: chính con đường trong game, xe tự chạy qua phố và quốc lộ
/// (không tiếng, không HUD).
class HomeBackdrop extends StatefulWidget {
  const HomeBackdrop({super.key});

  @override
  State<HomeBackdrop> createState() => _HomeBackdropState();
}

class _HomeBackdropState extends State<HomeBackdrop> {
  late final VeQueGame _game;
  late final Autopilot _pilot;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _game = VeQueGame(
      setup: StageSetup(
        vehicle: random.nextBool() ? VehicleKind.motorbike : VehicleKind.car,
        fromName: '',
        toName: '',
        sections: const [
          StageSection(RoadKind.city, 3),
          StageSection(RoadKind.highway, 30),
        ],
        startClockMinutes: 16 * 60 + 30,
        seed: random.nextInt(1 << 20),
      ),
      onHud: (_) {},
      onPhaseChanged: (_) {},
      onChase: (_, _) {},
      onFinished: (_) {},
      onSound: (_) {},
      onNotice: (_) {},
    );
    _pilot = Autopilot(_game, mode: 'drive')..start();
  }

  @override
  void dispose() {
    _pilot.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: GameWidget(game: _game));
}
