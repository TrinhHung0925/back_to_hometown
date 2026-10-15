import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../../model/map_theme.dart';
import '../../model/trip.dart';
import '../../resource/app_resource.dart';
import '../game_config.dart';
import '../logic/road_layout.dart';
import '../logic/road_path.dart';
import 'world_paints.dart';

/// Hướng nắng chung cho mọi bóng đổ (toạ độ thế giới): nắng từ tây bắc.
const Offset sunShadow = Offset(9, 12);

/// Đổi một độ lệch theo toạ độ thế giới sang toạ độ riêng của component
/// đang xoay góc [angle].
Offset toLocal(Offset world, double angle) =>
    Offset(world.dx * cos(angle) + world.dy * sin(angle), -world.dx * sin(angle) + world.dy * cos(angle));

/// Cảnh hai bên đường, sinh dần phía trước và bỏ dần phía sau, theo loại
/// đường: phố (nhà ống san sát, mái bạt, cột điện), quốc lộ (ruộng, nhà rải
/// rác, cây, chuối), cao tốc (cây thưa sau hộ lan).
enum SceneryKind { tree, banana, house }

/// Một món cảnh ven đường theo toạ độ đường ([d] có dấu: dương là bên phải
/// chiều về quê) — góc nhìn ghế lái đọc để dựng lại bằng ảnh đứng.
class SceneryItem {
  const SceneryItem(this.kind, this.s, this.d, this.size, this.seed, {this.house, this.species});

  final SceneryKind kind;
  final double s;
  final double d;

  /// Cây: đường kính tán; nhà: bề ngang mặt tiền.
  final double size;
  final int seed;
  final House? house;

  /// Loài cây cho ảnh đứng ở góc nhìn ghế lái (tree_broad, palm_coconut,
  /// tree_casuarina, tree_pine, banana, bush…); null: không có ảnh đứng
  /// (thuyền, đá) hoặc cây thường.
  final String? species;
}

class SceneryLayer extends Component with HasGameReference<FlameGame> {
  SceneryLayer({required this.road, required this.layout, required this.paints, required this.random, this.theme = MapTheme.delta})
      : super(priority: 1);

  /// Bản đồ đã chọn: đổi loài cây, nhà cửa, thuyền ven quốc lộ.
  final MapTheme theme;

  final RoadPath road;
  final RoadLayout layout;
  final WorldPaints paints;
  final Random random;

  final List<(double, Component)> _items = [];

  /// Cảnh đang có (cùng vòng đời với [_items]).
  final List<SceneryItem> items = [];
  final Map<int, double> _next = {-1: 0, 1: 0};

  static const double _half = GameConfig.roadHalfWidth;
  static const double _sidewalk = GameConfig.sidewalkWidth;

  /// Sinh cảnh tới quá [toS]; giữ cảnh phía sau tới [keepFrom] (đi ngược
  /// lại sau khi quay đầu vẫn còn nguyên).
  void sync(double fromS, double toS, {double? keepFrom}) {
    for (final side in [-1, 1]) {
      var s = _next[side]!;
      if (s < fromS - 400) s = fromS - 400;
      while (s < toS + 300) {
        s = _spawn(side, s);
      }
      _next[side] = s;
    }
    final keep = keepFrom ?? fromS;
    items.removeWhere((item) => item.s < keep - 500);
    _items.removeWhere((item) {
      if (item.$1 >= keep - 500) return false;
      item.$2.removeFromParent();
      return true;
    });
  }

  /// Sinh một món cảnh ở [s] phía [side]; trả về quãng của món kế tiếp.
  double _spawn(int side, double s) {
    if (layout.nearFeature(s, margin: 20) || layout.nearStall(s, side, margin: 100)) {
      return s + 40;
    }
    return switch (layout.kindAt(s)) {
      RoadKind.city => _cityLot(side, s),
      RoadKind.highway => switch (theme) {
          MapTheme.coast => _coast(side, s),
          MapTheme.mountain => _mountain(side, s),
          MapTheme.mekong => _mekong(side, s),
          _ => _countryside(side, s),
        },
      RoadKind.expressway => _expresswayVerge(side, s),
    };
  }

