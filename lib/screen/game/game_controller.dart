import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../game/debug/autopilot.dart';
import '../../game/debug/debug_launch.dart';
import '../../game/game_config.dart';
import '../../game/logic/family.dart';
import '../../game/logic/gas_chat.dart';
import '../../game/logic/roadside.dart';
import '../../game/logic/soundscape.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../game/vehicle_spec.dart';
import '../../dialog/map_picker_dialog.dart';
import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import '../../route.dart';
import '../../service/audio_service.dart';
import '../../service/daily_service.dart';
import '../../service/local_service.dart';
import '../../service/route_service.dart';
import '../../service/trip_service.dart';

class GameController extends GetxController {
  late StageSetup setup;
  late VeQueGame game;

  /// Trời đang chọn (đổi được ngay giữa chặng ở menu tạm dừng).
  final sky = SkyMode.clock.obs;

  /// Hỗ trợ lái đang bật (giữ làn, bám xe trước, tự chậm trước khúc cua).
  final driveAssist = LocalService.shared.getDriveAssist().obs;

  /// Rung máy khi va chạm, quệt lề, có nguy hiểm.
  final haptics = LocalService.shared.getHaptics().obs;

  /// Radio trên xe: bản tin giao thông, nhạc xuân (lưu cho lần chơi sau).
  final radio = LocalService.shared.getRadio().obs;

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

  /// Thử thách hôm nay: điểm lần này, kỷ lục trong ngày, chuỗi ngày.
  final dailyResult = Rxn<DailyResult>();

  /// Đang xem cảnh về tới nhà, đón giao thừa (trước bảng kết quả chặng cuối).
  final homecoming = false.obs;

  /// Vì sao công an tới (để bảng chọn ghi đúng lý do) và chi tiết lỗi.
  final incidentKind = IncidentKind.collision.obs;
  final violation = Rxn<Violation>();

  /// Thông báo ngắn đang hiện (tự ẩn sau vài giây).
  final notice = Rxn<GameNotice>();
  Timer? _noticeTimer;

  /// Thông báo chờ tới lượt (cái đang hiện quan trọng hơn hoặc vừa mới hiện),
  /// xếp theo [NoticeKind.rank] rồi theo lúc báo.
  final List<(GameNotice, DateTime)> _noticeQueue = [];
  DateTime _noticeAt = DateTime(0);
  DateTime _noticeEnd = DateTime(0);

  /// Hiện ít nhất chừng này mới để thông báo cùng mức thay; chờ quá
  /// [_noticeStale] thì bỏ (chuyện đã qua rồi).
  static const _noticeMin = Duration(milliseconds: 2200);

  /// Bản tin radio dài hai dòng: giữ lâu hơn mới nhường thông báo cùng mức.
  static const _radioMin = Duration(milliseconds: 4200);
  static const _noticeStale = Duration(seconds: 7);

  /// Đang ghé quán (null khi đang lái).
  final stallVisit = Rxn<StallVisit>();

  /// Việc bên lề đang làm (thay lốp, chờ xăng…), null khi không có.
  final job = Rxn<JobState>();

  /// Lần đổ xăng gần nhất: mức bình trước / sau (bảng cột bơm chạy số).
  final pump = Rxn<(double, double)>();

  /// Góc nhìn ghế lái (lưu lại cho lần chơi sau); đang nạp ảnh của góc này.
  final driverView = false.obs;
  final viewLoading = false.obs;

  /// Điện thoại từ nhà đang reo / đang nói chuyện (null khi không có).
  final call = Rxn<PhoneCallState>();

  /// Chở cả nhà: câu vợ / con / mình vừa nói (tự ẩn sau vài giây).
  final familyLine = Rxn<FamilyLine>();
  Timer? _familyTimer;

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
    // Chặng tập lái đã có thẻ hướng dẫn riêng.
    if (!setup.tutorial && !LocalService.shared.getCruiseTipShown()) {
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
    sky.value = setup.sky;
    hud.value = null;
    phase.value = GamePhase.driving;
    result.value = null;
    dailyResult.value = null;
    homecoming.value = false;
    isPaused.value = false;
    chaseProgress.value = 0;
    stallVisit.value = null;
    job.value = null;
    call.value = null;
    familyLine.value = null;
    _familyTimer?.cancel();
    pump.value = null;
    notice.value = null;
    _noticeQueue.clear();
    _noticeTimer?.cancel();
    _endChat();
    _chatUsed.clear();
    game = VeQueGame(
      setup: setup,
      onHud: (data) {
        hud.value = data;
        _audio.setEngineLevel(data.speedKmh / maxSpeedKmh);
        if (!isPaused.value && !chatOpen.value) {
          _audio.setRain(data.rain);
          _updateAmbient(data);
        }
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
      onCall: (value) => call.value = value,
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
        // Chặng tập lái: thẻ hướng dẫn tự hiện bảng kết thúc, không lưu gì.
        if (setup.tutorial) return;
        // Về tới cuối chặng thì lưu tiến độ ngay (trạm dừng nghỉ); thử thách
        // hôm nay không thuộc chuyến đi nào, chỉ lưu kỷ lục trong ngày.
        if (setup.daily) {
          dailyResult.value = DailyService.shared.submit(value);
        } else if (value.won) {
          tripSummary.value = TripService.shared.completeStage(value);
        }
        homecoming.value = value.won && isLastStage;
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
      onHaptic: _haptic,
      // Tập lái: không buồn ngủ, không hết xăng, không mưa, không sự cố.
      fatigue: !setup.tutorial,
      onFamilyLine: _showFamilyLine,
    );
    game.driveAssist = driveAssist.value;
    game.radioOn = radio.value;
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
    _playDriveMusic();
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
      case GameSound.phoneRing:
        _audio.play(AppAudio.sfxPhoneRing, volume: 0.75);
      case GameSound.windGust:
        _audio.play(AppAudio.sfxWindGust, volume: 0.7);
      case GameSound.truckHorn:
        _audio.play(AppAudio.sfxTruckHorn, volume: 0.9);
      case GameSound.fireworks:
        _audio.play(AppAudio.sfxFireworks, volume: 0.8);
    }
  }

