import 'dart:ui';

import 'package:flame/components.dart';

import '../../resource/app_colors.dart';
import '../game_config.dart';
import 'vehicle_sprite.dart';

/// Xe máy công an: xe máy + cụm đèn xanh/đỏ nhấp nháy.
/// Cố ý không vẽ quân hàm, phù hiệu hay biển số giống thật.
class PoliceComponent extends VehicleSprite {
  PoliceComponent({required super.sprite, required super.shadow}) : super(width: 27 * GameConfig.motorbikeVisualScale, priority: 5, motorbike: true) {
    add(_LightBar(size));
  }
}

class _LightBar extends PositionComponent {
  _LightBar(Vector2 parentSize) : super(position: Vector2(parentSize.x / 2, parentSize.y * 0.86), anchor: Anchor.center);

  static final Paint _red = Paint()..color = AppColors.ffD62828;
  static final Paint _blue = Paint()..color = AppColors.ff2F6BFF;
  static final Paint _glowRed = Paint()
    ..color = AppColors.ffD62828.withValues(alpha: 0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  static final Paint _glowBlue = Paint()
    ..color = AppColors.ff2F6BFF.withValues(alpha: 0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final redOn = (_t * 6).floor().isEven;
    canvas.drawCircle(const Offset(-6, 0), redOn ? 12 : 6, redOn ? _glowRed : _glowBlue);
    canvas.drawCircle(const Offset(6, 0), redOn ? 6 : 12, redOn ? _glowRed : _glowBlue);
    canvas.drawCircle(const Offset(-6, 0), 3.5, redOn ? _red : _blue);
    canvas.drawCircle(const Offset(6, 0), 3.5, redOn ? _blue : _red);
  }
}
