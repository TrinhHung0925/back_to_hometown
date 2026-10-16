import 'dart:math';

import 'roadside.dart';

/// Ai đang nói trên xe (chế độ "Chở cả nhà về quê").
enum FamilySpeaker {
  kid('Bé Bin'),
  spouse('Mẹ Bin'),
  me('Mình');

  const FamilySpeaker(this.label);

  final String label;
}

/// Tâm trạng của bé (mặt bé trên HUD).
enum KidMood {
  happy,
  ok,
  fussy,
  crying,
  asleep;

  /// Ngưỡng kiên nhẫn: từ 65 vui, 35 bình thường, dưới nữa là bắt đầu quấy.
  static KidMood of(double patience) => patience >= 65
      ? happy
      : patience >= 35
          ? ok
          : fussy;
}

/// Một câu vợ / con / mình nói trên xe (hiện ở thẻ lời nói trên HUD).
class FamilyLine {
  const FamilyLine(this.speaker, this.text, {this.mood = KidMood.ok, this.seconds = 3.0});

  final FamilySpeaker speaker;
  final String text;

  /// Tâm trạng của bé lúc nói (mặt bé trên thẻ).
  final KidMood mood;

  /// Giữ câu trên thẻ bao lâu (giây chơi).
  final double seconds;

  @override
  bool operator ==(Object other) => other is FamilyLine && other.speaker == speaker && other.text == text && other.mood == mood;

  @override
  int get hashCode => Object.hash(speaker, text, mood);
}

/// Số liệu chở cả nhà cho HUD: bé còn kiên nhẫn bao nhiêu (0..100), tâm
/// trạng, đang buồn tè thì còn bao nhiêu km phải tìm chỗ dừng.
class FamilyHud {
  const FamilyHud({required this.patience, required this.mood, this.bathroomKm});

  final int patience;
  final KidMood mood;
  final int? bathroomKm;

  @override
  bool operator ==(Object other) =>
      other is FamilyHud && other.patience == patience && other.mood == mood && other.bathroomKm == bathroomKm;

  @override
  int get hashCode => Object.hash(patience, mood, bathroomKm);
}

/// Món mua cho bé ở quán (bim bim, hộp sữa): bé vui lên bao nhiêu.
class FamilySnack extends StallItem {
  const FamilySnack(super.name, {required super.price, required super.minutes, required super.art, required this.patience})
      : super(alert: 0);

  final double patience;

  static const bimBim = FamilySnack('Bim bim', price: 1, minutes: 2, art: 'bim_bim', patience: 34);
  static const hopSua = FamilySnack('Hộp sữa', price: 1, minutes: 2, art: 'hop_sua', patience: 28);

  /// Quán ăn uống nào cũng bán (quán nước, quán cơm, bánh mì, cà phê). Cây
  /// xăng, tiệm vá xe, xăng lẻ thì không (ghé vẫn cho bé đi vệ sinh được).
  static List<FamilySnack> menuFor(StallKind kind) => kind.food ? const [bimBim, hopSua] : const [];
}

/// Tình hình trên đường mỗi bước (game đo rồi đưa vào).
class FamilyInput {
  const FamilyInput({
    required this.dt,
    this.speedKmh = 0,
    this.km = 0,
    this.kmLeft = 0,
    this.jam = false,
    this.rain = 0,
    this.night = 0,
    this.raincoat = false,
    this.speeding = false,
    this.drowsy = false,
    this.lightsNeeded = false,
    this.fuelLow = false,
    this.onPhone = false,
    this.curve = false,
    this.peach = false,
    this.nextStopKm,
  });

  /// Giây chơi của bước này.
  final double dt;
  final double speedKmh;

  /// Quãng đã đi trong chặng (km, chỉ tăng) và còn bao xa tới cuối chặng.
  final double km;
  final double kmLeft;

  /// Đang nhích từng chút trong đoạn tắc đường.
  final bool jam;

  /// Mưa (0..1), trời tối (0..1), xe máy có áo mưa chưa.
  final double rain;
  final double night;
  final bool raincoat;

