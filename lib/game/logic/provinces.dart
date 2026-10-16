import '../../model/place.dart';
import '../../resource/vn_route_data.dart';
import 'roadside.dart';

/// Kiểu món đặc sản: món ăn no (quán cơm, xe bánh mì xôi), quà vặt (quán
/// nào cũng bày bán), đồ uống (quán nước, cà phê, quán cơm).
enum SpecialtyKind { meal, snack, drink }

/// Món đặc sản của một tỉnh: tỉnh táo hồi nhiều hơn món thường một chút,
/// kèm câu chủ quán mời và câu tả hương vị khi ăn.
class Specialty {
  const Specialty(this.item, this.kind, {required this.pitch, required this.taste});

  final StallItem item;
  final SpecialtyKind kind;

  /// Chủ quán mời (chen vào chuyện ở quán).
  final String pitch;

  /// Ăn / uống xong thấy thế nào (thông báo sau khi gọi món).
  final String taste;

  /// Quán kiểu [stall] có bán món này không.
  bool soldAt(StallKind stall) => switch (kind) {
        SpecialtyKind.meal => stall == StallKind.com || stall == StallKind.banhMi,
        SpecialtyKind.snack => stall.food,
        SpecialtyKind.drink =>
          stall == StallKind.traDa || stall == StallKind.caPheVong || stall == StallKind.nuocMia || stall == StallKind.com,
      };
}

/// Một tỉnh / thành phố trên đường về quê.
class Province {
  const Province(this.name, this.specialties, {this.city = false});

  /// Tên tỉnh như trong dữ liệu điểm (tỉnh cũ trước sáp nhập 2025).
  final String name;

  /// Thành phố trực thuộc trung ương (Hà Nội, Hải Phòng, Đà Nẵng, Cần Thơ,
  /// TP. Hồ Chí Minh).
  final bool city;
  final List<Specialty> specialties;

  /// "tỉnh Thanh Hoá", "thành phố Hải Phòng", "TP. Hồ Chí Minh".
  String get title => name.startsWith('TP.') ? name : '${city ? 'thành phố' : 'tỉnh'} $name';

  /// Chữ trên cổng chào (viết hoa).
  String get gateName => name.toUpperCase();

  /// Gọi tắt khi nói về đặc sản: "xứ Thanh", "đất Cảng"…
  String get nickname => _nicknames[name] ?? name;

  static const Map<String, String> _nicknames = {
    'Thanh Hoá': 'xứ Thanh',
    'Nghệ An': 'xứ Nghệ',
    'Hà Tĩnh': 'xứ Nghệ',
    'Hải Phòng': 'đất Cảng',
    'Bắc Ninh': 'xứ Kinh Bắc',
    'Thừa Thiên Huế': 'đất Cố đô',
    'Quảng Nam': 'xứ Quảng',
    'Đà Nẵng': 'xứ Quảng',
    'TP. Hồ Chí Minh': 'Sài Gòn',
    'Hà Nội': 'đất Hà thành',
  };
}

/// Tỉnh của các điểm trên bản đồ và đặc sản từng tỉnh.
abstract class Provinces {
  /// Tên tỉnh của một điểm (tỉnh cũ nếu điểm là thành phố / thị xã).
  static String of(Place p) => p.region ?? p.name;

  /// Điểm có tên ở cuối tên điểm dừng của chặng (kể cả "Trạm nghỉ trên
  /// đường tới …"); lấy tên dài nhất khớp được.
  static Place? placeOf(String stopName, [List<Place>? places]) {
    Place? best;
    for (final p in places ?? VnRouteData.places) {
      if (stopName.endsWith(p.name) && (best == null || p.name.length > best.name.length)) best = p;
    }
    return best;
  }

  /// Tỉnh của điểm dừng [stopName] (null nếu không phải điểm trên bản đồ).
  static String? ofStop(String stopName) {
    final p = placeOf(stopName);
    return p == null ? null : of(p);
  }

  static Province? byName(String? name) => name == null ? null : _all[name];

  /// Đặc sản tỉnh [province] bán ở quán kiểu [stall] (tối đa hai món, chọn
  /// theo [seed] của quán).
  static List<Specialty> at(String? province, StallKind stall, {int seed = 0}) {
    final all = [for (final sp in byName(province)?.specialties ?? const <Specialty>[]) if (sp.soldAt(stall)) sp];
    if (all.length <= 2) return all;
    final first = seed % all.length;
    return [all[first], all[(first + 1) % all.length]];
  }

  /// Món đặc sản ứng với món vừa gọi (null nếu là món thường).
  static Specialty? specialtyOf(StallItem item) {
    for (final p in _all.values) {
      for (final sp in p.specialties) {
        if (identical(sp.item, item) || sp.item.name == item.name) return sp;
      }
    }
    return null;
  }

