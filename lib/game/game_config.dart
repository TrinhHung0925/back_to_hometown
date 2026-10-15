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

  /// Lực văng xe tự ôm được (lốp còn bám, người lái nghiêng theo cua): vào
  /// cua không quá tốc độ khuyên dùng thì không phải bẻ lái giữ làn.
  static const double curveHoldDrift = curveAdviseDrift;

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

  /// Quy đổi quãng đường: 100 km chạy ở [normalSpeed] mất 2,5 phút chơi
  /// (chạy nhanh như người chơi thật thì chừng 2 phút).
  static const double unitsPerKm = normalSpeed * 150 / 100;

  // --------------------------------------------------------- Đồng hồ Tết
  /// Một giây chơi bằng bao nhiêu giây trong game. Chạy thường 100 km mất
  /// 2,5 phút chơi ↔ 2 giờ trong game (50 km/h).
  static const double gameSecondsPerPlaySecond = 2 * 3600 / 150;

  /// Giờ xuất phát tính sao cho chạy đều [guaranteedKmh] km/h (chậm hơn
  /// nhiều so với 50 km/h chạy thường) vẫn về kịp giao thừa, lại dư thêm
  /// [stopAllowanceMinutes] mỗi chặng cho ghé quán, đổ xăng, qua phà, bị
  /// phạt. Chỉ ai dừng quá nhiều, gặp nạn mấy lần mới bị lỡ giao thừa.
  static const double guaranteedKmh = 20;
  static const double stopAllowanceMinutes = 40;

  /// Đánh dấu chuyến đã tính giờ theo cách trên (chuyến lưu từ bản cũ dùng
  /// hệ số ×1,25 / ×1,6 thời gian chạy thường thì được lùi giờ cho đủ).
  static const double timeBudgetFactor = 100;

  // ------------------------------------------------------- Lộ trình
  /// Mỗi km quốc lộ mất bao nhiêu giây chơi (100 km ≈ 2,5 phút).
  static const double playSecondsPerKm = 1.5;

  /// Đường phố chậm hơn (đèn đỏ, xe đông), cao tốc nhanh hơn.
  static const double cityPaceFactor = 1.7;
  static const double expresswayPaceFactor = 0.65;

  /// Mỗi lần ra/vào thành phố đi bao nhiêu km đường phố.
  static const double cityKmPerSide = 6;

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
  /// (Các khoảng cách tính bằng km dưới đây đặt theo nhịp chơi: 1 km ≈ 1,5
  /// giây chạy thường.)
  static const double busStopEveryKm = 36;
  static const double firstBusStopAfterStart = 1500;

  /// Dừng cách tâm điểm đón tối đa bao xa, dừng bao lâu thì khách lên xong.
  static const double busStopWindow = 80;
  static const double busBoardSeconds = 1.2;

  /// Mỗi khách trả bao nhiêu lì xì tiền xe.
  static const int fareLixi = 2;

  // ------------------------------------------------- Quán ven đường
  /// Khoảng cách giữa hai quán (km) trên quốc lộ / trong phố; quán đầu tiên
  /// cách điểm xuất phát.
  static const double stallGapHighwayKmMin = 2.0;
  static const double stallGapHighwayKmMax = 5.2;
  static const double stallGapCityKmMin = 1.4;
  static const double stallGapCityKmMax = 3.0;
  static const double firstStallAfterStart = 1200;

  /// Lề đất trước quán để dựng xe; khu bàn ghế sâu vào trong bao nhiêu.
  static const double stallPadWidth = 56;
  static const double stallPlotDepth = 150;
  static const double stallPlotHalfLength = 85;

  /// Dừng hẳn sát lề phải trong khoảng ± này quanh quán thì ghé được.
  static const double stallStopWindow = 95;
  static const double stallStopSpeed = 25;

  /// Nút "Vào quán / Vào đổ xăng" hiện khi quán cùng phía còn cách chừng
  /// này (≈ 2,9 km) và vẫn đủ quãng phanh; bấm là xe tự tấp vào với tốc độ
  /// không quá [stallApproachSpeed], giảm dần để dừng đúng trước quán.
  static const double stallApproachReach = 1300;
  static const double stallApproachSpeed = 180;

  // ------------------------------------------------- Chuyện dọc đường
  /// Sương mù dày dần / tan dần trong quãng này.
  static const double fogFade = 900;

  /// Tắc đường cửa ngõ: dài chừng 2 km trước đầu phố; mỗi lối vào phố có
  /// [jamChance] bị tắc. Xe máy được đi lề rộng [shoulderWidth], chậm thôi.
  static const double jamLength = 950;
  static const double jamChance = 0.6;

  /// Quãng trước đuôi tắc giữ đường thẳng (thấy hàng xe từ xa), quãng bắt
  /// đầu báo tắc / hiện biển "Tắc …m", và khoảng hở tối đa giữa hai xe
  /// trong cùng một hàng tắc.
  static const double jamClearView = 1100;
  static const double jamWarnAhead = 2200;
  static const double jamChainGap = 150;
  static const double shoulderWidth = 30;
  static const double shoulderSpeed = 0.38 * normalSpeed;

  /// Gió biển giật kéo dài bao lâu.
  static const double gustSeconds = 1.6;

  /// Doi cát trên đường ven biển: đi nhanh hơn mức này thì trượt.
  static const double sandSlipSpeed = 0.62 * normalSpeed;
  static const double sandSlipSeconds = 0.5;
  static const double sandSlipDrift = 70;

  /// Xe tải mất phanh đổ dốc: tỉ lệ gặp ở mỗi đường cứu nạn, báo trước bao
  /// lâu, nhanh hơn mình bao nhiêu; dải sỏi đường cứu nạn dài, ghì xe mạnh.
  static const double runawayChance = 0.75;
  static const double runawayWarningSeconds = 3.2;
  static const double runawayExtraSpeed = 0.85;
  static const double rampLength = 480;
  static const double rampDecel = 520;

  /// Điện thoại: chuông reo bao lâu, mỗi câu nói bao lâu, tấp vào nghe mất
  /// mấy phút.
  static const double callRingSeconds = 11;
  static const double callLineSeconds = 2.7;
  static const double callStopMinutes = 3;

  /// Phà qua sông (bản đồ sông nước): sông rộng bao nhiêu, phà chạy nhanh
  /// cỡ nào, đỗ bến bao lâu; xe tự vào bến từ quãng [ferryApproach]; cả lượt
  /// chờ + qua sông tốn [ferryMinutes] phút trong game.
  static const double riverWidth = 1500;
  static const double ferrySpeed = 150;
  static const double ferryDockSeconds = 3;
  static const double ferryApproach = 700;
  static const double ferryBoardSeconds = 2.2;
  static const double ferryLandSeconds = 2.0;
  static const double ferryMinutes = 12;

  /// Dừng xe bao nhiêu phút trong game dù chưa gọi món (dựng xe, ngồi xuống).
  static const double stallBaseMinutes = 2;

  // ------------------------------------------------- Tỉnh táo, ngủ gật
  /// Mức tỉnh táo lúc vào chặng (0..100) và tụt mỗi giây chơi khi đang lái;
  /// ban đêm tụt nhanh hơn. Một chặng ~5 phút chơi ≈ 2 giờ lái liền.
  static const double alertStart = 82;
  static const double alertDecayPerSecond = 0.17;
  static const double alertNightFactor = 1.7;

  /// Dưới mức này: ngáp, mép màn hình tối dần.
  static const double alertDrowsy = 45;

  /// Nhân viên cây xăng tặng chai nước lúc tán gẫu: tỉnh táo thêm.
  static const double chatWaterAlert = 12;

  /// Dưới mức này: ngủ gật (mắt nhắm, xe tự dạt), càng thấp càng hay gật.
  static const double alertMicrosleep = 25;
  static const double alertSevere = 10;
  static const double microsleepGapMin = 5;
  static const double microsleepGapMax = 15;
  static const double microsleepSeconds = 0.9;

  /// Lúc ngủ gật xe dạt ngang (u/s) và tay lái không ăn.
  static const double microsleepDrift = 60;

  // ------------------------------------------------------- Quay đầu
  /// Chỉ quay đầu được khi chạy chậm dưới mức này (≈ 15 km/h).
  static const double uTurnMaxSpeed = 90;

  /// Bán kính quay đầu nhỏ nhất: xe máy quay gọn trong một làn, ô tô cần sát
  /// lề phải, xe khách chỉ quay được ở ngã tư (có thêm chỗ của đường ngang).
  static const double uTurnRadiusMotorbike = 32;
  static const double uTurnRadiusCar = 88;
  static const double uTurnRadiusBus = 120;

  /// Ở ngã tư, cung quay đầu được lấn thêm sang đường ngang bao nhiêu.
  static const double uTurnCrossRoom = 110;

  /// Đi ngược tối đa bao xa so với chỗ xa nhất đã tới (≈ 3 km).
  static const double maxBacktrack = 2700;

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

  /// Chênh lệch tốc độ lúc đâm từ mức này trở lên là tai nạn: xe hỏng, lập
  /// biên bản, chờ sửa xe (mất nhiều lì xì, nhiều phút) rồi mới đi tiếp.
  static const double accidentRelativeSpeed = 1.0 * normalSpeed;

  /// Đâm cực mạnh: thua chặng ngay. Đối đầu xe ngược chiều thì ngưỡng thấp
  /// hơn; tông đuôi / đâm ngang / đâm barrier thì phải rất nhanh mới tới mức này.
  static const double fatalRelativeSpeed = 1.5 * normalSpeed;
  static const double fatalRearRelativeSpeed = 1.9 * normalSpeed;

  /// Tai nạn (chưa tới mức thua): phạt lì xì, phút chờ lập biên bản + sửa xe.
  static const int crashFineLixi = 6;
  static const double crashFineMinutes = 35;

  // ------------------------------------------------------------ Công an
  /// Phạt: số lì xì và số phút trong game bị giữ lại.
  static const int fineLixi = 5;
  static const double fineMinutes = 10;

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

  // ------------------------------------------------------------ Xăng
  /// Đầy bình chạy được bao nhiêu km (ở tốc độ thường, không chở gì).
  static const double fuelRangeKmMotorbike = 280;
  static const double fuelRangeKmCar = 840;
  static const double fuelRangeKmBus = 1120;

  /// Chuyến mới: bình còn khoảng này (đi vội chưa kịp đổ đầy).
  static const double fuelTripStartMin = 0.42;
  static const double fuelTripStartMax = 0.7;

  /// Đèn báo xăng sáng; xe bắt đầu khục khặc (lâu lâu mất ga).
  static const double fuelLow = 0.12;
  static const double fuelSputter = 0.035;

  /// Một lì xì đổ được bao nhiêu phần bình ở cây xăng.
  static const double fuelPerLixiMotorbike = 0.5;
  static const double fuelPerLixiCar = 0.2;
  static const double fuelPerLixiBus = 0.14;

  /// Xăng lẻ đóng chai (chỉ xe máy): một chai một lì xì.
  static const double fuelBottle = 0.25;

  /// Nghiêng xe dồn xăng (xe máy, mỗi lần cạn được một lần).
  static const double fuelTilt = 0.025;

  /// Gọi người mang xăng tới / gọi cứu hộ: đổ thêm, mất lì xì và phút chờ.
  static const double fuelRescue = 0.2;
  static const int fuelRescueLixiMotorbike = 2;
  static const int fuelRescueLixiCar = 4;
  static const int fuelRescueLixiBus = 6;
  static const double fuelRescueMinutesMotorbike = 15;
  static const double fuelRescueMinutesCar = 25;

  /// Dắt bộ xe máy hết xăng: tốc độ tối đa (≈ 12 km/h).
  static const double pushSpeed = 72;

  /// Khoảng cách giữa hai cây xăng (km): quốc lộ, phố, cao tốc (trạm dừng
  /// nghỉ); xăng lẻ ven quốc lộ.
  static const double gasGapHighwayKmMin = 16;
  static const double gasGapHighwayKmMax = 28;
  static const double gasGapCityKmMin = 10;
  static const double gasGapCityKmMax = 16;
  static const double gasGapExpresswayKmMin = 44;
  static const double gasGapExpresswayKmMax = 64;
  static const double bottleGapKmMin = 5;
  static const double bottleGapKmMax = 10;

  /// Cây xăng rộng hơn quán nước (mái che, chòi bán hàng).
  static const double gasPlotHalfLength = 125;

  // ------------------------------------------------------------- Lốp
  /// Tiệm vá xe: khoảng cách giữa hai tiệm (km).
  static const double tireShopGapHighwayKmMin = 8;
  static const double tireShopGapHighwayKmMax = 14;
  static const double tireShopGapCityKmMin = 6;
  static const double tireShopGapCityKmMax = 10;

  /// Đinh tặc: bao nhiêu km quốc lộ có một bãi đinh, xác suất xì lốp khi cán
  /// qua theo loại xe.
  static const double nailGapKmMin = 36;
  static const double nailGapKmMax = 68;
  static const double nailPatchLength = 70;
  static const double nailFlatChanceMotorbike = 0.65;
  static const double nailFlatChanceCar = 0.5;
  static const double nailFlatChanceBus = 0.4;

  /// Sập ổ gà lúc chạy nhanh hơn mức này thì có thể xì lốp.
  static const double potholeFlatSpeed = 1.25 * normalSpeed;
  static const double potholeFlatChance = 0.15;

  /// Lốp xẹp: tốc độ tối đa còn bao nhiêu phần tốc độ thường, xe bị kéo lệch
  /// ngang (u/s). Chạy lốp xẹp quá xa thì nát săm (chỉ còn cách thay).
  static const double flatSpeedFactor = 0.45;
  static const double ruinedSpeedFactor = 0.32;
  static const double flatPull = 20;
  static const double flatRuinKm = 3;

  /// Thay lốp dự phòng bên lề (ô tô, xe khách): phút trong game.
  static const double spareMinutesCar = 15;
  static const double spareMinutesBus = 25;

  /// Gọi thợ vá xe lưu động tới tận nơi.
  static const int mobileRepairLixi = 3;
  static const double mobileRepairMinutes = 15;

  // ------------------------------------------------------------- Mưa
  /// Miền Bắc dịp Tết hay mưa phùn, thỉnh thoảng mưa rào; miền Nam ít mưa.
  static const double rainChanceNorth = 0.55;
  static const double rainChanceSouth = 0.15;

  /// Độ bám đường lúc đường ướt hẳn: phanh ăn còn bấy nhiêu phần, lực văng
  /// khi vào cua mạnh lên tương ứng (1 / độ bám).
  static const double wetGrip = 0.74;

  /// Đường còn ướt bao nhiêu phút trong game sau khi tạnh.
  static const double wetLingerMinutes = 20;

  /// Vũng nước: bao lâu xuất hiện một vũng (lúc mưa to), lao qua nhanh hơn
  /// mức này thì trượt nước, tay lái không ăn một lúc.
  static const double puddleIntervalMin = 4;
  static const double puddleIntervalMax = 8;
  static const double aquaplaneSpeed = 0.8 * normalSpeed;
  static const double aquaplaneSeconds = 0.55;
  static const double aquaplaneDrift = 70;

  /// Xe máy không mặc áo mưa: ướt dần, lạnh run, tỉnh táo tụt nhanh hơn.
  static const double soakPerSecond = 0.05;
  static const double soakAlertFactor = 1.8;
  static const int raincoatLixi = 1;

  /// Trời mưa tối thêm bao nhiêu (cộng vào mức tối ban đêm).
  static const double rainDarkness = 0.32;

  // ------------------------------------------------------------- CSGT
  /// Chốt CSGT trên quốc lộ: bao nhiêu km quốc lộ có một chốt.
  static const double checkpointEveryKm = 90;

  /// Biển hạn chế tốc độ đặt trước chốt; súng bắn tốc độ đứng trước lều.
  static const double speedSignAhead = 750;
  static const double radarAhead = 200;

  /// Vượt quá biển bao nhiêu km/h mới bị thổi.
  static const double speedTolerance = 3;

  /// Vùng cấm quay đầu quanh chốt (± quanh lều).
  static const double noUTurnReach = 950;

  /// Bị vẫy vào: phải dừng trong quãng này sau súng bắn tốc độ, không thì
  /// CSGT đuổi theo.
  static const double pullOverReach = 650;

  /// Ngã tư trong phố có biển cấm quay đầu (camera phạt nguội).
  static const double noUTurnJunctionChance = 0.4;
  static const int coldFineLixi = 3;

  /// Mức phạt theo lỗi (lì xì, phút bị giữ).
  static const int speedingFineLixi = 4;
  static const double speedingFineMinutes = 12;
  static const int uTurnFineLixi = 3;
  static const double uTurnFineMinutes = 10;
}
