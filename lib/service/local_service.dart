import 'package:get_storage/get_storage.dart';

import '../model/difficulty.dart';
import '../model/map_theme.dart';

enum LocalKey {
  intro,
  soundOn,
  currentTrip,
  records,
  cruiseTip,
  driverView,
  mapTheme,
  skyMode,
  driveAssist,
  controlTip,
  difficulty,
  haptics,
  tutorialDone,
  daily,
  radioOn,
}

class LocalService {
  static final LocalService shared = LocalService._internal();

  factory LocalService() => shared;

  LocalService._internal();

  var storage = GetStorage();

  void saveIntro() {
    storage.write(LocalKey.intro.name, false);
  }

  bool getIntro() {
    return storage.read(LocalKey.intro.name) ?? true;
  }

  void saveSoundOn(bool on) {
    storage.write(LocalKey.soundOn.name, on);
  }

  bool getSoundOn() {
    return storage.read(LocalKey.soundOn.name) ?? true;
  }

  /// Đã chỉ cách dùng ga, phanh, cần lái (kiểu nấc + hỗ trợ lái) chưa —
  /// chỉ một lần.
  bool getCruiseTipShown() => storage.read(LocalKey.controlTip.name) ?? false;

  void saveCruiseTipShown() {
    storage.write(LocalKey.controlTip.name, true);
  }

  /// Độ khó chọn cho chuyến sắp đi.
  Difficulty getDifficulty() => Difficulty.values.asNameMap()[storage.read<String>(LocalKey.difficulty.name)] ?? Difficulty.normal;

  void saveDifficulty(Difficulty value) {
    storage.write(LocalKey.difficulty.name, value.name);
  }

  /// Rung máy khi va chạm, quệt lề, sắp đâm (mặc định bật).
  bool getHaptics() => storage.read(LocalKey.haptics.name) ?? true;

  void saveHaptics(bool on) {
    storage.write(LocalKey.haptics.name, on);
  }

  /// Radio trên xe: bản tin giao thông, nhạc xuân khi lái (mặc định bật).
  bool getRadio() => storage.read(LocalKey.radioOn.name) ?? true;

  void saveRadio(bool on) {
    storage.write(LocalKey.radioOn.name, on);
  }

  /// Đã chơi xong chặng tập lái chưa.
  bool getTutorialDone() => storage.read(LocalKey.tutorialDone.name) ?? false;

  void saveTutorialDone() {
    storage.write(LocalKey.tutorialDone.name, true);
  }

  /// Thử thách hôm nay: kỷ lục trong ngày, chuỗi ngày (JSON của DailyRecord).
  Map<String, dynamic>? getDaily() {
    final value = storage.read(LocalKey.daily.name);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void saveDaily(Map<String, dynamic> json) {
    storage.write(LocalKey.daily.name, json);
  }

  /// Hỗ trợ lái: giữ làn, bám xe trước, tự giảm tốc trước khúc cua (mặc định bật).
  bool getDriveAssist() => storage.read(LocalKey.driveAssist.name) ?? true;

  void saveDriveAssist(bool on) {
    storage.write(LocalKey.driveAssist.name, on);
  }

  /// Người chơi chọn góc nhìn ghế lái (giữ cho các chặng sau).
  bool getDriverView() => storage.read(LocalKey.driverView.name) ?? false;

  void saveDriverView(bool on) {
    storage.write(LocalKey.driverView.name, on);
  }

  /// Cảnh đường và trời người chơi chọn (áp cho các chặng sắp chơi).
  MapTheme getMapTheme() => MapTheme.values.asNameMap()[storage.read<String>(LocalKey.mapTheme.name)] ?? MapTheme.auto;

  void saveMapTheme(MapTheme theme) {
    storage.write(LocalKey.mapTheme.name, theme.name);
  }

  SkyMode getSkyMode() => SkyMode.values.asNameMap()[storage.read<String>(LocalKey.skyMode.name)] ?? SkyMode.clock;

  void saveSkyMode(SkyMode mode) {
    storage.write(LocalKey.skyMode.name, mode.name);
  }

  /// Chuyến đi đang chơi dở (JSON của TripProgress).
  void saveTrip(Map<String, dynamic> json) {
    storage.write(LocalKey.currentTrip.name, json);
  }

  Map<String, dynamic>? getTrip() {
    final value = storage.read(LocalKey.currentTrip.name);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void clearTrip() {
    storage.remove(LocalKey.currentTrip.name);
  }

  /// Kỷ lục theo tuyến: danh sách JSON của TripRecord.
  void saveRecords(List<Map<String, dynamic>> records) {
    storage.write(LocalKey.records.name, records);
  }

  List<Map<String, dynamic>> getRecords() {
    final value = storage.read(LocalKey.records.name);
    if (value is! List) return [];
    return [for (final item in value) if (item is Map) Map<String, dynamic>.from(item)];
  }
}