  // ------------------------------------------------------------- Phố
  double _cityLot(int side, double s) {
    final width = 52 + random.nextDouble() * 40;
    // Thỉnh thoảng có ngõ nhỏ giữa hai nhà.
    if (random.nextDouble() < 0.1) return s + 18 + random.nextDouble() * 16;
    final front = _half + _sidewalk + random.nextDouble() * 6;
    if (layout.nearFeature(s + width / 2, margin: width / 2 + 10)) return s + 40;
    final bend = _bend(s + width / 2, side);
    final step = _lotStep(width, front, bend);
    final center = s + step / 2;
    final roof = _randomRoof(city: true);
    final awning = random.nextDouble() < 0.65 ? _awningColors[random.nextInt(_awningColors.length)] : null;
    final house = _house(
      width: width - 2,
      front: front,
      bend: bend,
      roof: roof,
      awning: awning,
      awningDepth: _sidewalk - 6 - random.nextDouble() * 8,
    );
    if (house != null) {
      _add(center, house, side, front);
      items.add(SceneryItem(SceneryKind.house, center, side * front, house.size.x, (center * 13).round() & 0xfffff, house: house));
    }
    // Cây trồng trên vỉa hè.
    if (random.nextDouble() < 0.22) {
      _tree(center + (random.nextDouble() - 0.5) * width * 0.6, side, _half + 16, 60 + random.nextDouble() * 40);
    }
    return s + step;
  }

  /// Độ cong của đường ở quãng [s] nhìn từ phía [side]: dương là phía này
  /// nằm trong khúc cua (gần tâm cong), âm là phía ngoài.
  double _bend(double s, int side) => road.at(s).curvature * side;

  /// Độ cong lớn nhất phía trong cua quanh [s] (± [span]); 0 nếu thẳng hay
  /// phía này nằm ngoài cua.
  double _innerBend(double s, int side, double span) =>
      [for (final x in [s - span, s, s + span]) _bend(x, side)].reduce(max).clamp(0.0, double.infinity);

  /// Bề ngang lô đất dọc tim đường để mặt tiền nhà rộng đúng [width]: trong
  /// khúc cua mặt tiền co lại, ngoài cua giãn ra.
  double _lotStep(double width, double front, double bend) => width / (1 - front * bend).clamp(0.4, 2.0);

  /// Nhà ở lô đất cách tim đường [front]. Phía trong khúc cua nhà nông hơn
  /// và thu hẹp dần về phía sau (lô đất hình thang); cua gắt quá thì bỏ trống.
  House? _house({
    required double width,
    required double front,
    required double bend,
    required RoofKind roof,
    required Color? awning,
    required double awningDepth,
  }) {
    var depth = House.fullDepth;
    var taper = 0.0;
    if (bend > 0) {
      final radius = 1 / bend;
      if (radius < GameConfig.minHouseRadius) return null;
      depth = min(depth, 0.35 * (radius - front));
      taper = bend / (1 - front * bend);
    }
    return House(
      paints: paints,
      images: game.images,
      width: width,
      depth: depth,
      taper: taper,
      roof: roof,
      awning: awning,
      awningDepth: awningDepth,
      seed: random.nextInt(1 << 20),
    );
  }

  static const List<Color> _awningColors = [
    Color(0xff2F6FB5),
    Color(0xffC8372D),
    Color(0xffE9822E),
    Color(0xff2E8B57),
    Color(0xffE7C33D),
    Color(0xff8E44AD),
  ];

  RoofKind _randomRoof({required bool city}) {
    final r = random.nextDouble();
    if (city) {
      if (r < 0.45) return RoofKind.flat;
      if (r < 0.75) return RoofKind.iron;
      return RoofKind.clay;
    }
    if (r < 0.5) return RoofKind.clay;
    if (r < 0.8) return RoofKind.iron;
    return RoofKind.flat;
  }

