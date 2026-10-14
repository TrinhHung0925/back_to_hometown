import '../model/trip.dart';
import 'logic/road_layout.dart';
import 'game_config.dart';
import 'vehicle_spec.dart';

/// Đầu vào của một chặng (dựng từ lộ trình trên bản đồ).
class StageSetup {
  const StageSetup({
    required this.vehicle,
    required this.fromName,
    required this.toName,
    required this.sections,
    required this.startClockMinutes,
    this.tollBooths = 0,
    this.startLixi = 0,
    this.startCargo = 0,
    this.stageNumber = 1,
    this.stageCount = 1,
    this.seed = 0,
    this.south = false,
  });

  final VehicleKind vehicle;
  final String fromName;
  final String toName;

  /// Các đoạn đường liên tiếp trong chặng (phố, quốc lộ, cao tốc).
  final List<StageSection> sections;
  final int tollBooths;

  /// Giờ trong game lúc xuất phát (phút kể từ 00:00 ngày giao thừa; âm là
  /// các ngày trước đó).
  final double startClockMinutes;

  final int startLixi;
  final int startCargo;

  /// Chặng thứ mấy / tổng số chặng của chuyến đi.
  final int stageNumber;
  final int stageCount;
  final int seed;

  /// Chặng ở miền Nam (lúa chín vàng dịp Tết thay cho lúa non).
  final bool south;

  double get lengthKm => sections.fold(0, (sum, s) => sum + s.km);
  double get lengthUnits => lengthKm * GameConfig.unitsPerKm;

  StageSetup withSeed(int value) => StageSetup(
        vehicle: vehicle,
        fromName: fromName,
        toName: toName,
        sections: sections,
        startClockMinutes: startClockMinutes,
        tollBooths: tollBooths,
        startLixi: startLixi,
        startCargo: startCargo,
        stageNumber: stageNumber,
        stageCount: stageCount,
        seed: value,
        south: south,
      );
}

enum StageEndReason {
  arrived,

  /// Quá giao thừa mà chưa tới nơi.
  timeUp,

  /// Bỏ chạy và bị công an bắt.
  caught,

  /// Đâm mạnh.
  accident,
}

class StageResult {
  const StageResult({
    required this.reason,
    required this.lixi,
    required this.cargo,
    required this.clockMinutes,
    required this.minutesLeft,
  });

  final StageEndReason reason;
  final int lixi;
  final int cargo;
  final double clockMinutes;
  final double minutesLeft;

  bool get won => reason == StageEndReason.arrived;

  /// 1 sao khi về kịp; thêm sao khi còn dư nhiều thời gian.
  int get stars {
    if (!won) return 0;
    if (minutesLeft >= 25) return 3;
    if (minutesLeft >= 10) return 2;
    return 1;
  }

  int get score => won ? lixi * 100 + cargo * 300 + (minutesLeft * 10).round() : 0;
}

enum GamePhase { driving, incident, chase, finished }

/// Vì sao công an tới.
enum IncidentKind {
  /// Quẹt xe, đâm barrier / đảo phân làn ở tốc độ thấp.
  collision,

  /// Vượt đèn đỏ.
  redLight,
}

/// Sự kiện âm thanh game báo ra ngoài (tầng Flutter quyết định phát gì).
enum GameSound { lixi, gift, pothole, crashLight, crashHeavy, skid, horn, hornOther, toll, barrier }

enum NoticeKind { info, warning, money }

/// Thông báo ngắn hiện giữa phía trên màn hình (vào phố, sắp tới trạm thu
/// phí, xe vượt phía sau…).
class GameNotice {
  const GameNotice(this.text, {this.kind = NoticeKind.info});

  final String text;
  final NoticeKind kind;
}

/// Đèn giao thông sắp tới (hiện góc trên HUD).
class LightHud {
  const LightHud({required this.color, required this.seconds, required this.meters});

  final LightColor color;
  final int seconds;
  final int meters;

  @override
  bool operator ==(Object other) =>
      other is LightHud && other.color == color && other.seconds == seconds && other.meters == meters;

  @override
  int get hashCode => Object.hash(color, seconds, meters);
}

/// Khúc cua gắt phía trước (hiện trên HUD): hướng cua, khoảng cách, tốc độ
/// khuyên dùng và mình có đang chạy quá nhanh không.
class CurveHud {
  const CurveHud({required this.right, required this.meters, required this.adviseKmh, required this.tooFast});

  final bool right;
  final int meters;
  final int adviseKmh;
  final bool tooFast;

  @override
  bool operator ==(Object other) =>
      other is CurveHud &&
      other.right == right &&
      other.meters == meters &&
      other.adviseKmh == adviseKmh &&
      other.tooFast == tooFast;

  @override
  int get hashCode => Object.hash(right, meters, adviseKmh, tooFast);
}

/// Ảnh chụp số liệu để HUD Flutter hiển thị. Game chỉ gửi khi có số thay đổi.
class HudData {
  const HudData({
    required this.kmDone,
    required this.kmTotal,
    required this.speedKmh,
    required this.clockLabel,
    required this.minutesLeft,
    required this.lixi,
    required this.cargo,
    required this.danger,
    this.light,
    this.curve,
    this.headlightsOn = false,
    this.night = false,
  });

  final int kmDone;
  final int kmTotal;
  final int speedKmh;
  final String clockLabel;
  final int minutesLeft;
  final int lixi;
  final int cargo;

  /// Đang ở tốc độ / làn mà đâm vào là tai nạn.
  final bool danger;

  /// Đèn giao thông phía trước (null nếu không có đèn gần).
  final LightHud? light;

  /// Khúc cua gắt phía trước (null nếu không có).
  final CurveHud? curve;
  final bool headlightsOn;

  /// Trời đã tối (nên bật đèn).
  final bool night;

  @override
  bool operator ==(Object other) =>
      other is HudData &&
      other.kmDone == kmDone &&
      other.kmTotal == kmTotal &&
      other.speedKmh == speedKmh &&
      other.clockLabel == clockLabel &&
      other.minutesLeft == minutesLeft &&
      other.lixi == lixi &&
      other.cargo == cargo &&
      other.danger == danger &&
      other.light == light &&
      other.curve == curve &&
      other.headlightsOn == headlightsOn &&
      other.night == night;

  @override
  int get hashCode =>
      Object.hash(kmDone, kmTotal, speedKmh, clockLabel, minutesLeft, lixi, cargo, danger, light, curve, headlightsOn, night);
}
