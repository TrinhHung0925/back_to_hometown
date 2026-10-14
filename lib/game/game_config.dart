/// Mọi con số cân bằng game, gom một chỗ để chỉnh khi chơi thử.
///
/// Đơn vị: "u" là đơn vị thế giới game (≈ 1 điểm ảnh khi camera zoom = 1),
/// thời gian tính bằng giây chơi thật.
abstract class GameConfig {
  // ---------------------------------------------------------------- Đường
  /// Bề rộng một làn.
  static const double laneWidth = 60;

  /// Khoảng giữa hai vạch vàng đôi phân cách hai chiều.
  static const double centerGap = 6;

  /// Số làn mỗi chiều.
  static const int lanesPerDirection = 2;

  /// Nửa bề rộng mặt đường (tim đường → mép đường).
  static const double roadHalfWidth = centerGap / 2 + laneWidth * lanesPerDirection;

  static const double sidewalkWidth = 34;

  /// Hướng đường lệch tối đa so với hướng chung của tuyến (≈ 75°). Camera
  /// xoay theo đường nên cua gắt mấy cũng thấy; chưa tới 90° nên đường không
  /// bao giờ quay ngược lại, không tự cắt nhau.
  static const double maxRoadHeading = 1.3;

  /// Khoảng cách giữa hai điểm lấy mẫu trên tim đường.
  static const double roadSampleStep = 8;

  /// Hình xe máy vẽ to hơn hộp va chạm một chút cho thấy rõ người lái.
  static const double motorbikeVisualScale = 1.25;

  /// Phố ít lệch hướng (ngã tư cần đường thẳng), cao tốc vừa phải.
  static const double maxHeadingCity = 0.55;
  static const double maxHeadingExpressway = 0.9;

  // ------------------------------------------------------------ Khúc cua
  /// Bán kính cong nhỏ nhất (ở giữa khúc cua) theo loại đường. Phải lớn hơn
  /// hẳn bề rộng đường + nhà ven đường để cảnh phía trong cua không đè lên nhau.
  static const double minCurveRadiusHighway = 430;
  static const double minCurveRadiusCity = 1000;
  static const double minCurveRadiusExpressway = 1400;

  /// Phía trong khúc cua gắt hơn mức này thì không đặt nhà (chỉ cây, chuối).
  static const double minHouseRadius = 650;

  /// Cua có bán kính nhỏ hơn mức này là cua gắt: có biển báo, biển hướng
  /// cua, cảnh báo trên HUD.
  static const double sharpCurveRadius = 760;

  /// Biển báo cua đặt trước khúc cua; HUD báo trước từ khoảng này.
  static const double curveSignAhead = 300;
  static const double curveWarnDistance = 900;

  /// Vào cua xe bị văng ra phía ngoài: tốc độ dạt = v² × độ cong × hệ số này
  /// (giây). Chạy nhanh vào cua gắt thì kéo hết cần lái cũng không giữ nổi.
  static const double curveDrift = 0.35;

  /// Tốc độ khuyên dùng khi vào cua: lực văng chỉ bằng chừng này (u/s) —
  /// khoảng nửa sức kéo cần lái của ô tô.
  static const double curveAdviseDrift = 60;

  /// Bị văng tì vào mép đường / dải phân cách (lực văng vượt mức này): quệt
  /// lề, mất tốc độ nhanh.
  static const double scrapeMinDrift = 30;
  static const double scrapeDecel = 280;

  // ------------------------------------------------- Ngã tư, đèn đỏ
  /// Chu kỳ đèn (giây chơi) cho chiều dọc đường; đường ngang xanh khi
  /// chiều dọc đỏ, trừ [lightAllRedSeconds] ở hai đầu.
  static const double lightGreenSeconds = 7;
  static const double lightYellowSeconds = 2.5;
  static const double lightRedSeconds = 6;
  static const double lightAllRedSeconds = 1;

  /// Bề rộng đường cắt ngang và khoảng từ mép đường ngang tới vạch dừng.
  static const double crossRoadWidth = 120;
  static const double stopLineGap = 26;

  /// Vạch dừng của đường ngang, tính từ mép đường chính.
  static const double crossStopGap = 30;

  /// Ngã tư đầu tiên cách điểm xuất phát; chừa đầu/cuối đoạn phố; khoảng
  /// cách giữa hai ngã tư.
  static const double firstLightAfterStart = 700;
  static const double lightZoneMargin = 300;
  static const double lightSpacingMin = 1000;
  static const double lightSpacingMax = 1500;

  /// Xe đường ngang: tối đa mỗi ngã tư, khoảng sinh, tốc độ.
  static const int crossVehiclesPerLight = 2;
  static const double crossSpawnIntervalMin = 1.2;
  static const double crossSpawnIntervalMax = 2.6;
  static const double crossSpeedMin = 0.45;
  static const double crossSpeedMax = 0.7;

  // ---------------------------------------------------- Trạm thu phí
  /// Đoạn mặt đường mở rộng trước/sau barrier, đoạn vát, mép làn xe máy.
  static const double tollPlazaBefore = 520;
  static const double tollPlazaAfter = 320;
  static const double tollTaper = 160;
  static const double tollMotoLaneOuter = 165;

