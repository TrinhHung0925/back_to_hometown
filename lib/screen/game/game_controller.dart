import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';

import '../../game/debug/autopilot.dart';
import '../../game/debug/debug_launch.dart';
import '../../game/game_config.dart';
import '../../game/logic/gas_chat.dart';
import '../../game/logic/roadside.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../game/vehicle_spec.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import '../../route.dart';
import '../../service/audio_service.dart';
import '../../service/local_service.dart';
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

  /// Vì sao công an tới (để bảng chọn ghi đúng lý do) và chi tiết lỗi.
  final incidentKind = IncidentKind.collision.obs;
  final violation = Rxn<Violation>();

  /// Thông báo ngắn đang hiện (tự ẩn sau vài giây).
  final notice = Rxn<GameNotice>();
  Timer? _noticeTimer;

  /// Đang ghé quán (null khi đang lái).
  final stallVisit = Rxn<StallVisit>();

  /// Việc bên lề đang làm (thay lốp, chờ xăng…), null khi không có.
  final job = Rxn<JobState>();

  /// Lần đổ xăng gần nhất: mức bình trước / sau (bảng cột bơm chạy số).
  final pump = Rxn<(double, double)>();

  /// Góc nhìn ghế lái (lưu lại cho lần chơi sau); đang nạp ảnh của góc này.
  final driverView = false.obs;
  final viewLoading = false.obs;

  /// Tán gẫu với nhân viên cây xăng (null khi không đứng ở cây xăng).
  final gasChat = Rxn<GasChatState>();
  final Set<int> _chatUsed = {};
  Timer? _chatTimer;

  /// Tăng mỗi lần bóp còi thành công — nút Còi chạy vòng hồi chiêu.
  final hornTick = 0.obs;

  /// Đang hiện thẻ chỉ cách dùng ga giữ mức (chỉ lần đầu chơi).
  final cruiseTip = false.obs;
  Timer? _cruiseTipTimer;

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
    if (!LocalService.shared.getCruiseTipShown()) {
      cruiseTip.value = true;
      LocalService.shared.saveCruiseTipShown();
      _cruiseTipTimer = Timer(const Duration(seconds: 12), () => cruiseTip.value = false);
    }
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
    stallVisit.value = null;
    job.value = null;
    pump.value = null;
    _endChat();
    _chatUsed.clear();
    game = VeQueGame(
      setup: setup,
      onHud: (data) {
        hud.value = data;
        _audio.setEngineLevel(data.speedKmh / maxSpeedKmh);
        if (!isPaused.value && !chatOpen.value) _audio.setRain(data.rain);
      },
      onRest: (visit) {
        stallVisit.value = visit;
        if (visit == null) {
          pump.value = null;
          _endChat();
        } else if (visit.seated && visit.stall.kind == StallKind.xang && gasChat.value == null) {
          // Nhân viên ra tới xe thì bắt chuyện.
          _chatTimer?.cancel();
          _chatTimer = Timer(const Duration(milliseconds: 900), nextChat);
        }
      },
      onJob: (value) => job.value = value,
      onPhaseChanged: (value) {
        if (value == GamePhase.incident) {
          incidentKind.value = game.incidentKind;
          violation.value = game.violation;
        }
        final previous = phase.value;
        phase.value = value;
        // Dựng xe vào quán thì tắt máy, lên đường thì nổ máy lại.
        if (value == GamePhase.resting) _audio.stopEngine();
        if (previous == GamePhase.resting && value == GamePhase.driving) {
          _audio.startEngine(setup.vehicle.fourWheels ? AppAudio.sfxEngineCar : AppAudio.sfxEngineMoto);
        }
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
    driverView.value = LocalService.shared.getDriverView();
    if (driverView.value) {
      final created = game;
      created.loaded.then((_) {
        if (identical(created, game)) _applyView();
      });
    }
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
      case GameSound.tireHiss:
        _audio.play(AppAudio.sfxTireHiss, volume: 0.8);
      case GameSound.whistle:
        _audio.play(AppAudio.sfxWhistle, volume: 0.8);
      case GameSound.sputter:
        _audio.play(AppAudio.sfxSputter, volume: 0.8);
      case GameSound.fuelPump:
        _audio.play(AppAudio.sfxFuelPump, volume: 0.7);
    }
  }

  void _showNotice(GameNotice value) {
    notice.value = value;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(milliseconds: 3200), () => notice.value = null);
  }

  // ------------------------------------------- Quán ven đường, quay đầu
  void stopAtStall() => game.stopAtStall();
  void order(StallItem item) => game.order(item);
  void leaveStall() => game.leaveStall();
  void uTurn() => game.uTurn();
  void repair(RepairOption option) => game.repair(option);
  void buyRaincoat() => game.buyRaincoat();

  /// Đổ xăng ([lixi] lì xì, null = đổ đầy) hoặc mua chai xăng lẻ.
  void refuel({int? lixi, bool bottle = false}) {
    final before = game.fuel.level;
    final added = bottle ? game.buyBottle() : game.refuel(lixiSpent: lixi);
    if (added > 0) pump.value = (before, game.fuel.level);
  }

  /// Đổi góc nhìn bản đồ trên cao ↔ ghế lái.
  Future<void> toggleView() async {
    driverView.value = !driverView.value;
    LocalService.shared.saveDriverView(driverView.value);
    await _applyView();
  }

  Future<void> _applyView() async {
    final g = game;
    viewLoading.value = true;
    await g.setDriverView(driverView.value);
    if (identical(g, game)) viewLoading.value = false;
  }

  /// Nhân viên cây xăng hỏi chuyện tiếp (tối đa [GasChat.maxRounds] lượt).
  void nextChat() {
    final round = (gasChat.value?.round ?? 0) + 1;
    if (round > GasChat.maxRounds || stallVisit.value?.seated != true) return;
    final i = GasChat.pick(_random, _chatUsed);
    _chatUsed.add(i);
    final topic = GasChat.topics[i];
    gasChat.value = GasChatState(topic: topic, round: round);
  }

  void answerChat(ChatReply reply) {
    final chat = gasChat.value;
    if (chat == null || chat.answered) return;
    final (mine, react) = game.chatAnswer(reply);
    if (mine.isNotEmpty) gasChat.value = chat.answer(mine, react);
  }

  void _endChat() {
    _chatTimer?.cancel();
    gasChat.value = null;
  }

  /// Nút theo tình huống.
  void onAction(RoadAction action) {
    switch (action) {
      case RoadAction.visit:
        game.stopAtStall();
      case RoadAction.uTurn:
        game.uTurn();
      case RoadAction.tiltBike:
        game.tiltBike();
      case RoadAction.push:
        game.startPushing();
      case RoadAction.callFuel:
        game.callFuel();
      case RoadAction.spareTire:
        game.changeSpare();
      case RoadAction.callMechanic:
        game.callMechanic();
    }
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
      case GamePhase.resting:
        break;
      case GamePhase.finished:
        _audio.stopEngine();
        _audio.stopSiren();
        _audio.setRain(0);
        _audio.stopMusic();
    }
  }

  @override
  void onClose() {
    _noticeTimer?.cancel();
    _cruiseTipTimer?.cancel();
    _chatTimer?.cancel();
    _autopilot?.stop();
    _audio.stopEngine();
    _audio.stopSiren();
    _audio.setRain(0);
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
