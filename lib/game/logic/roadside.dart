import 'dart:math';

import '../../model/trip.dart';
import '../game_config.dart';
import 'road_layout.dart';

/// Một món trong quán: giá (lì xì), tỉnh táo hồi lại, phút trong game ngồi.
class StallItem {
  const StallItem(this.name, {required this.price, required this.alert, required this.minutes, required this.art});

  final String name;
  final int price;
  final double alert;
  final double minutes;

  /// Tên hình minh hoạ món (assets/images/img_item_[art].png).
  final String art;
}

/// Các kiểu quán ven quốc lộ Việt Nam.
enum StallKind {
  traDa('TRÀ ĐÁ', 'Quán trà đá', [
    StallItem('Cốc trà đá', price: 1, alert: 18, minutes: 5, art: 'tra_da'),
    StallItem('Đĩa hướng dương', price: 1, alert: 8, minutes: 10, art: 'huong_duong'),
    StallItem('Ngồi nghỉ chân', price: 0, alert: 10, minutes: 12, art: 'ghe_nhua'),
  ]),
  nuocMia('NƯỚC MÍA', 'Quán nước mía', [
    StallItem('Cốc nước mía', price: 1, alert: 24, minutes: 6, art: 'nuoc_mia'),
    StallItem('Nước mía tắc', price: 2, alert: 32, minutes: 7, art: 'nuoc_mia_tac'),
    StallItem('Ngồi nghỉ chân', price: 0, alert: 10, minutes: 12, art: 'ghe_nhua'),
  ]),
  caPheVong('CÀ PHÊ VÕNG', 'Cà phê võng', [
    StallItem('Cà phê đen đá', price: 2, alert: 45, minutes: 10, art: 'ca_phe'),
    StallItem('Bạc xỉu', price: 2, alert: 38, minutes: 10, art: 'bac_xiu'),
    StallItem('Nằm võng chợp mắt', price: 1, alert: 75, minutes: 30, art: 'vong'),
  ]),
  banhMi('BÁNH MÌ', 'Xe bánh mì', [
    StallItem('Bánh mì pate', price: 2, alert: 20, minutes: 8, art: 'banh_mi'),
    StallItem('Xôi xéo', price: 2, alert: 22, minutes: 10, art: 'xoi'),
    StallItem('Ngồi nghỉ chân', price: 0, alert: 10, minutes: 12, art: 'ghe_nhua'),
  ]),
  com('CƠM BÌNH DÂN', 'Quán cơm bình dân', [
    StallItem('Suất cơm bình dân', price: 3, alert: 35, minutes: 20, art: 'com'),
    StallItem('Trà đá miễn phí', price: 0, alert: 10, minutes: 4, art: 'tra_da'),
  ]),

  /// Tiệm vá xe: vá săm, thay lốp; kê thêm ấm trà đá cho khách ngồi chờ.
  vaXe('VÁ XE', 'Tiệm vá xe', [
    StallItem('Cốc trà đá', price: 1, alert: 18, minutes: 5, art: 'tra_da'),
  ]),

  /// Cây xăng: mái che, cột bơm, chòi bán hàng.
  xang('XĂNG DẦU', 'Cây xăng', []),

  /// Xăng lẻ đóng chai bán ven đường (chỉ đổ được xe máy).
  xangLe('XĂNG', 'Xăng lẻ', []);

  const StallKind(this.sign, this.title, this.menu);

  final String sign;
  final String title;
  final List<StallItem> menu;

  /// Ghé vào ngồi được (có ghế, có đồ uống).
  bool get canSit => menu.isNotEmpty;

  /// Quán ăn uống (không phải tiệm dịch vụ).
  bool get food => canSit && this != vaXe;

  /// Bán xăng: cây xăng, xăng lẻ.
  bool get sellsFuel => this == xang || this == xangLe;

  bool get fixesTires => this == vaXe;
}

/// Một quán ven đường. [side] = 1: bên phải chiều về quê, -1: bên kia đường.
class Stall {
  Stall({
    required this.s,
    required this.side,
    required this.kind,
    required this.owner,
    required this.seed,
    this.gouging = false,
  });

  final double s;
  final int side;
  final StallKind kind;
  final String owner;
  final int seed;

