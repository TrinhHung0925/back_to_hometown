import 'dart:math';

import 'package:back_to_hometown/game/logic/radio_bulletin.dart';
import 'package:back_to_hometown/game/logic/soundscape.dart';
import 'package:back_to_hometown/game/logic/weather.dart';
import 'package:back_to_hometown/game/stage.dart';
import 'package:back_to_hometown/model/map_theme.dart';
import 'package:back_to_hometown/model/trip.dart';
import 'package:back_to_hometown/resource/app_resource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quiet = RadioFacts(minutesLeft: 400, clockMinutes: 1040, spareMinutes: 30);

  group('RadioDesk', () {
    test('tin đường đọc trước, gần nhất trước, mỗi tin một lần', () {
      final desk = RadioDesk(Random(1));
      const facts = RadioFacts(minutesLeft: 400, clockMinutes: 1040, jamKm: 12, fogKm: 5.2, ferryKm: 60);
      final first = desk.next(facts);
      expect(first.kind, NoticeKind.radio);
      expect(first.segment, RadioSegment.traffic);
      expect(first.text, contains('Sương mù'));
      expect(first.text, contains('5 km'));
      final second = desk.next(facts);
      expect(second.segment, RadioSegment.traffic);
      expect(second.text, contains('ùn ứ'));
      expect(second.text, contains('10 km'));
      // Bến phà còn xa quá (60 km) thì chưa báo; các tin đã báo không lặp.
      for (var i = 0; i < 6; i++) {
        final b = desk.next(facts);
        expect(b.text, isNot(contains('Bến phà')));
        expect(b.text, isNot(contains('ùn ứ')));
      }
    });

    test('gần quá thì thôi báo (game tự cảnh báo), đi qua rồi cũng thôi', () {
      final desk = RadioDesk(Random(2));
      final b = desk.next(const RadioFacts(minutesLeft: 400, clockMinutes: 1040, jamKm: 0.8, rampKm: null));
      expect(b.segment, isNot(RadioSegment.traffic));
    });

    test('báo trước cơn mưa sắp tới, nhắc xe máy mặc áo mưa', () {
      final desk = RadioDesk(Random(3));
      final b = desk.next(const RadioFacts(
        minutesLeft: 400,
        clockMinutes: 1040,
        rainInMinutes: 22,
        rainKind: RainKind.drizzle,
        nextSpell: 0,
        motorbike: true,
      ));
      expect(b.segment, RadioSegment.weather);
      expect(b.text, contains('20 phút'));
      expect(b.text, contains('áo mưa'));
      // Cùng cơn mưa đó không báo lại.
      final again = desk.next(const RadioFacts(minutesLeft: 390, clockMinutes: 1050, rainInMinutes: 12, rainKind: RainKind.drizzle, nextSpell: 0));
      expect(again.text, isNot(contains('mưa phùn, đường sẽ trơn')));
    });

    test('đường cứu nạn trên đèo và đang mưa to', () {
      final desk = RadioDesk(Random(4));
      final ramp = desk.next(const RadioFacts(minutesLeft: 400, clockMinutes: 1040, rampKm: 7.6, theme: MapTheme.mountain));
      expect(ramp.text, contains('đường cứu nạn'));
      expect(ramp.text, contains('8 km'));
      final rain = desk.next(const RadioFacts(minutesLeft: 400, clockMinutes: 1040, rainNow: 0.8, rainNowKind: RainKind.shower, rainSpell: 1));
      expect(rain.segment, RadioSegment.weather);
      expect(rain.text, contains('Mưa rào'));
    });

    test('không có tin đường: chào, báo giờ giao thừa định kỳ, xen lời chúc, không lặp câu', () {
      final desk = RadioDesk(Random(5));
      final texts = <String>[];
      final segments = <RadioSegment>[];
      for (var i = 0; i < 14; i++) {
        final b = desk.next(quiet);
        texts.add(b.text);
        segments.add(b.segment);
      }
      expect(segments.first, RadioSegment.greeting);
      expect(texts.first, contains('Chiều 30 Tết'));
      expect(segments.where((s) => s == RadioSegment.countdown).length, greaterThanOrEqualTo(3));
      expect(segments, contains(RadioSegment.weather));
      expect(segments, contains(RadioSegment.dedication));
      expect(segments, contains(RadioSegment.safety));
      // Ngoài báo giờ (cùng số liệu nên cùng câu), không câu nào lặp lại.
      final others = [for (var i = 0; i < texts.length; i++) if (segments[i] != RadioSegment.countdown) texts[i]];
      expect(others.toSet().length, others.length);
    });

    test('báo giờ: dư giờ, sát giờ, trễ giờ, giờ cuối', () {
      expect(RadioDesk.countdownText(const RadioFacts(minutesLeft: 200, clockMinutes: 1240, spareMinutes: 25)), allOf(contains('3 tiếng 20 phút'), contains('dư chừng 25 phút')));
      expect(RadioDesk.countdownText(const RadioFacts(minutesLeft: 95, clockMinutes: 1345, spareMinutes: 2)), contains('vừa kịp'));
      expect(RadioDesk.countdownText(const RadioFacts(minutesLeft: 95, clockMinutes: 1345, spareMinutes: -18)), contains('trễ chừng 20 phút'));
      expect(RadioDesk.countdownText(const RadioFacts(minutesLeft: 42, clockMinutes: 1398)), startsWith('Chỉ còn 40 phút'));
      // Giờ cuối báo ngay, không chờ tới lượt.
      final desk = RadioDesk(Random(6));
      desk.next(quiet);
      final last = desk.next(const RadioFacts(minutesLeft: 50, clockMinutes: 1390));
      expect(last.segment, RadioSegment.countdown);
    });

    test('thời tiết theo miền', () {
      expect(RadioDesk.weatherText(const RadioFacts(minutesLeft: 1, clockMinutes: 0)), contains('miền Bắc rét đậm'));
      expect(RadioDesk.weatherText(const RadioFacts(minutesLeft: 1, clockMinutes: 0, south: true)), contains('Nam Bộ nắng ấm'));
      expect(RadioDesk.weatherText(const RadioFacts(minutesLeft: 1, clockMinutes: 0, theme: MapTheme.coast)), contains('Miền Trung'));
    });

    test('bản tin ngắn (tối đa hai dòng trên khung)', () {
      final desk = RadioDesk(Random(7));
      for (var i = 0; i < 40; i++) {
        final facts = RadioFacts(minutesLeft: 400.0 - i * 9, clockMinutes: 1040.0 + i * 9, spareMinutes: -40.0 + i * 3, night: i.isOdd, motorbike: i % 3 == 0);
        expect(desk.next(facts).text.length, lessThanOrEqualTo(125));
      }
      expect(RadioDesk.km(3.4), '3 km');
      expect(RadioDesk.km(17), '15 km');
      expect(RadioDesk.minutes(63), '1 tiếng 5 phút');
    });
  });

  group('Soundscape', () {
    test('theo cảnh, ngày đêm, đoạn đường', () {
      Soundscape pick(MapTheme theme, RoadKind zone, {bool night = false, double left = 400, double rain = 0, bool cabin = false}) =>
          Soundscape.pick(theme: theme, zone: zone, night: night, minutesLeft: left, rain: rain, cabin: cabin);
      expect(pick(MapTheme.delta, RoadKind.highway).file, AppAudio.ambDeltaDay);
      expect(pick(MapTheme.delta, RoadKind.highway, night: true).file, AppAudio.ambDeltaNight);
      expect(pick(MapTheme.coast, RoadKind.highway).file, AppAudio.ambCoastDay);
      expect(pick(MapTheme.coast, RoadKind.highway, night: true).file, AppAudio.ambCoastNight);
      expect(pick(MapTheme.mountain, RoadKind.highway, night: true).file, AppAudio.ambMountainNight);
      expect(pick(MapTheme.mekong, RoadKind.highway).file, AppAudio.ambMekongDay);
      expect(pick(MapTheme.mekong, RoadKind.highway, night: true).file, AppAudio.ambDeltaNight);
      expect(pick(MapTheme.mountain, RoadKind.city).file, AppAudio.ambCity);
      // Phố đêm gần giao thừa, hay sát giờ ở bất cứ đâu: trống lân, pháo hoa.
      expect(pick(MapTheme.delta, RoadKind.city, night: true, left: 120).file, AppAudio.ambTetEve);
      expect(pick(MapTheme.coast, RoadKind.highway, night: true, left: 30).file, AppAudio.ambTetEve);
      // Cao tốc, mưa, ngồi trong ô tô thì nhỏ hơn.
      final base = pick(MapTheme.delta, RoadKind.highway).volume;
      expect(pick(MapTheme.delta, RoadKind.expressway).volume, lessThan(base));
      expect(pick(MapTheme.delta, RoadKind.highway, rain: 0.9).volume, lessThan(base));
      expect(pick(MapTheme.delta, RoadKind.highway, cabin: true).volume, lessThan(base));
      expect(base, closeTo(Soundscape.baseVolume, 0.011));
    });
  });
}
