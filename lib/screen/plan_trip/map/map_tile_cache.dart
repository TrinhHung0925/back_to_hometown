import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../resource/app_resource.dart';

/// Nạp các ô ảnh nền bản đồ theo nhu cầu, giữ tối đa [capacity] ô trong bộ
/// nhớ (bỏ ô lâu không dùng nhất). Nạp xong một ô thì báo để vẽ lại.
class MapTileCache extends ChangeNotifier {
  MapTileCache({this.capacity = 56});

  final int capacity;
  final _images = <int, ui.Image>{}; // giữ thứ tự thêm vào: đầu = lâu nhất
  final _loading = <int>{};
  final _loadingExtra = <String>{};
  final _extra = <String, ui.Image>{};
  bool _disposed = false;

  static int _key(int level, int i, int j) => (level * 1000 + i) * 1000 + j;

  /// Ảnh của ô nếu đã nạp; chưa có thì bắt đầu nạp và trả về null.
  ui.Image? tile(int level, int i, int j) {
    final key = _key(level, i, j);
    final image = _images.remove(key);
    if (image != null) {
      _images[key] = image; // đưa lên cuối = vừa dùng
      return image;
    }
    if (_loading.add(key)) {
      _decode(Img.mapTile(level, i, j)).then((img) {
        _loading.remove(key);
        if (img == null) return;
        if (_disposed) {
          img.dispose();
          return;
        }
        _images[key] = img;
        while (_images.length > capacity) {
          final oldest = _images.keys.first;
          _images.remove(oldest)!.dispose();
        }
        notifyListeners();
      });
    }
    return null;
  }

  /// Ảnh lẻ (xe trên lộ trình…), nạp một lần.
  ui.Image? asset(String path) {
    final image = _extra[path];
    if (image != null) return image;
    if (_loadingExtra.add(path)) {
      _decode(path).then((img) {
        if (img == null) return;
        if (_disposed) {
          img.dispose();
          return;
        }
        _extra[path] = img;
        notifyListeners();
      });
    }
    return null;
  }

  static Future<ui.Image?> _decode(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    for (final img in _extra.values) {
      img.dispose();
    }
    _images.clear();
    _extra.clear();
    super.dispose();
  }
}
