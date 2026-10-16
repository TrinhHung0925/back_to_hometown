import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';

/// Tiếng nền hai bên đường đang nghe: file lặp nào, to bao nhiêu (đặt dưới
/// tiếng máy xe).
class Soundscape {
  const Soundscape(this.file, this.volume);

  final String file;
  final double volume;

  /// Độ to chuẩn (file đã chuẩn hoá cùng độ to nghe được).
  static const double baseVolume = 0.3;

  /// Còn chừng này phút là giao thừa thì đâu đâu cũng rộn tiếng trống lân,
  /// pháo hoa; trong phố thì rộn sớm hơn từ lúc tối.
  static const double eveMinutes = 45;
  static const double cityEveMinutes = 150;

  /// Cảnh [theme], đoạn đường [zone], trời tối chưa, còn bao lâu tới giao
  /// thừa, mưa to cỡ nào (mưa át tiếng chim, côn trùng nín), ngồi trong ô tô
  /// đóng kính ([cabin]) thì nghe nhỏ hơn đi xe máy.
  static Soundscape pick({
    required MapTheme theme,
    required RoadKind zone,
    required bool night,
    required double minutesLeft,
    double rain = 0,
    bool cabin = false,
  }) {
    var volume = baseVolume;
    final String file;
    if (minutesLeft <= eveMinutes || (zone == RoadKind.city && night && minutesLeft <= cityEveMinutes)) {
      file = AppAudio.ambTetEve;
      volume *= zone == RoadKind.city ? 1.05 : 0.8;
    } else if (zone == RoadKind.city) {
      file = AppAudio.ambCity;
      if (night) volume *= 0.75;
    } else {
      file = switch (theme) {
        MapTheme.coast => night ? AppAudio.ambCoastNight : AppAudio.ambCoastDay,
        MapTheme.mountain => night ? AppAudio.ambMountainNight : AppAudio.ambMountainDay,
        MapTheme.mekong => night ? AppAudio.ambDeltaNight : AppAudio.ambMekongDay,
        MapTheme.delta || MapTheme.auto => night ? AppAudio.ambDeltaNight : AppAudio.ambDeltaDay,
      };
      // Cao tốc: xa làng xóm, gió và tiếng lốp át gần hết.
      if (zone == RoadKind.expressway) volume *= 0.6;
    }
    volume *= 1 - 0.55 * rain.clamp(0.0, 1.0);
    if (cabin) volume *= 0.7;
    // Làm tròn để khỏi đổi âm lượng liên tục theo từng chút mưa.
    return Soundscape(file, (volume * 50).round() / 50);
  }

  @override
  bool operator ==(Object other) => other is Soundscape && other.file == file && other.volume == volume;

  @override
  int get hashCode => Object.hash(file, volume);

  @override
  String toString() => 'Soundscape($file, $volume)';
}
