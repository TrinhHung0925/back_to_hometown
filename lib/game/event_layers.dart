part of 've_que_game.dart';

/// Sương mù nhìn từ trên: quanh xe mình còn thấy, xa dần trắng đục.
class _FogLayer extends Component {
  _FogLayer(this.game) : super(priority: 13);

  final VeQueGame game;

  @override
  void render(Canvas canvas) {
    final fog = game._events.fog;
    if (fog < 0.02 || game._driverShown) return;
    final (x, y) = game.road.worldAt(game.player.s + game.dir * 60, game.player.d);
    final center = Offset(x, y);
    final r = game._events.visibility;
    final dim = 1 - 0.7 * game.nightLevel;
    final c = Color.fromRGBO((222 * dim).round(), (228 * dim).round(), (232 * dim).round(), 1);
    canvas.drawRect(
      Rect.fromCircle(center: center, radius: 6000),
      Paint()
        ..shader = Gradient.radial(center, r * 1.5, [
          c.withValues(alpha: 0),
          c.withValues(alpha: 0.35 * fog),
          c.withValues(alpha: 0.85 * fog),
          c.withValues(alpha: 0.97 * fog),
        ], const [
          0,
          0.4,
          0.72,
          1,
        ]),
    );
  }
}

/// Người xin đi nhờ, CSGT phân luồng chỗ tắc đường, cát gió thổi ngang
/// đường (nhìn từ trên).
class _EventProps extends Component {
  _EventProps(this.game) : super(priority: 5);

  final VeQueGame game;
  double _t = 0;

  static final Paint _image = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _shadow = Paint()..colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn);
  static final Paint _streak = Paint()
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    if (game._driverShown) return;
    final ev = game._events;
    final from = game._camLeftS - 100, to = game._camRightS + 100;
    for (final h in ev.hitches) {
      if (h.state == _HitchState.riding || h.standS < from || h.standS > to) continue;
      // Khách đã xuống xe thì đứng vẫy chào một lúc rồi đi.
      if (h.state == _HitchState.done && (game.player.s - h.standS).abs() > 900) continue;
      final img = game.images.fromCache(Img.people[(h.art * 3 + h.name.length) % Img.people.length]);
      final wave = sin(_t * 7) * 0.25;
      _draw(canvas, img, h.standS, h.side, 24, game.road.at(h.standS).heading + pi + wave);
    }
    final j = ev.jam;
    if (j != null && j.head > from && j.head < to) {
      final img = game.images.fromCache(Img.imgPoliceOfficerWave);
      _draw(canvas, img, j.head + 14, 0, 46, game.road.at(j.head).heading - pi / 2 + sin(_t * 4) * 0.3);
    }
    if (ev.gust > 0.05) {
      // Cát bị gió thổi bay ngang qua đường.
      final heading = game.road.at(game.player.s).heading;
      final across = Offset(-sin(heading), cos(heading)) * (-game.dir.toDouble());
      _streak.color = Color.fromRGBO(226, 210, 168, 0.55 * ev.gust);
      for (var i = 0; i < 22; i++) {
        final ks = ((i * 0.618) % 1) * 900 - 300;
        final kd = ((i * 0.382 + _t * 1.7) % 1) * 360 - 180;
        final (x, y) = game.road.worldAt(game.player.s + game.dir * ks, kd);
        final p = Offset(x, y);
        canvas.drawLine(p, p + across * 26, _streak);
      }
    }
  }

  void _draw(Canvas canvas, Image img, double s, double d, double size, double rotation) {
    final (x, y) = game.road.worldAt(s, d);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotation);
    canvas.drawImageRect(img, src, dst.shift(const Offset(3, 3)), _shadow);
    canvas.drawImageRect(img, src, dst, _image);
    canvas.restore();
  }
}

/// Cành đào buộc sau yên xe máy (nhìn từ trên): cành nâu, bông hồng — rụng
/// dần khi va quẹt, gió giật.
class _PeachBranch extends Component {
  _PeachBranch(this.game) : super(priority: 7);

  final VeQueGame game;

  static final Paint _wood = Paint()
    ..color = const Color(0xff6B4A32)
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;
  static final Paint _bloom = Paint();

  @override
  void render(Canvas canvas) {
    final health = game._events.peach;
    if (health < 0 || game._driverShown || game._riderOff || game.pushing) return;
    final back = game.player.s - game.dir * game.spec.length * 0.42;
    final (x, y) = game.road.worldAt(back, game.player.d);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(game.road.at(back).heading + (game.dir < 0 ? pi : 0) + game.player.yawOffset);
    // Cành chĩa ra sau, xoè hai bên.
    const branches = [(-26.0, -7.0), (-24.0, 6.0), (-18.0, -11.0), (-30.0, 1.0)];
    for (final (bx, by) in branches) {
      canvas.drawLine(Offset.zero, Offset(bx, by), _wood);
    }
    final shown = (health / 100 * 18).round();
    for (var i = 0; i < shown; i++) {
      final (bx, by) = branches[i % branches.length];
      final k = 0.45 + ((i * 0.37) % 0.55);
      final c = Offset(bx * k + ((i * 7) % 5 - 2), by * k + ((i * 11) % 5 - 2));
      _bloom.color = i.isEven ? const Color(0xffF4A3B8) : const Color(0xffE9809D);
      canvas.drawCircle(c, 2.3, _bloom);
    }
    canvas.restore();
  }
}
