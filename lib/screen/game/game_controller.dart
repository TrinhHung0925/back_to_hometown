import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';

import '../../game/debug/autopilot.dart';
import '../../game/debug/debug_launch.dart';
import '../../game/game_config.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../game/vehicle_spec.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import '../../route.dart';
import '../../service/audio_service.dart';
import '../../service/route_service.dart';
import '../../service/trip_service.dart';

class GameController extends GetxController {
  late StageSetup setup;
  late VeQueGame game;

  /// Tăng mỗi lần chơi lại để dựng GameWidget mới.
  final gameKey = 0.obs;

  final hud = Rxn<HudData>();
  final phase = GamePhase.driving.obs;
  final chaseProgress = 0.0.obs;
  final chaseTimeLeft = 0.0.obs;
  final result = Rxn<StageResult>();
  final isPaused = false.obs;

  /// Tổng kết cả chuyến khi vừa xong chặng cuối.
  final tripSummary = Rxn<TripSummary>();

  /// Vì sao công an tới (để bảng chọn ghi đúng lý do).
  final incidentKind = IncidentKind.collision.obs;

  /// Thông báo ngắn đang hiện (tự ẩn sau vài giây).
  final notice = Rxn<GameNotice>();
  Timer? _noticeTimer;

  /// Tăng mỗi lần bóp còi thành công — nút Còi chạy vòng hồi chiêu.
  final hornTick = 0.obs;

  /// Chat: đang gõ (game tạm dừng) và các tin vừa gửi (hiện ~4 giây).
  final chatOpen = false.obs;
  final chatMessages = <ChatMessage>[].obs;

  final _random = Random();
  Autopilot? _autopilot;

  /// Tốc độ tối đa hiển thị (km/h) để vẽ vòng tốc độ.
  double get maxSpeedKmh => VehicleSpec.of(setup.vehicle).maxSpeed * GameConfig.displayKmhPerUnitSpeed;

