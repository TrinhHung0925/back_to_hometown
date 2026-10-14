/// Chỉ dùng khi phát triển: mở thẳng một màn để chụp màn hình trên
/// simulator (simulator không nhận thao tác chạm từ dòng lệnh).
///
///   --dart-define=VEQUE_SCREEN=planTrip          mở màn theo tên AppPage
///   --dart-define=VEQUE_TRIP=ha_noi:vinh:car     chọn sẵn lộ trình
///   --dart-define=VEQUE_STAGE=c1.2,h2,e2          chặng thử: phố 1,2 km,
///       quốc lộ 2 km, cao tốc 2 km (kèm VEQUE_TOLLS, VEQUE_CLOCK=phút,
///       VEQUE_VEHICLE=car|motorbike)
abstract class DebugLaunch {
  static const String screen = String.fromEnvironment('VEQUE_SCREEN');
  static const String trip = String.fromEnvironment('VEQUE_TRIP');
  static const String stage = String.fromEnvironment('VEQUE_STAGE');
  static const int tolls = int.fromEnvironment('VEQUE_TOLLS');
  static const int clock = int.fromEnvironment('VEQUE_CLOCK', defaultValue: 600);
  static const String vehicle = String.fromEnvironment('VEQUE_VEHICLE', defaultValue: 'motorbike');

  /// (điểm đi, điểm đến, loại xe) hoặc null.
  static (String, String, String)? get tripParts {
    final parts = trip.split(':');
    if (parts.length != 3) return null;
    return (parts[0], parts[1], parts[2]);
  }
}
