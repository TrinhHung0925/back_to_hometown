import '../game/vehicle_spec.dart';

const assetsImgPath = 'assets/images';
const assetsIconPath = 'assets/icons';
const assetsAudioPath = 'assets/audio';

abstract class Img {
  /// icons — nút, cần lái, icon (Kenney Mobile Controls, CC0; còi và đèn tự vẽ,
  /// xem tool/asset_pipeline/build_ui_icons.py)
  static const String icButtonCircle = '$assetsIconPath/ic_button_circle.png';
  static const String icJoystickPad = '$assetsIconPath/ic_joystick_pad.png';
  static const String icJoystickNub = '$assetsIconPath/ic_joystick_nub.png';
  static const String icPedalGas = '$assetsIconPath/ic_pedal_gas.png';
  static const String icPedalBrake = '$assetsIconPath/ic_pedal_brake.png';
  static const String icHorn = '$assetsIconPath/ic_horn.png';
  static const String icHeadlight = '$assetsIconPath/ic_headlight.png';
  static const String icChat = '$assetsIconPath/ic_chat.png';
  static const String icPause = '$assetsIconPath/ic_pause.png';
  static const String icPlay = '$assetsIconPath/ic_play.png';
  static const String icRetry = '$assetsIconPath/ic_retry.png';
  static const String icMenu = '$assetsIconPath/ic_menu.png';
  static const String icStar = '$assetsIconPath/ic_star.png';
  static const String icSoundOn = '$assetsIconPath/ic_sound_on.png';
  static const String icSoundOff = '$assetsIconPath/ic_sound_off.png';
  static const String icSwap = '$assetsIconPath/ic_swap.png';
  static const String icSearch = '$assetsIconPath/ic_search.png';
  static const String icTarget = '$assetsIconPath/ic_target.png';
  static const String icZoomOut = '$assetsIconPath/ic_zoom_out.png';
  static const String icClose = '$assetsIconPath/ic_close.png';
  static const String icCheck = '$assetsIconPath/ic_check.png';
  static const String icMoney = '$assetsIconPath/ic_money.png';
  static const String icArrow = '$assetsIconPath/ic_arrow.png';

  /// images — xe nhìn từ trên xuống, mũi xe hướng lên trên.
  /// Ô tô: UnLuckY Studio (đổi màu bằng code); xe máy có người lái, xe khách,
  /// xe container: vẽ bằng code (tool/asset_pipeline/build_vehicles.py).
  static const String imgScooterPlayer = '$assetsImgPath/img_scooter_player.png';
  static const String imgScooterPolice = '$assetsImgPath/img_scooter_police.png';
  static final List<String> scootersAi = [for (var i = 1; i <= 10; i++) '$assetsImgPath/img_scooter_ai_$i.png'];

  /// Xe người chơi khi đi ô tô: sedan đỏ (xe AI không dùng màu đỏ).
  static const String imgCarPlayer = '$assetsImgPath/img_sedan_red.png';
  static const List<String> sedansAi = [
    '$assetsImgPath/img_sedan_white.png',
    '$assetsImgPath/img_sedan_silver.png',
    '$assetsImgPath/img_sedan_black.png',
    '$assetsImgPath/img_sedan_blue.png',
    '$assetsImgPath/img_sedan_gray.png',
    '$assetsImgPath/img_sedan_brown.png',
    '$assetsImgPath/img_sedan_green.png',
    '$assetsImgPath/img_mini_van.png',
  ];
  static const List<String> pickups = [
    '$assetsImgPath/img_pickup_blue.png',
    '$assetsImgPath/img_pickup_white.png',
    '$assetsImgPath/img_pickup_gray.png',
  ];
  static const List<String> buses = [
    '$assetsImgPath/img_bus_1.png',
    '$assetsImgPath/img_bus_2.png',
    '$assetsImgPath/img_bus_3.png',
  ];
  static const List<String> trucks = [
    '$assetsImgPath/img_container_1.png',
    '$assetsImgPath/img_container_2.png',
    '$assetsImgPath/img_truck.png',
  ];

  /// Người đứng chờ xe ở điểm đón (vẽ bằng code).
  static final List<String> people = [for (var i = 1; i <= 8; i++) '$assetsImgPath/img_person_$i.png'];

  /// Hàng Tết chở theo (cành đào, cây quất, thùng quà).
  static const List<String> cargo = [
    '$assetsImgPath/img_cargo_peach.png',
    '$assetsImgPath/img_cargo_kumquat.png',
    '$assetsImgPath/img_cargo_box.png',
  ];

  /// Xe của người chơi theo loại xe.
  static String player(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => imgScooterPlayer,
        VehicleKind.car => imgCarPlayer,
        VehicleKind.bus => imgBusPlayer,
      };

  static const String imgBusPlayer = '$assetsImgPath/img_bus_player.png';

  static List<String> get vehicles => [
        imgBusPlayer,
        imgScooterPlayer,
        imgScooterPolice,
        ...scootersAi,
        imgCarPlayer,
        ...sedansAi,
        ...pickups,
        ...buses,
        ...trucks,
        ...cargo,
        ...people,
      ];

  /// images — các ô ảnh nền bản đồ (dựng bằng tool/route_data/build_map_tiles.py)
  static String mapTile(int level, int i, int j) => '$assetsImgPath/map/l${level}_${i}_$j.jpg';