  // ---------------------------------------------------------- Quốc lộ
  double _countryside(int side, double s) {
    // Nhà ven quốc lộ tụ thành xóm; giữa các xóm là ruộng, cây, chuối.
    final village = sin(s / 2300 + side * 1.7) > 0.35;
    if (village && random.nextDouble() < 0.75) {
      final width = 56 + random.nextDouble() * 34;
      final front = _half + 64 + random.nextDouble() * 18;
      final bend = _bend(s + width / 2, side);
      final step = _lotStep(width, front, bend);
      final house = _house(
        width: width,
        front: front,
        bend: bend,
        roof: _randomRoof(city: false),
        awning: random.nextDouble() < 0.3 ? _awningColors[random.nextInt(_awningColors.length)] : null,
        awningDepth: 22,
      );
      if (house != null) {
        _add(s + step / 2, house, side, front);
        items.add(SceneryItem(SceneryKind.house, s + step / 2, side * front, house.size.x, (s * 13).round() & 0xfffff, house: house));
      }
      if (random.nextDouble() < 0.5) {
        _sprite(Img.bananas[random.nextInt(2)], s + step + 10, side, front + 20 + random.nextDouble() * 40, 54 + random.nextDouble() * 20,
            kind: SceneryKind.banana);
      }
      return s + step + 10 + random.nextDouble() * 40;
    }
    // Quanh xóm có lũy tre; ngoài đồng cây bóng mát, xoài, bụi chuối.
    final roll = random.nextDouble();
    final nearVillage = sin(s / 2300 + side * 1.7) > 0.05;
    if (nearVillage && roll < 0.4) {
      _pick(Img.bambooTops, s, side, _half + 80 + random.nextDouble() * 70, 100 + random.nextDouble() * 45, 'tree_bamboo');
    } else if (roll < 0.62) {
      _tree(s, side, _half + 80 + random.nextDouble() * 90, 70 + random.nextDouble() * 70);
    } else if (roll < 0.76) {
      _pick(Img.mangoes, s, side, _half + 85 + random.nextDouble() * 100, 90 + random.nextDouble() * 40, 'tree_broad');
    } else if (roll < 0.92) {
      _sprite(Img.bananas[random.nextInt(2)], s, side, _half + 75 + random.nextDouble() * 60, 50 + random.nextDouble() * 24,
          kind: SceneryKind.banana);
    }
    return s + 50 + random.nextDouble() * 150;
  }

  // ------------------------------------------------------- Ven biển
  double _coast(int side, double s) {
    final r = random.nextDouble();
    if (side > 0) {
      // Bãi cát: rặng phi lao sát đường, thúng chai phơi trên cát, dưới nước.
      if (r < 0.55) {
        _pick(Img.casuarinas, s, side, _half + 44 + random.nextDouble() * 34, 64 + random.nextDouble() * 40, 'tree_casuarina');
      } else if (r < 0.75) {
        _pick(Img.basketBoats, s, side, _half + 70 + random.nextDouble() * 150, 44 + random.nextDouble() * 8, null);
      }
      return s + 34 + random.nextDouble() * 80;
    }
    // Đất liền: rặng phi lao dày, thỉnh thoảng xóm chài mái tôn.
    final village = sin(s / 2600 + 0.4) > 0.55;
    if (village && r < 0.6) return _villageHouse(side, s, RoofKind.iron);
    _pick(Img.casuarinas, s, side, _half + 60 + random.nextDouble() * 110, 70 + random.nextDouble() * 50, 'tree_casuarina');
    return s + 26 + random.nextDouble() * 60;
  }

