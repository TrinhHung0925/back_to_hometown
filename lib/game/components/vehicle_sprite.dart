import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../logic/road_path.dart';
import 'scenery_layer.dart';

/// Xe đặt theo toạ độ đường (s, d): bóng đổ, thân xe, đèn phanh, xi-nhan,
/// hàng Tết chất trên xe. Ảnh gốc mũi xe hướng lên trên nên quay thêm ±90°.
class VehicleSprite extends PositionComponent {
  VehicleSprite({
    required this.sprite,
    required this.shadow,
    required double width,
    int priority = 4,
    this.motorbike = false,
  }) : super(
          size: Vector2(width, width * sprite.srcSize.y / sprite.srcSize.x),
          anchor: Anchor.center,
          priority: priority,
        );

  Sprite sprite;
  Sprite shadow;
  final bool motorbike;

  /// Xe máy: chỗ đèn pha, đèn hậu (tỉ lệ chiều dài từ mũi xe) và xi-nhan
  /// (tỉ lệ chiều ngang) — theo đúng hình xe đang dùng.
  double headY = 0.09;
  double tailY = 0.88;
  double blinkX = 0.22;
  double frontBlinkY = 0.12;

  /// Đèn, xi-nhan khớp xe máy dựng 3D: đèn pha ở đầu ghi-đông, đèn hậu dưới
  /// baga, xi-nhan hai bên đầu xe.
  void fitMotorbike3d() {
    headY = 0.22;
    tailY = 0.93;
    blinkX = 0.38;
    frontBlinkY = 0.21;
  }

  bool braking = false;

  /// Xi-nhan theo phía của xe: -1 trái, 1 phải, 0 tắt.
  int blinker = 0;

  /// Hàng chất trên xe (vẽ ở yên sau / nóc xe).
  List<Sprite> cargo = const [];

  /// Bật đèn pha (ban đêm): vẽ đèn pha sáng và đèn hậu.
  bool lightsOn = false;

  /// Đèn khẩn cấp: cả bốn xi-nhan cùng nháy (dừng bên lề sửa xe).
  bool hazard = false;

  /// Người dắt xe đi bộ bên trái xe (xe máy hết xăng).
  Sprite? walker;

  double _t = 0;

  static final Paint _shadowPaint = Paint()..color = const Color(0xBB000000);
  static final Paint _brake = Paint()..color = const Color(0xffFF2A1F);
  static final Paint _brakeGlow = Paint()
    ..color = const Color(0x88FF2A1F)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  static final Paint _tail = Paint()..color = const Color(0xaaC81E14);
  static final Paint _blink = Paint()..color = const Color(0xffFFB020);
  static final Paint _blinkGlow = Paint()
    ..color = const Color(0x99FFB020)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  static final Paint _head = Paint()..color = const Color(0xffFFF6D8);

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final w = size.x, h = size.y;
    // Bóng đổ mềm, lệch theo hướng nắng.
    final o = toLocal(sunShadow * (motorbike ? 0.45 : 0.7), angle);
    shadow.render(canvas, position: Vector2(o.dx - w * 0.08, o.dy - h * 0.04), size: Vector2(w * 1.16, h * 1.08), overridePaint: _shadowPaint);
    sprite.render(canvas, size: size);

    // Hàng chất trên xe: xe máy để yên sau, ô tô buộc trên nóc.
    for (var i = 0; i < cargo.length; i++) {
      final c = cargo[i];
      final cw = w * (motorbike ? 1.0 : 0.62);
      final cy = motorbike ? h * (0.68 + i * 0.1) : h * (0.42 + i * 0.12);
      c.render(canvas, position: Vector2(w / 2 - cw / 2, cy - cw / 2), size: Vector2.all(cw));
    }

    final rearY = motorbike ? h * tailY : h - 3;
    if (braking || lightsOn) {
      final paint = braking ? _brake : _tail;
      for (final x in motorbike ? [w / 2] : [w * 0.2, w * 0.8]) {
        if (braking) canvas.drawCircle(Offset(x, rearY), motorbike ? 5 : 6, _brakeGlow);
        canvas.drawCircle(Offset(x, rearY), motorbike ? 2 : 2.6, paint);
      }
    }
    if (lightsOn) {
      for (final x in motorbike ? [w / 2] : [w * 0.22, w * 0.78]) {
        canvas.drawCircle(Offset(x, motorbike ? h * headY : 4), motorbike ? 2.2 : 3, _head);
      }
    }
    if ((blinker != 0 || hazard) && (_t * 2.6).floor().isEven) {
      final left = w * (motorbike ? blinkX : 0.05), right = w * (motorbike ? 1 - blinkX : 0.95);
      for (final x in hazard ? [left, right] : [blinker > 0 ? right : left]) {
        for (final y in [motorbike ? h * frontBlinkY : 6.0, rearY]) {
          canvas.drawCircle(Offset(x, y), 6, _blinkGlow);
          canvas.drawCircle(Offset(x, y), 2.4, _blink);
        }
      }
    }
    final person = walker;
    if (person != null) {
      // Người dắt xe: đứng bên trái, tay vịn ghi-đông, bước đi lắc nhẹ.
      final step = sin(_t * 7) * 1.5;
      person.render(canvas, position: Vector2(-w * 0.95, h * 0.18 + step), size: Vector2.all(w * 1.05));
    }
  }

  /// [facingBackward]: xe ngược chiều. [yaw]: lệch thêm khi đang đánh lái.
  /// [blinkerD]: xi-nhan theo chiều lệch ngang đường (-1 về phía d âm).
  void placeOn(RoadPath road, double s, double d, {bool facingBackward = false, double yaw = 0, int blinkerD = 0}) {
    final (x, y) = road.worldAt(s, d);
    position.setValues(x, y);
    final heading = road.at(s).heading;
    angle = heading + yaw + (facingBackward ? -pi / 2 : pi / 2);
    blinker = facingBackward ? -blinkerD : blinkerD;
  }

  /// Xe trên đường ngang (chạy dọc trục d).
  void placeAcross(RoadPath road, double s, double d, {required bool down}) {
    final (x, y) = road.worldAt(s, d);
    position.setValues(x, y);
    final heading = road.at(s).heading;
    angle = heading + (down ? pi : 0);
  }
}
