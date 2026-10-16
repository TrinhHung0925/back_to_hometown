import 'package:get/get.dart';

import '../../dialog/map_picker_dialog.dart';
import '../../dialog/place_picker_dialog.dart';
import '../../game/debug/debug_launch.dart';
import '../../game/vehicle_spec.dart';
import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../route.dart';
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

  /// Bản đồ và trời đang chọn (hàng "Bản đồ ›" + Theo giờ / Ngày / Đêm).
  final mapTheme = LocalService.shared.getMapTheme().obs;
  final sky = LocalService.shared.getSkyMode().obs;

  RouteService get routes => RouteService.shared;

  /// Chế độ lái xe khách: loại xe cố định là xe khách.
  late final bool coachMode = Get.arguments == VehicleKind.bus;

  @override
  void onInit() {
    super.onInit();
    if (coachMode) vehicle.value = VehicleKind.bus;
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
    sky.value = LocalService.shared.getSkyMode();
  }

  /// Chọn trời ngay trên bảng (lưu cho các chặng sắp chơi).
  void setSky(SkyMode value) {
    LocalService.shared.saveSkyMode(value);
    sky.value = value;
  }

  /// Chạm vào ô: chọn ô đó và mở danh sách để tìm theo tên.
  Future<void> pickFromList(TripField field) async {
    activeField.value = field;
    final id = await Get.dialog<String>(PlacePickerDialog(
      title: field == TripField.from ? 'Điểm xuất phát' : 'Điểm đến (quê bạn)',
      places: routes.places,
      selectedId: field == TripField.from ? fromId.value : toId.value,
    ));
    if (id != null) tapPlace(id);
  }

  void setVehicle(VehicleKind value) {
    if (coachMode) return;
    vehicle.value = value;
    _replan();
  }

  void swap() {
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
    return p == null ? null : TripService.departureFor(p, LocalService.shared.getDifficulty());
  }

  void start() {
    final p = plan.value;
    if (p == null) return;
    final progress = TripService.shared.start(p);
    Get.offNamed(AppPage.game.routeName, arguments: TripService.shared.stageSetup(progress));
  }

  onBack() {
    Get.back();
  }
}