  /// Đang chạy quá nhanh (so với loại đường), người lái buồn ngủ, trời tối
  /// mà chưa bật đèn, đèn xăng sáng, vừa lái vừa nghe điện thoại.
  final bool speeding;
  final bool drowsy;
  final bool lightsNeeded;
  final bool fuelLow;
  final bool onPhone;

  /// Đang ôm khúc cua gắt (ô tô: bé dễ say xe).
  final bool curve;

  /// Xe máy đang chở cành đào sau xe.
  final bool peach;

  /// Chỗ dừng được gần nhất phía trước (quán, cây xăng) còn bao nhiêu km;
  /// null nếu trong tầm không có.
  final double? nextStopKm;
}

/// Chở vợ và con nhỏ về quê: bé có mức kiên nhẫn 0..100 tụt dần khi ngồi xe
/// (nhanh hơn lúc tắc đường, mưa, đêm, xóc ổ gà, phanh gấp), lên lại khi ghé
/// quán và được mua bim bim, hộp sữa. Thỉnh thoảng bé hỏi "sắp tới chưa",
/// đòi đi vệ sinh (phải ghé quán trong vài km), vợ nhắc đi chậm, bật đèn…
/// Kiên nhẫn cạn thì bé khóc: người lái phân tâm (tay lái kém ăn), mau mệt.
/// Khóc mệt thì bé ngủ thiếp đi. Dễ thương là chính, phạt nhẹ thôi.
class FamilyRide {
  FamilyRide({
    required this.motorbike,
    required Random random,
    this.toName = '',
    this.stageKm = 0,
    this.pace = 1,
    double patience = startPatience,
  })  : _r = random,
        patience = patience.clamp(0.0, 100.0) {
    // Chặng nào đủ dài cũng có thể bé đòi đi vệ sinh một lần.
    if (stageKm > 15 && _r.nextDouble() < bathroomChance) {
      _bathroomAtKm = stageKm * (0.22 + _r.nextDouble() * 0.45);
    }
    _chatIn = 6 + _r.nextDouble() * 8;
  }

  final bool motorbike;
  final Random _r;
  final String toName;
  final double stageKm;

  /// Hệ số độ khó (dễ tụt chậm hơn, khó tụt nhanh hơn).
  final double pace;

  /// Kiên nhẫn của bé (0..100).
  double patience;

  /// Điểm cộng / trừ của cả nhà trong chặng (tè dầm, khóc nhè, về tới nơi
  /// bé còn vui).
  int score = 0;

  bool crying = false;
  bool asleep = false;

  void Function(FamilyLine line)? onLine;

  /// Thông báo ngắn trên màn hình ([warning]: màu cảnh báo).
  void Function(String text, bool warning)? onNotice;

  // ---------------------------------------------------------- Cân chỉnh
  static const double startPatience = 92;

  /// Tụt mỗi giây chơi lúc ngồi xe bình thường.
  static const double drainPerSecond = 0.22;
  static const double jamFactor = 2.4;
  static const double nightFactor = 0.3;

  /// Mưa (theo độ nặng hạt): xe máy có áo mưa / không áo mưa / ô tô.
  static const double rainCoated = 0.22;
  static const double rainSoaking = 0.6;
  static const double rainCar = 0.04;
  static const double carsickPerSecond = 0.25;

  static const double bumpHit = 5;
  static const double brakeHit = 4;
  static const double crashHit = 16;

  /// Vào quán: xuống xe duỗi chân, rồi mỗi giây ngồi nghỉ lên thêm.
  static const double stopBoost = 12;
  static const double restPerSecond = 2.2;
  static const double sleepRecoverPerSecond = 0.35;

  /// Dưới mức này bé oà khóc; khóc lâu quá thì mệt, ngủ thiếp đi.
  static const double cryBelow = 12;
  static const double calmAbove = 35;
  static const double crySeconds = 22;

  static const double bathroomChance = 0.65;

  /// Km dư thêm sau chỗ dừng gần nhất (lỡ quán đầu còn kịp quán sau).
  static const double bathroomSpareKm = 3;
  static const double bathroomMinKm = 4;
  static const double bathroomHit = 25;
  static const int bathroomPenalty = 150;
  static const int cryPenalty = 50;

