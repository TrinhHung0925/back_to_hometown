import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../../resource/app_resource.dart';
import '../logic/animals.dart';
import '../logic/road_path.dart';

/// Gà vịt chó đang qua đường và người chăn vịt cầm sào.
class AnimalLayer extends Component {
  AnimalLayer({required this.road, required this.animals, required this.images}) : super(priority: 4);

  final RoadPath road;
  final AnimalSystem animals;
  final Images images;

  late final Map<String, Sprite> _sprites = {
    for (final path in Img.animals) path: Sprite(images.fromCache(path)),
  };
  late final List<Sprite> _people = [for (final p in Img.people) Sprite(images.fromCache(p))];

  static final Paint _shadow = Paint()..color = const Color(0x40000000);
  static final Paint _pole = Paint()
    ..color = const Color(0xff8A6A3A)
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;

  Sprite _spriteFor(Animal a) {
    final flap = a.fleeing && a.pause <= 0;
    final path = switch (a.kind) {
      AnimalKind.duck => a.variant == 1 ? (flap ? Img.imgAnimalDuckWhiteFlap : Img.imgAnimalDuckWhite) : (flap ? Img.imgAnimalDuckFlap : Img.imgAnimalDuck),
      AnimalKind.chicken => a.variant == 1 ? (flap ? Img.imgAnimalHenFlap : Img.imgAnimalHen) : (flap ? Img.imgAnimalRoosterFlap : Img.imgAnimalRooster),
      AnimalKind.dog => a.fleeing ? Img.imgAnimalDogRun : ((a.t * 7).floor().isEven || a.pause > 0 ? Img.imgAnimalDog1 : Img.imgAnimalDog2),
    };
    return _sprites[path]!;
  }

  @override
  void render(Canvas canvas) {
    for (final g in animals.groups) {
      for (final a in g.animals) {
        final p = road.at(a.s);
        final (x, y) = road.worldAt(a.s + a.sway, a.d);
        final moving = a.pause <= 0 && a.delay <= 0;
        // Đầu hướng theo chiều chạy ngang đường; vịt lạch bạch, gà mổ mổ.
        final waddle = !moving
            ? 0.0
            : switch (a.kind) {
                AnimalKind.duck => sin(a.t * 12) * 0.22,
                AnimalKind.chicken => sin(a.t * 18) * 0.12,
                AnimalKind.dog => sin(a.t * 14) * 0.05,
              };
        final angle = p.heading + (a.dir > 0 ? pi / 2 : -pi / 2) + pi / 2 + waddle;
        final size = a.kind.drawSize * (a.fleeing && a.kind != AnimalKind.dog ? 1.08 : 1);
        canvas.save();
        canvas.translate(x + 2.2, y + 2.6);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: a.kind.width * 0.75, height: a.kind.width * 0.75), _shadow);
        canvas.translate(-2.2, -2.6);
        canvas.rotate(angle);
        _spriteFor(a).render(canvas, position: Vector2(-size / 2, -size / 2), size: Vector2.all(size));
        canvas.restore();
      }
      final h = g.herder;
      if (h != null) {
        final p = road.at(g.s);
        final (x, y) = road.worldAt(g.s + 18, h);
        final facing = p.heading + (g.dir > 0 ? pi / 2 : -pi / 2);
        canvas.save();
        canvas.translate(x, y);
        // Cây sào tre chìa ra phía trước đàn vịt.
        canvas.drawLine(Offset.zero, Offset(cos(facing) * 34 - sin(facing) * 6, sin(facing) * 34 + cos(facing) * 6), _pole);
        canvas.rotate(facing + pi / 2);
        _people[(g.s.abs() ~/ 7) % _people.length].render(canvas, position: Vector2(-12, -12), size: Vector2.all(24));
        canvas.restore();
      }
    }
  }
}
