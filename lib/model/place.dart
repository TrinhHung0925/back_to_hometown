/// Phía đặt tên thành phố so với chấm trên bản đồ (nếu chỗ đó còn trống).
enum LabelSide { right, left, top, bottom }

/// Vùng miền của một điểm, để nhóm danh sách chọn điểm (bắc → nam).
enum PlaceZone {
  north('Miền Bắc'),
  central('Miền Trung'),
  highlands('Tây Nguyên'),
  south('Miền Nam');

  const PlaceZone(this.title);

  final String title;
}

/// Một điểm chọn được trên bản đồ (thành phố / thị xã).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.label,
    required this.zone,
    this.region,
  });

  final String id;
  final String name;

  /// Toạ độ bản đồ (xem MapProjection): 1 đơn vị ≈ 1 độ vĩ, y tăng về phía nam.
  final double x;
  final double y;
  final LabelSide label;
  final PlaceZone zone;

  /// Tên tỉnh cũ quen thuộc (trước sáp nhập 2025) khi khác tên điểm, vd. Đồng
  /// Hới → Quảng Bình. Hiện mờ trong danh sách chọn và tìm được theo tên này.
  final String? region;
}

/// Đoạn đường nối hai điểm kề nhau.
class RoadLink {
  const RoadLink({
    required this.a,
    required this.b,
    required this.km,
    required this.expresswayKm,
    required this.carHours,
  });

  final String a;
  final String b;
  final double km;

  /// Phần có cao tốc (chỉ ô tô được đi).
  final double expresswayKm;

  /// Thời gian lái ô tô thực tế (OSRM).
  final double carHours;

  String other(String id) => id == a ? b : a;
}
