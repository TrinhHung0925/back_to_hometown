/// Phía đặt tên thành phố so với chấm trên bản đồ (nếu chỗ đó còn trống).
enum LabelSide { right, left, top, bottom }

/// Một điểm chọn được trên bản đồ (thành phố / thị xã).
class Place {
  const Place({required this.id, required this.name, required this.x, required this.y, required this.label});

  final String id;
  final String name;

  /// Toạ độ bản đồ (xem MapProjection): 1 đơn vị ≈ 1 độ vĩ, y tăng về phía nam.
  final double x;
  final double y;
  final LabelSide label;
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
