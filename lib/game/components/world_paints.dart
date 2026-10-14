import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/cache.dart';

import '../../resource/app_resource.dart';

/// Các Paint tô bằng vân ảnh (lặp liền mạch theo toạ độ thế giới, nên mặt
/// đất đứng yên khi camera trôi). Dựng một lần sau khi nạp ảnh.
class WorldPaints {
  WorldPaints(this._images);

  final Images _images;

  /// [worldSize]: một ô vân phủ bao nhiêu đơn vị thế giới. [tint]: nhân màu.
  Paint texture(String path, double worldSize, {Color? tint}) {
    final image = _images.fromCache(path);
    final m = Float64List(16)
      ..[0] = worldSize / image.width
      ..[5] = worldSize / image.height
      ..[10] = 1
      ..[15] = 1;
    final paint = Paint()
      ..shader = ImageShader(image, TileMode.repeated, TileMode.repeated, m, filterQuality: FilterQuality.medium)
      ..isAntiAlias = true;
    if (tint != null) paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    return paint;
  }

  /// Nét sơn vạch kẻ: màu [color], độ phủ loang lổ theo vân sơn mòn.
  Paint paint(Color color, double width) => texture(Img.texPaint, 90, tint: color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  late final Paint asphalt = texture(Img.texAsphalt, 260);
  late final Paint asphaltDark = texture(Img.texAsphalt, 260, tint: const Color(0xffB4B6BC));
  late final Paint asphaltLight = texture(Img.texAsphalt, 260, tint: const Color(0xffF4F2EC));
  late final Paint paving = texture(Img.texPaving, 70);
  late final Paint pavingRed = texture(Img.texPavingRed, 70);
  late final Paint grass = texture(Img.texGrass, 230);
  late final Paint grassRough = texture(Img.texGrassRough, 260);
  late final Paint laterite = texture(Img.texLaterite, 170);
  late final Paint verge = texture(Img.texVerge, 190);
  late final Paint gravel = texture(Img.texGravel, 140);
  late final Paint concrete = texture(Img.texConcrete, 160);
  late final Paint curb = texture(Img.texConcrete, 120, tint: const Color(0xffE9E6DE));
  late final Paint paddy = texture(Img.texPaddy, 150);

  /// Ruộng lúa chín vàng (miền Nam mùa Tết).
  late final Paint paddyRipe = texture(Img.texPaddy, 150, tint: const Color(0xffF2D48A));
  late final Paint roofClay = texture(Img.texRoofClay, 110);
  late final Paint roofClayDark = texture(Img.texRoofClay, 110, tint: const Color(0xffB08A7A));
  late final List<Paint> roofIron = [
    texture(Img.texRoofIron, 90, tint: const Color(0xff6E93C2)),
    texture(Img.texRoofIron, 90, tint: const Color(0xffB4675A)),
    texture(Img.texRoofIron, 90, tint: const Color(0xffD8DADC)),
    texture(Img.texRoofIron, 90, tint: const Color(0xff7FA98A)),
  ];
  late final Paint roofFlat = texture(Img.texConcrete, 140, tint: const Color(0xffD9D6CE));
}
