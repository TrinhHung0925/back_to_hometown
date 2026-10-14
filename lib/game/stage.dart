import 'package:flutter/foundation.dart';

import '../model/trip.dart';
import 'logic/road_layout.dart';
import 'logic/roadside.dart';
import 'logic/vehicle_condition.dart';
import 'logic/weather.dart';
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
    this.startFuel = 0.6,
    this.stageNumber = 1,
    this.stageCount = 1,
    this.seed = 0,
    this.south = false,
    this.laterMinutes = 0,
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

  /// Xăng trong bình lúc vào chặng (0..1), mang từ chặng trước sang.
  final double startFuel;

  /// Chặng thứ mấy / tổng số chặng của chuyến đi.
  final int stageNumber;
  final int stageCount;
  final int seed;

  /// Chặng ở miền Nam (lúa chín vàng dịp Tết thay cho lúa non).
  final bool south;

  /// Các chặng sau chặng này cần chừng bao nhiêu phút trong game (chạy ở tốc
  /// độ thường) — để HUD báo đang dư hay trễ giờ so với giao thừa.
  final double laterMinutes;

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
        startFuel: startFuel,
        stageNumber: stageNumber,
        stageCount: stageCount,
        seed: value,
        south: south,
        laterMinutes: laterMinutes,
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
    this.fuel = 0.6,
  });

  final StageEndReason reason;
  final int lixi;
  final int cargo;

  /// Xăng còn lại khi tới cuối chặng.
  final double fuel;
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

enum GamePhase {
  driving,

  /// Ghé quán ven đường (uống nước, đổ xăng, vá xe), hoặc dừng bên lề làm
  /// việc gì đó (thay lốp dự phòng, chờ người mang xăng tới).
  resting,
  incident,
  chase,
  finished,
}

/// Đang ghé quán: quán nào, chuyện nghe được ở quán, đã ngồi xuống chưa
/// (ngồi rồi mới gọi món được).
class StallVisit {
  const StallVisit({required this.stall, required this.chatter, required this.seated});

  final Stall stall;
  final List<String> chatter;
  final bool seated;
}

/// Việc làm bên lề không cần quán: thay lốp dự phòng, chờ người mang xăng /
/// thợ vá lưu động tới. [steps] hiện lần lượt theo [progress].
enum RoadsideJobKind { spareTire, fuelDelivery, mobileRepair }

/// Việc bên lề đang làm tới đâu (0..1).
class JobState {
  const JobState(this.job, this.progress);

  final RoadsideJob job;
  final double progress;
}

class RoadsideJob {
  const RoadsideJob({required this.kind, required this.title, required this.steps, required this.minutes, this.lixi = 0});

  final RoadsideJobKind kind;
  final String title;
  final List<String> steps;
  final double minutes;
  final int lixi;
}

/// Vì sao công an tới.
enum IncidentKind {
  /// Quẹt xe, đâm barrier / đảo phân làn ở tốc độ thấp.
  collision,

  /// Vượt đèn đỏ.
  redLight,

  /// Chạy quá tốc độ qua chốt CSGT.
  speeding,

  /// Quay đầu nơi cấm (vùng chốt CSGT).
  illegalUTurn,

  /// Đâm mạnh gây tai nạn: xe hỏng, chờ lập biên bản và sửa xe (không bỏ
  /// chạy được).
  crash;

  /// Tiền phạt (lì xì) và số phút bị giữ lại.
  int get fineLixi => switch (this) {
        speeding => GameConfig.speedingFineLixi,
        illegalUTurn => GameConfig.uTurnFineLixi,
        crash => GameConfig.crashFineLixi,
        _ => GameConfig.fineLixi,
      };
  double get fineMinutes => switch (this) {
        speeding => GameConfig.speedingFineMinutes,
        illegalUTurn => GameConfig.uTurnFineMinutes,
        crash => GameConfig.crashFineMinutes,
        _ => GameConfig.fineMinutes,
      };
}

/// Chi tiết lỗi để ghi biên bản (tốc độ đo được, tốc độ cho phép).
class Violation {
  const Violation(this.kind, {this.measuredKmh = 0, this.limitKmh = 0, this.place = ''});

  final IncidentKind kind;
  final int measuredKmh;
  final int limitKmh;
  final String place;
}

/// Nút theo tình huống hiện cạnh cụm nút lái.
enum RoadAction {
  /// Ghé quán / đổ xăng / mua xăng lẻ / vá xe (nhãn theo kiểu quán).
  visit,
  uTurn,

  /// Hết xăng (xe máy): nghiêng xe dồn xăng, dắt bộ, thôi dắt.
  tiltBike,
  push,

  /// Gọi người mang xăng tới / gọi cứu hộ.
  callFuel,

  /// Thay lốp dự phòng (ô tô, xe khách), gọi thợ vá lưu động.
  spareTire,
  callMechanic,
}

/// Biển hạn chế tốc độ ở chốt CSGT phía trước.
class SpeedLimitHud {
  const SpeedLimitHud({required this.limit, required this.meters, required this.over});

  final int limit;
  final int meters;
  final bool over;

  @override
  bool operator ==(Object other) => other is SpeedLimitHud && other.limit == limit && other.meters == meters && other.over == over;

  @override
  int get hashCode => Object.hash(limit, meters, over);
}

