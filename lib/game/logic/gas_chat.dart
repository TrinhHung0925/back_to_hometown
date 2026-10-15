import 'dart:math';

/// Quà nhỏ sau câu trả lời: chai nước (tỉnh táo), lì xì lấy may, tin đường.
enum ChatPerk { none, water, lixi, tip }

/// Một câu mình trả lời và câu nhân viên đáp lại. `{to}` là nơi đang về,
/// `{tip}` là tin đường phía trước (game điền vào).
class ChatReply {
  const ChatReply(this.text, this.react, {this.perk = ChatPerk.none});

  final String text;
  final String react;
  final ChatPerk perk;
}

/// Nhân viên hỏi một câu, mình chọn một trong ba câu trả lời.
class ChatTopic {
  const ChatTopic(this.ask, this.replies);

  final String ask;
  final List<ChatReply> replies;
}

/// Tán gẫu với nhân viên cây xăng lúc chờ đổ: hỏi han, đùa theo trend mạng
/// (đỉnh nóc kịch trần, còn cái nịt, chill guy, ét o ét, hẹ hẹ hẹ…), chuyện
/// Tết (thưởng Tết, bị hỏi lương, bánh chưng). Nhân viên gọi khách là "sếp".
abstract class GasChat {
  /// Mỗi lần ghé được tán tối đa bấy nhiêu chuyện.
  static const int maxRounds = 3;

