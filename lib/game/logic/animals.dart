import 'dart:math';

import '../game_config.dart';
import 'collision.dart';
import 'traffic_system.dart';

enum AnimalKind {
  /// Đàn vịt lạch bạch nối đuôi nhau qua đường, có người chăn cầm sào.
  duck,

  /// Gà chạy ngang, lúc khựng lại, có con quay đầu chạy ngược.
  chicken,

  /// Chó chạy rông lao qua đường, có khi đứng giữa đường nhìn.
  dog;

  /// Hộp va chạm (dọc đường × ngang đường) và cỡ hình vẽ.
  double get length => switch (this) { duck => 12, chicken => 12, dog => 14 };
  double get width => switch (this) { duck => 14, chicken => 13, dog => 28 };
  /// Vẽ to hơn kích thước thật một chút cho dễ thấy (như xe máy).
  double get drawSize => switch (this) { duck => 21, chicken => 21, dog => 35 };

  /// Tốc độ đi qua đường bình thường / khi bị bóp còi (u/s).
  double get walk => switch (this) { duck => 24, chicken => 52, dog => 66 };
  double get flee => switch (this) { duck => 80, chicken => 125, dog => 150 };
}

class Animal {
  Animal({required this.kind, required this.s, required this.d, required this.dir, required this.variant, this.delay = 0});

  final AnimalKind kind;
  double s;
  double d;

  /// Chiều đang chạy ngang đường: 1 về phía d dương, -1 ngược lại.
  int dir;
  final int variant;

  /// Còn đứng chờ bao lâu mới bước (vịt đi sau chờ con trước).
  double delay;

  /// Đang khựng lại giữa đường (gà, chó).
  double pause = 0;

  /// Bị bóp còi / bị xe quệt: chạy thục mạng, vỗ cánh.
  bool fleeing = false;
  bool struck = false;
  bool turnedBack = false;
  double t = 0;

  /// Lệch dọc đường khi đi (vịt đi lạch bạch không thẳng hàng).
  double sway = 0;

  RoadBox get box => RoadBox(s: s, d: d, length: kind.length, width: kind.width);
}

/// Một đợt con vật qua đường ở quãng [s].
class AnimalGroup {
  AnimalGroup({required this.kind, required this.s, required this.dir, required this.animals, this.herder});

  final AnimalKind kind;
  final double s;

  /// Chiều qua đường (1: từ bên d âm sang bên d dương).
  final int dir;
  final List<Animal> animals;

  /// Người chăn vịt đi sau đàn (d), null nếu không có.
  double? herder;

  /// Đã báo trên HUD chưa; đã phải đền tiền chưa (mỗi đàn một lần).
  bool announced = false;
  bool fined = false;

  bool get onRoad => animals.any((a) => a.d.abs() < GameConfig.roadHalfWidth + 8);

  /// Con nào cũng đã sang hẳn bên kia (hoặc chạy khỏi đường).
  bool get done => animals.every((a) => a.d.abs() > GameConfig.roadHalfWidth + 70);

  double get minS => animals.fold(s, (m, a) => min(m, a.s - a.kind.length));
  double get maxS => animals.fold(s, (m, a) => max(m, a.s + a.kind.length));
}

/// Gà vịt chó qua đường trên quốc lộ: sinh ra ngay ngoài khung nhìn phía
/// trước, đi ngang qua đường; bóp còi thì chạy tán loạn; xe AI dừng chờ.
class AnimalSystem {
  AnimalSystem(this._random);

  final Random _random;
  final List<AnimalGroup> groups = [];

  static const double _edge = GameConfig.roadHalfWidth;

  /// Thả một đợt con vật ở quãng [s], qua đường theo chiều [dir].
  AnimalGroup spawn(AnimalKind kind, double s, int dir) {
    final start = -dir * (_edge + 26);
    final animals = <Animal>[];
    switch (kind) {
      case AnimalKind.duck:
        // Đàn 6–11 con nối đuôi, con sau chờ con trước một chút.
        final n = 6 + _random.nextInt(6);
        final variant = _random.nextInt(3) == 0 ? 1 : 0;
        for (var i = 0; i < n; i++) {
          animals.add(Animal(
            kind: kind,
            s: s + (_random.nextDouble() - 0.5) * 22,
            d: start - dir * i * 11,
            dir: dir,
            variant: _random.nextInt(4) == 0 ? 1 - variant : variant,
            delay: i * 0.08,
          )..t = _random.nextDouble() * 5);
        }
      case AnimalKind.chicken:
        final n = 1 + _random.nextInt(3);
        for (var i = 0; i < n; i++) {
          animals.add(Animal(
            kind: kind,
            s: s + (_random.nextDouble() - 0.5) * 40,
            d: start - dir * _random.nextDouble() * 20,
            dir: dir,
            variant: _random.nextInt(2),
            delay: _random.nextDouble() * 0.8,
          ));
        }
      case AnimalKind.dog:
        animals.add(Animal(kind: kind, s: s, d: start, dir: dir, variant: 0));
    }
    final group = AnimalGroup(
      kind: kind,
      s: s,
      dir: dir,
      animals: animals,
      herder: kind == AnimalKind.duck ? animals.last.d - dir * 22 : null,
    );
    groups.add(group);
    return group;
  }

