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

  /// images — xe nhìn từ trên xuống, mũi xe hướng lên trên. Mọi xe là mô
  /// hình 3D render sẵn: xe của mình ở tool/asset_pipeline/build_vehicles_3d.py,
  /// dòng xe AI ở tool/asset_pipeline/build_traffic_3d.py.
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

  // Bóng đổ theo dáng từng xe của mình (ảnh 3D render sẵn), khung vừa đúng
  // chỗ VehicleSprite vẽ bóng.
  static const String imgShadowScooterPlayer = '$assetsImgPath/img_shadow_scooter_player.png';
  static const String imgShadowScooterRaincoat = '$assetsImgPath/img_shadow_scooter_player_raincoat.png';
  static const String imgShadowScooterParked = '$assetsImgPath/img_shadow_scooter_parked.png';
  static const String imgShadowCarPlayer = '$assetsImgPath/img_shadow_car_player.png';
  static const String imgShadowBusPlayer = '$assetsImgPath/img_shadow_bus_player.png';

  /// Thợ vá lưu động / người mang xăng chạy xe máy tới chỗ mình.
  static const String imgScooterMechanic = '$assetsImgPath/img_scooter_mechanic.png';
  static const String imgScooterFuel = '$assetsImgPath/img_scooter_fuel.png';

  /// Bóng đổ theo dáng một xe AI: `img_shadow_` + tên ảnh xe.
  static String shadowOf(String path) => path.replaceFirst('/img_', '/img_shadow_');

  /// Ảnh xe AI (mỗi ảnh có bóng đổ riêng [shadowOf]).
  static List<String> get traffic => [
        ...scootersAi,
        ...scootersRaincoat,
        imgScooterPolice,
        ...sedansAi,
        ...pickups,
        ...buses,
        ...trucks,
      ];

  static String playerShadow(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => imgShadowScooterPlayer,
        VehicleKind.car => imgShadowCarPlayer,
        VehicleKind.bus => imgShadowBusPlayer,
      };

  static List<String> get vehicles => [
        imgShadowScooterPlayer,
        imgShadowScooterRaincoat,
        imgShadowScooterParked,
        imgShadowCarPlayer,
        imgShadowBusPlayer,
        for (final path in traffic) shadowOf(path),
        imgScooterMechanic,
        imgScooterFuel,
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

  /// images — cảnh của các bản đồ ven biển, đèo núi, sông nước (vân mặt đất,
  /// cây và thuyền nhìn từ trên; dựng bằng tool/asset_pipeline/build_theme_art.py)
  static const String texSand = '$assetsImgPath/tex_sand.jpg';
  static const String texSandWet = '$assetsImgPath/tex_sand_wet.jpg';
  static const String texSea = '$assetsImgPath/tex_sea.jpg';
  static const String texCanal = '$assetsImgPath/tex_canal.jpg';
  static const String texRock = '$assetsImgPath/tex_rock.jpg';
  static const String texForest = '$assetsImgPath/tex_forest.jpg';
  static const String texScrub = '$assetsImgPath/tex_scrub.jpg';
  static final List<String> palmsCoconut = [for (var i = 1; i <= 3; i++) '$assetsImgPath/img_palm_coconut_$i.png'];
  static final List<String> palmsNipa = [for (var i = 1; i <= 2; i++) '$assetsImgPath/img_palm_nipa_$i.png'];
  static final List<String> casuarinas = [for (var i = 1; i <= 3; i++) '$assetsImgPath/img_tree_casuarina_$i.png'];
  static final List<String> pines = [for (var i = 1; i <= 3; i++) '$assetsImgPath/img_tree_pine_$i.png'];
  static final List<String> mangoes = [for (var i = 1; i <= 2; i++) '$assetsImgPath/img_tree_mango_$i.png'];
  static final List<String> bambooTops = [for (var i = 1; i <= 2; i++) '$assetsImgPath/img_bamboo_top_$i.png'];
  static final List<String> basketBoats = [for (var i = 1; i <= 2; i++) '$assetsImgPath/img_boat_basket_$i.png'];
  static final List<String> sampans = [for (var i = 1; i <= 2; i++) '$assetsImgPath/img_boat_sampan_$i.png'];
  static final List<String> rocks = [for (var i = 1; i <= 3; i++) '$assetsImgPath/img_rock_$i.png'];

  /// Ảnh xem trước của một bản đồ trong hộp chọn bản đồ.
  static String mapPreview(String theme) => '$assetsImgPath/img_map_$theme.jpg';

  static List<String> get themeArt => [
        texSand,
        texSandWet,
        texSea,
        texCanal,
        texRock,
        texForest,
        texScrub,
        ...palmsCoconut,
        ...palmsNipa,
        ...casuarinas,
        ...pines,
        ...mangoes,
        ...bambooTops,
        ...basketBoats,
        ...sampans,
        ...rocks,
      ];

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

  /// images — quán ven đường, xe dựng, người lái đi bộ (vẽ bằng code:
  /// tool/asset_pipeline/build_roadside.py)
  static const String imgScooterParked = '$assetsImgPath/img_scooter_parked.png';
  static final List<String> scootersParked = [for (var i = 1; i <= 3; i++) '$assetsImgPath/img_scooter_parked_$i.png'];
  static const String imgDriverMoto = '$assetsImgPath/img_driver_moto.png';
  static const String imgDriverCar = '$assetsImgPath/img_driver_car.png';
  static const List<String> stools = ['$assetsImgPath/img_stool_red.png', '$assetsImgPath/img_stool_blue.png'];
  static const List<String> tables = ['$assetsImgPath/img_table_1.png', '$assetsImgPath/img_table_2.png'];
  static const List<String> umbrellas = [
    '$assetsImgPath/img_umbrella_red.png',
    '$assetsImgPath/img_umbrella_blue.png',
    '$assetsImgPath/img_umbrella_green.png',
  ];
  static const List<String> hammocks = [
    '$assetsImgPath/img_hammock_1.png',
    '$assetsImgPath/img_hammock_2.png',
    '$assetsImgPath/img_hammock_3.png',
  ];
  static const String imgTeaJug = '$assetsImgPath/img_tea_jug.png';
  static const String imgCooler = '$assetsImgPath/img_cooler.png';
  static const String imgCanePress = '$assetsImgPath/img_cane_press.png';
  static const String imgCaneBundle = '$assetsImgPath/img_cane_bundle.png';
  static const String imgBreadCart = '$assetsImgPath/img_bread_cart.png';
  static const String imgFoodTray = '$assetsImgPath/img_food_tray.png';
  static const String imgTireStack = '$assetsImgPath/img_tire_stack.png';
  static const String imgGasPump = '$assetsImgPath/img_gas_pump.png';

  static List<String> get roadside => [
        imgScooterParked,
        ...scootersParked,
        imgDriverMoto,
        imgDriverCar,
        ...stools,
        ...tables,
        ...umbrellas,
        ...hammocks,
        imgTeaJug,
        imgCooler,
        imgCanePress,
        imgCaneBundle,
        imgBreadCart,
        imgFoodTray,
        imgTireStack,
        imgGasPump,
      ];

  /// images — tình huống dọc đường: áo mưa, chốt CSGT, xăng lẻ, sửa xe (vẽ
  /// bằng code: tool/asset_pipeline/build_trip_events.py)
  static const String imgScooterPlayerRaincoat = '$assetsImgPath/img_scooter_player_raincoat.png';
  static final List<String> scootersRaincoat = [for (var i = 1; i <= 4; i++) '$assetsImgPath/img_scooter_ai_raincoat_$i.png'];
  static const String imgPoliceOfficer = '$assetsImgPath/img_police_officer.png';
  static const String imgPoliceOfficerWave = '$assetsImgPath/img_police_officer_wave.png';
  static const String imgPoliceOfficerRadar = '$assetsImgPath/img_police_officer_radar.png';
  static const String imgRadarTripod = '$assetsImgPath/img_radar_tripod.png';
  static const String imgTrafficCone = '$assetsImgPath/img_traffic_cone.png';
  static const String imgPoliceTable = '$assetsImgPath/img_police_table.png';
  static const String imgScooterPoliceParked = '$assetsImgPath/img_scooter_police_parked.png';
  static const String imgBottleShelf = '$assetsImgPath/img_bottle_shelf.png';
  static const String imgFunnel = '$assetsImgPath/img_funnel.png';
  static const String imgJerrycan = '$assetsImgPath/img_jerrycan.png';
  static const String imgCompressor = '$assetsImgPath/img_compressor.png';
  static const String imgWaterBasin = '$assetsImgPath/img_water_basin.png';
  static const String imgWarningTriangle = '$assetsImgPath/img_warning_triangle.png';
  static const String imgSpareTire = '$assetsImgPath/img_spare_tire.png';
  static const String imgCarJack = '$assetsImgPath/img_car_jack.png';
  static const String imgAttendant = '$assetsImgPath/img_attendant.png';
  static const String imgMechanic = '$assetsImgPath/img_mechanic.png';
  static const String imgSeller = '$assetsImgPath/img_seller.png';
  static const String imgDriverMotoCrouch = '$assetsImgPath/img_driver_moto_crouch.png';
  static const String imgDriverCarCrouch = '$assetsImgPath/img_driver_car_crouch.png';

  /// images — minh hoạ món trong quán, cây xăng, tiệm vá xe (vẽ bằng code:
  /// tool/asset_pipeline/build_menu_items.py)
  static String item(String art) => '$assetsImgPath/img_item_$art.png';
  static final String imgItemRaincoat = item('ao_mua');
  static final String imgItemNozzle = item('voi_xang');
  static final String imgItemBottle = item('chai_xang');
  static List<String> get items => [
        for (final art in const [
          'tra_da', 'nuoc_mia', 'nuoc_mia_tac', 'ca_phe', 'bac_xiu', 'huong_duong', 'ghe_nhua', 'vong', 'banh_mi', //
          'xoi', 'com', 'ao_mua', 'voi_xang', 'chai_xang', 'va_sam', 'thay_sam', 'va_lop', 'thay_lop',
        ])
          item(art),
      ];

  static List<String> get tripEvents => [
        imgScooterPlayerRaincoat,
        ...scootersRaincoat,
        imgPoliceOfficer,
        imgPoliceOfficerWave,
        imgPoliceOfficerRadar,
        imgRadarTripod,
        imgTrafficCone,
        imgPoliceTable,
        imgScooterPoliceParked,
        imgBottleShelf,
        imgFunnel,
        imgJerrycan,
        imgCompressor,
        imgWaterBasin,
        imgWarningTriangle,
        imgSpareTire,
        imgCarJack,
        imgAttendant,
        imgMechanic,
        imgSeller,
        imgDriverMotoCrouch,
        imgDriverCarCrouch,
      ];

  // Gà vịt chó qua đường (đầu hướng lên trên; khung _flap/_run khi chạy).
  static const String imgAnimalDuck = '$assetsImgPath/img_animal_duck.png';
  static const String imgAnimalDuckFlap = '$assetsImgPath/img_animal_duck_flap.png';
  static const String imgAnimalDuckWhite = '$assetsImgPath/img_animal_duck_white.png';
  static const String imgAnimalDuckWhiteFlap = '$assetsImgPath/img_animal_duck_white_flap.png';
  static const String imgAnimalRooster = '$assetsImgPath/img_animal_rooster.png';
  static const String imgAnimalRoosterFlap = '$assetsImgPath/img_animal_rooster_flap.png';
  static const String imgAnimalHen = '$assetsImgPath/img_animal_hen.png';
  static const String imgAnimalHenFlap = '$assetsImgPath/img_animal_hen_flap.png';
  static const String imgAnimalDog1 = '$assetsImgPath/img_animal_dog_1.png';
  static const String imgAnimalDog2 = '$assetsImgPath/img_animal_dog_2.png';
  static const String imgAnimalDogRun = '$assetsImgPath/img_animal_dog_run.png';

  static const List<String> animals = [
    imgAnimalDuck,
    imgAnimalDuckFlap,
    imgAnimalDuckWhite,
    imgAnimalDuckWhiteFlap,
    imgAnimalRooster,
    imgAnimalRoosterFlap,
    imgAnimalHen,
    imgAnimalHenFlap,
    imgAnimalDog1,
    imgAnimalDog2,
    imgAnimalDogRun,
  ];

  static List<String> get worldArt => [
        ...animals,
        // Săm, lốp thợ vá lưu động bày ra đất.
        item('va_sam'),
        item('va_lop'),
        ...roadside,
        ...tripEvents,
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
        ...themeArt,
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
  static const String sfxTireHiss = 'sfx_tire_hiss.wav';
  static const String sfxWhistle = 'sfx_whistle.wav';
  static const String sfxSputter = 'sfx_sputter.wav';
  static const String sfxFuelPump = 'sfx_fuel_pump.wav';
  static const String sfxRain = 'sfx_rain.wav';

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
    sfxTireHiss,
    sfxWhistle,
    sfxSputter,
    sfxFuelPump,
    sfxRain,
    jingleWin,
    jingleLose,
  ];
}