  /// Đảo phân làn: từ mũi đảo tới barrier và sau barrier.
  static const double tollIslandBefore = 130;
  static const double tollIslandAfter = 50;

  /// Đảo giữa hai làn ô tô, đảo giữa làn ô tô và làn xe máy (lệch ngang).
  static const double tollIslandInnerFrom = 58;
  static const double tollIslandInnerTo = 68;
  static const double tollIslandEdgeFrom = 123;
  static const double tollIslandEdgeTo = 131;

  /// Không đặt trạm quá sát chỗ đổi loại đường.
  static const double tollZoneMargin = 1500;

  /// Làn không dừng (ô tô): chạy chậm dưới mức này thì barrier tự mở.
  static const double etcMaxSpeed = 0.6 * normalSpeed;

  /// Làn thu phí thường: dừng hẳn (dưới tốc độ này) trong bao lâu thì trả xong.
  static const double tollStopSpeed = 12;
  static const double tollStopSeconds = 0.8;

  /// Phí (lì xì) mỗi trạm; không đủ thì bị giữ thêm (phút trong game).
  static const int tollFeeCar = 2;
  static const int tollFeeMotorbike = 1;
  static const int tollFeeBus = 3;
  static const double tollBrokeMinutes = 10;

  /// Xe AI dừng ở barrier bao lâu thì barrier mở, mở trong bao lâu.
  static const double tollAiWait = 1.0;
  static const double tollOpenSeconds = 1.6;

  // ------------------------------------------------------- Cao tốc
  /// Dải phân cách cứng: lùi vào trong đoạn cao tốc, nửa bề rộng.
  static const double medianInset = 260;
  static const double medianHalfWidth = 5;

  // --------------------------------------------------------------- Camera
  /// Chiều cao thế giới luôn nhìn thấy: 4 làn + vỉa hè + một ít cảnh hai bên.
  static const double visibleWorldHeight = 470;

  /// Tầm nhìn phía trước tối thiểu (máy gần vuông như iPad thì thu nhỏ để đủ).
  static const double minVisibleWorldWidth = 820;

  /// Đường đặt lệch lên trên để chừa chỗ dưới cùng cho cần lái và cụm nút.
  static const double cameraRoadOffsetY = 48;

  /// Camera xoay theo hướng dây cung từ xe tới điểm cách giữa màn hình
  /// thêm chừng này phía trước, bám theo nhanh cỡ nào (1/giây).
  static const double cameraChordAhead = 280;
  static const double cameraTurnRate = 4;

  /// Vị trí xe theo chiều ngang màn hình (tỉ lệ từ mép trái) khi đứng yên
  /// và khi chạy hết tốc độ.
  static const double playerScreenXSlow = 0.15;
  static const double playerScreenXFast = 0.45;

  // ------------------------------------------------------------- Tốc độ
  /// Tốc độ "chạy thường" — mốc để quy đổi km, thời gian và tốc độ xe AI.
  static const double normalSpeed = 300;

  /// Nhả ga thì xe chậm dần đều với gia tốc này (u/s²): từ tốc độ thường
  /// về 0 mất khoảng 4 giây.
  static const double coastDecel = 75;

  /// Quy đổi tốc độ hiển thị: [normalSpeed] ↔ 50 km/h.
  static const double displayKmhPerUnitSpeed = 50 / normalSpeed;

  /// Quy đổi quãng đường: 100 km chạy ở [normalSpeed] mất 5 phút chơi.
  static const double unitsPerKm = normalSpeed * 300 / 100;

  // --------------------------------------------------------- Đồng hồ Tết
  /// Một giây chơi bằng bao nhiêu giây trong game. Chạy thường 100 km mất
  /// 5 phút chơi ↔ 2 giờ trong game (50 km/h).
  static const double gameSecondsPerPlaySecond = 2 * 3600 / 300;

  /// Thời gian cho phép = thời gian ước tính × hệ số này.
  static const double timeBudgetFactor = 1.25;

  // ------------------------------------------------------- Lộ trình
  /// Mỗi km quốc lộ mất bao nhiêu giây chơi (100 km ≈ 5 phút).
  static const double playSecondsPerKm = 3;

  /// Đường phố chậm hơn (đèn đỏ, xe đông), cao tốc nhanh hơn.
  static const double cityPaceFactor = 1.7;
  static const double expresswayPaceFactor = 0.65;

  /// Mỗi lần ra/vào thành phố đi bao nhiêu km đường phố.
  static const double cityKmPerSide = 3;

  /// Độ dài một chặng chơi.
  static const double stageMinKm = 60;
  static const double stageMaxKm = 110;

  /// Tốc độ trung bình thực tế của xe máy trên quốc lộ (km/h) để ước tính giờ.
  static const double motorbikeRealKmh = 40;

  /// Xe khách chạy chậm hơn ô tô con, còn dừng đón khách.
  static const double busHoursFactor = 1.2;

