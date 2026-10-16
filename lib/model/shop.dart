import '../game/vehicle_spec.dart';

/// Nâng cấp xe mua ở trạm dừng nghỉ, dùng cho cả phần đường còn lại của
/// chuyến đi. Giá (lì xì) theo loại xe: đồ cho ô tô, xe khách đắt hơn.
///
/// Mặt bằng giá: một chặng 60–110 km thường nhặt được chừng 15–30 lì xì
/// (lì xì rơi trên đường, khách đi nhờ biếu, tiền xe khách), tiêu chừng 3–8
/// (trạm thu phí, xăng, quán, phạt) — nên sau một chặng mua được 2–3 món.
enum Upgrade {
  tires(
    'Lốp tốt',
    'Lốp gai sâu, bám đường ướt gấp đôi, ít bị xịt vì đinh, ổ gà',
    art: 'lop_tot',
    prices: (8, 12, 16),
  ),
  extraTank(
    'Bình xăng phụ',
    'Can xăng phụ đổ đầy sẵn: chạy xa thêm 40% mỗi bình',
    art: 'binh_xang',
    prices: (5, 8, 10),
  ),
  led(
    'Đèn LED',
    'Đèn pha LED trắng, chiếu xa gấp rưỡi khi trời tối',
    art: 'den_led',
    prices: (6, 9, 9),
  ),
  airHorn(
    'Còi hơi',
    'Kêu to, vang xa, hồi còi nhanh — xe to cũng phải nhường',
    art: 'coi_hoi',
    prices: (4, 6, 6),
  ),
  cushion(
    'Đệm ghế êm',
    'Đệm hạt gỗ thoáng lưng, lái lâu đỡ mỏi, chậm buồn ngủ',
    art: 'dem_ghe',
    prices: (4, 5, 5),
  );

  const Upgrade(this.title, this.detail, {required this.art, required this.prices});

  final String title;
  final String detail;

  /// Ảnh minh hoạ (assets/images/img_shop_[art].png).
  final String art;

  /// Giá cho xe máy, ô tô, xe khách.
  final (int, int, int) prices;

  int priceFor(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => prices.$1,
        VehicleKind.car => prices.$2,
        VehicleKind.bus => prices.$3,
      };

  /// Tác dụng tóm tắt bằng số (hiện trên thẻ cửa hàng).
  String get effect {
    String pct(double k) => '${(k * 100).round()}%';
    String times(double k) => '×${k.toStringAsFixed(1).replaceAll('.', ',')}';
    return switch (this) {
      tires => 'Xịt lốp −${pct(1 - Perks.punctureTires)}',
      extraTank => 'Tầm chạy +${pct(Perks.fuelCapacityExtraTank - 1)}',
      led => 'Tầm chiếu ${times(Perks.headlightReachLed)}',
      airHorn => 'Vang xa ${times(Perks.hornReachAirHorn)}',
      cushion => 'Buồn ngủ −${pct(1 - Perks.drowsinessCushion)}',
    };
  }

  /// Tên theo loại xe (xe máy thì là đệm yên).
  String titleFor(VehicleKind kind) => this == cushion && kind == VehicleKind.motorbike ? 'Đệm yên êm' : title;

  /// Đọc danh sách tên đã lưu (bỏ tên lạ của bản khác).
  static Set<Upgrade> parse(Object? json) => {
        if (json is List)
          for (final name in json)
            if (Upgrade.values.asNameMap()[name] case final Upgrade u) u,
      };
}

/// Tác dụng của các nâng cấp lên xe trong game (hệ số nhân, 1 = như xe thường).
class Perks {
  const Perks._({
    required this.wetGripLoss,
    required this.puncture,
    required this.fuelCapacity,
    required this.headlightReach,
    required this.led,
    required this.hornReach,
    required this.hornCooldown,
    required this.heavyIgnoreHorn,
    required this.drowsiness,
  });

  factory Perks.of(Set<Upgrade> upgrades) {
    bool has(Upgrade u) => upgrades.contains(u);
    return Perks._(
      wetGripLoss: has(Upgrade.tires) ? wetGripLossTires : 1,
      puncture: has(Upgrade.tires) ? punctureTires : 1,
      fuelCapacity: has(Upgrade.extraTank) ? fuelCapacityExtraTank : 1,
      headlightReach: has(Upgrade.led) ? headlightReachLed : 1,
      led: has(Upgrade.led),
      hornReach: has(Upgrade.airHorn) ? hornReachAirHorn : 1,
      hornCooldown: has(Upgrade.airHorn) ? hornCooldownAirHorn : 1,
      heavyIgnoreHorn: has(Upgrade.airHorn) ? heavyIgnoreAirHorn : 1,
      drowsiness: has(Upgrade.cushion) ? drowsinessCushion : 1,
    );
  }

