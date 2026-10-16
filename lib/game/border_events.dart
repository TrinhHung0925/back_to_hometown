part of 've_que_game.dart';

/// Đất nước dọc đường về quê: qua cổng chào thì báo đã vào địa phận tỉnh
/// mới; quán ven đường bày bán đặc sản của tỉnh đang đi qua, chủ quán mời,
/// ăn xong tả hương vị.
class _Culture {
  _Culture(this.g);

  final VeQueGame g;

  List<BorderGate> get gates => g.layout.gates;

  /// Tỉnh ở đầu chặng (trước cổng chào đầu tiên).
  late final String? origin = gates.isNotEmpty
      ? gates.first.from
      : Provinces.ofStop(g.setup.fromName) ?? Provinces.ofStop(g.setup.toName);

  double? _lastS;

  /// Tỉnh ở quãng [s] của chặng.
  String? provinceAt(double s) {
    var p = origin;
    for (final gate in gates) {
      if (s < gate.s) break;
      p = gate.to;
    }
    return p;
  }

  /// Chạy qua cổng chào (cả lúc đi ngược lại sau khi quay đầu) thì báo —
  /// báo sớm một chút (đầu xe sắp chui qua cổng) cho kịp lượt thông báo.
  void step() {
    final s = g.player.s + g.dir * _early;
    final prev = _lastS;
    _lastS = s;
    if (prev == null || (s - prev).abs() > 600) return;
    for (final gate in gates) {
      if (prev < gate.s && s >= gate.s) _entered(gate, gate.to);
      if (prev > gate.s && s <= gate.s) _entered(gate, gate.from);
    }
  }

  static const double _early = 140;

  void _entered(BorderGate gate, String name) {
    final p = Provinces.byName(name);
    if (p == null) return;
    final foods = [for (final sp in p.specialties.take(2)) _lower(sp.item.name)];
    final offer = foods.isEmpty ? '' : ' Quán ven đường có ${foods.join(', ')} — ghé nếm thử nhé!';
    g._notice('gate${gate.s.round()}/${g.dir}', 'Đã vào địa phận ${p.title}!$offer', NoticeKind.info);
  }

  /// Chữ đầu viết thường (tên món đứng giữa câu), trừ khi là tên riêng.
  static String _lower(String name) => name.isEmpty ? name : name[0].toLowerCase() + name.substring(1);

  /// Đặc sản quán [stall] bày bán (theo tỉnh chỗ quán đứng).
  List<Specialty> at(Stall stall) => Provinces.at(provinceAt(stall.s), stall.kind, seed: stall.seed);

  /// Chuyện ở quán: chủ quán mời món đặc sản (chen vào sau câu chào).
  List<String> withPitch(Stall stall, List<String> lines) {
    final specials = at(stall);
    if (specials.isEmpty) return lines;
    final owner = stall.owner.isEmpty ? 'Chủ quán' : stall.owner;
    final pitch = '$owner: ${specials[stall.seed % specials.length].pitch}';
    return [...lines.take(1), pitch, ...lines.skip(1)];
  }

  /// Vừa gọi món đặc sản: tả hương vị.
  void tasted(StallItem item) {
    final sp = Provinces.specialtyOf(item);
    if (sp == null) return;
    final p = Provinces.provinceOf(item);
    g.onNotice(GameNotice(p == null ? sp.taste : 'Đặc sản ${p.nickname}: ${sp.taste}'));
  }
}

/// Đặc sản, tỉnh dọc chặng cho tầng giao diện (bảng quán).
extension VeQueCulture on VeQueGame {
  /// Món đặc sản quán [stall] bán thêm (gọi bằng [VeQueGame.order]).
  List<StallItem> specialtiesAt(Stall stall) => [for (final sp in _culture.at(stall)) sp.item];

  /// Tỉnh đang đi qua.
  String? get provinceNow => _culture.provinceAt(player.s);

  /// Cổng chào tỉnh trên chặng (để thử).
  List<double> get borderGateSpots => [for (final g in layout.gates) g.s];
}

/// Cổng chào tỉnh nhìn từ trên: hai trụ có mũ mái, xà ngang lợp ngói đỏ
/// nóc vàng bắc qua đường, bóng đổ xuống mặt đường.
class _GateLayer extends Component {
  _GateLayer(this.game) : super(priority: 8);