/// Sự kiện âm thanh game báo ra ngoài (tầng Flutter quyết định phát gì).
enum GameSound {
  lixi,
  gift,
  pothole,
  crashLight,
  crashHeavy,
  skid,
  horn,
  hornOther,
  toll,
  barrier,

  /// Lốp xì hơi, còi CSGT thổi, máy khục khặc, cột bơm xăng chạy.
  tireHiss,
  whistle,
  sputter,
  fuelPump,
}

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
    this.cruiseKmh = 0,
    this.spareMinutes = 0,
    required this.clockLabel,
    required this.minutesLeft,
    required this.lixi,
    required this.cargo,
    required this.danger,
    this.light,
    this.curve,
    this.headlightsOn = false,
    this.night = false,
    this.alert = 100,
    this.drowse = 0,
    this.canUTurn = false,
    this.stallPrompt,
    this.stallKind,
    this.reversed = false,
    this.fuel = 1,
    this.fuelKm = 0,
    this.tire = TireState.ok,
    this.spare = false,
    this.rain = 0,
    this.rainKind,
    this.raincoat = false,
    this.soaked = 0,
    this.speedLimit,
    this.pullOver,
    this.outOfFuel = false,
    this.pushing = false,
    this.fuelAhead,
    this.repairAhead,
    this.actions = const [],
  });

  final int kmDone;
  final int kmTotal;
  final int speedKmh;

  /// Mức ga đang giữ (km/h): xe tự giữ tốc độ này khi buông tay.
  final int cruiseKmh;

  /// Chạy tiếp ở tốc độ thường thì về tới nhà dư (dương) / trễ (âm) bao
  /// nhiêu phút so với giao thừa.
  final int spareMinutes;
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

  /// Mức tỉnh táo 0..100; [drowse] 0..1 độ díp mắt (1 = đang ngủ gật).
  final int alert;
  final double drowse;

  /// Đang đủ chậm, đủ chỗ để hiện nút Quay đầu.
  final bool canUTurn;

  /// Tên quán đang dừng ngay trước mặt (hiện nút Ghé quán), null nếu không.
  final String? stallPrompt;

  /// Kiểu quán đang dừng trước mặt (để đặt nhãn nút: Đổ xăng, Vá xe…).
  final StallKind? stallKind;

  /// Đã quay đầu, đang đi ngược về phía điểm xuất phát.
  final bool reversed;

  /// Xăng còn (0..1, làm tròn 1%) và còn chạy được chừng bao nhiêu km.
  final double fuel;
  final int fuelKm;

  final TireState tire;

  /// Còn lốp dự phòng (ô tô, xe khách).
  final bool spare;

  /// Mưa: độ nặng hạt (0..1, làm tròn 0,1), loại mưa; xe máy có áo mưa
  /// chưa, ướt bao nhiêu (0..1).
  final double rain;
  final RainKind? rainKind;
  final bool raincoat;
  final double soaked;

  /// Biển hạn chế tốc độ phía trước (chốt CSGT), null nếu không có.
  final SpeedLimitHud? speedLimit;

  /// CSGT vẫy vào: còn bao nhiêu mét phải dừng (null nếu không bị vẫy).
  final int? pullOver;

  /// Hết sạch xăng, xe đứng / đang dắt bộ.
  final bool outOfFuel;
  final bool pushing;

  /// Chỗ đổ xăng / vá xe gần nhất phía trước (nhãn + km), null nếu không cần.
  final String? fuelAhead;
  final String? repairAhead;

  /// Nút theo tình huống đang hiện.
  final List<RoadAction> actions;

  @override
  bool operator ==(Object other) =>
      other is HudData &&
      other.kmDone == kmDone &&
      other.kmTotal == kmTotal &&
      other.speedKmh == speedKmh &&
      other.cruiseKmh == cruiseKmh &&
      other.spareMinutes == spareMinutes &&
      other.clockLabel == clockLabel &&
      other.minutesLeft == minutesLeft &&
      other.lixi == lixi &&
      other.cargo == cargo &&
      other.danger == danger &&
      other.light == light &&
      other.curve == curve &&
      other.headlightsOn == headlightsOn &&
      other.night == night &&
      other.alert == alert &&
      other.drowse == drowse &&
      other.canUTurn == canUTurn &&
      other.stallPrompt == stallPrompt &&
      other.stallKind == stallKind &&
      other.reversed == reversed &&
      other.fuel == fuel &&
      other.fuelKm == fuelKm &&
      other.tire == tire &&
      other.spare == spare &&
      other.rain == rain &&
      other.rainKind == rainKind &&
      other.raincoat == raincoat &&
      other.soaked == soaked &&
      other.speedLimit == speedLimit &&
      other.pullOver == pullOver &&
      other.outOfFuel == outOfFuel &&
      other.pushing == pushing &&
      other.fuelAhead == fuelAhead &&
      other.repairAhead == repairAhead &&
      listEquals(other.actions, actions);

  @override
  int get hashCode => Object.hashAll([
        kmDone, kmTotal, speedKmh, cruiseKmh, spareMinutes, clockLabel, minutesLeft, lixi, cargo, danger, light, curve, headlightsOn, night, //
        alert, drowse, canUTurn, stallPrompt, stallKind, reversed, fuel, fuelKm, tire, spare, rain, rainKind, raincoat,
        soaked, speedLimit, pullOver, outOfFuel, pushing, fuelAhead, repairAhead, Object.hashAll(actions),
      ]);
}