  /// Người lái phân tâm khi bé khóc (gọi điện vừa lái là 1).
  static const double cryDistraction = 0.5;
  static const double cryAlertFactor = 1.5;

  // ---------------------------------------------------------- Trạng thái
  double _cryT = 0;
  double _sleepLeft = 0;
  double _nightCheckIn = 10;
  double _smoothT = 0;
  double? _bathroomAtKm;
  double? _bathroomDeadline;
  bool _bathroomReminded = false;
  bool _bathroomUrged = false;
  double _km = 0;
  double _kmLeft = 0;

  /// Câu đang chờ nói (đối đáp nối nhau) và còn bao lâu mới tới câu sau.
  final List<FamilyLine> _queue = [];
  double _lineIn = 0;
  double _chatIn = 10;
  double _reactCooldown = 0;
  final Map<String, double> _cooldowns = {};
  double _speedingT = 0;
  double _sinceSnack = 999;
  bool _jamTold = false;
  bool _lightsTold = false;
  bool _fuelTold = false;
  bool _phoneTold = false;
  int _idleIndex = 0;

  /// Người lái phân tâm (0..1): bé khóc ré bên tai.
  double get distraction => crying ? cryDistraction : 0;

  /// Tỉnh táo tụt nhanh hơn bao nhiêu lần (bé khóc, người lái căng thẳng).
  double get alertFactor => crying ? cryAlertFactor : 1;

  KidMood get mood => asleep
      ? KidMood.asleep
      : crying
          ? KidMood.crying
          : KidMood.of(patience);

  /// Bé đang buồn tè: còn bao nhiêu km phải dừng (null nếu không).
  double? get bathroomKm => _bathroomDeadline == null ? null : max(0.0, _bathroomDeadline! - _km);

  FamilyHud get hud => FamilyHud(patience: patience.round(), mood: mood, bathroomKm: bathroomKm?.ceil());

  /// Về tới nơi mà bé còn vui thì được thưởng thêm điểm.
  int get arrivalBonus => patience >= 60
      ? 200
      : patience >= 30
          ? 80
          : 0;

  // ------------------------------------------------------------- Mỗi bước
  /// Một bước đang lái (cả lúc dừng đèn đỏ, chờ phà…).
  void step(FamilyInput i) {
    final dt = i.dt;
    _km = max(_km, i.km);
    _kmLeft = i.kmLeft;
    _sinceSnack += dt;
    _reactCooldown = max(0, _reactCooldown - dt);
    _cooldowns.updateAll((_, v) => v - dt);
    _drain(i);
    _stepCry(dt);
    _stepSleep(i);
    _stepBathroom(i);
    _stepWarnings(i);
    _stepChat(i);
    _stepQueue(dt);
  }

  void _drain(FamilyInput i) {
    final dt = i.dt;
    if (asleep) {
      patience = min(100, patience + sleepRecoverPerSecond * dt);
      return;
    }
    var rate = drainPerSecond;
    if (i.jam) rate *= jamFactor;
    rate *= 1 + nightFactor * i.night.clamp(0.0, 1.0);
    if (i.rain > 0) rate += i.rain * (motorbike ? (i.raincoat ? rainCoated : rainSoaking) : rainCar);
    if (!motorbike && i.curve) rate += carsickPerSecond;
    patience = max(0, patience - rate * pace * dt);
    if (!crying && patience < cryBelow) _startCry();
  }

  void _startCry() {
    if (crying) return;
    crying = true;
    asleep = false;
    _sleepLeft = 0;
    _cryT = 0;
    score -= cryPenalty;
    onNotice?.call('Bé khóc ré lên — tay lái phân tâm! Ghé quán dỗ bé đi', true);
    _say([
      _kid(_pick(const ['Oa oa oa… con không đi nữa đâu…', 'Hu hu hu… con muốn về nhà bà cơ…', 'Oa… con mệt lắm rồi…']), KidMood.crying),
      _wife(motorbike ? 'Nín đi con, mẹ thương… Anh tấp vào quán cho con nghỉ tí đi!' : 'Nín nào con… Anh ơi, tấp vào quán cho con nghỉ đi!'),
    ], urgent: true);
  }

