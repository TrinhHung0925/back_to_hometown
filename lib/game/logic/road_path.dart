import 'dart:math';

import '../game_config.dart';

/// Một điểm lấy mẫu trên tim đường.
class RoadSample {
  const RoadSample(this.s, this.x, this.y, this.heading, [this.curvature = 0]);

  /// Quãng đường tính dọc tim đường từ điểm xuất phát.
  final double s;
  final double x;
  final double y;

  /// Hướng đi của đường (radian). 0 = sang phải, dương = chúi xuống dưới.
  final double heading;

  /// Độ cong (1/bán kính) có dấu: dương là đường cua phải (tâm cong nằm phía
  /// d dương), âm là cua trái.
  final double curvature;
}

/// Một mảnh đường: hướng đổi mượt từ [headingStart] sang [headingEnd]
/// trên quãng [length]. Hai hướng bằng nhau là đoạn thẳng.
class RoadPiece {
  const RoadPiece(this.length, this.headingStart, this.headingEnd);

  final double length;
  final double headingStart;
  final double headingEnd;

  /// Hướng tại [t] (0..1) dọc mảnh — smoothstep để độ cong tăng/giảm dần,
  /// không gãy khúc ở chỗ nối hai mảnh.
  double headingAt(double t) {
    final k = t * t * (3 - 2 * t);
    return headingStart + (headingEnd - headingStart) * k;
  }

  /// Độ cong tại [t]: 0 ở hai đầu, lớn nhất ở giữa mảnh.
  double curvatureAt(double t) => (headingEnd - headingStart) * 6 * t * (1 - t) / length;
}

/// Một khúc cua đã sinh (để đặt biển báo, cảnh báo trên HUD).
class RoadCurve {
  const RoadCurve({required this.startS, required this.length, required this.turn});

  final double startS;
  final double length;

  /// Góc đổi hướng (radian), dương là cua phải.
  final double turn;

  double get endS => startS + length;
  bool get right => turn > 0;

  /// Bán kính nhỏ nhất (ở giữa khúc cua).
  double get radius => length / (1.5 * turn.abs());

  /// Cua gắt: có biển báo, cảnh báo trên HUD.
  bool get sharp => radius < GameConfig.sharpCurveRadius;

  /// Tốc độ khuyên dùng (u/s): lực văng ở giữa cua chỉ bằng
  /// [GameConfig.curveAdviseDrift].
  double get adviseSpeed => sqrt(GameConfig.curveAdviseDrift * radius / GameConfig.curveDrift);

  /// Tốc độ khuyên dùng đổi ra km/h hiển thị, làm tròn xuống bội số của 5.
  int get adviseKmh => (adviseSpeed * GameConfig.displayKmhPerUnitSpeed / 5).floor() * 5;

  bool contains(double s) => s >= startS && s <= endS;
}

/// Kiểu uốn của đường ở một quãng: lệch hướng tối đa so với hướng chung của
/// tuyến, bán kính cong, độ lớn khúc cua và độ dài đoạn thẳng xen giữa.
class CurveStyle {
  const CurveStyle({
    required this.maxHeading,
    required this.minRadius,
    required this.maxRadius,
    required this.minTurn,
    required this.maxTurn,
    required this.straightMin,
    required this.straightMax,
    this.sCurveChance = 0,
  });

  final double maxHeading;
  final double minRadius;
  final double maxRadius;
  final double minTurn;
  final double maxTurn;
  final double straightMin;
  final double straightMax;

  /// Xác suất cua tiếp sang phía kia ngay (khúc cua chữ S).
  final double sCurveChance;

  /// Kiểu chặt hơn của hai kiểu (sắp đổi loại đường thì uốn theo đoạn tới).
  CurveStyle stricter(CurveStyle o) => identical(this, o)
      ? this
      : CurveStyle(
          maxHeading: min(maxHeading, o.maxHeading),
          minRadius: max(minRadius, o.minRadius),
          maxRadius: max(maxRadius, o.maxRadius),
          minTurn: min(minTurn, o.minTurn),
          maxTurn: min(maxTurn, o.maxTurn),
          straightMin: max(straightMin, o.straightMin),
          straightMax: max(straightMax, o.straightMax),
          sCurveChance: min(sCurveChance, o.sCurveChance),
        );

