import 'place.dart';

/// Cảnh hai bên đường ("bản đồ") người chơi chọn.
enum MapTheme {
  /// Theo vùng của từng chặng: Tây Bắc, Tây Nguyên, đèo Hải Vân là đèo núi;
  /// dải ven biển miền Trung, Hạ Long, Vũng Tàu là ven biển; miền Tây là sông
  /// nước; còn lại là đồng bằng.
  auto('Tự động', 'Đổi theo vùng của từng chặng'),

  /// Ruộng lúa non, lũy tre, xóm mái ngói đỏ, chuối; sương sớm.
  delta('Đồng bằng', 'Ruộng lúa, lũy tre, xóm mái ngói'),

  /// Cát trắng, rặng phi lao, biển xanh một bên đường, thúng chai.
  coast('Ven biển', 'Cát trắng, phi lao, biển xanh'),

  /// Vách đá một bên, vực rừng một bên, thông, đường cua liên tục.
  mountain('Đèo núi', 'Vách đá, vực sâu, rừng thông, cua gắt'),

  /// Kênh rạch dọc đường, dừa nước, dừa xiêm, lúa chín vàng, xuồng ba lá.
  mekong('Sông nước', 'Kênh rạch, dừa, lúa chín vàng');

  const MapTheme(this.title, this.subtitle);

  final String title;
  final String subtitle;

  /// Cảnh thật dùng cho chặng nối [from] → [to] (khi chọn [auto]).
  MapTheme resolve(Place? from, Place? to) {
    if (this != auto) return this;
    bool any(Set<String> ids) => (from != null && ids.contains(from.id)) || (to != null && ids.contains(to.id));
    if (any(_mountain) || (from != null && to != null && {from.id, to.id}.containsAll(const {'hue', 'da_nang'}))) {
      return mountain;
    }
    if (to != null && _coast.contains(to.id)) return coast;
    if (to != null && _mekong.contains(to.id)) return mekong;
    if (from != null && _coast.contains(from.id) && (to == null || to.zone == PlaceZone.central)) return coast;
    return delta;
  }

  static const Set<String> _mountain = {
    'ha_giang', 'cao_bang', 'bac_kan', 'lao_cai', 'sa_pa', 'lai_chau', 'dien_bien', 'son_la', 'yen_bai', 'moc_chau', //
    'hoa_binh', 'kon_tum', 'pleiku', 'buon_ma_thuot', 'gia_nghia', 'da_lat', 'bao_loc',
  };

  static const Set<String> _coast = {
    'ha_long', 'mong_cai', 'dong_hoi', 'dong_ha', 'hue', 'da_nang', 'hoi_an', 'tam_ky', 'quang_ngai', 'quy_nhon', //
    'tuy_hoa', 'nha_trang', 'phan_rang', 'phan_thiet', 'vung_tau',
  };

  static const Set<String> _mekong = {
    'tan_an', 'my_tho', 'ben_tre', 'tra_vinh', 'vinh_long', 'cao_lanh', 'can_tho', 'long_xuyen', 'chau_doc', 'ha_tien', //
    'rach_gia', 'vi_thanh', 'soc_trang', 'bac_lieu', 'ca_mau',
  };
}

/// Trời: theo giờ của chuyến đi (sáng, chiều, tối dần tới giao thừa), hoặc
/// luôn ban ngày / luôn ban đêm.
enum SkyMode {
  clock('Theo giờ', 'Trời tối dần theo đồng hồ chuyến đi'),
  day('Ban ngày', 'Luôn nắng sáng'),
  night('Ban đêm', 'Đường tối, phải bật đèn pha');

  const SkyMode(this.title, this.subtitle);

  final String title;
  final String subtitle;
}