  void _stepCry(double dt) {
    if (!crying) return;
    _cryT += dt;
    if (patience >= calmAbove) {
      crying = false;
      _say([_wife('Nín rồi, con ngoan quá!'), _kid('Con hết khóc rồi…', KidMood.ok)]);
      return;
    }
    if (_cryT >= crySeconds) {
      // Khóc mệt rồi ngủ thiếp đi, dậy là vui trở lại.
      crying = false;
      patience = max(patience, 25);
      _fallAsleep(motorbike ? 'Khóc mệt quá, bé ngủ thiếp đi — mẹ với tay ôm con' : 'Khóc mệt quá, bé ngủ thiếp đi trên ghế ô tô');
      return;
    }
    if ((_cryT % 7) < dt && _cryT > 1) {
      _say([_kid(_pick(const ['Oa oa…', 'Hu hu… bố ơi…', 'Oa… con muốn xuống!']), KidMood.crying)]);
    }
  }

  void _fallAsleep(String notice) {
    asleep = true;
    _sleepLeft = 45 + _r.nextDouble() * 35;
    onNotice?.call(notice, false);
    _say([_wife('Suỵt… con ngủ rồi, anh đi êm êm thôi nhé.')]);
  }

  void _stepSleep(FamilyInput i) {
    if (asleep) {
      _sleepLeft -= i.dt;
      if (_sleepLeft <= 0) _wake(gently: true);
      return;
    }
    // Đêm, đường êm, bé không buồn tè thì dễ ngủ gà ngủ gật.
    final smooth = !i.jam && i.speedKmh > 10;
    _smoothT = smooth ? _smoothT + i.dt : 0;
    if (crying || i.night < 0.6 || _bathroomDeadline != null || patience < 30) return;
    _nightCheckIn -= i.dt;
    if (_nightCheckIn > 0) return;
    _nightCheckIn = 10;
    if (_smoothT > 20 && _r.nextDouble() < 0.35) _fallAsleep('Đêm khuya, xe êm — bé ngủ say rồi');
  }

  void _wake({required bool gently}) {
    if (!asleep) return;
    asleep = false;
    _sleepLeft = 0;
    if (gently) {
      patience = min(100, patience + 15);
      _say([_kid(_pick(const ['Ơ… tới nhà bà chưa bố?', 'Oáp… con ngủ ngon quá!', 'Bố ơi, con dậy rồi!']), KidMood.happy)]);
    } else {
      patience = max(0, patience - 4);
      _say([_kid(_pick(const ['Oa… con đang ngủ mà…', 'Hu… sao bố làm con thức dậy…']), KidMood.fussy)], urgent: true);
    }
  }

  // ------------------------------------------------------------ Đi vệ sinh
  void _stepBathroom(FamilyInput i) {
    final deadline = _bathroomDeadline;
    if (deadline == null) {
      final at = _bathroomAtKm;
      if (at == null || _km < at || crying || asleep) return;
      final stop = i.nextStopKm;
      if (stop == null || i.kmLeft < stop + 1) {
        // Phía trước chưa có chỗ dừng: để lát nữa bé mới đòi.
        _bathroomAtKm = _km + 3;
        return;
      }
      _bathroomAtKm = null;
      final km = max(bathroomMinKm, stop + bathroomSpareKm);
      _bathroomDeadline = _km + km;
      _bathroomLen = km;
      _bathroomReminded = false;
      _bathroomUrged = false;
      onNotice?.call('Bé buồn tè! Ghé quán hoặc cây xăng trong vòng ${km.ceil()} km', true);
      _say([
        _kid(_pick(const ['Bố ơi con buồn tè!', 'Bố ơi, con buồn đi vệ sinh!', 'Bố ơi dừng xe, con buồn tè quá!']), KidMood.fussy),
        _me('Cố nhịn tí nhé con, chừng ${stop.ceil()} cây nữa có quán!'),
      ], urgent: true);
      return;
    }
    final left = deadline - _km;
    if (!_bathroomReminded && left < _bathroomLen / 2) {
      _bathroomReminded = true;
      _say([_kid('Bố ơi nhanh lên, con sắp tè ra quần rồi!', KidMood.fussy)]);
    }
    if (!_bathroomUrged && left < 1.2) {
      _bathroomUrged = true;
      _say([_wife('Anh tấp vào đâu đó nhanh lên, con không nhịn được nữa rồi!')], urgent: true);
    }
    if (left <= 0) {
      _bathroomDeadline = null;
      patience = max(0, patience - bathroomHit);
      score -= bathroomPenalty;
      onNotice?.call('Bé tè dầm ra quần rồi… Lần sau dừng sớm hơn nhé', true);
      _say([
        _kid('Hu hu… con tè ra quần rồi…', KidMood.crying),
        _wife('Thôi xong… Anh ghé quán nào đó cho em thay quần cho con.'),
      ], urgent: true);
      if (patience < calmAbove) _startCry();
    }
  }

