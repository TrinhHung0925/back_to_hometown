import 'dart:convert';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flutter/services.dart';

/// Ảnh đứng (cây, nhà, quán, người…) và chiều cao thật của khung ảnh.
class BillboardArt {
  const BillboardArt(this.image, this.heightM, [this.info = const {}]);

  final Image image;
  final double heightM;

  /// Thông tin thêm trong tệp mô tả (điểm treo, đầu cần đèn…).
  final Map<dynamic, dynamic> info;

  /// Điểm [key] trên ảnh theo tỉ lệ [u, v] (u tính từ trái, v từ trên).
  Offset? anchor(String key) {
    final v = info[key];
    if (v is List && v.length >= 2) return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
    return null;
  }

  double get aspect => image.width / image.height;
}

/// Hình cho góc nhìn ghế lái (assets/images/driver, dựng bằng các script
/// tool/asset_pipeline/build_driver_*.py). Nạp khi người chơi bật góc nhìn
/// này lần đầu; thiếu ảnh nào thì cảnh đó vẽ tạm bằng khối màu.
class DriverArt {
  DriverArt._();

  static const String dir = 'assets/images/driver';

  /// Quy đổi mét ra đơn vị bản đồ cho ảnh đứng (xe ô tô trên bản đồ rộng
  /// chừng 21 đơn vị mỗi mét).
  static const double unitsPerMeter = 21;

  /// Ảnh xe nhìn từ đuôi / đầu / hông: 80 điểm ảnh mỗi mét, gốc ảnh ở giữa
  /// mép dưới.
  static const double vehiclePixelsPerMeter = 80;

  final Map<String, BillboardArt> props = {};
  final Map<String, Image> vehicles = {};

  /// Đèn hậu (ảnh đuôi) và đèn pha (ảnh đầu) theo điểm ảnh của từng xe.
  final Map<String, Map<String, List<Offset>>> lamps = {};

  /// Khung buồng lái theo loại xe và vô-lăng (đặt trong khung 1600 × 740).
  final Map<String, Image> cockpits = {};
  Map<String, dynamic> cockpitInfo = {};

  BillboardArt? prop(String key) => props[key];

  /// Ảnh xe [view] ('rear', 'front', 'side') của ảnh bản đồ [spritePath]
  /// (ví dụ assets/images/img_sedan_white.png → sedan_white_rear).
  Image? vehicle(String spritePath, String view) => vehicles['${baseOf(spritePath)}_$view'];

  static String baseOf(String spritePath) {
    final file = spritePath.split('/').last;
    return file.substring(4, file.length - 4);
  }

  /// Ảnh có thật trong gói ứng dụng (nạp ảnh thiếu sẽ báo lỗi ồn ào).
  static Set<String> _available = const {};

  static Future<Map<String, dynamic>> _json(String name) async {
    if (!_available.contains('$dir/$name')) return {};
    try {
      return jsonDecode(await rootBundle.loadString('$dir/$name')) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<Image?> _image(Images images, String key) async {
    if (!_available.contains('$dir/$key.png')) return null;
    try {
      return await images.load('$dir/$key.png');
    } catch (_) {
      return null;
    }
  }

  /// Nạp mọi ảnh liệt kê trong các tệp mô tả, cùng ảnh xe của [trafficSprites].
  static Future<DriverArt> load(Images images, List<String> trafficSprites) async {
    final art = DriverArt._();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available = manifest.listAssets().where((a) => a.startsWith(dir)).toSet();
    } catch (_) {
      _available = const {};
    }
    for (final manifest in ['scenery.json', 'props.json']) {
      final entries = await _json(manifest);
      await Future.wait(entries.entries.map((e) async {
        final image = await _image(images, e.key);
        final info = e.value;
        if (image == null || info is! Map) return;
        art.props[e.key] = BillboardArt(image, (info['h_m'] as num?)?.toDouble() ?? image.height / 100, info);
      }));
    }
    await Future.wait([
      for (final path in trafficSprites)
        for (final view in const ['rear', 'front', 'side'])
          () async {
            final key = '${baseOf(path)}_$view';
            final image = await _image(images, key);
            if (image != null) art.vehicles[key] = image;
          }(),
    ]);
    final lamps = await _json('vehicle_lamps.json');
    for (final e in lamps.entries) {
      final views = <String, List<Offset>>{};
      if (e.value is Map) {
        for (final v in (e.value as Map).entries) {
          views[v.key as String] = [
            for (final p in v.value as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
          ];
        }
      }
      art.lamps[e.key] = views;
    }
    art.cockpitInfo = await _json('cockpits.json');
    for (final key in const ['cockpit_moto', 'cockpit_car', 'cockpit_car_wheel', 'cockpit_bus', 'cockpit_bus_wheel']) {
      final image = await _image(images, key);
      if (image != null) art.cockpits[key] = image;
    }
    // Phà nhìn từ đầu cầu dẫn (cùng tỉ lệ ảnh xe: 80 điểm ảnh mỗi mét).
    final ferry = await _image(images, 'ferry_front');
    if (ferry != null) art.props['ferry_front'] = BillboardArt(ferry, ferry.height / vehiclePixelsPerMeter);
    for (final key in const ['sky_day', 'sky_dusk', 'sky_night']) {
      final image = await _image(images, key);
      if (image != null) art.props[key] = BillboardArt(image, 1);
    }
    return art;
  }
}