  // -------------------------------------------------------- Đèo núi
  double _mountain(int side, double s) {
    final r = random.nextDouble();
    if (side > 0) {
      // Ngọn thông dưới vực, thưa dần.
      if (r < 0.6) _pick(Img.pines, s, side, _half + 60 + random.nextDouble() * 170, 80 + random.nextDouble() * 45, 'tree_pine');
      return s + 40 + random.nextDouble() * 110;
    }
    // Trên đỉnh vách đá: thông; chân vách: đá lở.
    if (r < 0.6) {
      _pick(Img.pines, s, side, _half + 105 + random.nextDouble() * 110, 85 + random.nextDouble() * 45, 'tree_pine');
    } else if (r < 0.75) {
      _pick(Img.rocks, s, side, _half + 22 + random.nextDouble() * 12, 16 + random.nextDouble() * 14, null);
    }
    return s + 36 + random.nextDouble() * 90;
  }

  // ------------------------------------------------------ Sông nước
  double _mekong(int side, double s) {
    final r = random.nextDouble();
    if (side > 0) {
      // Dừa nước hai bờ kênh, xuồng ba lá dưới kênh, vườn dừa bên kia.
      if (r < 0.45) {
        // Bờ gần sát đường thì khóm nhỏ, bờ bên kia khóm to.
        final far = random.nextBool();
        _pick(Img.palmsNipa, s, side, far ? _half + 156 : _half + 46, far ? 110 + random.nextDouble() * 40 : 72 + random.nextDouble() * 20, 'banana');
      } else if (r < 0.55) {
        _pick(Img.sampans, s, side, _half + 75 + random.nextDouble() * 40, 105 + random.nextDouble() * 15, null, aligned: true);
      } else if (r < 0.85) {
        _pick(Img.palmsCoconut, s, side, _half + 185 + random.nextDouble() * 80, 110 + random.nextDouble() * 35, 'palm_coconut');
      }
      return s + 30 + random.nextDouble() * 60;
    }
    final village = sin(s / 2100 + 1.1) > 0.3;
    if (village && r < 0.6) return _villageHouse(side, s, r < 0.3 ? RoofKind.clay : RoofKind.iron);
    if (r < 0.75) {
      _pick(Img.palmsCoconut, s, side, _half + 85 + random.nextDouble() * 110, 110 + random.nextDouble() * 35, 'palm_coconut');
    } else if (r < 0.88) {
      _sprite(Img.bananas[random.nextInt(2)], s, side, _half + 75 + random.nextDouble() * 60, 50 + random.nextDouble() * 24, kind: SceneryKind.banana);
    } else {
      _pick(Img.mangoes, s, side, _half + 90 + random.nextDouble() * 100, 90 + random.nextDouble() * 40, 'tree_broad');
    }
    return s + 40 + random.nextDouble() * 120;
  }

  /// Nhà một tầng ven quốc lộ (xóm chài, xóm vườn).
  double _villageHouse(int side, double s, RoofKind roof) {
    final width = 52 + random.nextDouble() * 30;
    final front = _half + 64 + random.nextDouble() * 18;
    final bend = _bend(s + width / 2, side);
    final step = _lotStep(width, front, bend);
    final house = _house(width: width, front: front, bend: bend, roof: roof, awning: null, awningDepth: 22);
    if (house != null) {
      _add(s + step / 2, house, side, front);
      items.add(SceneryItem(SceneryKind.house, s + step / 2, side * front, house.size.x, (s * 13).round() & 0xfffff, house: house));
    }
    return s + step + 20 + random.nextDouble() * 50;
  }

  /// Một cây / thuyền ngẫu nhiên trong [paths] (ảnh chưa nạp thì bỏ qua).
  void _pick(List<String> paths, double s, int side, double d, double size, String? species, {bool aligned = false}) {
    final path = paths[random.nextInt(paths.length)];
    if (!game.images.containsKey(path)) return;
    _sprite(path, s, side, d, size, species: species, aligned: aligned, upright: species != null);
  }

  // ----------------------------------------------------------- Cao tốc
  double _expresswayVerge(int side, double s) {
    if (random.nextDouble() < 0.6) {
      _tree(s, side, _half + 110 + random.nextDouble() * 120, 80 + random.nextDouble() * 60);
    }
    return s + 120 + random.nextDouble() * 260;
  }