  /// Lúc bé đòi đi vệ sinh còn bao nhiêu km để dừng.
  double _bathroomLen = 0;

  // ---------------------------------------------------- Vợ nhắc chồng
  void _stepWarnings(FamilyInput i) {
    _speedingT = i.speeding ? _speedingT + i.dt : 0;
    if (_speedingT > 2.5 && _ready('speed', 30)) {
      _say([
        _wife(_pick(const ['Anh đi chậm lại! Chở cả con đấy!', 'Nhanh quá anh ơi, em sợ lắm!', 'Không phải vội đâu anh, kịp giao thừa mà!'])),
      ], urgent: true);
    }
    if (i.drowsy && _ready('drowsy', 45)) {
      _say([_wife('Anh buồn ngủ à? Tấp vào quán uống cốc trà đá đi, em lo lắm.')]);
    }
    if (i.onPhone && !_phoneTold) {
      _phoneTold = true;
      _say([_wife('Đưa em nghe cho! Đang lái xe chở con mà anh.')], urgent: true);
    }
    if (motorbike && !i.raincoat && i.rain > 0.2 && _ready('rain', 60)) {
      _say([_wife('Mưa rồi anh ơi! Ghé quán mua áo mưa kẻo con ướt lạnh ốm mất.')], urgent: true);
    }
    if (i.lightsNeeded && !_lightsTold) {
      _lightsTold = true;
      _say([_wife('Tối rồi, anh bật đèn lên đi!')]);
    }
    if (i.fuelLow && !_fuelTold) {
      _fuelTold = true;
      _say([_wife('Đèn xăng sáng rồi kìa anh, nhớ tìm cây xăng nhé.')]);
    }
    if (i.jam && !_jamTold) {
      _jamTold = true;
      _say([_kid('Sao xe đứng im thế bố?'), _me('Tắc đường con ạ, ngồi im chút là đi được.')]);
    }
  }

  bool _ready(String key, double cooldown) {
    if ((_cooldowns[key] ?? 0) > 0) return false;
    _cooldowns[key] = cooldown;
    return true;
  }

