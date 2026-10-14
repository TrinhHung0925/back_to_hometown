import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../resource/app_resource.dart';

/// Cần lái nổi ở góc dưới bên trái: chạm chỗ nào trong vùng thì cần lái
/// hiện ra ở đó, ngón cái giữ liên tục và kéo lên/xuống để đánh lái.
///
/// Dùng [Listener] (cử chỉ kéo, không phải tap) để theo đúng một ngón tay
/// trong khi tay phải đang bấm cụm nút.
class SteeringStick extends StatefulWidget {
  const SteeringStick({super.key, required this.onChanged});

  /// -1 (kéo hết lên) .. 1 (kéo hết xuống).
  final ValueChanged<double> onChanged;

  @override
  State<SteeringStick> createState() => _SteeringStickState();
}

class _SteeringStickState extends State<SteeringStick> {
  static const double _deadZone = 0.12;

  int? _pointer;
  Offset? _origin;
  double _value = 0;

  double get _padSize => 124.h;
  double get _nubSize => 58.h;
  double get _travel => 46.h;

  void _down(PointerDownEvent e, Size zone) {
    if (_pointer != null) return;
    final half = _padSize / 2;
    _pointer = e.pointer;
    // Giữ cả đế cần lái nằm trong vùng.
    _origin = Offset(
      e.localPosition.dx.clamp(half, zone.width - half),
      e.localPosition.dy.clamp(half, zone.height - half),
    );
    _update(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _update(e.localPosition);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _origin = null;
      _value = 0;
    });
    widget.onChanged(0);
  }

  void _update(Offset position) {
    final raw = ((position.dy - _origin!.dy) / _travel).clamp(-1.0, 1.0);
    setState(() => _value = raw);
    // Vùng chết ở giữa để đi thẳng không bị lệch tay; gần giữa thì nhẹ tay
    // (chỉnh làn từng chút), kéo xa mới đánh lái gắt.
    final m = raw.abs() < _deadZone ? 0.0 : (raw.abs() - _deadZone) / (1 - _deadZone);
    widget.onChanged((0.35 * m + 0.65 * m * m) * raw.sign);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final zone = constraints.biggest;
      final restCenter = Offset(_padSize / 2 + 18.h, zone.height - _padSize / 2 - 10.h);
      final center = _origin ?? restCenter;
      final active = _pointer != null;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _down(e, zone),
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(
          children: [
            Positioned(
              left: center.dx - _padSize / 2,
              top: center.dy - _padSize / 2,
              child: Opacity(
                opacity: active ? 0.95 : 0.6,
                child: Image.asset(Img.icJoystickPad, width: _padSize, height: _padSize),
              ),
            ),
            Positioned(
              left: center.dx - _nubSize / 2,
              top: center.dy - _nubSize / 2 + _value * _travel,
              child: Opacity(
                opacity: active ? 1 : 0.7,
                child: Image.asset(Img.icJoystickNub, width: _nubSize, height: _nubSize),
              ),
            ),
          ],
        ),
      );
    });
  }
}