  static const Perks none = Perks._(
    wetGripLoss: 1,
    puncture: 1,
    fuelCapacity: 1,
    headlightReach: 1,
    led: false,
    hornReach: 1,
    hornCooldown: 1,
    heavyIgnoreHorn: 1,
    drowsiness: 1,
  );

  /// Lốp tốt: đường ướt chỉ mất nửa độ bám; đinh tặc, sập ổ gà chỉ còn
  /// ~1/3 khả năng xịt lốp.
  static const double wetGripLossTires = 0.5;
  static const double punctureTires = 0.35;

  /// Bình xăng phụ: chứa thêm 40% (đổ đầy cũng tốn thêm 40%).
  static const double fuelCapacityExtraTank = 1.4;

  /// Đèn LED: chùm pha dài gấp rưỡi, trắng và sáng hơn.
  static const double headlightReachLed = 1.5;

  /// Còi hơi: vang xa ×1,6, hồi còi còn 60%, xe tải / xe khách ít lờ đi hơn.
  static const double hornReachAirHorn = 1.6;
  static const double hornCooldownAirHorn = 0.6;
  static const double heavyIgnoreAirHorn = 0.4;

  /// Đệm ghế êm: tỉnh táo tụt chậm còn 70%.
  static const double drowsinessCushion = 0.7;

  /// Phần độ bám bị mất khi đường ướt (nhân với độ ướt).
  final double wetGripLoss;

  /// Hệ số khả năng xịt lốp (đinh tặc, sập ổ gà).
  final double puncture;

  /// Dung tích bình so với bình zin.
  final double fuelCapacity;

  final double headlightReach;

  /// Đèn LED (ánh trắng xanh thay cho ánh vàng đèn halogen).
  final bool led;

  final double hornReach;
  final double hornCooldown;
  final double heavyIgnoreHorn;

  /// Hệ số mau buồn ngủ.
  final double drowsiness;
}

/// Người nhà ra cổng đón (thứ tự chào: bà, bố, mẹ, em).
enum FamilyMember {
  grandma('Bà', 'Bà hay kêu rét, trời lạnh là đau khớp', art: 'family_grandma'),
  dad('Bố', 'Bố mê đánh cờ với ông Tư hàng xóm', art: 'family_dad'),
  mom('Mẹ', 'Mẹ bận dọn nhà, chưa kịp gói bánh', art: 'family_mom'),
  kid('Em', 'Em mới vào lớp Một, suốt ngày vẽ tranh', art: 'family_kid');

  const FamilyMember(this.title, this.hint, {required this.art});

  final String title;

  /// Gợi ý người đó ưng quà gì nhất.
  final String hint;

  /// Ảnh người (assets/images/driver/[art]_1.png).
  final String art;

  /// Lời chào khi về mà không có quà.
  String get greeting => switch (this) {
        grandma => 'Cháu về là bà mừng rồi, quà cáp làm gì!',
        dad => 'Về là tốt rồi. Vào rửa mặt rồi ăn cơm con!',
        mom => 'Con về là mẹ vui nhất rồi, đi đường mệt không?',
        kid => 'A, về rồi! Thế quà của em đâu?',
      };
}

