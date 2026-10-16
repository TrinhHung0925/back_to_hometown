import 'dart:math';

import '../../model/map_theme.dart';
import '../stage.dart';
import 'weather.dart';

/// Mục của bản tin (hiện thành nhãn nhỏ trên khung radio).
enum RadioSegment {
  traffic('TIN ĐƯỜNG'),
  weather('THỜI TIẾT'),
  countdown('GIỜ GIAO THỪA'),
  dedication('LỜI CHÚC'),
  safety('AN TOÀN GIAO THÔNG'),
  tet('XUÂN VỀ'),
  greeting('CHÀO BÁC TÀI');

  const RadioSegment(this.label);

  final String label;
}

/// Một bản tin radio: thông báo kiểu [NoticeKind.radio] kèm mục của nó.
class RadioBulletin extends GameNotice {
  const RadioBulletin(super.text, {required this.segment}) : super(kind: NoticeKind.radio);

  final RadioSegment segment;
}

/// Những gì đài "biết" về đoạn đường phía trước, lấy từ chính chặng đang
/// chạy (khoảng cách tính theo km, null = không có / đã qua).
class RadioFacts {
  const RadioFacts({
    required this.minutesLeft,
    required this.clockMinutes,
    this.spareMinutes = 0,
    this.jamKm,
    this.fogKm,
    this.rampKm,
    this.ferryKm,
    this.rainInMinutes,
    this.rainKind,
    this.rainNow = 0,
    this.rainNowKind,
    this.rainSpell = -1,
    this.nextSpell = -1,
    this.theme = MapTheme.delta,
    this.south = false,
    this.night = false,
    this.motorbike = true,
  });

  /// Còn bao nhiêu phút tới giao thừa; giờ trong game (phút, như TripClock).
  final double minutesLeft;
  final double clockMinutes;

  /// Chạy đều thì về tới nhà dư (dương) / trễ (âm) bao nhiêu phút.
  final double spareMinutes;

  /// Đuôi đoạn tắc đường, đầu đoạn sương mù, đường cứu nạn gần nhất, bến phà.
  final double? jamKm;
  final double? fogKm;
  final double? rampKm;
  final double? ferryKm;

  /// Cơn mưa sắp tới: còn bao nhiêu phút (giờ trong game) và loại mưa.
  final double? rainInMinutes;
  final RainKind? rainKind;

  /// Đang mưa nặng cỡ nào (0..1), loại mưa; cơn đang mưa / cơn sắp tới là
  /// cơn thứ mấy của chặng (mỗi cơn chỉ báo một lần).
  final double rainNow;
  final RainKind? rainNowKind;
  final int rainSpell;
  final int nextSpell;

  final MapTheme theme;
  final bool south;
  final bool night;
  final bool motorbike;
}

/// Ban biên tập "Radio Giao thông": chọn bản tin kế tiếp. Tin đường hữu ích
/// (tắc đường, sương mù, mưa, phà, đường cứu nạn) đọc trước, mỗi tin một
/// lần; không có tin thì báo giờ giao thừa, thời tiết các miền, lời chúc của
/// thính giả, lời nhắc an toàn, chuyện Tết — không lặp lại câu đã đọc.
class RadioDesk {
  RadioDesk(this._random);

  final Random _random;
  final Set<String> _said = {};
  final Map<String, List<int>> _used = {};
  int _sinceCountdown = 0;
  int _flavour = 0;
  int count = 0;

  /// Bản tin đầu tiên sau chừng này giây lái; các bản tin sau cách nhau
  /// [intervalMin]..[intervalMax] giây.
  static const double firstMin = 18;
  static const double firstMax = 30;
  static const double intervalMin = 35;
  static const double intervalMax = 60;

  /// Tin đường chỉ đọc khi còn cách trong khoảng này (gần quá thì game tự
  /// cảnh báo rồi, xa quá thì chưa cần).
  static const double newsMinKm = 1.5;
  static const double newsMaxKm = 40;

  /// Mưa sắp tới trong chừng này phút (giờ trong game) thì báo trước.
  static const double rainHorizon = 75;

  static double firstDelay(Random r) => firstMin + r.nextDouble() * (firstMax - firstMin);
  static double interval(Random r) => intervalMin + r.nextDouble() * (intervalMax - intervalMin);

  RadioBulletin next(RadioFacts f) {
    count++;
    final news = _news(f);
    if (news != null) return news;
    _sinceCountdown++;
    final lastHour = f.minutesLeft > 0 && f.minutesLeft <= 60 && !_said.contains('lastHour');
    if (lastHour || (_sinceCountdown >= 3 && f.minutesLeft > 0)) {
      if (lastHour) _said.add('lastHour');
      _sinceCountdown = 0;
      return RadioBulletin(countdownText(f), segment: RadioSegment.countdown);
    }
    if (count == 1) return RadioBulletin(greetingText(f), segment: RadioSegment.greeting);
    if (_said.add('weather')) return RadioBulletin(weatherText(f), segment: RadioSegment.weather);
    final kinds = [RadioSegment.dedication, RadioSegment.safety, RadioSegment.dedication, RadioSegment.tet];
    final kind = kinds[_flavour++ % kinds.length];
    return switch (kind) {
      RadioSegment.safety => RadioBulletin(_pick('safety', _safety(f)), segment: kind),
      RadioSegment.tet => RadioBulletin(_pick('tet', _tet(f)), segment: kind),
      _ => RadioBulletin(_pick('dedication', _dedications), segment: RadioSegment.dedication),
    };
  }