  /// Ước tính số trạm thu phí: mỗi bao nhiêu km cao tốc / quốc lộ có một trạm.
  static const double expresswayKmPerToll = 60;
  static const double highwayKmPerToll = 120;

  // ------------------------------------------------------------ Xe AI
  static const int maxTrafficVehicles = 3;
  static const double trafficSpawnIntervalMin = 1.6;
  static const double trafficSpawnIntervalMax = 3.4;

  /// Tỉ lệ xe sinh ra là xe ngược chiều.
  static const double oncomingChance = 0.4;

  /// Xe cùng chiều chạy chậm hơn mình (tỉ lệ so với [normalSpeed]).
  static const double sameDirSpeedMin = 0.5;
  static const double sameDirSpeedMax = 0.78;

  /// Xe ngược chiều (tỉ lệ so với [normalSpeed]).
  static const double oncomingSpeedMin = 0.6;
  static const double oncomingSpeedMax = 0.85;

  /// Khoảng hở tối thiểu giữa hai xe AI cùng làn.
  static const double trafficSafeGap = 40;

  /// Không cho 2 xe cùng chiều chắn cả 2 làn trong khoảng này.
  static const double sideBySideBlockGap = 260;

  /// Xe AI bật xi-nhan bao lâu trước khi đánh lái sang làn khác.
  static const double blinkerSeconds = 0.9;

  /// Xe vượt từ phía sau: báo trước bao lâu, mỗi lần cách nhau bao lâu,
  /// nhanh hơn người chơi bao nhiêu (tỉ lệ [normalSpeed]).
  static const double overtakeWarningSeconds = 1.6;
  static const double overtakeIntervalMin = 14;
  static const double overtakeIntervalMax = 26;
  static const double overtakeExtraSpeed = 0.4;

  // ------------------------------------------------------- Trời tối, đèn
  /// Giờ trời bắt đầu tối / tối hẳn / bắt đầu sáng / sáng hẳn (phút trong ngày).
  static const double duskStart = 17 * 60 + 20;
  static const double duskEnd = 18 * 60 + 40;
  static const double dawnStart = 5 * 60 + 10;
  static const double dawnEnd = 6 * 60 + 30;

  /// Độ tối lúc tối hẳn (0..1).
  static const double nightDarkness = 0.86;

  /// Tầm chiếu đèn pha của mình; không bật đèn thì chỉ thấy quầng nhỏ quanh xe.
  static const double headlightReach = 620;
  static const double noHeadlightRadius = 150;

  // ------------------------------------------------- Xe khách đón khách
  /// Bao nhiêu km phố/quốc lộ có một điểm đón; điểm đầu tiên cách xuất phát.
  static const double busStopEveryKm = 18;
  static const double firstBusStopAfterStart = 1500;

  /// Dừng cách tâm điểm đón tối đa bao xa, dừng bao lâu thì khách lên xong.
  static const double busStopWindow = 80;
  static const double busBoardSeconds = 1.2;

  /// Mỗi khách trả bao nhiêu lì xì tiền xe.
  static const int fareLixi = 2;

  // ------------------------------------------------------- Quà Tết
  /// Quà Tết nằm trên đường: bao lâu xuất hiện một món.
  static const double giftIntervalMin = 9;
  static const double giftIntervalMax = 16;

  // ------------------------------------------------------------- Còi
  /// Còi xin đường: tầm với phía trước, thời gian hồi, tỉ lệ xe nặng không nhường.
  static const double hornReach = 420;
  static const double hornCooldown = 2;
  static const double heavyIgnoreHornChance = 0.35;

  // ------------------------------------------------------ Ổ gà, lì xì
  static const double potholeIntervalMin = 7;
  static const double potholeIntervalMax = 14;

  /// Ổ gà giảm tốc còn bao nhiêu phần.
  static const double potholeSpeedFactor = 0.7;

  static const double lixiIntervalMin = 3;
  static const double lixiIntervalMax = 6;

  // ----------------------------------------------- Va chạm, tai nạn
  /// Hộp va chạm nhỏ hơn hình vẽ cho cảm giác công bằng.
  static const double hitboxShrink = 0.82;

  /// Chênh lệch tốc độ lúc đâm từ mức này trở lên là tai nạn (thua ngay).
  static const double accidentRelativeSpeed = 0.75 * normalSpeed;

  // ------------------------------------------------------------ Công an
  /// Phạt: số lì xì và số phút trong game bị giữ lại.
  static const int fineLixi = 5;
  static const double fineMinutes = 15;

  /// Không đủ lì xì thì bị giữ thêm.
  static const double fineExtraMinutesIfBroke = 20;

  /// Rượt đuổi: công an xuất phát cách bao xa, kéo giãn tới bao xa là thoát,
  /// cầm cự bao lâu là thoát.
  static const double chaseStartGap = 160;
  static const double chaseEscapeGap = 900;
  static const double chaseDuration = 12;

  /// Công an chạy tối đa bằng bao nhiêu phần tốc độ tối đa của xe mình,
  /// và tăng tốc bằng bao nhiêu phần gia tốc gốc của xe mình.
  static const double policeMaxSpeedFactor = 0.92;
  static const double policeAccelFactor = 0.75;
}