  /// Quốc lộ: cua nhiều, có khúc cua gắt và cua chữ S.
  static const highway = CurveStyle(
    maxHeading: GameConfig.maxRoadHeading,
    minRadius: GameConfig.minCurveRadiusHighway,
    maxRadius: 1300,
    minTurn: 0.35,
    maxTurn: 1.45,
    straightMin: 200,
    straightMax: 900,
    sCurveChance: 0.3,
  );

  /// Phố: chủ yếu thẳng, thỉnh thoảng uốn nhẹ.
  static const city = CurveStyle(
    maxHeading: GameConfig.maxHeadingCity,
    minRadius: GameConfig.minCurveRadiusCity,
    maxRadius: 1700,
    minTurn: 0.2,
    maxTurn: 0.55,
    straightMin: 400,
    straightMax: 1100,
  );

  /// Cao tốc: cua rộng, êm.
  static const expressway = CurveStyle(
    maxHeading: GameConfig.maxHeadingExpressway,
    minRadius: GameConfig.minCurveRadiusExpressway,
    maxRadius: 2600,
    minTurn: 0.2,
    maxTurn: 0.8,
    straightMin: 600,
    straightMax: 1600,
  );
}

/// Sinh mảnh đường kế tiếp từ hướng và quãng [s] hiện tại.
typedef RoadPieceSource = RoadPiece Function(double currentHeading, double s);

/// Tim đường dạng đường cong uốn lượn, đi chung hướng trái → phải.
///
/// Mẫu được sinh dần phía trước ([ensureAhead]) và bỏ dần phía sau
/// ([trimBefore]) nên chạy bao xa cũng không phình bộ nhớ.
class RoadPath {
  RoadPath(this._pieceSource, {double startX = 0, double startY = 0}) {
    _samples.add(RoadSample(0, startX, startY, 0));
  }

  /// Đường uốn lượn ngẫu nhiên: đoạn thẳng xen khúc cua trái / phải. Hướng
  /// đường không bao giờ lệch quá [CurveStyle.maxHeading] so với hướng chung
  /// nên đường không quay ngược lại, không tự cắt nhau.
  ///
  /// [styleAt]: kiểu uốn theo loại đường ở quãng s.
  /// [keepStraight]: khoảng s có ngã tư / trạm thu phí thì không được uốn.
  factory RoadPath.winding({
    required Random random,
    CurveStyle Function(double s)? styleAt,
    bool Function(double fromS, double toS)? keepStraight,
  }) {
    var straightNext = true;
    return RoadPath((heading, s) {
      final style = styleAt?.call(s) ?? CurveStyle.highway;
      // Sắp vào đoạn ít cua hơn (phố, cao tốc) mà đường đang lệch nhiều: nắn lại.
      final level = heading.abs() > style.maxHeading + 1e-9;
      if (straightNext && !level) {
        straightNext = false;
        return RoadPiece(style.straightMin + random.nextDouble() * (style.straightMax - style.straightMin), heading, heading);
      }
      var bend = level ? _levelBend(heading, style) : _randomBend(random, heading, style);
      // Khúc cua dài kéo sang đoạn ít cua hơn: uốn lại theo kiểu của đoạn đó.
      final end = styleAt?.call(s + bend.length);
      if (!level && end != null && end.maxHeading < style.maxHeading) {
        bend = _randomBend(random, heading, style.stricter(end));
      }
      // Không uốn ở ngã tư, trạm thu phí: đi thẳng thêm một đoạn rồi tính tiếp.
      if (keepStraight != null && keepStraight(s, s + bend.length)) {
        return RoadPiece(240, heading, heading);
      }
      straightNext = level || random.nextDouble() >= style.sCurveChance;
      return bend;
    });
  }

  /// Khúc cua đưa hướng về trong giới hạn của [style].
  static RoadPiece _levelBend(double heading, CurveStyle style) {
    final target = heading.sign * style.maxHeading * 0.5;
    return RoadPiece(1.5 * (target - heading).abs() * style.minRadius, heading, target);
  }

  static RoadPiece _randomBend(Random random, double heading, CurveStyle style) {
    final turn = style.minTurn + random.nextDouble() * (style.maxTurn - style.minTurn);
    // Đang lệch nhiều thì thường cua về phía hướng chung của tuyến.
    var sign = random.nextBool() ? 1.0 : -1.0;
    if (heading.abs() > style.maxHeading * 0.45 && random.nextDouble() < 0.7) sign = -heading.sign;
    var target = heading + sign * turn;
    if (target.abs() > style.maxHeading) {
      final other = heading - sign * turn;
      target = other.abs() <= style.maxHeading ? other : target.clamp(-style.maxHeading, style.maxHeading);
    }
    // Cua gắt hiếm hơn cua rộng.
    final u = random.nextDouble();
    final radius = style.minRadius + (style.maxRadius - style.minRadius) * u * u;
    // Độ cong lớn nhất của mảnh smoothstep là 1.5·|Δθ|/L.
    final length = max(160.0, 1.5 * (target - heading).abs() * radius);
    return RoadPiece(length, heading, target);
  }