  final VeQueGame game;

  static const double _half = GameConfig.roadHalfWidth;

  /// Tim trụ (theo d) và nửa cạnh trụ, nửa bề dày xà (theo s).
  static const double pillarD = _half + 36;
  static const double pillarHalf = 17;
  static const double beamHalf = 11;

  static final Paint _shadow = Paint()..color = const Color(0x3D000000);
  static final Paint _gold = Paint()..color = const Color(0xffE2B33F);
  static final Paint _goldLine = Paint()
    ..color = const Color(0xffF2C94C)
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;
  static final Paint _trim = Paint()
    ..color = const Color(0xffD9A93A)
    ..strokeWidth = 2.2;
  static final Paint _red = Paint()..color = const Color(0xffB3261E);
  static final Paint _stone = Paint()..color = const Color(0xffB8B1A4);
  static final Paint _shade = Paint()..color = const Color(0x47000000);
  static final Paint _light = Paint()..color = const Color(0x2BFFFFFF);
  static final Paint _edge = Paint()
    ..color = const Color(0x66000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void render(Canvas canvas) {
    if (game._driverShown) return;
    final from = game._camLeftS - 200, to = game._camRightS + 200;
    for (final g in game.layout.gates) {
      if (g.s < from || g.s > to) continue;
      final p = game.road.at(g.s);
      final (x, y) = game.road.worldAt(g.s, 0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.heading);
      // Hệ toạ độ riêng: x dọc đường (chiều về quê), y sang phải.
      final sh = toLocal(sunShadow * 3.2, p.heading);
      final beam = Rect.fromLTRB(-beamHalf - 9, -pillarD, beamHalf + 9, pillarD);
      canvas.drawRect(beam.shift(sh), _shadow);
      for (final side in const [-1.0, 1.0]) {
        final base = Rect.fromCenter(center: Offset(0, side * pillarD), width: 2 * pillarHalf + 12, height: 2 * pillarHalf + 12);
        canvas.drawRect(base.shift(sh * 1.25), _shadow);
      }
      // Mái xà ngang: hai mái dốc về hai phía, nóc vàng chạy ngang đường.
      final roof = Rect.fromLTRB(-beamHalf - 9, -pillarD + pillarHalf, beamHalf + 9, pillarD - pillarHalf);
      canvas.drawRect(roof, game._paints.roofClayDark);
      canvas.drawRect(Rect.fromLTRB(roof.left, roof.top, 0, roof.bottom), _light);
      canvas.drawRect(Rect.fromLTRB(0, roof.top, roof.right, roof.bottom), _shade);
      canvas.drawRect(Rect.fromLTRB(-1.8, roof.top, 1.8, roof.bottom), _gold);
      // Diềm mái vàng hai mép.
      canvas.drawLine(roof.topLeft, roof.bottomLeft, _trim);
      canvas.drawLine(roof.topRight, roof.bottomRight, _trim);
      // Lưỡng long chầu nhật giữa nóc.
      canvas.drawCircle(Offset.zero, 4.2, _red);
      canvas.drawCircle(Offset.zero, 2.6, _gold);
      for (final k in const [-1.0, 1.0]) {
        canvas.drawLine(Offset(0, k * 7), Offset(0, k * 26), _goldLine);
      }
      canvas.drawRect(roof, _edge);
      for (final side in const [-1.0, 1.0]) {
        final c = Offset(0, side * pillarD);
        final cap = Rect.fromCenter(center: c, width: 2 * pillarHalf + 12, height: 2 * pillarHalf + 12);
        canvas.drawRect(cap.inflate(2), _stone);
        canvas.drawRect(cap, game._paints.roofClayDark);
        // Mũ trụ mái bốn dốc: bờ chảy vàng từ bốn góc lên chóp.
        for (final corner in [cap.topLeft, cap.topRight, cap.bottomLeft, cap.bottomRight]) {
          canvas.drawLine(corner, c, _goldLine);
        }
        canvas.drawRect(Rect.fromLTRB(cap.left, cap.top, c.dx, cap.bottom), _light);
        canvas.drawCircle(c, 3.4, _gold);
        canvas.drawRect(cap, _edge);
      }
      canvas.restore();
    }
  }
}