  /// images — vật liệu mặt đất, mái nhà (Poly Haven, CC0) và vạch sơn mòn;
  /// dựng bằng tool/asset_pipeline/build_world_art.py
  static const String texAsphalt = '$assetsImgPath/tex_asphalt.jpg';
  static const String texPaving = '$assetsImgPath/tex_paving.jpg';
  static const String texPavingRed = '$assetsImgPath/tex_paving_red.jpg';
  static const String texGrass = '$assetsImgPath/tex_grass.jpg';
  static const String texGrassRough = '$assetsImgPath/tex_grass_rough.jpg';
  static const String texLaterite = '$assetsImgPath/tex_laterite.jpg';
  static const String texVerge = '$assetsImgPath/tex_verge.jpg';
  static const String texGravel = '$assetsImgPath/tex_gravel.jpg';
  static const String texConcrete = '$assetsImgPath/tex_concrete.jpg';
  static const String texPaddy = '$assetsImgPath/tex_paddy.jpg';
  static const String texRoofClay = '$assetsImgPath/tex_roof_clay.jpg';
  static const String texRoofIron = '$assetsImgPath/tex_roof_iron.jpg';
  static const String texPaint = '$assetsImgPath/tex_paint.png';

  /// images — cây nhìn từ trên cao (Prime_8, CC0) và cảnh vật vẽ bằng code
  static final List<String> trees = [
    for (var i = 1; i <= 13; i++) '$assetsImgPath/img_tree_${i.toString().padLeft(2, '0')}.png',
  ];
  static const List<String> bananas = ['$assetsImgPath/img_banana_1.png', '$assetsImgPath/img_banana_2.png'];
  static const List<String> potholes = [
    '$assetsImgPath/img_pothole_1.png',
    '$assetsImgPath/img_pothole_2.png',
    '$assetsImgPath/img_pothole_3.png',
  ];
  static const List<String> roadPatches = [
    '$assetsImgPath/img_road_patch_1.png',
    '$assetsImgPath/img_road_patch_2.png',
    '$assetsImgPath/img_road_patch_3.png',
  ];
  static const List<String> oilStains = ['$assetsImgPath/img_oil_1.png', '$assetsImgPath/img_oil_2.png'];
  static const String imgLixi = '$assetsImgPath/img_lixi.png';
  static const String imgManhole = '$assetsImgPath/img_manhole.png';
  static const String imgDrain = '$assetsImgPath/img_drain.png';
  static const String imgShadow = '$assetsImgPath/img_shadow.png';
  static const String imgShadowBox = '$assetsImgPath/img_shadow_box.png';
  static const String imgWaterTank = '$assetsImgPath/img_water_tank.png';
  static const String imgWaterTankRound = '$assetsImgPath/img_water_tank_round.png';

  static List<String> get worldArt => [
        texAsphalt,
        texPaving,
        texPavingRed,
        texGrass,
        texGrassRough,
        texLaterite,
        texVerge,
        texGravel,
        texConcrete,
        texPaddy,
        texRoofClay,
        texRoofIron,
        texPaint,
        ...trees,
        ...bananas,
        ...potholes,
        ...roadPatches,
        ...oilStains,
        imgLixi,
        imgManhole,
        imgDrain,
        imgShadow,
        imgShadowBox,
        imgWaterTank,
        imgWaterTankRound,
      ];

}

/// Tên file âm thanh, tính từ thư mục assets/audio (tiền tố mặc định của
/// flame_audio). Nguồn và giấy phép: document/asset_credits.md; cách dựng:
/// tool/asset_pipeline/build_audio.py.
abstract class AppAudio {
  static const String sfxEngineMoto = 'sfx_engine_moto.wav';
  static const String sfxEngineCar = 'sfx_engine_car.wav';
  static const String sfxSkid = 'sfx_skid.wav';
  static const String sfxHornMoto = 'sfx_horn_moto.wav';
  static const String sfxHornCar = 'sfx_horn_car.wav';
  static const String sfxCrashLight = 'sfx_crash_light.wav';
  static const String sfxCrashHeavy = 'sfx_crash_heavy.wav';
  static const String sfxPothole = 'sfx_pothole.wav';
  static const String sfxLixi = 'sfx_lixi.wav';
  static const String sfxClick = 'sfx_click.wav';
  static const String sfxConfirm = 'sfx_confirm.wav';
  static const String sfxSiren = 'sfx_siren.wav';
  static const String sfxFirecrackers = 'sfx_firecrackers.wav';

  static const String musicMain = 'music_main.m4a';
  static const String musicChase = 'music_chase.m4a';
  static const String jingleWin = 'jingle_win.m4a';
  static const String jingleLose = 'jingle_lose.m4a';

  /// Nạp sẵn để lần phát đầu không bị trễ.
  static const List<String> preload = [
    sfxEngineMoto,
    sfxEngineCar,
    sfxSkid,
    sfxHornMoto,
    sfxHornCar,
    sfxCrashLight,
    sfxCrashHeavy,
    sfxPothole,
    sfxLixi,
    sfxClick,
    sfxConfirm,
    sfxSiren,
    sfxFirecrackers,
    jingleWin,
    jingleLose,
  ];
}