  // ------------------------------------------------------------- Tin đường
  RadioBulletin? _news(RadioFacts f) {
    bool near(double? km) => km != null && km >= newsMinKm && km <= newsMaxKm;
    final items = <(String, double, String)>[
      if (near(f.jamKm))
        ('jam', f.jamKm!, 'Cửa ngõ vào phố phía trước đang ùn ứ, cách bạn chừng ${km(f.jamKm!)}. Giảm tốc sớm, đi theo hướng dẫn của CSGT.'),
      if (near(f.fogKm))
        (
          'fog',
          f.fogKm!,
          f.theme == MapTheme.mountain
              ? 'Đèo phía trước sương mù dày đặc, cách chừng ${km(f.fogKm!)}. Bật đèn, đi chậm, tuyệt đối không vượt ẩu.'
              : 'Sương mù dày trên quốc lộ phía trước, cách chừng ${km(f.fogKm!)}. Bật đèn, giữ khoảng cách với xe trước.',
        ),
      if (near(f.rampKm))
        ('ramp', f.rampKm!, 'Dốc dài phía trước, đường cứu nạn bên phải cách chừng ${km(f.rampKm!)}. Nghe còi hơi phía sau thì tránh sang phải ngay!'),
      if (near(f.ferryKm))
        ('ferry', f.ferryKm!, 'Bến phà cách bạn chừng ${km(f.ferryKm!)}, khách qua sông dịp Tết rất đông. Mua vé, xếp hàng, chờ phà cập hẳn rồi mới lên.'),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (key, _, text) in items) {
      if (_said.add(key)) return RadioBulletin(text, segment: RadioSegment.traffic);
    }
    if (f.rainNow >= 0.3 && f.rainSpell >= 0 && _said.add('rainNow${f.rainSpell}')) {
      final text = f.rainNowKind == RainKind.shower
          ? 'Mưa rào đang nặng hạt, đường đọng nước, dễ trơn trượt. Giảm tốc, bật đèn, phanh nhẹ và đều tay.'
          : 'Mưa phùn lất phất, mặt đường trơn như đổ dầu. Giữ khoảng cách gấp đôi, đừng phanh gấp.';
      return RadioBulletin(text, segment: RadioSegment.weather);
    }
    final inMin = f.rainInMinutes;
    if (inMin != null && inMin >= 5 && inMin <= rainHorizon && _said.add('rainSoon${f.nextSpell}')) {
      final when = 'Khoảng ${minutes(inMin)} nữa';
      final coat = f.motorbike ? ' Đi xe máy nhớ mặc áo mưa.' : ' Bật gạt mưa, giảm tốc khi đường ướt.';
      final text = f.rainKind == RainKind.shower
          ? '$when có mưa rào trái mùa trên tuyến bạn đang đi.$coat'
          : '$when trời chuyển mưa phùn, đường sẽ trơn.$coat';
      return RadioBulletin(text, segment: RadioSegment.weather);
    }
    return null;
  }

  /// "8 km", "15 km" (xa thì làm tròn 5 km).
  static String km(double value) {
    final k = value < 10 ? max(1, value.round()) : (value / 5).round() * 5;
    return '$k km';
  }

  /// "20 phút", "1 tiếng 10 phút" (làm tròn 5 phút).
  static String minutes(double value) {
    final m = max(5, (value / 5).round() * 5);
    if (m < 60) return '$m phút';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h tiếng' : '$h tiếng $rest phút';
  }

  // ------------------------------------------------------------- Giờ, chào
  static String countdownText(RadioFacts f) {
    final left = f.minutesLeft;
    final head = left <= 60 ? 'Chỉ còn ${minutes(left)} nữa là giao thừa!' : 'Còn ${minutes(left)} nữa là giao thừa.';
    final spare = f.spareMinutes;
    if (spare >= 10) return '$head Theo đà này bạn về kịp, dư chừng ${minutes(spare)}.';
    if (spare >= -4) return '$head Đi đều tay, bớt ghé quán là vừa kịp đấy!';
    return '$head Cứ đà này sẽ trễ chừng ${minutes(-spare)} — giữ tốc độ đều, đừng dừng lâu.';
  }

  static String partOfDay(double clockMinutes) {
    final h = (clockMinutes % 1440) / 60;
    if (h < 5) return 'Đêm';
    if (h < 11) return 'Sáng';
    if (h < 13) return 'Trưa';
    if (h < 18) return 'Chiều';
    return 'Tối';
  }

  static String greetingText(RadioFacts f) {
    final day = 30 + (f.clockMinutes / 1440).floor();
    final when = '${partOfDay(f.clockMinutes)} $day Tết';
    return 'Radio Giao thông xin chào! $when, dòng người về quê ăn Tết vẫn đông. Chúc bác tài thượng lộ bình an.';
  }