/// Quà Tết mua ở trạm dừng nghỉ, mang về biếu cả nhà. Mỗi người một món;
/// món người đó ưng nhất ([favorite]) được thưởng nhiều điểm hơn.
enum Gift {
  mutTet(FamilyMember.grandma, 'Hộp mứt Tết', 'Mứt gừng, mứt dừa, hạt sen', price: 4, art: 'mut_tet',
      reaction: 'Mứt gừng cay cay, bà nhâm nhi với chén trà là nhất!'),
  khanLen(FamilyMember.grandma, 'Khăn len ấm', 'Len lông cừu, quàng cổ ấm áp', price: 5, art: 'khan_len', favorite: true,
      reaction: 'Ấm quá! Cháu nhớ bà hay rét à? Thương cháu quá!'),
  traSen(FamilyMember.grandma, 'Trà sen Tây Hồ', 'Trà ướp bông sen, hộp sơn mài', price: 6, art: 'tra_sen',
      reaction: 'Trà sen thơm quá, sáng mùng Một bà pha mời khách.'),
  ruouNep(FamilyMember.dad, 'Chai rượu nếp', 'Nếp cái hoa vàng, nút lá chuối', price: 4, art: 'ruou_nep',
      reaction: 'Rượu nếp cái hoa vàng! Tối nay bố con mình làm một chén.'),
  amTra(FamilyMember.dad, 'Ấm trà men lam', 'Gốm Bát Tràng vẽ tay, kèm chén', price: 6, art: 'am_tra',
      reaction: 'Men lam đẹp quá! Ấm cũ của bố sứt quai rồi.'),
  coTuong(FamilyMember.dad, 'Bộ cờ tướng gỗ', 'Quân gỗ hương, bàn cờ gấp', price: 5, art: 'co_tuong', favorite: true,
      reaction: 'Cờ gỗ thơm! Mùng Hai bố phục thù ông Tư hàng xóm!'),
  banhChung(FamilyMember.mom, 'Cặp bánh chưng', 'Gói lá dong, buộc lạt giang', price: 4, art: 'banh_chung', favorite: true,
      reaction: 'Đỡ cho mẹ cả nồi bánh! Mẹ đặt lên bàn thờ ông bà ngay.'),
  hopBanh(FamilyMember.mom, 'Hộp bánh quy', 'Hộp thiếc xanh, bánh bơ giòn', price: 3, art: 'hop_banh',
      reaction: 'Để mẹ bày ra đĩa, mời khách đến chúc Tết.'),
  khanLua(FamilyMember.mom, 'Khăn lụa tơ tằm', 'Lụa Vạn Phúc dệt hoa văn', price: 6, art: 'khan_lua',
      reaction: 'Lụa mềm quá! Sáng mùng Một mẹ quàng đi lễ chùa.'),
  gauBong(FamilyMember.kid, 'Gấu bông', 'Gấu nâu thắt nơ đỏ', price: 3, art: 'gau_bong',
      reaction: 'Gấu to quá! Tối nay em ôm gấu đi ngủ!'),
  butMau(FamilyMember.kid, 'Hộp bút màu', 'Hai mươi bốn cây sáp màu', price: 3, art: 'but_mau', favorite: true,
      reaction: 'Bút màu! Em vẽ tranh Tết tặng cả nhà nhé!'),
  lixiDo(FamilyMember.kid, 'Phong bao lì xì', 'Lì xì đầu năm lấy may', price: 5, art: 'lixi_do',
      reaction: 'Lì xì đỏ! Em bỏ heo đất, để dành mua sách.');

  const Gift(this.member, this.title, this.detail,
      {required this.price, required this.art, required this.reaction, this.favorite = false});

  final FamilyMember member;
  final String title;
  final String detail;
  final int price;

  /// Ảnh minh hoạ (assets/images/img_shop_[art].png).
  final String art;

  /// Câu người nhận nói khi được tặng.
  final String reaction;

  /// Món người nhận ưng nhất.
  final bool favorite;

  /// Điểm thưởng cuối chuyến. Quà chở theo xe vẫn tính điểm chặng như lì xì
  /// còn giữ (StageResult.giftValue), nên mua quà chỉ đổi 50 điểm cuối chuyến
  /// mỗi lì xì lấy điểm thưởng này (gấp 5 lần, món ưng ý còn hơn).
  int get bonus => (price * bonusPerLixi * (favorite ? favoriteFactor : 1)).round();

  static const int bonusPerLixi = 250;
  static const double favoriteFactor = 1.6;

  /// Đủ quà cho cả bốn người thì thưởng thêm.
  static const int wholeFamilyBonus = 1000;

  static List<Gift> optionsFor(FamilyMember member) => [for (final g in values) if (g.member == member) g];

  /// Tổng điểm thưởng quà mang về.
  static int bonusOf(Iterable<Gift> gifts) {
    final list = gifts.toList();
    final members = {for (final g in list) g.member};
    return list.fold(0, (sum, g) => sum + g.bonus) + (members.length == FamilyMember.values.length ? wholeFamilyBonus : 0);
  }

  /// Đọc danh sách tên đã lưu (bỏ tên lạ, mỗi người giữ món đầu tiên).
  static List<Gift> parse(Object? json) {
    final out = <Gift>[];
    if (json is! List) return out;
    for (final name in json) {
      final gift = Gift.values.asNameMap()[name];
      if (gift != null && !out.any((g) => g.member == gift.member)) out.add(gift);
    }
    return out;
  }
}