  // ------------------------------------------------------------- Đặt
  void _tree(double s, int side, double d, double size) {
    final path = Img.trees[random.nextInt(Img.trees.length)];
    _sprite(path, s, side, d, size);
  }

  void _sprite(String path, double s, int side, double d, double size,
      {SceneryKind kind = SceneryKind.tree, String? species, bool aligned = false, bool upright = true}) {
    // Phía trong khúc cua gắt: không mọc lấn qua tâm cong sang đường.
    final inner = _innerBend(s, side, size);
    if (inner > 0 && (d + size / 2) * inner > 0.8) return;
    if (layout.nearStall(s, side, margin: size / 2)) return;
    final c = ShadowedSprite(
      sprite: Sprite(game.images.fromCache(path)),
      size: Vector2.all(size),
      // Thuyền dưới kênh nằm dọc theo bờ; cây thì xoay bất kỳ.
      angle: aligned ? road.at(s).heading + pi / 2 + (random.nextDouble() - 0.5) * 0.3 : random.nextDouble() * pi * 2,
      shadowLength: size * 0.12,
    );
    final (x, y) = road.worldAt(s, side * d);
    c.position.setValues(x, y);
    c.priority = 2;
    add(c);
    _items.add((s, c));
    // Thuyền, đá nằm sát đất: góc nhìn ghế lái không dựng thành ảnh đứng.
    if (upright) items.add(SceneryItem(kind, s, side * d, size, (s * 7).round() & 0xfffff, species: species));
  }

  void _add(double s, PositionComponent c, int side, double d) {
    final (x, y) = road.worldAt(s, side * d);
    c.position.setValues(x, y);
    // Mặt tiền quay ra đường: trục y riêng của nhà hướng ra xa đường.
    c.angle = road.at(s).heading + (side > 0 ? 0 : pi);
    add(c);
    _items.add((s, c));
  }
}

/// Sprite có bóng đổ theo hướng nắng chung.
class ShadowedSprite extends SpriteComponent {
  ShadowedSprite({required Sprite sprite, required Vector2 size, required double angle, required this.shadowLength})
      : super(sprite: sprite, size: size, angle: angle, anchor: Anchor.center);

  final double shadowLength;

  static final Paint _shadowPaint = Paint()
    ..colorFilter = const ColorFilter.mode(Color(0x66000000), BlendMode.srcIn)
    ..filterQuality = FilterQuality.low;

  @override
  void render(Canvas canvas) {
    final o = toLocal(sunShadow * (shadowLength / 12), angle);
    sprite?.render(canvas, position: Vector2(o.dx, o.dy), size: size, overridePaint: _shadowPaint);
    super.render(canvas);
  }
}

enum RoofKind { clay, iron, flat }

/// Nhà nhìn từ trên xuống: mái ngói (2 mái, có nóc), mái tôn (màu), hoặc mái
/// bằng (bê tông, bồn nước inox, tum cầu thang). Có thể có mái bạt che vỉa hè.
/// Gốc toạ độ ở giữa mặt tiền; trục y hướng ra xa đường.
class House extends PositionComponent {
  House({
    required this.paints,
    required this.images,
    required double width,
    required this.roof,
    required this.awning,
    required this.awningDepth,
    required int seed,
    double depth = fullDepth,
    this.taper = 0,
  })  : _random = Random(seed),
        super(size: Vector2(width, depth), priority: 3) {
    _iron = paints.roofIron[_random.nextInt(paints.roofIron.length)];
    _tank = _random.nextDouble() < 0.75;
    _tankX = (_random.nextDouble() - 0.5) * (width - 40);
    _tankY = 30 + _random.nextDouble() * 50;
    _stair = _random.nextDouble() < 0.5;
    _clayDark = _random.nextBool();
    _striped = _random.nextDouble() < 0.35;
    final tone = 0.82 + _random.nextDouble() * 0.3;
    _flatTint = Paint()
      ..color = Color.fromRGBO(
        tone < 1 ? 0 : 255,
        tone < 1 ? 0 : 240,
        tone < 1 ? 0 : 210,
        (tone - 1).abs() * 0.9,
      );
  }