  /// Chặng này là chặng cuối của chuyến đi.
  bool get isLastStage => setup.stageNumber >= setup.stageCount;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    setup = args is StageSetup ? args : _fallbackStage();
    _createGame();
  }

  /// Vào thẳng màn chơi (chế độ tự lái khi phát triển): đi tiếp chuyến đang
  /// dở, hoặc chạy thử Hà Nội → Phủ Lý bằng xe máy.
  StageSetup _fallbackStage() {
    if (DebugLaunch.stage.isNotEmpty) {
      const kinds = {'c': RoadKind.city, 'h': RoadKind.highway, 'e': RoadKind.expressway};
      return StageSetup(
        vehicle: VehicleKind.values.byName(DebugLaunch.vehicle),
        fromName: 'Chạy thử',
        toName: 'Đích',
        sections: [
          for (final part in DebugLaunch.stage.split(','))
            StageSection(kinds[part[0]]!, double.parse(part.substring(1))),
        ],
        tollBooths: DebugLaunch.tolls,
        startClockMinutes: DebugLaunch.clock.toDouble(),
        startLixi: 10,
        seed: 7,
      );
    }
    final trips = TripService.shared;
    var progress = trips.current;
    if (progress == null || progress.finished) {
      progress = trips.start(RouteService.shared.plan('ha_noi', 'phu_ly', VehicleKind.motorbike)!);
    }
    return trips.stageSetup(progress);
  }

  void _createGame() {
    hud.value = null;
    phase.value = GamePhase.driving;
    result.value = null;
    isPaused.value = false;
    chaseProgress.value = 0;
    game = VeQueGame(
      setup: setup,
      onHud: (data) {
        hud.value = data;
        _audio.setEngineLevel(data.speedKmh / maxSpeedKmh);
      },
      onPhaseChanged: (value) {
        if (value == GamePhase.incident) incidentKind.value = game.incidentKind;
        phase.value = value;
        // Bảng chọn hiện lên thì nhả hết ga/phanh đang giữ.
        if (value == GamePhase.incident || value == GamePhase.finished) {
          game
            ..setThrottle(false)
            ..setBrake(false);
        }
        _onPhaseAudio(value);
      },
      onChase: (progress, timeLeft) {
        chaseProgress.value = progress;
        chaseTimeLeft.value = timeLeft;
      },
      onFinished: (value) {
        // Về tới cuối chặng thì lưu tiến độ ngay (trạm dừng nghỉ).
        if (value.won) tripSummary.value = TripService.shared.completeStage(value);
        result.value = value;
        if (value.won) {
          _audio.play(AppAudio.jingleWin, volume: 0.8);
          _audio.play(AppAudio.sfxFirecrackers, volume: 0.6);
        } else {
          _audio.play(AppAudio.jingleLose, volume: 0.8);
        }
      },
      onSound: _onGameSound,
      onNotice: _showNotice,
    );
    gameKey.value++;
    _audio.startEngine(setup.vehicle.fourWheels ? AppAudio.sfxEngineCar : AppAudio.sfxEngineMoto);
    _audio.stopSiren();
    _audio.playMusic(AppAudio.musicMain);
    _autopilot?.stop();
    if (Autopilot.enabled) _autopilot = Autopilot(game, mode: Autopilot.modeFromEnv)..start();
  }

  AudioService get _audio => AudioService.shared;

  void _onGameSound(GameSound sound) {
    switch (sound) {
      case GameSound.lixi:
        _audio.lixi();
      case GameSound.pothole:
        _audio.play(AppAudio.sfxPothole, volume: 0.8);
      case GameSound.crashLight:
        _audio.play(AppAudio.sfxCrashLight);
      case GameSound.crashHeavy:
        _audio.play(AppAudio.sfxCrashHeavy);
      case GameSound.skid:
        _audio.play(AppAudio.sfxSkid, volume: 0.5);
      case GameSound.horn:
        _audio.play(setup.vehicle.fourWheels ? AppAudio.sfxHornCar : AppAudio.sfxHornMoto);
      case GameSound.hornOther:
        _audio.play(AppAudio.sfxHornCar, volume: 0.55);
      case GameSound.gift:
        _audio.play(AppAudio.sfxConfirm, volume: 0.8);
      case GameSound.toll:
        _audio.lixi();
      case GameSound.barrier:
        _audio.play(AppAudio.sfxCrashLight, volume: 0.7);
    }
  }

  void _showNotice(GameNotice value) {
    notice.value = value;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(milliseconds: 3200), () => notice.value = null);
  }

  // ------------------------------------------------------- Còi, đèn
  void honk() {
    if (game.honk()) hornTick.value++;
  }

  void toggleHeadlights() {
    AudioService.shared.click();
    game.toggleHeadlights();
  }

  // ------------------------------------------------------------ Chat
  /// Mở ô chat: game tạm dừng vì bàn phím màn ngang che gần hết màn hình.
  void openChat() {
    if (result.value != null || phase.value == GamePhase.incident) return;
    game
      ..setThrottle(false)
      ..setBrake(false)
      ..pauseEngine();
    _audio.pauseLoops();
    chatOpen.value = true;
  }

  void closeChat() {
    if (!chatOpen.value) return;
    chatOpen.value = false;
    if (!isPaused.value) {
      game.resumeEngine();
      _audio.resumeLoops();
    }
  }

  /// Gửi tin: hiện phía trên màn hình rồi tự mờ đi. Chỉ hiện trên máy mình.
  void sendChat(String text) {
    final value = text.trim();
    if (value.isNotEmpty) {
      final message = ChatMessage(value);
      chatMessages.add(message);
      if (chatMessages.length > 3) chatMessages.removeAt(0);
      Timer(const Duration(milliseconds: 4500), () => chatMessages.remove(message));
    }
    closeChat();
  }

  void _onPhaseAudio(GamePhase value) {
    switch (value) {
      case GamePhase.incident:
        _audio.startSiren();
      case GamePhase.chase:
        _audio.startSiren();
        _audio.playMusic(AppAudio.musicChase);
      case GamePhase.driving:
        _audio.stopSiren();
        _audio.playMusic(AppAudio.musicMain);
      case GamePhase.finished:
        _audio.stopEngine();
        _audio.stopSiren();
        _audio.stopMusic();
    }
  }

  @override
  void onClose() {
    _noticeTimer?.cancel();
    _autopilot?.stop();
    _audio.stopEngine();
    _audio.stopSiren();
    _audio.playMusic(AppAudio.musicMain);
    super.onClose();
  }

  void onThrottle(bool on) => game.setThrottle(on);
  void onBrake(bool on) => game.setBrake(on);
  void onSteer(double value) => game.setSteer(value);

  void payFine() => game.payFine();
  void flee() => game.flee();

  void pause() {
    if (isPaused.value || result.value != null) return;
    game
      ..setThrottle(false)
      ..setBrake(false)
      ..pauseEngine();
    isPaused.value = true;
    _audio.pauseLoops();
  }

  void resume() {
    game.resumeEngine();
    isPaused.value = false;
    _audio.resumeLoops();
  }

  /// Thua thì chơi lại chặng này từ trạm dừng nghỉ gần nhất.
  void retry() {
    setup = setup.withSeed(_random.nextInt(1 << 20));
    _createGame();
  }

  /// Về tới cuối chặng: sang trạm dừng nghỉ (hoặc về menu nếu đã tới nhà).
  void continueTrip() {
    if (isLastStage) {
      exitToMenu();
    } else {
      Get.offNamed(AppPage.restStop.routeName);
    }
  }

  void exitToMenu() => Get.offAllNamed(AppPage.home.routeName);

  onBack() {
    pause();
  }
}

/// Một tin chat vừa gửi (chỉ hiện trên máy người chơi, không lưu).
class ChatMessage {
  ChatMessage(this.text);

  final String text;
}
