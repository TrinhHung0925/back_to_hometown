part of 've_que_game.dart';

/// Radio trên xe ("Radio Giao thông"): cứ chừng 35–60 giây lái lại phát nhạc
/// hiệu và một bản tin. Tin đường lấy từ chính chặng đang chạy — đoạn tắc,
/// sương mù trên đèo, cơn mưa sắp tới, bến phà, đường cứu nạn — để người
/// chơi kịp chuẩn bị; xen giữa là giờ giao thừa, thời tiết, lời chúc của
/// thính giả, lời nhắc an toàn (chọn ở [RadioDesk]).
class _Radio {
  _Radio(this.g);

  final VeQueGame g;
  late final Random _r = Random(g.setup.seed * 67 + 13);
  late final RadioDesk desk = RadioDesk(_r);
  late double _next = RadioDesk.firstDelay(_r);

  void step(double dt) {
    if (!g.radioOn || !g.fatigue || g.setup.tutorial || g.phase != GamePhase.driving) return;
    // Đang nghe điện thoại thì tắt tiếng radio, nghe xong mới đọc tiếp.
    if (g._events.call != null) return;
    _next -= dt;
    if (_next > 0) return;
    _next = RadioDesk.interval(_r);
    g.onNotice(desk.next(facts()));
  }

  /// Phát ngay một bản tin (để thử).
  void now() => _next = 0;

  RadioFacts facts() {
    final s = g.player.s;
    final forward = g.dir > 0;
    double? km(double? at) => at == null || !forward || at <= s ? null : (at - s) / GameConfig.unitsPerKm;
    double? nearest(Iterable<double> list) => list.where((x) => x > s).fold<double?>(null, (a, b) => a == null ? b : min(a, b));
    final e = g._events;
    final m = g.clock.minutes;
    final spells = g.weather.spells;
    var next = -1;
    var current = -1;
    for (var i = 0; i < spells.length; i++) {
      if (spells[i].start > m && (next < 0 || spells[i].start < spells[next].start)) next = i;
      if (m > spells[i].start && m < spells[i].end) current = i;
    }
    return RadioFacts(
      minutesLeft: g.clock.minutesLeft,
      clockMinutes: m,
      spareMinutes: g.spareMinutes,
      jamKm: km(e.jam?.from),
      fogKm: km(nearest(e.fogBanks.map((b) => b.from))),
      rampKm: km(nearest(e.ramps.map((r) => r.s))),
      ferryKm: km(e.ferry?.a),
      rainInMinutes: next < 0 ? null : spells[next].start - m,
      rainKind: next < 0 ? null : spells[next].kind,
      nextSpell: next,
      rainNow: g.weather.rainAt(m),
      rainNowKind: current < 0 ? null : spells[current].kind,
      rainSpell: current,
      theme: g.setup.theme,
      south: g.setup.south,
      night: g.nightLevel > 0.5,
      motorbike: g.spec.kind == VehicleKind.motorbike,
    );
  }
}