  /// Chiều sâu nhà (từ mặt tiền ra sau) khi đường thẳng.
  static const double fullDepth = 320;

  final WorldPaints paints;
  final Images images;
  final RoofKind roof;

  /// Nhà phía trong khúc cua: bề ngang co lại theo chiều sâu (mỗi đơn vị sâu
  /// co [taper] phần) để nhà kề nhau không đè lên nhau.
  final double taper;
  final Color? awning;
  final double awningDepth;
  final Random _random;
  late final Paint _iron;
  late final bool _tank;
  late final double _tankX;
  late final double _tankY;
  late final bool _stair;
  late final bool _clayDark;
  late final bool _striped;
  late final Paint _flatTint;

  static final Paint _shadow = Paint()..color = const Color(0x52000000);
  static final Paint _shade = Paint()..color = const Color(0x2A000000);
  static final Paint _light = Paint()..color = const Color(0x1AFFFFFF);
  static final Paint _ridge = Paint()..color = const Color(0xff7A3E2A);
  static final Paint _parapet = Paint()
    ..color = const Color(0x55FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _innerShade = Paint()
    ..color = const Color(0x30000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final Paint _white = Paint()..color = const Color(0xD9F4F4F2);
  static final Paint _edge = Paint()
    ..color = const Color(0x66000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final body = Rect.fromLTWH(-w / 2, 0, w, size.y);
    if (taper > 0) {
      final back = w / 2 * (1 - size.y * taper);
      final front = w / 2 * (1 + awningDepth * taper);
      canvas.save();
      canvas.clipPath(Path()
        ..addPolygon([
          Offset(-front - 8, -awningDepth - 2),
          Offset(front + 8, -awningDepth - 2),
          Offset(back, size.y + 30),
          Offset(-back, size.y + 30),
        ], true));
      _paint(canvas, w, body);
      canvas.restore();
    } else {
      _paint(canvas, w, body);
    }
  }

  void _paint(Canvas canvas, double w, Rect body) {
    // Bóng đổ của nhà và mái bạt.
    final o = toLocal(sunShadow * 1.6, angle);
    canvas.drawRect(body.shift(o), _shadow);

    switch (roof) {
      case RoofKind.clay:
        canvas.drawRect(body, _clayDark ? paints.roofClayDark : paints.roofClay);
        // Hai mái dốc: nửa xa nắng tối hơn, nóc ở giữa.
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, size.y), _shade);
        canvas.drawRect(Rect.fromLTWH(-w / 2, 0, w / 2, size.y), _light);
        canvas.drawRect(Rect.fromLTWH(-2.5, 0, 5, size.y), _ridge);
      case RoofKind.iron:
        canvas.drawRect(body, _iron);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, size.y), _shade);
      case RoofKind.flat:
        canvas.drawRect(body, paints.roofFlat);
        canvas.drawRect(body, _flatTint);
        // Tường chắn mái: mép sáng, bóng đổ vào trong mặt sàn mái.
        canvas.drawRect(body.deflate(1), _parapet);
        canvas.drawRect(body.deflate(3.5), _innerShade);
        if (_stair) {
          final stair = Rect.fromLTWH(-w / 2 + 6, 70, w * 0.45, 46);
          canvas.drawRect(stair.shift(toLocal(sunShadow * 0.7, angle)), _shadow);
          canvas.drawRect(stair, _iron);
        }
        if (_tank) {
          final img = images.fromCache(Img.imgWaterTank);
          final dst = Rect.fromCenter(center: Offset(_tankX, _tankY), width: 34, height: 14);
          canvas.drawRect(dst.shift(toLocal(sunShadow * 0.5, angle)), _shadow);
          canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _image);
        }
    }
    canvas.drawRect(body, _edge);

    final a = awning;
    if (a != null) {
      final rect = Rect.fromLTWH(-w / 2 + 3, -awningDepth, w - 6, awningDepth);
      canvas.drawRect(rect.shift(toLocal(sunShadow * 0.6, angle)), _shadow);
      canvas.drawRect(rect, Paint()..color = a);
      if (_striped) {
        // Bạt sọc: các dải trắng xen màu chạy từ nhà ra đường.
        for (var x = rect.left + 4; x < rect.right; x += 12) {
          canvas.drawRect(Rect.fromLTWH(x, rect.top, 6, rect.height), _white);
        }
      }
      // Bạt dốc ra phía đường và võng ở giữa: sáng ở mép nhà, tối ở mép ngoài.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(rect.bottomCenter, rect.topCenter, const [Color(0x22FFFFFF), Color(0x00000000), Color(0x40000000)], const [0, 0.5, 1]),
      );
      canvas.drawRect(rect, _edge);
    }
  }
}