  /// Tiệm vá xe "chặn đầu" ngay sau bãi đinh tặc: lấy giá cắt cổ.
  final bool gouging;

  String get name => '${kind.title} ${owner.isEmpty ? '' : owner}'.trim();

  /// Nửa chiều dài và chiều sâu khu quán (cây xăng rộng, xăng lẻ chỉ một kệ).
  double get halfLength => switch (kind) {
        StallKind.xang => GameConfig.gasPlotHalfLength,
        StallKind.xangLe => 46,
        _ => GameConfig.stallPlotHalfLength,
      };
  double get depth => switch (kind) {
        StallKind.xang => 190,
        StallKind.xangLe => 64,
        _ => GameConfig.stallPlotDepth,
      };

  /// Xe đỗ ở lề trước quán, tính từ tim đường theo phía quán.
  static const double padFrom = GameConfig.roadHalfWidth;

  /// Mép trong của khu quán (ghế, bàn, ô dù...) tính từ tim đường.
  static const double plotFrom = GameConfig.roadHalfWidth + GameConfig.stallPadWidth;
}

/// Bãi đinh tặc rải trên một làn quốc lộ. Có khi người dân dựng tấm biển
/// viết tay cảnh báo phía trước.
class NailPatch {
  NailPatch({required this.s, required this.lane, required this.warned, required this.seed});

  final double s;
  final int lane;
  final bool warned;
  final int seed;

  /// Đã cán qua (mỗi bãi chỉ xét một lần mỗi chiều).
  bool hit = false;

  static const double length = GameConfig.nailPatchLength;
  static const double width = GameConfig.laneWidth * 0.8;
}

const _mechanics = ['Chú Tư', 'Anh Hùng', 'Chú Bảy', 'Anh Tuấn', 'Chú Năm', 'Anh Dũng'];
const _bottleSellers = ['Bà Sáu', 'Cô Ba', 'Bà Năm', 'Cô Hạnh', 'Bà Tám'];
const _owners = ['Cô Ba', 'Chú Tư', 'Bà Sáu', 'Chị Hoa', 'Anh Hùng', 'Cô Lan', 'Út Hiền', 'Chú Bảy', 'Bà Năm', 'Chị Mai', 'Anh Tuấn', 'Cô Hạnh'];

typedef StallZone = ({RoadKind kind, double startS, double endS});