  final RoadPieceSource _pieceSource;
  final List<RoadSample> _samples = [];

  RoadPiece? _piece;
  double _pieceStartS = 0;

  /// Các khúc cua đã sinh, theo thứ tự quãng đường.
  final List<RoadCurve> curves = [];

  static const double _step = GameConfig.roadSampleStep;

  double get firstS => _samples.first.s;
  double get lastS => _samples.last.s;

  /// Sinh thêm mẫu tới ít nhất quãng [s].
  void ensureAhead(double s) {
    while (_samples.last.s < s) {
      final last = _samples.last;
      var piece = _piece;
      if (piece == null || last.s >= _pieceStartS + piece.length) {
        _pieceStartS = last.s;
        piece = _pieceSource(last.heading, last.s);
        _piece = piece;
        final turn = piece.headingEnd - piece.headingStart;
        if (turn.abs() > 1e-9) curves.add(RoadCurve(startS: last.s, length: piece.length, turn: turn));
      }
      final nextS = last.s + _step;
      final t = ((nextS - _pieceStartS) / piece.length).clamp(0.0, 1.0);
      final heading = piece.headingAt(t);
      // Lấy hướng giữa bước để tích phân vị trí chính xác hơn.
      final mid = (last.heading + heading) / 2;
      _samples.add(RoadSample(nextS, last.x + cos(mid) * _step, last.y + sin(mid) * _step, heading, piece.curvatureAt(t)));
    }
  }

  /// Bỏ các mẫu trước quãng [s] (giữ lại một mẫu để nội suy).
  void trimBefore(double s) {
    final drop = ((s - firstS) / _step).floor() - 1;
    if (drop > 0 && drop < _samples.length - 1) {
      _samples.removeRange(0, drop);
    }
    curves.removeWhere((c) => c.endS < s);
  }

  /// Điểm trên tim đường tại quãng [s] (nội suy giữa hai mẫu).
  RoadSample at(double s) {
    ensureAhead(s);
    if (s <= firstS) return _samples.first;
    final f = (s - firstS) / _step;
    final i = f.floor().clamp(0, _samples.length - 2);
    final t = f - i;
    final a = _samples[i];
    final b = _samples[i + 1];
    return RoadSample(
      s,
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.heading + (b.heading - a.heading) * t,
      a.curvature + (b.curvature - a.curvature) * t,
    );
  }

  /// Toạ độ thế giới của điểm cách tim đường [d] tại quãng [s].
  /// [d] dương là bên phải theo hướng đi (phía dưới màn hình khi đường nằm ngang).
  (double x, double y) worldAt(double s, double d) {
    final p = at(s);
    return (p.x - sin(p.heading) * d, p.y + cos(p.heading) * d);
  }

  /// Quãng [s] mà tim đường đi qua hoành độ [x] (đường luôn đi về bên
  /// phải nên x tăng dần theo s — tìm nhị phân được).
  double sAtX(double x) {
    var lo = 0;
    var hi = _samples.length - 1;
    while (_samples[hi].x < x) {
      ensureAhead(lastS + 400);
      hi = _samples.length - 1;
    }
    if (x <= _samples[lo].x) return _samples[lo].s;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_samples[mid].x < x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = _samples[lo];
    final b = _samples[hi];
    return a.s + (b.s - a.s) * ((x - a.x) / (b.x - a.x));
  }

  Iterable<RoadCurve> curvesBetween(double a, double b) => curves.where((c) => c.endS >= a && c.startS <= b);

  /// Các mẫu trong khoảng [fromS]..[toS], dùng để vẽ.
  Iterable<RoadSample> samplesBetween(double fromS, double toS) sync* {
    ensureAhead(toS + _step);
    final start = ((fromS - firstS) / _step).floor().clamp(0, _samples.length - 1);
    for (var i = start; i < _samples.length; i++) {
      final sample = _samples[i];
      yield sample;
      if (sample.s > toS) break;
    }
  }
}