  // -------------------------------------------------------- Chuyện trò
  void _stepChat(FamilyInput i) {
    if (crying || _queue.isNotEmpty) return;
    _chatIn -= i.dt;
    if (_chatIn > 0) return;
    _chatIn = 13 + _r.nextDouble() * 10;
    final km = max(1, i.kmLeft.round());
    String fill(String s) => s.replaceAll('{km}', '$km').replaceAll('{to}', toName);
    if (asleep) {
      if (_r.nextDouble() < 0.4) _say([_wife(fill(_pick(const ['Con ngủ ngoan quá…', 'Còn {km} cây nữa thôi, anh đi êm nhé.'])))]);
      return;
    }
    if (patience < 30) {
      final hungry = _sinceSnack > 50 && _r.nextBool();
      _say(hungry
          ? [_kid('Bố ơi con đói!', KidMood.fussy), _wife('Anh ghé quán mua bim bim, hộp sữa cho con đi.')]
          : [_kid(_pick(const ['Con muốn xuống cơ!', 'Bố ơi dừng lại đi, con mệt lắm!', 'Hu… ngồi lâu quá con đau mông…']), KidMood.fussy)]);
      return;
    }
    if (patience < 60 && _r.nextDouble() < 0.65) {
      _say(_pick([
        [_kid('Bố ơi sắp tới chưa?'), _me(fill('Còn {km} cây nữa thôi con, ngoan nhé!'))],
        [_kid('Bao giờ mới tới nhà bà hả bố?'), _me('Ngủ một giấc dậy là tới con ạ.')],
        [_kid('Con mỏi chân quá…'), _wife('Ráng chút nữa con, tới quán mình nghỉ nhé.')],
        [_kid('Ngồi lâu quá, con buồn chán quá!'), _wife('Con đếm xem có bao nhiêu ô tô đỏ nào!')],
      ]));
      return;
    }
    // Vui vẻ: lần lượt bé, vợ, chuyện theo đường đi.
    _idleIndex++;
    final kidTurn = _idleIndex.isOdd;
    if (kidTurn) {
      _say(_pick([
        [_kid('Bố ơi, về quê có được đốt pháo hoa không?', KidMood.happy), _me('Có chứ, giao thừa cả nhà cùng xem pháo hoa!')],
        [_kid('Năm nay con được bà lì xì không bố?', KidMood.happy), _me('Ngoan thì bà lì xì to luôn!')],
        [_kid('Kìa bố, con trâu kìa! To ơi là to!', KidMood.happy)],
        [_kid('Con đếm được mười cái ô tô rồi đấy!', KidMood.happy)],
        [_kid('Nhà bà có gói bánh chưng không bố?', KidMood.happy), _me('Có, ông bà gói sẵn chờ con về đấy.')],
        [_kid('Con hát bài chúc Tết cho bố mẹ nghe nhé!', KidMood.happy), _wife('Hát đi con, mẹ nghe nào!')],
        if (motorbike) [_kid('Gió mát quá bố ơi!', KidMood.happy)] else [_kid('Bố mở nhạc Tết đi bố!', KidMood.happy)],
        if (i.peach) [_kid('Cành đào của mình có rụng bông nào không bố?', KidMood.happy), _me('Còn đẹp lắm, bố buộc chắc rồi.')],
        if (i.night > 0.5) [_kid('Bố ơi, trời tối thui, con hơi sợ…'), _wife('Có bố mẹ đây rồi, con không phải sợ.')],
      ]));
    } else {
      _say([
        _wife(fill(_pick([
          'Còn chừng {km} cây nữa là tới {to} rồi anh ạ.',
          'Năm nay về sớm, chắc mẹ mừng lắm.',
          'Anh lái cẩn thận nhé, cả nhà chỉ cần về bình an thôi.',
          'Đi xa thế này anh vất vả quá… Em thương anh.',
          'Nhớ ghé mua ít quà biếu ông bà nhé anh.',
          'Tết này nhà mình về đông đủ, vui ghê!',
          'Tới nhà anh nhớ mừng tuổi ông bà trước nhé.',
          if (i.night > 0.5) 'Đêm rồi, anh mỏi thì bảo em, mình nghỉ một lát.',
          if (motorbike && i.curve) 'Anh ôm cua chậm thôi, em ngồi sau sợ lắm.',
        ]))),
      ]);
    }
  }

  T _pick<T>(List<T> items) => items[_r.nextInt(items.length)];

  FamilyLine _kid(String text, [KidMood? mood]) => FamilyLine(FamilySpeaker.kid, text, mood: mood ?? this.mood);
  FamilyLine _wife(String text) => FamilyLine(FamilySpeaker.spouse, text, mood: mood);
  FamilyLine _me(String text) => FamilyLine(FamilySpeaker.me, text, mood: mood, seconds: 2.6);

  /// Xếp câu nói; [urgent]: bỏ chuyện đang dở, nói ngay.
  void _say(List<FamilyLine> lines, {bool urgent = false}) {
    if (lines.isEmpty) return;
    if (urgent) {
      _queue.clear();
      _lineIn = 0;
    } else if (_queue.length > 3) {
      return;
    }
    _queue.addAll(lines);
  }