/// Cột điện bê tông và ba sợi dây điện chạy dọc một bên đường (vẽ trên cùng
/// vì ở trên cao, có bóng dây in xuống mặt đất).
class PowerLines extends Component {
  PowerLines({required this.road}) : super(priority: 9);

  final RoadPath road;
  final List<(double, double)> _poles = [];

  /// Cột điện đang có: (s, d).
  List<(double, double)> get poles => _poles;

  static final Paint _wire = Paint()
    ..color = const Color(0xff1E2124)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1;
  static final Paint _wireShadow = Paint()
    ..color = const Color(0x22000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  static final Paint _pole = Paint()..color = const Color(0xffA9A69F);
  static final Paint _poleEdge = Paint()..color = const Color(0xff5F5C57);
  static final Paint _arm = Paint()..color = const Color(0xff6B6F74);

  void sync(double fromS, double toS, RoadLayout layout, {double? keepFrom}) {
    _poles.removeWhere((p) => p.$1 < (keepFrom ?? fromS) - 400);
    var s = _poles.isEmpty ? (fromS / 180).floor() * 180.0 - 360 : _poles.last.$1 + 180;
    while (s < toS + 400) {
      final kind = layout.kindAt(s);
      // Cột điện ở lề trái: chừa chỗ cho quán phía bên đó.
      if (kind != RoadKind.expressway && !layout.nearStall(s, -1, margin: 10)) {
        final d = kind == RoadKind.city
            ? -(GameConfig.roadHalfWidth + 12)
            : -(GameConfig.roadHalfWidth + 40);
        _poles.add((s, d));
      }
      s += 180;
    }
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i + 1 < _poles.length; i++) {
      final (s0, d0) = _poles[i];
      final (s1, d1) = _poles[i + 1];
      if (s1 - s0 > 200) continue;
      for (final off in [-9.0, 0.0, 9.0]) {
        final (x0, y0) = road.worldAt(s0, d0 + off);
        final (x1, y1) = road.worldAt(s1, d1 + off);
        canvas.drawLine(Offset(x0, y0) + sunShadow * 2.4, Offset(x1, y1) + sunShadow * 2.4, _wireShadow);
        // Dây võng xuống giữa nhịp (nhìn từ trên thấy hơi lệch).
        final mid = Offset((x0 + x1) / 2, (y0 + y1) / 2 + 3);
        final path = Path()
          ..moveTo(x0, y0)
          ..quadraticBezierTo(mid.dx, mid.dy, x1, y1);
        canvas.drawPath(path, _wire);
      }
    }
    for (final (s, d) in _poles) {
      final p = road.at(s);
      final (x, y) = road.worldAt(s, d);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      canvas.drawRect(const Rect.fromLTWH(-2, -13, 4, 26), _arm);
      canvas.drawCircle(Offset.zero, 4.6, _poleEdge);
      canvas.drawCircle(Offset.zero, 3.6, _pole);
      canvas.restore();
    }
  }
}