  static String weatherText(RadioFacts f) {
    if (f.south) {
      return f.theme == MapTheme.mountain
          ? 'Tây Nguyên hanh khô, sáng sớm se lạnh, trưa nắng gắt. Đường đèo bụi mù, đi chậm, giữ khoảng cách.'
          : 'Nam Bộ nắng ấm, trời trong xanh, chiều nay chừng 32 độ. Nhớ uống đủ nước, nghỉ chân dưới bóng mát.';
    }
    return switch (f.theme) {
      MapTheme.mountain => 'Vùng núi phía Bắc rét hại, đèo cao có nơi băng giá về đêm. Giữ ấm, đi chậm, bật đèn sương mù.',
      MapTheme.coast => 'Miền Trung nhiều mây, mưa nhỏ rải rác, gió đông bắc cấp 3–4. Đường ven biển có gió giật, cầm lái chắc tay.',
      _ => 'Không khí lạnh tràn về, miền Bắc rét đậm, Hà Nội chừng 11 độ. Đi xe máy nhớ áo ấm, găng tay, khẩu trang.',
    };
  }

  // ------------------------------------------------- Lời chúc, nhắc nhở, Tết
  static const List<String> _dedications = [
    'Chị Mai từ Sài Gòn về Cần Thơ nhắn ba má: "Năm nay con về sớm, nhớ gói bánh tét chờ con nha!"',
    'Anh Hùng, tài xế xe khách đường dài, chúc hành khách thượng lộ bình an, về tới nhà ăn Tết thật vui.',
    'Bạn Lan, sinh viên năm nhất, gửi cả nhà một bài nhạc xuân: "Con về rồi đây, mẹ đừng lo nữa!"',
    'Cô Bảy ở Bến Tre nhắn con trai: "Chạy chậm thôi con, nồi thịt kho trứng má nấu sẵn rồi."',
    'Nhóm công nhân khu công nghiệp Bắc Ninh chúc mọi người trên đường về quê một năm mới an khang.',
    'Ông Tư ở Huế nhắn cháu nội: "Về kịp giao thừa, ông lì xì cho bao thiệt to!"',
    'Anh Khoa chở vợ con về Nam Định, gửi tặng các bác tài đường dài một bản nhạc xuân rộn ràng.',
    'Bé Na nhắn bố đang lái xe: "Bố ơi đi cẩn thận, con với mẹ chờ bố đón giao thừa!"',
  ];

  static List<String> _safety(RadioFacts f) => [
        'Đã uống rượu bia thì không lái xe. CSGT tăng cường kiểm tra nồng độ cồn dịp Tết.',
        'Buồn ngủ thì tấp vào quán nghỉ dăm phút, uống cốc trà nóng rồi hẵng đi tiếp.',
        'Không nghe điện thoại khi đang lái. Có việc gấp thì tấp vào lề an toàn rồi hẵng gọi.',
        'Vượt xe chỉ khi đủ tầm nhìn, đừng lấn làn ở khúc cua và đỉnh dốc.',
        if (f.motorbike) 'Đội mũ bảo hiểm cài quai, hàng chở sau xe chằng buộc cho chắc — Tết an toàn là Tết trọn vẹn.',
        if (!f.motorbike) 'Thắt dây an toàn cho cả người ngồi sau, trẻ nhỏ ngồi ghế sau — Tết an toàn là Tết trọn vẹn.',
        if (f.night) 'Đi đêm nhớ bật đèn chiếu gần, gặp xe ngược chiều thì đừng bật đèn pha làm chói mắt nhau.',
      ];

  static List<String> _tet(RadioFacts f) => [
        'Chợ hoa xuân đông nghịt người, đào, quất, mai vàng đang được giá. Ai chở cành đào nhớ buộc chắc tay!',
        'Nhà nhà đang gói bánh chưng, bánh tét, dọn mâm ngũ quả. Chỉ còn chờ người đi xa về đoàn tụ.',
        'Các trạm thu phí mở thêm làn, nhiều tuyến đường thông thoáng — chúc bác tài một chặng đường suôn sẻ.',
        if (f.night || f.minutesLeft < 240) 'Pháo hoa giao thừa sẽ rực sáng ở nhiều tỉnh thành. Về kịp thì cả nhà cùng ngắm nhé!',
        if (!f.night) 'Nắng xuân lên rồi, ruộng đồng xanh mướt hai bên đường. Mở cửa sổ đón chút gió quê thôi!',
      ];

  /// Lấy một câu chưa đọc trong [lines]; đọc hết rồi thì quay vòng lại.
  String _pick(String key, List<String> lines) {
    final used = _used.putIfAbsent(key, () => []);
    var fresh = [for (var i = 0; i < lines.length; i++) if (!used.contains(i)) i];
    if (fresh.isEmpty) {
      used.clear();
      fresh = [for (var i = 0; i < lines.length; i++) i];
    }
    final i = fresh[_random.nextInt(fresh.length)];
    used.add(i);
    return lines[i];
  }
}