  void _stepQueue(double dt) {
    _lineIn -= dt;
    if (_lineIn > 0 || _queue.isEmpty) return;
    final line = _queue.removeAt(0);
    _lineIn = line.seconds;
    onLine?.call(line);
  }

  /// Câu đang chờ nói (để kiểm thử).
  List<FamilyLine> get pending => List.unmodifiable(_queue);

  // ----------------------------------------------------------- Sự kiện
  /// Sập ổ gà, quệt lề: xóc nảy người.
  void bump() {
    patience = max(0, patience - bumpHit * (motorbike ? 1 : 0.7));
    if (asleep) return _wake(gently: false);
    if (_reactCooldown > 0 || crying) return;
    _reactCooldown = 8;
    _say([
      _r.nextDouble() < 0.7
          ? _kid(_pick(const ['Ối! Xóc quá bố ơi!', 'Á! Con suýt văng ra!', 'Bố ơi ổ gà to thế!']), KidMood.fussy)
          : _wife('Anh tránh ổ gà ra chứ, con nó xóc!'),
    ], urgent: true);
  }

  /// Phanh gấp: con chúi người về trước.
  void hardBrake() {
    patience = max(0, patience - brakeHit);
    if (asleep) return _wake(gently: false);
    if (_reactCooldown > 0 || crying) return;
    _reactCooldown = 8;
    _say([
      _wife(motorbike ? 'Ối! Anh phanh từ từ thôi, con nó chúi cả người!' : 'Phanh gấp thế anh, con đập đầu vào ghế bây giờ!'),
    ], urgent: true);
  }

  /// Va chạm: cả nhà hết hồn.
  void crash() {
    patience = max(0, patience - crashHit);
    asleep = false;
    _reactCooldown = 8;
    _say([_wife('Trời ơi! Con có sao không? Anh lái cẩn thận vào!')], urgent: true);
    if (patience < 50) _startCry();
  }

  /// Ghé quán / cây xăng: cả nhà xuống xe duỗi chân, bé đi vệ sinh.
  void stopAt() {
    final needed = _bathroomDeadline != null;
    _bathroomDeadline = null;
    if (asleep) {
      // Bé đang ngủ thì mẹ bế, không đánh thức.
      return;
    }
    patience = min(100, patience + stopBoost + (needed ? 8 : 0));
    if (needed) {
      onNotice?.call('Hai mẹ con đi vệ sinh xong — nhẹ cả người!', false);
      _say([_kid('Con đi tè xong rồi, nhẹ cả người!', KidMood.happy)], urgent: true);
    } else if (patience < 60) {
      _say([_kid('A, được xuống xe rồi!', KidMood.ok)], urgent: true);
    }
  }

  /// Đang ngồi nghỉ trong quán.
  void rest(double dt) {
    if (asleep) {
      patience = min(100, patience + sleepRecoverPerSecond * dt);
    } else {
      patience = min(100, patience + restPerSecond * dt);
    }
    if (crying && patience >= calmAbove) {
      crying = false;
      _say([_wife('Nín rồi, con ngoan quá!')]);
    }
    _stepQueue(dt);
  }

  /// Mua món cho bé ăn ở quán.
  void eat(FamilySnack snack) {
    _sinceSnack = 0;
    if (asleep) _wake(gently: true);
    patience = min(100, patience + snack.patience);
    if (crying && patience >= calmAbove) crying = false;
    _say([
      snack == FamilySnack.hopSua
          ? _kid('Sữa ngon quá! Con cảm ơn mẹ!', KidMood.happy)
          : _kid('A! Bim bim! Con cảm ơn bố!', KidMood.happy),
    ], urgent: true);
    // Uống sữa xong một lúc lại buồn tè.
    if (snack == FamilySnack.hopSua && _bathroomAtKm == null && _bathroomDeadline == null && _kmLeft > 14) {
      _bathroomAtKm = _km + 8 + _r.nextDouble() * 6;
    }
  }

  /// Lên đường lại sau khi ghé quán.
  void leave() {
    if (!asleep && patience >= 60) _say([_kid('Đi tiếp thôi bố ơi!', KidMood.happy)]);
  }
}