  void update(double dt) {
    for (final g in groups) {
      for (final a in g.animals) {
        a.t += dt;
        if (a.delay > 0) {
          a.delay -= dt;
          continue;
        }
        if (a.pause > 0 && !a.fleeing) {
          a.pause -= dt;
          continue;
        }
        final speed = a.fleeing ? a.kind.flee : a.kind.walk;
        a.d += a.dir * speed * dt;
        switch (a.kind) {
          case AnimalKind.duck:
            a.sway = sin(a.t * 9) * 1.6;
            if (a.fleeing) a.s += (_random.nextDouble() - 0.5) * 40 * dt;
          case AnimalKind.chicken:
            final inRoad = a.d.abs() < _edge - 10;
            if (!a.fleeing && inRoad && _random.nextDouble() < dt * 0.9) a.pause = 0.3 + _random.nextDouble() * 0.6;
            // Gà hay quay đầu chạy ngược lại giữa đường.
            if (!a.fleeing && !a.turnedBack && inRoad && a.dir * a.d > -10 && _random.nextDouble() < dt * 0.5) {
              a.turnedBack = true;
              a.dir = -a.dir;
            }
          case AnimalKind.dog:
            if (!a.fleeing && a.d.abs() < 25 && a.pause <= 0 && !a.turnedBack && _random.nextDouble() < 0.4) {
              a.turnedBack = true; // chỉ đứng lại một lần
              a.pause = 1.2 + _random.nextDouble();
            } else if (a.d.abs() < 25) {
              a.turnedBack = true;
            }
        }
      }
      final h = g.herder;
      if (h != null) {
        // Người chăn đi sau đàn, cách con vịt cuối chừng 20.
        final last = g.animals.map((a) => a.d * g.dir).reduce(min) * g.dir;
        final gap = (last - g.dir * 20 - h) * g.dir;
        if (gap > 0) g.herder = h + g.dir * min(gap, AnimalKind.duck.walk * 1.2 * dt);
      }
    }
    groups.removeWhere((g) => g.done && (g.herder == null || g.herder!.abs() > _edge + 60));
  }

  /// Bóp còi: con vật trong tầm phía trước giật mình chạy nhanh. Trả về đợt
  /// con vật bị doạ (null nếu không có).
  AnimalGroup? scare(double playerS, int playerDir, double reach) {
    AnimalGroup? hit;
    for (final g in groups) {
      final ahead = (g.s - playerS) * playerDir;
      if (ahead < -40 || ahead > reach || !g.onRoad) continue;
      for (final a in g.animals) {
        if (a.fleeing) continue;
        a.fleeing = true;
        a.pause = 0;
        a.delay = min(a.delay, 0.05);
        // Chạy về phía lề gần nhất.
        if (a.kind != AnimalKind.duck && a.d.abs() > 6) a.dir = a.d > 0 ? 1 : -1;
      }
      hit = g;
    }
    return hit;
  }

  /// Con vật đụng phải hộp xe [box] (mỗi con chỉ tính một lần).
  Animal? hit(RoadBox box) {
    for (final g in groups) {
      for (final a in g.animals) {
        if (a.struck || a.delay > 0) continue;
        if (!a.box.overlaps(box, shrink: 0.85)) continue;
        a
          ..struck = true
          ..fleeing = true
          ..pause = 0
          ..dir = a.d > box.d ? 1 : -1;
        return a;
      }
    }
    return null;
  }

  /// Xe AI dừng chờ đàn đang qua (cả hai chiều).
  Iterable<StopPoint> stops() sync* {
    for (final g in groups) {
      if (!g.onRoad) continue;
      yield StopPoint(s: g.minS - 34, forward: true);
      yield StopPoint(s: g.maxS + 34, forward: false);
    }
  }

  void clearNear(double s, double range) => groups.removeWhere((g) => (g.s - s).abs() < range);
}
