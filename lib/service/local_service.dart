import 'package:get_storage/get_storage.dart';

enum LocalKey {
  intro,
  soundOn,
  currentTrip,
  records,
  cruiseTip,
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

  /// Đã chỉ cách dùng ga giữ mức chưa (chỉ một lần).
  bool getCruiseTipShown() => storage.read(LocalKey.cruiseTip.name) ?? false;

  void saveCruiseTipShown() {
    storage.write(LocalKey.cruiseTip.name, true);
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