  static const List<ChatTopic> topics = [
    ChatTopic('Sếp đổ bao nhiêu ạ? Đổ đầy bình hay đổ… cho có?', [
      ChatReply('Đổ đầy! Tết là phải ngon lành cành đào.', 'Chốt đơn! Sếp chịu chơi đỉnh nóc kịch trần luôn!'),
      ChatReply('Đổ ít thôi, ví còn đúng cái nịt.', 'Hiểu mà sếp, cuối năm ví ai cũng "chằm Zn" hết á.'),
      ChatReply('Đổ cho xíu niềm tin vào cuộc sống.', 'Niềm tin hết hàng rồi, còn mỗi xăng thôi sếp ơi!'),
    ]),
    ChatTopic('Sếp về quê ăn Tết hả? Chuẩn bị tinh thần bị hỏi lương chưa?', [
      ChatReply('Rồi, cứ nói "lương đủ đổ xăng về quê".', 'Câu này 10 điểm không có nhưng! Em xin nha.'),
      ChatReply('Định nói lương là bí mật quốc gia.', 'Hẹ hẹ hẹ, thế thì họ hàng hết đường hỏi!'),
      ChatReply('Đánh trống lảng, hỏi lại chuyện học của tụi nhỏ.', 'Phòng thủ bằng tấn công, sếp đúng là cao thủ!'),
    ]),
    ChatTopic('Nhìn sếp chill ghê, chạy đường xa có mệt không?', [
      ChatReply('Mệt xỉu ngang, ngồi tê cả người rồi.', 'Ối dồi ôi! Em tặng chai nước suối cho tỉnh nè.', perk: ChatPerk.water),
      ChatReply('Nghĩ tới nồi bánh chưng là hết mệt.', 'Động lực mlem mlem có khác!'),
      ChatReply('Đâu có, tui là "chill guy" mà.', 'Chill guy chính hiệu, cho em xin chữ ký!'),
    ]),
    ChatTopic('Nghe gì chưa sếp? Xăng E10 sắp bán khắp nơi rồi đó!', [
      ChatReply('Nghe như tên nhóm nhạc mới ra mắt.', 'Nhóm nhạc chạy bằng sắn với ngô đó sếp, hát hay mà sạch!'),
      ChatReply('Xe chạy được là mê liền.', 'Mê chữ ê kéo dài luôn!'),
      ChatReply('E10 là gì, ăn được không em?', 'Uống được thì em uống lâu rồi á sếp!'),
    ]),
    ChatTopic('Sếp đi một mình hay chở "người ấy" về ra mắt?', [
      ChatReply('Chở mỗi cành đào thôi em.', 'Cành đào cũng là người ấy, miễn nở đúng mùng Một!'),
      ChatReply('Người ấy đang đợi ở quê.', 'Trời ơi lãng mạn xỉu ngang! Đi chậm thôi cho người ấy yên tâm.'),
      ChatReply('Người ấy là chiếc xe này nè.', 'Chung thủy ghê! Vậy đổ đầy cho người ấy no luôn nha.'),
    ]),
    ChatTopic('Thưởng Tết năm nay của sếp là tiền hay… hộp bánh?', [
      ChatReply('Hộp bánh, mà là hộp to!', 'Thôi cũng ráng, năm sau thưởng hai hộp nha sếp!'),
      ChatReply('Thưởng một chuyến về quê bình an.', 'Câu trả lời chạm tới trái tim em luôn á!'),
      ChatReply('Ủa alo, thưởng là gì?', 'Kiếp nạn thứ 82 đây rồi! Em lì xì lấy may cho sếp nè.', perk: ChatPerk.lixi),
    ]),
    ChatTopic('Sếp có phải idol không mà nhìn sáng chói vậy?', [
      ChatReply('Idol của hội "nhà nghèo vượt khó".', 'Hội đó em cũng là fan cứng nè!'),
      ChatReply('Sáng là do thức trắng đêm qua đó.', 'Thiếu ngủ mà vẫn toả sáng, đỉnh thật sự. Uống nước cho tỉnh nè!', perk: ChatPerk.water),
      ChatReply('Ừ, idol đổ xăng đúng chuẩn.', 'Em xin tấm selfie… à thôi, ở cây xăng cấm điện thoại!'),
    ]),
    ChatTopic('Ở cây xăng nhớ tắt máy, cất điện thoại nha sếp!', [
      ChatReply('Tắt rồi, giờ chỉ còn tim đang chạy.', 'Tim chạy thì được, đừng chạy theo người yêu cũ là được!'),
      ChatReply('Cho chụp một tấm check-in thôi mà…', 'Khum được đâu sếp ơi, an toàn là trên hết!'),
      ChatReply('Rõ! Chấp hành nghiêm túc!', 'Sếp chuẩn chỉnh quá, em tặng chai nước nè!', perk: ChatPerk.water),
    ]),
    ChatTopic('Sếp đi đâu đấy? Để em mách nước đường cho.', [
      ChatReply('Về {to}, phía trước có gì không em?', '{tip}', perk: ChatPerk.tip),
      ChatReply('Đi theo tiếng gọi của bánh chưng.', 'Bánh chưng gọi là phải về liền, gét gô!'),
      ChatReply('Đi đâu cũng được, miễn có xăng.', 'Triết lý sống đỉnh nóc! Đổ đầy là đi đâu cũng tới.'),
    ]),
    ChatTopic('Tết này sếp có định "flex" gì với họ hàng không?', [
      ChatReply('Flex chiếc xe vừa rửa sạch bóng.', 'Bóng loáng như vậy flex là hợp lý!'),
      ChatReply('Flex đôi mắt thâm vì chạy xuyên đêm.', 'Thâm mà vẫn đẹp! Em tặng chai nước cho tỉnh nè.', perk: ChatPerk.water),
      ChatReply('Khum flex, ra dẻ là bị hỏi vay tiền.', 'Thông minh! Sống kín tiếng mới là cao thủ.'),
    ]),
    ChatTopic('Xăng lên giá rồi đó sếp, buồn không?', [
      ChatReply('Buồn như mất sóng wifi.', 'Ét o ét! Thôi đổ đầy cho bớt buồn nha!'),
      ChatReply('Giá lên nhưng tinh thần không xuống!', 'Tinh thần thép! Đỉnh nóc kịch trần bay phấp phới!'),
      ChatReply('Toang thật sự, còn mỗi cái nịt.', 'Thôi để em lì xì lấy may đầu năm cho sếp!', perk: ChatPerk.lixi),
    ]),
    ChatTopic('Về quê Tết này sếp thèm món gì nhất?', [
      ChatReply('Bánh chưng mẹ gói.', 'Ngon lành cành đào luôn, nghe mà thèm!'),
      ChatReply('Thịt đông với dưa hành.', 'Mlem mlem! Em đói theo sếp luôn rồi.'),
      ChatReply('Món "bao giờ cưới" của các cô các bác.', 'Hẹ hẹ, món đó năm nào cũng có, sếp cố lên!'),
    ]),
    ChatTopic('Chạy đường dài sếp nghe nhạc gì cho tỉnh?', [
      ChatReply('"Bắc Bling", nghe trăm lần chưa chán.', 'Bắc Bling Bắc Bling! Bật lên là tỉnh liền!'),
      ChatReply('Bolero cho chill.', 'Chill thì chill nhưng đừng chill quá mà ngủ gật nha sếp!'),
      ChatReply('Nghe tiếng máy nổ thôi.', 'Nghe máy nổ là biết xe khoẻ, sếp sành ghê!'),
    ]),
    ChatTopic('Ủa sếp ơi, xe sếp kêu "ét o ét" kìa!', [
      ChatReply('Nó đói xăng đó em.', 'Vậy cho nó ăn no nê luôn nha!'),
      ChatReply('Nó đang hát đó, đừng lo.', 'Hát hay ghê, em cho 10 điểm!'),
      ChatReply('Chắc nó cũng muốn về quê ăn Tết.', 'Xe cũng có quê mà, thương ghê!'),
    ]),
    ChatTopic('Sếp biết mẹo đổ số tròn lấy may đầu năm không?', [
      ChatReply('Biết chứ, số tròn cho cả năm tròn trịa.', 'Chuẩn bài! Năm mới tròn đầy như bình xăng!'),
      ChatReply('Đổ số lẻ cho… lẻ loi à?', 'Ối, năm mới đừng lẻ loi nha sếp!'),
      ChatReply('Mẹo hay vậy, ghi nhớ liền.', 'Ghi nhớ nha, em tặng chai nước lấy hên!', perk: ChatPerk.water),
    ]),
    ChatTopic('Hôm nay đông nghẹt, sếp có thấy áp lực đồng trang lứa không?', [
      ChatReply('Thấy, ai cũng về quê nhanh hơn mình.', 'Đi chậm mà chắc, về tới là thắng rồi sếp!'),
      ChatReply('Không, chỉ áp lực… đồng hồ thôi.', 'Hiểu rồi, em đổ lẹ cho sếp kịp giao thừa!'),
      ChatReply('Áp lực thì uống trà đá.', 'Trà đá chân ái! Ở đây chỉ có nước suối, em tặng nè.', perk: ChatPerk.water),
    ]),
    ChatTopic('Sếp có biết đoạn trước có gì hot không?', [
      ChatReply('Có gì hot, kể nghe coi!', '{tip}', perk: ChatPerk.tip),
      ChatReply('Hot nhất là trà sữa thôi em.', 'Trà sữa thì phải tới thị trấn mới có sếp ơi!'),
      ChatReply('Thôi, biết nhiều chi cho mệt.', 'Đúng là sống chill, nhưng nhớ đi chậm nha!'),
    ]),
    ChatTopic('Năm mới em chúc sếp gì nè: giàu, khoẻ hay… có bồ?', [
      ChatReply('Giàu trước, mấy cái kia tự tới.', 'Chuẩn tư duy! Năm mới tiền vô như nước!'),
      ChatReply('Khoẻ, để còn chạy về quê.', 'Chúc sếp khoẻ như voi, chạy như gió!'),
      ChatReply('Cả ba, Tết mà!', 'Tham ghê… nhưng Tết mà, em chúc đủ cả ba!'),
    ]),
  ];

  /// Chọn một chuyện chưa nói trong chặng này (nói hết rồi thì nói lại).
  static int pick(Random random, Set<int> used) {
    final fresh = [for (var i = 0; i < topics.length; i++) if (!used.contains(i)) i];
    if (fresh.isEmpty) {
      used.clear();
      return random.nextInt(topics.length);
    }
    return fresh[random.nextInt(fresh.length)];
  }
}

/// Chuyện đang tán: câu hỏi, câu mình chọn và câu nhân viên đáp (null khi
/// chưa trả lời), lượt thứ mấy trong lần ghé này.
class GasChatState {
  const GasChatState({required this.topic, required this.round, this.mine, this.react});

  final ChatTopic topic;
  final int round;
  final String? mine;
  final String? react;

  bool get answered => mine != null;
  bool get canMore => answered && round < GasChat.maxRounds;

  GasChatState answer(String mine, String react) => GasChatState(topic: topic, round: round, mine: mine, react: react);
}