  /// Thông báo nguy hiểm chen ngay lên trước; thông báo thường không đè lên
  /// cái quan trọng hơn hay cái vừa hiện chưa kịp đọc mà xếp hàng chờ.
  void _showNotice(GameNotice value) {
    if (value.kind == NoticeKind.danger) _haptic(GameHaptic.medium);
    final current = notice.value;
    if (current?.text == value.text || _noticeQueue.any((q) => q.$1.text == value.text)) return;
    if (current == null) return _presentNotice(value);
    final now = DateTime.now();
    final shown = now.difference(_noticeAt);
    if (value.kind.rank > current.kind.rank) {
      if (shown < _noticeMin) _queueNotice(current, _noticeAt, first: true);
      return _presentNotice(value);
    }
    final readMin = current.kind == NoticeKind.radio ? _radioMin : _noticeMin;
    if (value.kind.rank == current.kind.rank && current.kind != NoticeKind.danger && shown >= readMin) {
      return _presentNotice(value);
    }
    _queueNotice(value, now);
    // Có cái đang chờ: thông báo thường chỉ giữ đủ lâu để đọc rồi nhường.
    final due = _noticeAt.add(readMin);
    if (current.kind != NoticeKind.danger && due.isBefore(_noticeEnd)) _scheduleNotice(due);
  }

  void _queueNotice(GameNotice value, DateTime at, {bool first = false}) {
    var i = _noticeQueue.indexWhere((q) => first ? q.$1.kind.rank <= value.kind.rank : q.$1.kind.rank < value.kind.rank);
    if (i < 0) i = _noticeQueue.length;
    _noticeQueue.insert(i, (value, at));
    if (_noticeQueue.length > 3) _noticeQueue.removeLast();
  }

  void _presentNotice(GameNotice value) {
    notice.value = value;
    _noticeAt = DateTime.now();
    if (value.kind == NoticeKind.radio && radio.value) {
      // Nhạc hiệu của đài, nhạc nhỏ xuống trong lúc đọc bản tin.
      _audio.play(AppAudio.sfxRadioJingle, volume: 0.5);
      _audio.duckMusic(const Duration(milliseconds: 5200));
    }
    final hold = value.kind == NoticeKind.danger
        ? const Duration(milliseconds: 4500)
        : value.kind == NoticeKind.radio
            ? const Duration(milliseconds: 5600)
            : _noticeQueue.isEmpty
            ? const Duration(milliseconds: 3200)
            : _noticeMin;
    _scheduleNotice(_noticeAt.add(hold));
  }

  void _scheduleNotice(DateTime end) {
    _noticeEnd = end;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(end.difference(DateTime.now()), _nextNotice);
  }

  void _nextNotice() {
    final now = DateTime.now();
    _noticeQueue.removeWhere((q) => now.difference(q.$2) > _noticeStale);
    if (_noticeQueue.isEmpty) {
      notice.value = null;
      return;
    }
    _presentNotice(_noticeQueue.removeAt(0).$1);
  }

  /// Câu nói trên xe hiện ở thẻ góc trái, giữ đủ lâu để đọc.
  void _showFamilyLine(FamilyLine line) {
    familyLine.value = line;
    _familyTimer?.cancel();
    _familyTimer = Timer(Duration(milliseconds: (line.seconds * 1000).round() + 900), () => familyLine.value = null);
  }

  /// Chuyến này chở cả nhà (vợ + bé) về quê.
  bool get familyRide => game.familyRide;

  /// Mua bim bim / hộp sữa cho bé ở quán.
  void orderSnack(FamilySnack snack) => game.orderSnack(snack);