  /// Tỉnh có món [item].
  static Province? provinceOf(StallItem item) {
    for (final p in _all.values) {
      if (p.specialties.any((sp) => identical(sp.item, item) || sp.item.name == item.name)) return p;
    }
    return null;
  }

  static Iterable<Province> get all => _all.values;

  // Giá, tỉnh táo, số phút cho từng kiểu món (nhỉnh hơn món thường cùng loại).
  static Specialty _meal(String name, String art, String pitch, String taste, {int price = 3, double alert = 44, double minutes = 18}) =>
      Specialty(StallItem(name, price: price, alert: alert, minutes: minutes, art: art), SpecialtyKind.meal, pitch: pitch, taste: taste);

  static Specialty _snack(String name, String art, String pitch, String taste, {int price = 2, double alert = 26, double minutes = 8}) =>
      Specialty(StallItem(name, price: price, alert: alert, minutes: minutes, art: art), SpecialtyKind.snack, pitch: pitch, taste: taste);

  static Specialty _drink(String name, String art, String pitch, String taste, {int price = 2, double alert = 36, double minutes = 10}) =>
      Specialty(StallItem(name, price: price, alert: alert, minutes: minutes, art: art), SpecialtyKind.drink, pitch: pitch, taste: taste);

  static final Map<String, Province> _all = {
    for (final p in _provinces) p.name: p,
  };