/// Rải cây xăng, xăng lẻ, tiệm vá xe, bãi đinh tặc và quán nước dọc chặng,
/// tránh ngã tư, trạm thu phí, điểm đón khách, đầu và cuối chặng. Cao tốc chỉ
/// có trạm dừng nghỉ (cây xăng bên phải).
({List<Stall> stalls, List<NailPatch> nails}) placeRoadside({
  required List<StallZone> zones,
  required double startS,
  required double endS,
  required bool Function(double s) blocked,
  required Random random,
}) {
  final stalls = <Stall>[];
  final nails = <NailPatch>[];
  bool clear(double s, double room) => !blocked(s) && !stalls.any((t) => (t.s - s).abs() < t.halfLength + room);
  int roadSide() => random.nextDouble() < 0.62 ? 1 : -1;
  String owner() => _owners[random.nextInt(_owners.length)];
  // Thợ vá xe thường là đàn ông; bán xăng lẻ hay là các bà, các cô.
  String mechanic() => _mechanics[random.nextInt(_mechanics.length)];
  String bottleSeller() => _bottleSellers[random.nextInt(_bottleSellers.length)];

  /// Rải đều theo khoảng cách (km) trong các đoạn [kinds].
  void scatter(Set<RoadKind> kinds, (double, double) Function(RoadKind kind) gapKm, void Function(double s, RoadZone zone) put,
      {double firstAfter = GameConfig.firstStallAfterStart}) {
    for (final z in zones.where((z) => kinds.contains(z.kind))) {
      final zone = RoadZone(z.kind, z.startS, z.endS);
      final (gapMin, gapMax) = gapKm(z.kind);
      var s = max(z.startS, startS + firstAfter) + random.nextDouble() * gapMax * GameConfig.unitsPerKm * 0.5;
      while (s < min(z.endS - 300, endS - 900)) {
        put(s, zone);
        s += (gapMin + random.nextDouble() * (gapMax - gapMin)) * GameConfig.unitsPerKm;
      }
    }
  }

  // Cây xăng.
  scatter(
    {RoadKind.city, RoadKind.highway, RoadKind.expressway},
    (kind) => switch (kind) {
      RoadKind.city => (GameConfig.gasGapCityKmMin, GameConfig.gasGapCityKmMax),
      RoadKind.highway => (GameConfig.gasGapHighwayKmMin, GameConfig.gasGapHighwayKmMax),
      RoadKind.expressway => (GameConfig.gasGapExpresswayKmMin, GameConfig.gasGapExpresswayKmMax),
    },
    (s, zone) {
      for (var at = s; at < s + 900; at += 150) {
        if (!clear(at, 300)) continue;
        final side = zone.kind == RoadKind.expressway ? 1 : (random.nextDouble() < 0.7 ? 1 : -1);
        stalls.add(Stall(s: at, side: side, kind: StallKind.xang, owner: '', seed: random.nextInt(1 << 20)));
        return;
      }
    },
    firstAfter: 2500,
  );

  // Đinh tặc trên quốc lộ, ngay sau là tiệm vá xe "chặn đầu".
  scatter({RoadKind.highway}, (_) => (GameConfig.nailGapKmMin, GameConfig.nailGapKmMax), (s, zone) {
    final shop = s + 380 + random.nextDouble() * 320;
    if (!clear(s, 160) || !clear(shop, 220) || shop > zone.endS - 300) return;
    nails.add(NailPatch(s: s, lane: random.nextInt(2), warned: random.nextDouble() < 0.5, seed: random.nextInt(1 << 20)));
    stalls.add(Stall(s: shop, side: 1, kind: StallKind.vaXe, owner: mechanic(), seed: random.nextInt(1 << 20), gouging: true));
  }, firstAfter: 4000);

  // Tiệm vá xe.
  scatter(
    {RoadKind.city, RoadKind.highway},
    (kind) => kind == RoadKind.city
        ? (GameConfig.tireShopGapCityKmMin, GameConfig.tireShopGapCityKmMax)
        : (GameConfig.tireShopGapHighwayKmMin, GameConfig.tireShopGapHighwayKmMax),
    (s, zone) {
      if (clear(s, 260)) stalls.add(Stall(s: s, side: roadSide(), kind: StallKind.vaXe, owner: mechanic(), seed: random.nextInt(1 << 20)));
    },
  );

  // Xăng lẻ ven quốc lộ.
  scatter({RoadKind.highway}, (_) => (GameConfig.bottleGapKmMin, GameConfig.bottleGapKmMax), (s, zone) {
    if (clear(s, 220)) stalls.add(Stall(s: s, side: roadSide(), kind: StallKind.xangLe, owner: bottleSeller(), seed: random.nextInt(1 << 20)));
  });

  // Quán nước chen vào giữa.
  scatter(
    {RoadKind.city, RoadKind.highway},
    (kind) => kind == RoadKind.city
        ? (GameConfig.stallGapCityKmMin, GameConfig.stallGapCityKmMax)
        : (GameConfig.stallGapHighwayKmMin, GameConfig.stallGapHighwayKmMax),
    (s, zone) {
      if (!clear(s, 180)) return;
      final roll = random.nextDouble();
      final kind = zone.kind == RoadKind.city
          ? (roll < 0.45
              ? StallKind.traDa
              : roll < 0.65
                  ? StallKind.banhMi
                  : roll < 0.82
                      ? StallKind.nuocMia
                      : StallKind.com)
          : (roll < 0.3
              ? StallKind.traDa
              : roll < 0.5
                  ? StallKind.nuocMia
                  : roll < 0.72
                      ? StallKind.caPheVong
                      : roll < 0.87
                          ? StallKind.com
                          : StallKind.banhMi);
      // Phần nhiều quán ở bên phải chiều về; quán bên kia thì phải quay đầu.
      stalls.add(Stall(s: s, side: roadSide(), kind: kind, owner: owner(), seed: random.nextInt(1 << 20)));
    },
  );

  stalls.sort((a, b) => a.s.compareTo(b.s));
  nails.sort((a, b) => a.s.compareTo(b.s));
  return (stalls: stalls, nails: nails);
}