  // ------------------------------------------- Quán ven đường, quay đầu
  void stopAtStall() => game.stopAtStall();
  void answerCall({required bool pullOver}) => game.answerCall(pullOver: pullOver);
  void declineCall() => game.declineCall();
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
      case RoadAction.approach:
        game.approachStall();
      case RoadAction.pickUp:
        game.pickUpHitch();
      case RoadAction.dropOff:
        game.dropOffRider();
      case RoadAction.cancelApproach:
        game.cancelApproach();
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
        _playDriveMusic();
      case GamePhase.resting:
        break;
      case GamePhase.finished:
        _audio.stopEngine();
        _audio.stopSiren();
        _audio.setRain(0);
        _audio.stopAmbient();
        _audio.stopMusic();
    }
  }

  /// Nhạc khi lái: bật radio thì nghe nhạc xuân của đài (hai bài lần lượt),
  /// tắt thì nhạc nền của game.
  Future<void> _playDriveMusic() {
    if (radio.value) return _audio.playPlaylist(AppAudio.radioMusic, start: setup.stageNumber - 1);
    return _audio.playMusic(AppAudio.musicMain);
  }

  /// Tiếng nền theo cảnh hai bên đường, đoạn đường (phố, quốc lộ, cao tốc),
  /// ngày / đêm, mưa, giờ giao thừa.
  void _updateAmbient(HudData data) {
    if (phase.value == GamePhase.finished) return;
    final pick = Soundscape.pick(
      theme: setup.theme,
      zone: game.layout.kindAt(game.player.s),
      night: game.nightLevel > 0.5,
      minutesLeft: data.minutesLeft.toDouble(),
      rain: data.rain,
      cabin: setup.vehicle.fourWheels,
    );
    _audio.setAmbient(pick.file, pick.volume);
  }

  /// Bật / tắt radio (lưu cho các lần chơi sau): đổi nhạc ngay, tắt thì thôi
  /// đọc bản tin.
  Future<void> setRadio(bool on) async {
    LocalService.shared.saveRadio(on);
    radio.value = on;
    game.radioOn = on;
    if (phase.value != GamePhase.driving && phase.value != GamePhase.resting) return;
    await _playDriveMusic();
    // Đang ở menu tạm dừng thì nhạc mới cũng chờ tới lúc đi tiếp.
    if (isPaused.value) _audio.pauseLoops();
  }

  @override
  void onClose() {
    _noticeTimer?.cancel();
    _cruiseTipTimer?.cancel();
    _chatTimer?.cancel();
    _familyTimer?.cancel();
    _autopilot?.stop();
    _audio.stopEngine();
    _audio.stopSiren();
    _audio.setRain(0);
    _audio.stopAmbient();
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

  void _haptic(GameHaptic kind) {
    if (!haptics.value) return;
    switch (kind) {
      case GameHaptic.light:
        HapticFeedback.lightImpact();
      case GameHaptic.medium:
        HapticFeedback.mediumImpact();
      case GameHaptic.heavy:
        HapticFeedback.heavyImpact();
        Timer(const Duration(milliseconds: 140), HapticFeedback.heavyImpact);
    }
  }

  void setHaptics(bool on) {
    LocalService.shared.saveHaptics(on);
    haptics.value = on;
    if (on) HapticFeedback.mediumImpact();
  }

  /// Bật / tắt hỗ trợ lái (lưu cho các lần chơi sau).
  void setDriveAssist(bool on) {
    LocalService.shared.saveDriveAssist(on);
    driveAssist.value = on;
    game.driveAssist = on;
  }

  /// Đổi trời ngay (theo giờ / luôn ngày / luôn đêm), lưu cho các chặng sau.
  void setSky(SkyMode value) {
    LocalService.shared.saveSkyMode(value);
    sky.value = value;
    game.sky = value;
    setup = setup.copyWith(sky: value);
  }

  /// Chọn bản đồ giữa chặng: trời đổi ngay; bản đồ khác thì dựng lại chặng
  /// này (chơi lại từ đầu chặng) với cảnh mới.
  Future<void> pickMap() async {
    await MapPickerDialog.open(note: 'Đổi bản đồ thì chặng này chơi lại từ đầu');
    final chosenSky = LocalService.shared.getSkyMode();
    if (chosenSky != sky.value) setSky(chosenSky);
    final theme = TripService.themeFor(setup.fromName, setup.toName);
    if (theme == setup.theme) return;
    // Thử thách hôm nay giữ nguyên hạt giống (cùng chặng với mọi người).
    setup = setup.copyWith(theme: theme, seed: setup.daily ? null : _random.nextInt(1 << 20));
    _createGame();
  }

  /// Thua thì chơi lại chặng này từ trạm dừng nghỉ gần nhất.
  void retry() {
    // Thử thách hôm nay chơi lại đúng chặng đó.
    if (!setup.daily) setup = setup.withSeed(_random.nextInt(1 << 20));
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