  static final List<Province> _provinces = [
    // ------------------------------------------------------------ Miền Bắc
    Province('Hà Nội', city: true, [
      _meal('Bún chả Hà Nội', 'ds_bun_cha', 'Bún chả than hoa đây, chả viên chả miếng đủ cả!',
          'Chả nướng than hoa thơm lừng, chấm nước mắm chua ngọt với bún — đúng vị Hà Nội!'),
      _meal('Bánh cuốn Thanh Trì', 'ds_banh_cuon', 'Bánh cuốn Thanh Trì tráng mỏng tang, ăn với chả quế nhé!',
          'Bánh cuốn mỏng như lụa, rắc hành phi, chấm nước mắm — ăn mãi không ngán.', alert: 40, minutes: 14),
      _snack('Cốm làng Vòng', 'ds_com_vong', 'Cốm làng Vòng gói lá sen, mua về làm quà Tết đi!',
          'Cốm xanh non dẻo thơm mùi lúa mới, nhai chầm chậm thấy ngọt.'),
    ]),
    Province('Bắc Ninh', [
      _snack('Bánh phu thê Đình Bảng', 'ds_banh_phu_the', 'Bánh phu thê Đình Bảng đây, quà cưới hỏi xứ Kinh Bắc đấy!',
          'Bánh phu thê dẻo trong, nhân đậu xanh dừa sợi, thơm mùi hoa bưởi.'),
    ]),
    Province('Bắc Giang', [
      _meal('Mì Chũ xào thịt bò', 'ds_mi_xao', 'Mì Chũ Lục Ngạn làm từ gạo bao thai, xào thịt bò ngon lắm!',
          'Sợi mì gạo Chũ dai giòn, thơm mùi gạo, xào bò cải xanh — ngon tuyệt!', alert: 42),
      _snack('Bánh đa Kế', 'ds_banh_da', 'Bánh đa Kế nướng giòn rụm, mua mấy cái về nhâm nhi!',
          'Bánh đa Kế nướng than giòn tan, vừng đen bùi thơm.'),
    ]),
    Province('Vĩnh Phúc', [
      _meal('Cá thính Lập Thạch', 'ds_ca_thinh', 'Cá thính Lập Thạch, cuốn lá sung chấm tương ớt, thử đi!',
          'Cá ướp thính gạo rang chua thơm, cuốn lá sung chấm tương ớt — lạ miệng mà ngon.'),
    ]),
    Province('Phú Thọ', [
      _snack('Bưởi Đoan Hùng', 'ds_buoi', 'Bưởi Đoan Hùng đúng mùa Tết đây, múi vàng ngọt lịm!',
          'Bưởi Đoan Hùng múi vàng mọng nước, ngọt thanh — mát cả người.', alert: 24, minutes: 6),
    ]),
    Province('Thái Nguyên', [
      _drink('Chè Tân Cương', 'ds_che_xanh', 'Ấm chè Tân Cương mới pha đây, uống cho tỉnh ngủ!',
          'Chè Tân Cương nước xanh trong, chát trước ngọt hậu — tỉnh hẳn cả người!', alert: 42),
    ]),
    Province('Tuyên Quang', [
      _snack('Cam sành Hàm Yên', 'ds_cam', 'Cam sành Hàm Yên mới hái, vỏ sần mà ngọt lắm!',
          'Cam sành Hàm Yên múi mọng nước, ngọt lịm — khát mấy cũng hết.', alert: 24, minutes: 6),
    ]),
    Province('Bắc Kạn', [
      _meal('Miến dong Na Rì xào', 'ds_mien', 'Miến dong Na Rì xào lòng gà, sợi dai mà không nát!',
          'Sợi miến dong dai giòn, thơm mùi mộc nhĩ, nấm hương — ăn chắc bụng.', alert: 42),
      _snack('Hạt dẻ Bắc Kạn', 'ds_hat_de', 'Hạt dẻ rừng Bắc Kạn rang nóng đây, bùi lắm!',
          'Hạt dẻ Bắc Kạn nhỏ mà bùi, rang cát thơm phức.'),
    ]),
    Province('Hà Giang', [
      _snack('Bánh tam giác mạch', 'ds_banh_tam_giac_mach', 'Bánh tam giác mạch nướng than đây, đặc sản cao nguyên đá!',
          'Bánh tam giác mạch nướng thơm bùi, chấm mật ong rừng — vị núi rừng Hà Giang.'),
      _meal('Cháo ấu tẩu', 'ds_chao', 'Cháo ấu tẩu nóng đây, trời rét ăn một bát là ấm!',
          'Cháo ấu tẩu đắng nhẹ, cay nồng, ăn xong ấm bụng giữa trời rét.', alert: 42, minutes: 15),
    ]),
    Province('Cao Bằng', [
      _meal('Bánh cuốn canh Cao Bằng', 'ds_banh_cuon_canh', 'Bánh cuốn Cao Bằng chan nước xương, ăn khác hẳn dưới xuôi!',
          'Bánh cuốn chan nước xương hầm, thêm trứng và chả — ấm lòng ngày giá rét.', alert: 42, minutes: 15),
      _snack('Hạt dẻ Trùng Khánh', 'ds_hat_de', 'Hạt dẻ Trùng Khánh rang nóng đây, bùi lắm!',
          'Hạt dẻ Trùng Khánh rang nóng, bóc vỏ thơm bùi.'),
    ]),
    Province('Lạng Sơn', [
      _meal('Vịt quay Lạng Sơn', 'ds_vit_quay', 'Vịt quay lá mắc mật vừa ra lò, da giòn bóng!',
          'Vịt quay lá mắc mật da giòn bóng, thịt thơm lừng — đúng vị xứ Lạng.', price: 4, alert: 46),
    ]),
    Province('Quảng Ninh', [
      _snack('Chả mực Hạ Long', 'ds_cha_muc', 'Chả mực Hạ Long giã tay đây, giòn sần sật!',
          'Chả mực giã tay vàng ruộm, giòn sần sật, ngọt vị biển.', price: 3, alert: 30, minutes: 10),
    ]),
    Province('Hải Dương', [
      _snack('Bánh đậu xanh Hải Dương', 'ds_banh_dau_xanh', 'Bánh đậu xanh Hải Dương, nhâm nhi với chén trà là hết ý!',
          'Bánh đậu xanh mịn tan ngay đầu lưỡi, nhấp ngụm trà nóng là tỉnh cả người.'),
    ]),
    Province('Hải Phòng', city: true, [
      _meal('Bánh đa cua Hải Phòng', 'ds_banh_da_cua', 'Bánh đa cua đất Cảng đây, riêu cua béo ngậy!',
          'Bánh đa đỏ dai, riêu cua béo ngậy, thêm chả lá lốt — chuẩn đất Cảng!'),
      _snack('Nem cua bể', 'ds_nem_cua_be', 'Nem cua bể vuông vức đây, rán giòn nóng hổi!',
          'Nem cua bể giòn rụm, nhân cua thịt đậm đà, chấm nước mắm chua ngọt.', price: 3, alert: 30),
    ]),
    Province('Hưng Yên', [
      _snack('Chè sen long nhãn', 'ds_che_long_nhan', 'Chè long nhãn Hưng Yên đây, nhãn lồng bọc hạt sen!',
          'Long nhãn bọc hạt sen ngọt thanh, mát lịm — đúng đặc sản phố Hiến.', alert: 28),
    ]),
    Province('Hà Nam', [
      _meal('Cá kho làng Vũ Đại', 'ds_ca_kho', 'Cá kho Vũ Đại niêu đất, kho cả ngày, ăn với cơm nóng!',
          'Cá kho niêu đất xương nhừ, đậm đà cay thơm — món ăn Tết xứ Hà Nam.', price: 4, alert: 46, minutes: 20),
      _snack('Chuối ngự Đại Hoàng', 'ds_chuoi', 'Chuối ngự Đại Hoàng đây, ngày xưa tiến vua đấy!',
          'Chuối ngự quả nhỏ, vỏ mỏng, thơm ngọt lịm — xưa dâng tiến vua.', alert: 24, minutes: 6),
    ]),
    Province('Nam Định', [
      _meal('Phở bò Nam Định', 'ds_pho', 'Phở bò Nam Định đây, nước dùng ninh xương cả đêm!',
          'Nước phở ngọt xương, bánh phở mềm, thịt bò tái chín — đúng gốc phở Nam Định.'),
      _snack('Kẹo Sìu Châu', 'ds_keo_lac', 'Kẹo Sìu Châu Nam Định đây, lạc vừng giòn tan!',
          'Kẹo Sìu Châu giòn tan, thơm lạc vừng, ngọt vừa phải.'),
    ]),
    Province('Thái Bình', [
      _snack('Bánh cáy làng Nguyễn', 'ds_banh_cay', 'Bánh cáy làng Nguyễn nhiều màu đây, quà Tết Thái Bình!',
          'Bánh cáy thơm gừng, ngọt bùi, đủ màu như ngày Tết.'),
    ]),
    Province('Ninh Bình', [
      _meal('Cơm cháy Ninh Bình', 'ds_com_chay', 'Cơm cháy chan sốt tim cật đây, giòn rụm!',
          'Cơm cháy giòn rụm chan sốt tim cật nóng hổi — đặc sản cố đô Hoa Lư.', alert: 42),
    ]),
    Province('Lào Cai', [
      _meal('Thắng cố Bắc Hà', 'ds_thang_co', 'Thắng cố nóng hổi đây, ăn cho ấm người rồi đi tiếp!',
          'Thắng cố nghi ngút, cay nồng thảo quả, giữa trời rét núi ăn là ấm.', price: 4, alert: 46),
    ]),
    Province('Lai Châu', [
      _snack('Thịt trâu gác bếp', 'ds_thit_gac_bep', 'Thịt trâu gác bếp chấm chẳm chéo, ăn là nhớ!',
          'Thịt trâu gác bếp xé sợi, thơm mùi khói, chấm chẳm chéo cay tê.', price: 3, alert: 30),
    ]),
    Province('Điện Biên', [
      _snack('Xôi nếp nương Mường Thanh', 'xoi', 'Xôi nếp nương Mường Thanh đây, dẻo thơm lắm!',
          'Xôi nếp nương dẻo thơm, ăn với muối vừng — chắc bụng đường xa.', alert: 30, minutes: 10),
    ]),
    Province('Sơn La', [
      _meal('Bê chao Mộc Châu', 'ds_be_chao', 'Bê chao Mộc Châu đây, chấm tương bần là hết ý!',
          'Bê chao giòn ngoài mềm trong, chấm tương — đặc sản cao nguyên Mộc Châu.', price: 4, alert: 46),
      _drink('Sữa tươi Mộc Châu', 'ds_sua', 'Sữa tươi Mộc Châu đây, uống cho khoẻ!',
          'Sữa tươi Mộc Châu béo ngậy, thơm mùi đồng cỏ.', alert: 30, minutes: 6),
    ]),
    Province('Yên Bái', [
      _snack('Xôi nếp Tú Lệ', 'xoi', 'Xôi nếp Tú Lệ đây, hạt nếp thơm nhất Tây Bắc!',
          'Xôi Tú Lệ dẻo thơm, chưa ăn đã ngửi thấy mùi nếp mới.', alert: 30, minutes: 10),
    ]),
    Province('Hoà Bình', [
      _snack('Cơm lam Hoà Bình', 'ds_com_lam', 'Cơm lam nướng ống tre đây, chấm muối vừng nhé!',
          'Cơm lam nướng ống tre dẻo thơm, chấm muối vừng — vị núi rừng Hoà Bình.', alert: 30, minutes: 10),
    ]),
    // ----------------------------------------------------------- Miền Trung
    Province('Thanh Hoá', [
      _snack('Nem chua Thanh Hoá', 'ds_nem_chua', 'Nem chua xứ Thanh gói lá chuối đây, ăn thử một chiếc!',
          'Nem chua chua chua cay cay, thơm lá đinh lăng — ăn một miếng tỉnh cả người!', alert: 28),
      _snack('Bánh gai Tứ Trụ', 'ds_banh_gai', 'Bánh gai Tứ Trụ nhân đậu dừa đây, mua về biếu Tết!',
          'Bánh gai dẻo đen, nhân đậu xanh dừa mỡ thơm bùi.'),
    ]),
    Province('Nghệ An', [
      _meal('Cháo lươn xứ Nghệ', 'ds_chao_luon', 'Cháo lươn Vinh đây, lươn đồng xào nghệ cay nồng!',
          'Cháo lươn đồng xào nghệ, cay nồng hạt tiêu — ăn là ấm bụng.', alert: 42, minutes: 15),
      _snack('Cam Vinh', 'ds_cam', 'Cam Vinh đúng vụ Tết đây, vỏ mỏng ngọt thơm!',
          'Cam Vinh mọng nước, ngọt đậm, thơm tinh dầu vỏ — giải khát tức thì.', alert: 24, minutes: 6),
    ]),
    Province('Hà Tĩnh', [
      _snack('Kẹo cu đơ Hà Tĩnh', 'ds_cu_do', 'Kẹo cu đơ Hà Tĩnh đây, mật mía thơm gừng!',
          'Kẹo cu đơ kẹp bánh tráng, mật mía thơm gừng — ngọt mà không gắt.'),
      _snack('Bưởi Phúc Trạch', 'ds_buoi', 'Bưởi Phúc Trạch đây, ngọt nhất xứ Nghệ!',
          'Bưởi Phúc Trạch múi hồng, mọng nước, ngọt thanh.', alert: 24, minutes: 6),
    ]),
    Province('Quảng Bình', [
      _meal('Cháo canh Quảng Bình', 'ds_chao_canh', 'Cháo canh cá lóc Quảng Bình đây, sợi bánh dai mềm!',
          'Sợi bánh canh bột gạo dai mềm trong nước cá lóc ngọt thơm — ấm lòng.', alert: 42, minutes: 15),
      _snack('Khoai deo Quảng Bình', 'ds_khoai_deo', 'Khoai deo Quảng Bình đây, dẻo ngọt lắm!',
          'Khoai deo phơi gió Lào dẻo quánh, ngọt tự nhiên — nhai mãi không chán.'),
    ]),
    Province('Quảng Trị', [
      _meal('Cháo bột Hải Lăng', 'ds_chao_canh', 'Cháo bột Hải Lăng đây, nấu với cá lóc đồng!',
          'Cháo bột sợi dai, nước cá lóc ngọt, thêm ớt tươi cay xé — đúng vị Quảng Trị.', alert: 42, minutes: 15),
    ]),
    Province('Thừa Thiên Huế', [
      _meal('Bún bò Huế', 'ds_bun_bo', 'Bún bò Huế đây, cay thơm mắm ruốc sả ớt!',
          'Bún bò Huế cay nồng sả ớt, giò heo mềm, nước dùng thơm mắm ruốc.'),
      _snack('Bánh bèo chén Huế', 'ds_banh_beo', 'Bánh bèo chén đây, tôm chấy mỡ hành đủ cả!',
          'Bánh bèo chén nhỏ xinh, tôm chấy đỏ, mỡ hành — chan nước mắm ngọt ăn mãi không chán.'),
      _snack('Mè xửng Huế', 'ds_me_xung', 'Mè xửng Huế đây, mua mấy hộp về làm quà nhé!',
          'Mè xửng dẻo dai, thơm vừng, ngọt mật — quà xứ Huế.'),
    ]),
    Province('Đà Nẵng', city: true, [
      _meal('Bánh tráng cuốn thịt heo', 'ds_cuon', 'Bánh tráng cuốn thịt heo hai đầu da, chấm mắm nêm nhé!',
          'Thịt heo luộc cuốn bánh tráng rau sống, chấm mắm nêm đậm đà — chuẩn vị Đà Nẵng.', alert: 42),
      _snack('Mực rim me Đà Nẵng', 'ds_muc_nuong', 'Mực rim me Đà Nẵng đây, chua ngọt cay cay!',
          'Mực rim me dai ngọt, chua chua cay cay — nhâm nhi đỡ buồn ngủ.', price: 3, alert: 30),
    ]),
    Province('Quảng Nam', [
      _meal('Mì Quảng', 'ds_mi_quang', 'Mì Quảng ếch đây, có bánh tráng mè nướng giòn!',
          'Mì Quảng sợi vàng, ít nước, đậu phộng rang và bánh tráng giòn — đặc sản xứ Quảng.'),
      _meal('Cao lầu Hội An', 'ds_cao_lau', 'Cao lầu Hội An đây, sợi mì ngâm nước giếng Bá Lễ!',
          'Sợi cao lầu dai vàng, xá xíu thơm, tóp mỡ giòn — vị phố cổ Hội An.'),
    ]),
    Province('Quảng Ngãi', [
      _meal('Cá bống sông Trà kho', 'ds_ca_kho', 'Cá bống sông Trà kho tiêu đây, ăn với cơm nóng!',
          'Cá bống kho tiêu săn chắc, mặn ngọt đậm đà — đặc sản sông Trà.', price: 3, alert: 44, minutes: 18),
      _snack('Kẹo gương Quảng Ngãi', 'ds_keo_lac', 'Kẹo gương Quảng Ngãi đây, đường phổi giòn tan!',
          'Kẹo gương mỏng trong, giòn tan, thơm lạc vừng.'),
    ]),
    Province('Bình Định', [
      _meal('Bún chả cá Quy Nhơn', 'ds_bun_ca', 'Bún chả cá Quy Nhơn đây, chả cá thu chiên giòn!',
          'Nước dùng ngọt thanh, chả cá dai giòn, thêm tí ớt — đúng vị biển Quy Nhơn.'),
      _snack('Bánh ít lá gai', 'ds_banh_gai', 'Bánh ít lá gai Bình Định đây, mua về làm quà đi!',
          'Bánh ít lá gai dẻo đen, nhân đậu dừa ngọt bùi.'),
    ]),
    Province('Phú Yên', [
      _meal('Bánh canh hẹ Phú Yên', 'ds_banh_canh', 'Bánh canh hẹ Tuy Hoà đây, thêm chả cá nhé!',
          'Sợi bánh canh dai mềm, hẹ xanh thơm, chả cá chiên vàng.', alert: 42, minutes: 15),
      _snack('Bánh tráng Hoà Đa', 'ds_banh_trang', 'Bánh tráng Hoà Đa nướng giòn đây, chấm mắm nêm nhé!',
          'Bánh tráng mè Hoà Đa nướng giòn rụm, thơm mè đen.', alert: 24),
    ]),
    Province('Khánh Hoà', [
      _meal('Nem nướng Ninh Hoà', 'ds_nem_nuong', 'Nem nướng Ninh Hoà đây, cuốn bánh tráng rau sống!',
          'Nem nướng than hồng cuốn bánh tráng, chấm nước sốt sền sệt béo bùi.'),
      _meal('Bún chả cá Nha Trang', 'ds_bun_ca', 'Bún chả cá Nha Trang đây, cá tươi buổi sáng!',
          'Chả cá dai ngọt, nước dùng trong veo — vị biển Nha Trang.'),
    ]),
    Province('Ninh Thuận', [
      _meal('Bánh căn Phan Rang', 'ds_banh_can', 'Bánh căn khuôn đất nóng hổi đây, chấm nước cá!',
          'Bánh căn giòn đáy, trứng mềm, chấm nước mắm cá kho — đặc sản Phan Rang.', alert: 40, minutes: 14),
      _snack('Nho Phan Rang', 'ds_nho', 'Nho Phan Rang mới cắt đây, chùm nào cũng mọng!',
          'Nho Phan Rang chua ngọt nắng gió, mát lịm.', alert: 24, minutes: 6),
    ]),
    Province('Bình Thuận', [
      _snack('Thanh long Bình Thuận', 'ds_thanh_long', 'Thanh long Hàm Thuận đây, ngọt mát lắm!',
          'Thanh long ruột trắng mát lạnh, ngọt dịu — giải khát đường xa.', alert: 24, minutes: 6),
      _snack('Mực một nắng Phan Thiết', 'ds_muc_nuong', 'Mực một nắng nướng than đây, chấm tương ớt!',
          'Mực một nắng nướng thơm, dai ngọt, chấm tương ớt cay xè.', price: 3, alert: 30),
    ]),
    // --------------------------------------------------------- Tây Nguyên
    Province('Kon Tum', [
      _meal('Gỏi lá Kon Tum', 'ds_goi_la', 'Gỏi lá Kon Tum đây, mấy chục loại lá rừng đấy!',
          'Đủ loại lá rừng cuốn thịt tôm, chấm nước chấm sền sệt — lạ miệng mà ngon.', price: 4, alert: 44),
    ]),
    Province('Gia Lai', [
      _meal('Phở khô Gia Lai', 'ds_pho_kho', 'Phở hai tô Pleiku đây, sợi phở nhỏ dai lắm!',
          'Phở khô hai tô: bánh phở trộn sốt và chén nước dùng — đặc sản phố núi Pleiku.'),
    ]),
    Province('Đắk Lắk', [
      _drink('Cà phê Buôn Ma Thuột', 'ds_ca_phe_phin', 'Cà phê phin Buôn Ma Thuột đây, đậm đặc lắm!',
          'Cà phê phin Buôn Ma Thuột đậm đặc, thơm nồng — tỉnh hẳn người!', alert: 55),
    ]),
    Province('Đắk Nông', [
      _snack('Cơm lam gà nướng', 'ds_com_lam', 'Cơm lam gà nướng đây, gà thả đồi thơm lắm!',
          'Cơm lam dẻo thơm, gà nướng da giòn, chấm muối lá é.', price: 3, alert: 32, minutes: 12),
    ]),
    Province('Lâm Đồng', [
      _snack('Bánh tráng nướng Đà Lạt', 'ds_banh_trang_nuong', 'Bánh tráng nướng trứng hành đây, giòn rụm!',
          'Bánh tráng nướng than, trứng cút hành lá, tương ớt — giòn rụm, nóng hổi.'),
      _drink('Trà Bảo Lộc', 'ds_che_xanh', 'Trà ô long Bảo Lộc đây, uống nóng cho ấm!',
          'Trà Bảo Lộc thơm dịu, hậu ngọt — tỉnh người mà không gắt.', alert: 38),
    ]),
    // ------------------------------------------------------------ Miền Nam
    Province('Bình Phước', [
      _snack('Hạt điều rang muối', 'ds_hat_dieu', 'Hạt điều Bình Phước rang củi đây, béo giòn!',
          'Hạt điều rang muối giòn béo, còn nguyên vỏ lụa — đặc sản đất đỏ Bình Phước.', price: 3, alert: 28),
    ]),
    Province('Tây Ninh', [
      _snack('Bánh tráng phơi sương', 'ds_banh_trang', 'Bánh tráng phơi sương Trảng Bàng cuốn thịt luộc đây!',
          'Bánh tráng phơi sương dẻo mềm, cuốn thịt luộc rau rừng — đặc sản Trảng Bàng.', price: 3, alert: 32, minutes: 12),
    ]),
    Province('Bình Dương', [
      _meal('Bánh bèo bì Bến Cát', 'ds_banh_beo', 'Bánh bèo bì Bến Cát đây, chan nước cốt dừa!',
          'Bánh bèo mềm, bì heo thơm thính, rưới nước cốt dừa béo.', alert: 40, minutes: 14),
    ]),
    Province('Đồng Nai', [
      _snack('Bưởi Tân Triều', 'ds_buoi', 'Bưởi Tân Triều đây, múi ráo ngọt thanh!',
          'Bưởi Tân Triều múi ráo, ngọt thanh, không đắng.', alert: 24, minutes: 6),
    ]),
    Province('TP. Hồ Chí Minh', city: true, [
      _meal('Cơm tấm Sài Gòn', 'ds_com_tam', 'Cơm tấm sườn bì chả đây, mỡ hành thơm phức!',
          'Cơm tấm sườn nướng, bì chả, mỡ hành, nước mắm chua ngọt — đúng chất Sài Gòn.'),
      _meal('Hủ tiếu Nam Vang', 'ds_hu_tieu', 'Hủ tiếu Nam Vang đây, tôm gan đủ cả!',
          'Hủ tiếu dai, nước lèo ngọt xương, tôm thịt gan — ăn một tô no tới chiều.'),
      _drink('Cà phê sữa đá Sài Gòn', 'bac_xiu', 'Cà phê sữa đá Sài Gòn đây, đậm mà béo!',
          'Cà phê sữa đá đậm đà, ngọt béo — đúng chất Sài Gòn, tỉnh cả người.', alert: 48),
    ]),
    Province('Bà Rịa – Vũng Tàu', [
      _meal('Bánh khọt Vũng Tàu', 'ds_banh_khot', 'Bánh khọt tôm tươi đây, cuốn rau chấm nước mắm!',
          'Bánh khọt giòn rụm, tôm tươi đỏ au, cuốn rau sống chấm nước mắm chua ngọt.', alert: 42, minutes: 15),
    ]),
    Province('Long An', [
      _snack('Lạp xưởng Cần Đước', 'ds_lap_xuong', 'Lạp xưởng Cần Đước đây, chiên lên thơm cả xóm!',
          'Lạp xưởng Cần Đước chiên vàng, ngọt thơm mùi rượu mai quế lộ.', price: 3, alert: 30),
    ]),
    Province('Tiền Giang', [
      _meal('Hủ tiếu Mỹ Tho', 'ds_hu_tieu', 'Hủ tiếu Mỹ Tho đây, sợi hủ tiếu Gò Cát dai lắm!',
          'Hủ tiếu Mỹ Tho sợi dai, nước lèo ngọt thanh tôm tép — đặc sản miền Tây.'),
      _snack('Vú sữa Lò Rèn', 'ds_vu_sua', 'Vú sữa Lò Rèn đúng mùa Tết đây, ngọt như sữa!',
          'Vú sữa Lò Rèn mềm mọng, ngọt mát như sữa — trái cây Tết miền Tây.', alert: 24, minutes: 6),
    ]),
    Province('Bến Tre', [
      _snack('Kẹo dừa Bến Tre', 'ds_keo_dua', 'Kẹo dừa Bến Tre đây, mua về làm quà Tết nhé!',
          'Kẹo dừa béo ngậy, thơm nước cốt dừa — ngọt cả miệng.'),
      _drink('Nước dừa xiêm', 'ds_dua', 'Dừa xiêm Bến Tre chặt tại chỗ đây, ngọt mát lắm!',
          'Nước dừa xiêm ngọt mát, giải khát tức thì.', alert: 30, minutes: 6),
    ]),
    Province('Trà Vinh', [
      _meal('Bún nước lèo Trà Vinh', 'ds_bun_nuoc_leo', 'Bún nước lèo mắm bò hóc đây, món của bà con Khmer!',
          'Bún nước lèo thơm mắm bò hóc, cá lóc ngọt, ăn kèm bông điên điển.'),
      _snack('Bánh tét Trà Cuôn', 'ds_banh_tet', 'Bánh tét Trà Cuôn nhân mỡ trứng muối đây, Tết phải có!',
          'Bánh tét dẻo thơm, nhân đậu mỡ trứng muối béo bùi — đúng vị Tết miền Tây.', price: 3, alert: 32, minutes: 10),
    ]),
    Province('Vĩnh Long', [
      _snack('Bưởi Năm Roi', 'ds_buoi', 'Bưởi Năm Roi Bình Minh đây, ngọt mà không hạt!',
          'Bưởi Năm Roi múi mọng, ngọt thanh, ít hạt.', alert: 24, minutes: 6),
    ]),
    Province('Đồng Tháp', [
      _snack('Nem Lai Vung', 'ds_nem_chua', 'Nem Lai Vung đây, chua ngọt vừa ăn!',
          'Nem Lai Vung chua ngọt dịu, thơm tỏi ớt, ăn kèm lá chùm ruột.', alert: 28),
      _meal('Hủ tiếu Sa Đéc', 'ds_hu_tieu', 'Hủ tiếu Sa Đéc đây, sợi tươi mới làm!',
          'Hủ tiếu Sa Đéc sợi tươi dai mềm, nước lèo ngọt xương.'),
    ]),
    Province('Cần Thơ', city: true, [
      _snack('Bánh tét lá cẩm', 'ds_banh_tet_cam', 'Bánh tét lá cẩm Cần Thơ đây, nếp tím đẹp lắm!',
          'Bánh tét lá cẩm nếp tím dẻo thơm, nhân thịt mỡ trứng muối — đặc sản Tết Cần Thơ.', price: 3, alert: 32, minutes: 10),
    ]),
    Province('An Giang', [
      _meal('Bún cá Châu Đốc', 'ds_bun_ca', 'Bún cá Châu Đốc đây, nước lèo vàng nghệ thơm lắm!',
          'Bún cá Châu Đốc nước lèo vàng nghệ, cá lóc thơm ngọt, ăn kèm bông điên điển.'),
      _snack('Đường thốt nốt', 'ds_thot_not', 'Đường thốt nốt Bảy Núi đây, ngọt thanh thơm khói!',
          'Đường thốt nốt ngọt thanh, thơm mùi khói bếp — ngậm một miếng là tỉnh.'),
    ]),
    Province('Kiên Giang', [
      _meal('Bún cá Kiên Giang', 'ds_bun_ca', 'Bún cá Kiên Giang đây, cá nục cá lóc tươi rói!',
          'Bún cá nước dùng ngọt thanh, cá tươi, thêm tí mắm ruốc — vị biển Kiên Giang.'),
    ]),
    Province('Hậu Giang', [
      _snack('Khóm Cầu Đúc', 'ds_khom', 'Khóm Cầu Đúc gọt sẵn đây, ngọt lịm!',
          'Khóm Cầu Đúc ngọt lịm, mọng nước, không rát lưỡi.', alert: 24, minutes: 6),
    ]),
    Province('Sóc Trăng', [
      _snack('Bánh pía Sóc Trăng', 'ds_banh_pia', 'Bánh pía sầu riêng trứng muối đây, vỏ ngàn lớp!',
          'Bánh pía vỏ ngàn lớp, nhân sầu riêng đậu xanh trứng muối — đặc sản Sóc Trăng.'),
      _meal('Bún nước lèo Sóc Trăng', 'ds_bun_nuoc_leo', 'Bún nước lèo Sóc Trăng đây, thơm mắm bò hóc!',
          'Bún nước lèo ngọt thanh, thơm mắm bò hóc, thịt heo quay giòn.'),
    ]),
    Province('Bạc Liêu', [
      _meal('Bánh tằm bì Bạc Liêu', 'ds_banh_tam_bi', 'Bánh tằm bì đây, rưới nước cốt dừa béo lắm!',
          'Sợi bánh tằm dai mềm, bì thơm thính, nước cốt dừa béo ngậy.', alert: 42, minutes: 15),
    ]),
    Province('Cà Mau', [
      _meal('Cua Cà Mau hấp', 'ds_cua', 'Cua Cà Mau chắc thịt đây, hấp bia ngon lắm!',
          'Cua Cà Mau chắc thịt, gạch vàng ươm, chấm muối tiêu chanh — đáng đồng tiền!', price: 5, alert: 48, minutes: 22),
    ]),
  ];
}
