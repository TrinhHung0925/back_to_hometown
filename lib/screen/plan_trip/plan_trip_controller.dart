import 'package:get/get.dart';

import '../../dialog/map_picker_dialog.dart';
import '../../dialog/place_picker_dialog.dart';
import '../../game/debug/debug_launch.dart';
import '../../game/vehicle_spec.dart';
import '../../model/difficulty.dart';
import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../route.dart';
import '../../service/daily_service.dart';
import '../../service/route_service.dart';
import '../../service/local_service.dart';
import '../../service/trip_service.dart';

/// Ô đang được chọn: chạm vào bản đồ sẽ điền vào ô này.
enum TripField { from, to }

class PlanTripController extends GetxController {
  final fromId = RxnString();
  final toId = RxnString();
  final vehicle = VehicleKind.motorbike.obs;
  final activeField = TripField.from.obs;
  final plan = Rxn<TripPlan>();

  /// Chở cả nhà về quê (vợ ngồi sau, con nhỏ đi cùng); xe khách thì không.
  final family = false.obs;

  /// Bản đồ và trời đang chọn (hàng "Bản đồ ›" + Theo giờ / Ngày / Đêm).
  final mapTheme = LocalService.shared.getMapTheme().obs;
  final sky = LocalService.shared.getSkyMode().obs;

  RouteService get routes => RouteService.shared;

  /// Chế độ lái xe khách: loại xe cố định là xe khách.
  late final bool coachMode = Get.arguments == VehicleKind.bus;

  /// Thử thách hôm nay: lộ trình, xe, độ khó cố định theo ngày — chỉ xem lại
  /// trên bản đồ và chọn bản đồ / trời rồi xuất phát.
  late final DailyChallenge? daily = Get.arguments is DailyChallenge ? Get.arguments as DailyChallenge : null;

  /// Điểm đi / đến và loại xe không đổi được (thử thách hôm nay).
  bool get locked => daily != null;

  /// Độ khó của chuyến sắp đi (thử thách thì theo ngày).
  Difficulty get difficulty => daily?.difficulty ?? LocalService.shared.getDifficulty();

  @override
  void onInit() {
    super.onInit();
    if (coachMode) vehicle.value = VehicleKind.bus;
    final challenge = daily;
    if (challenge != null) {
      vehicle.value = challenge.route.vehicle;
      mapTheme.value = challenge.route.theme;
      sky.value = challenge.sky;
      fromId.value = challenge.route.fromId;
      toId.value = challenge.route.toId;
      activeField.value = TripField.to;
      _replan();
    }
    final debugTrip = DebugLaunch.tripParts;
    if (debugTrip != null) {
      if (!coachMode) vehicle.value = VehicleKind.values.byName(debugTrip.$3);
      tapPlace(debugTrip.$1);
      tapPlace(debugTrip.$2);
    }
  }

  /// Chạm một thành phố trên bản đồ: điền vào ô đang chọn, rồi tự chuyển
  /// sang ô điểm đến.
  void tapPlace(String id) {
    if (locked) return;
    if (activeField.value == TripField.from) {
      fromId.value = id;
      if (toId.value == id) toId.value = null;
      activeField.value = TripField.to;
    } else {
      toId.value = id;
      if (fromId.value == id) fromId.value = null;
    }
    _replan();
  }

  /// Mở hộp chọn bản đồ (cảnh hai bên đường, trời ngày / đêm).
  Future<void> pickMap() async {
    await MapPickerDialog.open();
    mapTheme.value = LocalService.shared.getMapTheme();
    if (!locked) sky.value = LocalService.shared.getSkyMode();
  }

  /// Chọn trời ngay trên bảng (lưu cho các chặng sắp chơi).
  void setSky(SkyMode value) {
    // Thử thách hôm nay: chỉ đổi cho chặng này, không lưu cho chuyến về quê.
    if (!locked) LocalService.shared.saveSkyMode(value);
    sky.value = value;
  }

  /// Chạm vào ô: chọn ô đó và mở danh sách để tìm theo tên.
  Future<void> pickFromList(TripField field) async {
    if (locked) return;
    activeField.value = field;
    final id = await Get.dialog<String>(PlacePickerDialog(
      title: field == TripField.from ? 'Điểm xuất phát' : 'Điểm đến (quê bạn)',
      places: routes.places,
      selectedId: field == TripField.from ? fromId.value : toId.value,
    ));
    if (id != null) tapPlace(id);
  }

  void setVehicle(VehicleKind value) {
    if (coachMode || locked) return;
    vehicle.value = value;
    _replan();
  }

  void setFamily(bool value) {
    if (coachMode || locked) return;
    family.value = value;
  }

  void swap() {
    if (locked) return;
    final from = fromId.value;
    fromId.value = toId.value;
    toId.value = from;
    _replan();
  }

  void _replan() {
    final from = fromId.value;
    final to = toId.value;
    plan.value = from != null && to != null ? routes.plan(from, to, vehicle.value) : null;
  }

  /// Giờ xuất phát của lộ trình đang chọn (phút trong game).
  double? get departureMinutes {
    final p = plan.value;
    return p == null ? null : TripService.departureFor(p, difficulty);
  }

  void start() {
    final p = plan.value;
    if (p == null) return;
    final challenge = daily;
    if (challenge != null) {
      // Thử thách: giữ nguyên chặng, hạt giống, độ khó; bản đồ và trời theo lựa chọn ở đây.
      final from = fromId.value;
      final to = toId.value;
      final setup = DailyService.setupFor(challenge).copyWith(
        theme: mapTheme.value.resolve(from == null ? null : routes.place(from), to == null ? null : routes.place(to)),
        sky: sky.value,
      );
      Get.offNamed(AppPage.game.routeName, arguments: setup);
      return;
    }
    final progress = TripService.shared.start(p, family: family.value && !coachMode);
    Get.offNamed(AppPage.game.routeName, arguments: TripService.shared.stageSetup(progress));
  }

  onBack() {
    Get.back();
  }
}
