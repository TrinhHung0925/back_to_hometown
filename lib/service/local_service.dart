import 'package:get_storage/get_storage.dart';

enum LocalKey {
  intro,
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
}
