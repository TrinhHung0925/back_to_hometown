import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/app_button.dart';
import '../../common/lixi_icon.dart';
import '../../game/game_config.dart';
import '../../game/logic/gas_chat.dart';
import '../../game/logic/provinces.dart';
import '../../game/logic/roadside.dart';
import '../../game/logic/vehicle_condition.dart';
import '../../game/stage.dart';
import '../../game/ve_que_game.dart';
import '../../game/vehicle_spec.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import 'family_widgets.dart';
import 'game_controller.dart';
import 'road_icons.dart';
import 'tet_night_widgets.dart';

/// Nút theo tình huống, hiện cạnh cụm nút lái: ghé quán / đổ xăng / vá xe
/// khi dừng sát lề trước quán, quay đầu khi đủ chậm, xử lý hết xăng / lốp xẹp.
class ContextActions extends StatelessWidget {
  const ContextActions({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hud = controller.hud.value;
      if (hud == null || controller.phase.value != GamePhase.driving || hud.actions.isEmpty) return const SizedBox.shrink();
      final vehicle = controller.setup.vehicle;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 250.h),
        child: Wrap(
          alignment: WrapAlignment.end,
          verticalDirection: VerticalDirection.up,
          spacing: 8.h,
          runSpacing: 8.h,
          children: [
            for (final action in hud.actions)
              _ActionPill(spec: _ActionSpec.of(action, hud, vehicle), onPressed: () => controller.onAction(action)),
          ],
        ),
      );
    });
  }
}

/// Nhãn, chú thích, icon, màu của một nút tình huống.
class _ActionSpec {
  const _ActionSpec(this.label, this.caption, this.glyph, this.color, {this.highlighted = false});

  final String label;
  final String? caption;
  final RoadGlyph glyph;
  final Color color;
  final bool highlighted;

  static _ActionSpec of(RoadAction action, HudData hud, VehicleKind vehicle) {
    final moto = vehicle == VehicleKind.motorbike;
    return switch (action) {
      RoadAction.visit => switch (hud.stallKind) {
          StallKind.xang => _ActionSpec('Đổ xăng', 'Vào cây xăng', RoadGlyph.pump, AppColors.ffEE9B2F, highlighted: true),
          StallKind.xangLe => _ActionSpec('Mua xăng', 'Xăng lẻ đóng chai', RoadGlyph.bottle, AppColors.ffEE9B2F, highlighted: true),
          StallKind.vaXe => _ActionSpec('Vá xe', hud.stallPrompt, RoadGlyph.wrench, AppColors.ff3A78A8, highlighted: true),
          _ => _ActionSpec('Ghé quán', hud.stallPrompt, RoadGlyph.cup, AppColors.ffD62828, highlighted: true),
        },
      RoadAction.approach => _ActionSpec(
          hud.stallKind?.enterLabel ?? 'Vào quán',
          [if (hud.stallPrompt != null) hud.stallPrompt!, if (hud.stallMeters != null) _distance(hud.stallMeters!)].join(' · '),
          switch (hud.stallKind) {
            StallKind.xang => RoadGlyph.pump,
            StallKind.xangLe => RoadGlyph.bottle,
            StallKind.vaXe => RoadGlyph.wrench,
            _ => RoadGlyph.cup,
          },
          hud.stallKind?.sellsFuel ?? false ? AppColors.ffEE9B2F : AppColors.ffD62828,
          highlighted: true,
        ),
      RoadAction.cancelApproach => _ActionSpec(
          'Thôi, không ghé',
          hud.stallMeters != null
              ? 'đang tấp vào · ${_distance(hud.stallMeters!)}'
              : hud.hitchMeters != null
                  ? 'đang tấp vào đón ${hud.hitchPrompt}'
                  : 'tự lái tiếp',
          RoadGlyph.steering,
          AppColors.ff5B6169,
        ),
      RoadAction.pickUp => _ActionSpec(
          'Cho đi nhờ',
          '${hud.hitchPrompt ?? 'Người vẫy xe'}${hud.hitchMeters == null ? '' : ' · ${_distance(hud.hitchMeters!)}'}',
          RoadGlyph.walker,
          AppColors.ff1E9C53,
          highlighted: true,
        ),
      RoadAction.dropOff => _ActionSpec(
          'Thả khách',
          hud.riderMeters == null ? '${hud.rider ?? 'Khách'} xuống đây' : '${hud.rider} · ${_distance(hud.riderMeters!)}',
          RoadGlyph.walker,
          AppColors.ff1E9C53,
          highlighted: true,
        ),
      RoadAction.uTurn => _ActionSpec(
          hud.reversed ? 'Quay đầu' : 'Quay đầu',
          hud.reversed ? 'về quê' : 'đi ngược lại',
          RoadGlyph.uTurn,
          AppColors.ff5B6169,
          highlighted: hud.reversed,
        ),
      RoadAction.tiltBike => const _ActionSpec('Nghiêng xe', 'dồn xăng sang bình', RoadGlyph.tilt, AppColors.ff1E9C53),
      RoadAction.push => _ActionSpec('Dắt bộ', hud.fuelAhead ?? 'tới chỗ bán xăng', RoadGlyph.walker, AppColors.ff5B6169),
      RoadAction.callFuel => _ActionSpec(
          moto ? 'Gọi xăng' : 'Gọi cứu hộ',
          '${switch (vehicle) {
            VehicleKind.motorbike => GameConfig.fuelRescueLixiMotorbike,
            VehicleKind.car => GameConfig.fuelRescueLixiCar,
            VehicleKind.bus => GameConfig.fuelRescueLixiBus,
          }} lì xì · ${(moto ? GameConfig.fuelRescueMinutesMotorbike : GameConfig.fuelRescueMinutesCar).round()} phút',
          RoadGlyph.phone,
          AppColors.ffD62828,
        ),
      RoadAction.spareTire => _ActionSpec(
          'Thay lốp',
          'dự phòng · ${(vehicle == VehicleKind.bus ? GameConfig.spareMinutesBus : GameConfig.spareMinutesCar).round()} phút',
          RoadGlyph.tire,
          AppColors.ff1E9C53,
        ),
      RoadAction.callMechanic => _ActionSpec(
          'Gọi thợ vá',
          '${GameConfig.mobileRepairLixi} lì xì · ${GameConfig.mobileRepairMinutes.round()} phút',
          RoadGlyph.phone,
          AppColors.ff3A78A8,
        ),
    };
  }
}

/// 650 m, 1,2 km.
String _distance(int meters) =>
    meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.spec, required this.onPressed});

  final _ActionSpec spec;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        height: 46.h,
        constraints: BoxConstraints(maxWidth: 196.h),
        padding: EdgeInsets.only(left: 5.h, right: 14.h),
        decoration: BoxDecoration(
          color: AppColors.ff1B1D22.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(23.h),
          border: Border.all(
            color: spec.highlighted ? AppColors.ffFFD166 : AppColors.ffFFFFFF.withValues(alpha: 0.28),
            width: 2.h,
          ),
          boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.25), blurRadius: 8.h, offset: Offset(0, 2.h))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34.h,
              height: 34.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(spec.color, AppColors.ffFFFFFF, 0.25)!, spec.color],
                ),
              ),
              child: RoadIcon(spec.glyph, size: 20.h, color: AppColors.ffFFFFFF, accent: spec.color),
            ),
            SizedBox(width: 8.h),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(spec.label, fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                  if (spec.caption != null)
                    AppText.manrope(spec.caption!, fontSize: 10.h, fontWeight: FontWeight.w700, color: AppColors.ffB8BCC4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nhãn nhắc đang đi ngược chiều về quê (sau khi quay đầu); dắt bộ thì báo
/// đang dắt xe.
class ReversedChip extends StatelessWidget {
  const ReversedChip({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hud = controller.hud.value;
      // Đang có điện thoại thì thẻ cuộc gọi nằm chỗ này.
      if (hud == null || controller.phase.value == GamePhase.resting || controller.call.value != null) return const SizedBox.shrink();
      final chips = <Widget>[
        // Chở cả nhà: bé còn kiên nhẫn bao nhiêu (mặt bé theo tâm trạng).
        if (hud.family != null) FamilyChip(family: hud.family!),
        if (hud.reversed) _chip(RoadGlyph.uTurn, 'Đi ngược về ${controller.setup.fromName}', AppColors.ffB4231E),
        if (hud.pushing) _chip(RoadGlyph.walker, 'Dắt bộ — giữ Ga để đẩy', AppColors.ff5B6169),
        if (hud.rider != null)
          _chip(RoadGlyph.walker, hud.riderMeters == null ? 'Chở ${hud.rider} — tấp lề' : 'Chở ${hud.rider} · còn ${_distance(hud.riderMeters!)}',
              AppColors.ff1E9C53),
        if (hud.peach != null)
          _chip(RoadGlyph.blossom, hud.peach! > 0 ? 'Cành đào ${hud.peach}%' : 'Cành đào gãy mất rồi', hud.peach! >= 60 ? AppColors.ffD94F7A : AppColors.ff5B6169),
        if (hud.fog) _chip(RoadGlyph.fog, 'Sương mù — bật đèn', AppColors.ff5B6169),
        ...NightColdChips.of(hud.cold),
      ];
      if (chips.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final c in chips) Padding(padding: EdgeInsets.only(bottom: 3.h), child: c)],
      );
    });
  }

  Widget _chip(RoadGlyph glyph, String text, Color color) => Container(
        height: 22.h,
        padding: EdgeInsets.symmetric(horizontal: 8.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(11.h),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoadIcon(glyph, size: 13.h, color: AppColors.ffFFFFFF, accent: color),
            SizedBox(width: 5.h),
            AppText.manrope(text, fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
          ],
        ),
      );
}

/// Buồn ngủ: mép màn hình tối dần; ngủ gật thì mí mắt khép lại.
class DrowsyOverlay extends StatelessWidget {
  const DrowsyOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Obx(() {
        final drowse = controller.hud.value?.drowse ?? 0;
        if (drowse <= 0.01) return const SizedBox.shrink();
        return CustomPaint(size: Size.infinite, painter: _EyelidPainter(drowse));
      }),
    );
  }
}

class _EyelidPainter extends CustomPainter {
  const _EyelidPainter(this.drowse);

  final double drowse;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final vignette = (drowse / 0.45).clamp(0.0, 1.0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.85,
          colors: [AppColors.ff000000.withValues(alpha: 0), AppColors.ff000000.withValues(alpha: 0.6 * vignette)],
          stops: const [0.55, 1],
        ).createShader(rect),
    );
    final close = ((drowse - 0.45) / 0.55).clamp(0.0, 1.0);
    if (close <= 0) return;
    final lid = size.height / 2 * close;
    final fade = size.height * 0.08;
    final top = Rect.fromLTWH(0, 0, size.width, lid + fade);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff000000, AppColors.ff000000, AppColors.ff000000.withValues(alpha: 0)],
          stops: [0, lid / top.height, 1],
        ).createShader(top),
    );
    final bottom = Rect.fromLTWH(0, size.height - lid - fade, size.width, lid + fade);
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppColors.ff000000, AppColors.ff000000, AppColors.ff000000.withValues(alpha: 0)],
          stops: [0, lid / bottom.height, 1],
        ).createShader(bottom),
    );
  }

  @override
  bool shouldRepaint(_EyelidPainter oldDelegate) => oldDelegate.drowse != drowse;
}

// ------------------------------------------------------------- Bảng quán
/// Đang ghé quán / cây xăng / tiệm vá xe: mái che sọc màu quán, tên quán,
/// chuyện trò, thực đơn (hoặc cột bơm, bảng vá xe), nút lên đường. Đặt bên
/// trái để vẫn thấy cảnh mình ngồi trong quán.
class StallSheet extends StatelessWidget {
  const StallSheet({super.key, required this.controller, required this.visit});

  final GameController controller;
  final StallVisit visit;

  static Color kindColor(StallKind kind) => switch (kind) {
        StallKind.traDa => AppColors.ffD62828,
        StallKind.nuocMia => AppColors.ff1E9C53,
        StallKind.caPheVong => AppColors.ff5B3A29,
        StallKind.banhMi => AppColors.ffEE9B2F,
        StallKind.com => AppColors.ff2F6BFF,
        StallKind.vaXe => AppColors.ff3A78A8,
        StallKind.xang || StallKind.xangLe => AppColors.ffC1121F,
      };

  @override
  Widget build(BuildContext context) {
    final stall = visit.stall;
    final color = kindColor(stall.kind);
    return Container(
      width: 420.h,
      decoration: BoxDecoration(
        color: AppColors.ffFFFBF2,
        borderRadius: BorderRadius.circular(20.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.3), blurRadius: 18.h, offset: Offset(0, 6.h))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final hud = controller.hud.value;
        final lixi = hud?.lixi ?? 0;
        final moto = controller.setup.vehicle == VehicleKind.motorbike;
        final raincoatOffer = moto && hud != null && !hud.raincoat && controller.game.weather.spells.isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 14.h, child: CustomPaint(painter: _AwningPainter(color))),
            Padding(
              padding: EdgeInsets.fromLTRB(14.h, 4.h, 14.h, 10.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.h, vertical: 4.h),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6.h)),
                        child: AppText.manrope(
                          stall.gouging ? 'VÁ XE 24H' : stall.kind.sign,
                          fontSize: 11.h,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ffFFFFFF,
                        ),
                      ),
                      SizedBox(width: 8.h),
                      Expanded(child: AppText.manrope(stall.name, fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22)),
                      _LixiBadge(lixi: lixi),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  if (!visit.seated)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      child: AppText.manrope(
                        stall.kind.sellsFuel ? 'Tắt máy, chờ người bán ra…' : 'Dựng xe, đi vào quán…',
                        fontSize: 13.h,
                        fontWeight: FontWeight.w700,
                        textAlign: TextAlign.center,
                        color: AppColors.ff6B7280,
                      ),
                    )
                  else ...[
                    ...switch (stall.kind) {
                      StallKind.xang => _gasOffers(hud, lixi),
                      StallKind.xangLe => _bottleOffers(hud, lixi),
                      StallKind.vaXe => _repairOffers(hud, lixi, stall),
                      _ => [
                          // Đặc sản tỉnh đang đi qua (nhỉnh hơn món thường); quán
                          // đã nhiều món thì chỉ bày một món cho bảng khỏi dài.
                          for (final item in controller.game
                              .specialtiesAt(stall)
                              .take(stall.kind.menu.length + (raincoatOffer ? 1 : 0) >= 3 ? 1 : 2))
                            _OfferRow(
                              art: Img.item(item.art),
                              title: item.name,
                              caption: 'Đặc sản ${Provinces.provinceOf(item)?.name ?? 'địa phương'} · +${item.alert.round()} tỉnh táo · ${item.minutes.round()} phút',
                              price: item.price,
                              button: 'Gọi',
                              accent: AppColors.ffEE9B2F,
                              enabled: lixi >= item.price,
                              onPressed: () => controller.order(item),
                            ),
                          for (final item in stall.kind.menu)
                            _OfferRow(
                              art: Img.item(item.art),
                              title: item.name,
                              caption: '+${item.alert.round()} tỉnh táo · ${item.minutes.round()} phút',
                              price: item.price,
                              button: 'Gọi',
                              enabled: lixi >= item.price,
                              onPressed: () => controller.order(item),
                            ),
                        ],
                    },
                    // Chở cả nhà: bim bim, hộp sữa cho bé (một hàng gọn).
                    FamilySnackRow(controller: controller, kind: stall.kind, lixi: lixi),
                    if (raincoatOffer)
                      _OfferRow(
                        art: Img.imgItemRaincoat,
                        title: 'Áo mưa cánh dơi',
                        caption: 'Đi mưa không ướt, không lạnh run',
                        price: GameConfig.raincoatLixi,
                        button: 'Mua',
                        accent: AppColors.ff3A78A8,
                        enabled: lixi >= GameConfig.raincoatLixi,
                        onPressed: controller.buyRaincoat,
                      ),
                    SeasonalOffers(controller: controller, lixi: lixi),
                  ],
                  SizedBox(height: 6.h),
                  Row(
                    children: [
                      Expanded(child: _FooterStatus(hud: hud, fuelFirst: stall.kind.sellsFuel)),
                      SizedBox(width: 12.h),
                      AppButton(label: 'Đi tiếp', icon: Img.icPlay, onPressed: controller.leaveStall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Cây xăng: màn hình cột bơm, đổ theo lì xì hoặc đổ đầy.
  List<Widget> _gasOffers(HudData? hud, int lixi) {
    final tank = controller.game.fuel;
    final full = tank.fullPrice;
    return [
      _PumpDisplay(pump: controller.pump.value, level: tank.level, tankLiters: _tankLiters(controller.setup.vehicle) * controller.game.perks.fuelCapacity),
      SizedBox(height: 6.h),
      _OfferRow(
        art: Img.imgItemNozzle,
        title: 'Đổ 1 lì xì',
        caption: full == 0 ? 'Bình đầy rồi' : '+${(min(tank.perLixi, 1 - tank.level) * 100).round()}% bình',
        price: full == 0 ? -1 : 1,
        button: 'Đổ',
        accent: AppColors.ffEE9B2F,
        enabled: lixi >= 1 && full > 0,
        onPressed: () => controller.refuel(lixi: 1),
      ),
      _OfferRow(
        art: Img.imgItemNozzle,
        title: 'Đổ đầy bình',
        caption: full == 0 ? 'Bình đầy rồi' : 'Chạy được chừng ${tank.rangeKm.round()} km',
        price: full == 0 ? -1 : full,
        button: 'Đầy',
        accent: AppColors.ffEE9B2F,
        enabled: full > 0 && lixi >= full,
        onPressed: () => controller.refuel(),
      ),
    ];
  }

  /// Xăng lẻ: kệ chai, mua từng chai.
  List<Widget> _bottleOffers(HudData? hud, int lixi) {
    final tank = controller.game.fuel;
    return [
      _PumpDisplay(pump: controller.pump.value, level: tank.level, tankLiters: _tankLiters(controller.setup.vehicle) * controller.game.perks.fuelCapacity, bottles: true),
      SizedBox(height: 6.h),
      _OfferRow(
        art: Img.imgItemBottle,
        title: 'Một chai xăng',
        caption: '+${(min(GameConfig.fuelBottle, 1 - tank.level) * 100).round()}% bình · đắt hơn cây xăng',
        price: 1,
        button: 'Mua',
        accent: AppColors.ffEE9B2F,
        enabled: lixi >= 1 && tank.level < 0.99,
        onPressed: () => controller.refuel(bottle: true),
      ),
    ];
  }

  /// Tiệm vá xe: tình trạng lốp, các cách sửa, cốc trà đá ngồi chờ.
  List<Widget> _repairOffers(HudData? hud, int lixi, Stall stall) {
    final tire = hud?.tire ?? TireState.ok;
    final options = RepairOption.shopOptions(controller.setup.vehicle, gouging: stall.gouging);
    return [
      _TireStatus(tire: tire, gouging: stall.gouging),
      SizedBox(height: 4.h),
      for (final o in options)
        _OfferRow(
          art: Img.item(o.art),
          title: o.name,
          caption: tire == TireState.ruined && !o.forRuined ? 'Săm nát rồi, vá không được' : '${o.detail} · ${o.minutes.round()} phút',
          price: o.price,
          button: 'Làm',
          accent: AppColors.ff3A78A8,
          enabled: tire != TireState.ok && (tire != TireState.ruined || o.forRuined) && lixi >= o.price,
          onPressed: () => controller.repair(o),
        ),
      for (final item in stall.kind.menu)
        _OfferRow(
          art: Img.item(item.art),
          title: item.name,
          caption: '+${item.alert.round()} tỉnh táo · ${item.minutes.round()} phút',
          price: item.price,
          button: 'Gọi',
          enabled: lixi >= item.price,
          onPressed: () => controller.order(item),
        ),
    ];
  }

  static double _tankLiters(VehicleKind kind) => switch (kind) {
        VehicleKind.motorbike => 5,
        VehicleKind.car => 45,
        VehicleKind.bus => 200,
      };
}

/// Mái che sọc kiểu mái hiên quán, mép dưới lượn vỏ sò.
class _AwningPainter extends CustomPainter {
  const _AwningPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stripe = size.height * 1.6;
    final n = (size.width / stripe).ceil();
    final body = size.height * 0.62;
    for (var i = 0; i < n; i++) {
      final x = i * stripe;
      final paint = Paint()..color = i.isEven ? color : AppColors.ffFFFFFF;
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, body), paint);
      canvas.drawArc(Rect.fromLTWH(x, body - stripe / 2, stripe, stripe), 0, pi, true, paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, body),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff000000.withValues(alpha: 0.18), AppColors.ff000000.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, body)),
    );
  }

  @override
  bool shouldRepaint(_AwningPainter oldDelegate) => oldDelegate.color != color;
}

class _LixiBadge extends StatelessWidget {
  const _LixiBadge({required this.lixi});

  final int lixi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.h, vertical: 3.h),
      decoration: BoxDecoration(color: AppColors.ffFFF4D6, borderRadius: BorderRadius.circular(10.h)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LixiIcon(height: 18.h),
          SizedBox(width: 4.h),
          AppText.manrope('$lixi', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
        ],
      ),
    );
  }
}

/// Chuyện nghe được ở quán: bong bóng lời thoại nổi trên cảnh quán (người
/// nói in đậm), đổi câu mỗi ~4 giây.
class StallChatter extends StatefulWidget {
  const StallChatter({super.key, required this.chatter});

  final List<String> chatter;

  @override
  State<StallChatter> createState() => _StallChatterState();
}

class _StallChatterState extends State<StallChatter> {
  int _line = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 4200), (_) {
      if (mounted) setState(() => _line = (_line + 1) % max(1, widget.chatter.length));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chatter.isEmpty) return const SizedBox.shrink();
    final text = widget.chatter[_line % widget.chatter.length];
    final split = text.indexOf(': ');
    final speaker = split > 0 ? text.substring(0, split) : '';
    final line = split > 0 ? text.substring(split + 2) : text;
    return Align(
      alignment: Alignment.bottomRight,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        // Chỉ hiện câu mới (câu cũ biến luôn) để chữ không chồng lên nhau.
        layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), alignment: Alignment.topLeft, child: child),
        ),
        child: Column(
          key: ValueKey(_line),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Đuôi bong bóng chĩa lên phía quán.
            Padding(
              padding: EdgeInsets.only(left: 28.h),
              child: Transform.flip(flipY: true, child: CustomPaint(size: Size(16.h, 10.h), painter: _BubbleTailPainter())),
            ),
            Container(
              constraints: BoxConstraints(maxWidth: 280.h),
              padding: EdgeInsets.fromLTRB(12.h, 7.h, 12.h, 8.h),
              decoration: BoxDecoration(
                color: AppColors.ffFFFBF2,
                borderRadius: BorderRadius.circular(14.h),
                border: Border.all(color: AppColors.ff1B1D22, width: 2.h),
                boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.25), blurRadius: 10.h, offset: Offset(0, 3.h))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaker.isNotEmpty)
                    AppText.manrope(speaker, fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ffB4231E),
                  AppText.manrope(line, fontSize: 12.5.h, fontWeight: FontWeight.w700, maxLines: 3, color: AppColors.ff1B1D22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tán gẫu với nhân viên cây xăng: câu hỏi, ba câu trả lời để chọn, rồi
/// câu mình nói và câu nhân viên đáp; được hỏi tiếp vài lượt.
class GasChatPanel extends StatelessWidget {
  const GasChatPanel({super.key, required this.chat, required this.onAnswer, required this.onMore});

  final GasChatState chat;
  final ValueChanged<ChatReply> onAnswer;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final to = Get.find<GameController>().setup.toName;
    return Container(
      width: 266.h,
      padding: EdgeInsets.fromLTRB(10.h, 8.h, 10.h, 10.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFBF2,
        borderRadius: BorderRadius.circular(16.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 2.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.25), blurRadius: 12.h, offset: Offset(0, 4.h))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26.h,
                height: 26.h,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.ffC1121F, shape: BoxShape.circle),
                child: RoadIcon(RoadGlyph.pump, size: 15.h, color: AppColors.ffFFFFFF, accent: AppColors.ffC1121F),
              ),
              SizedBox(width: 7.h),
              Expanded(child: AppText.manrope('Nhân viên cây xăng', fontSize: 11.5.h, fontWeight: FontWeight.w800, color: AppColors.ffB4231E)),
              AppText.manrope('${chat.round}/${GasChat.maxRounds}', fontSize: 10.h, fontWeight: FontWeight.w700, color: AppColors.ff9A9385),
            ],
          ),
          SizedBox(height: 6.h),
          _ChatBubble(text: chat.topic.ask),
          if (!chat.answered) ...[
            SizedBox(height: 7.h),
            for (final reply in chat.topic.replies)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => onAnswer(reply),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.h, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppColors.ffFFFFFF,
                      borderRadius: BorderRadius.circular(10.h),
                      border: Border.all(color: AppColors.ffEE9B2F, width: 1.5.h),
                    ),
                    child: Row(
                      children: [
                        Image.asset(Img.icChat, height: 13.h, color: AppColors.ffEE9B2F),
                        SizedBox(width: 6.h),
                        Expanded(
                          child: AppText.manrope(reply.text.replaceAll('{to}', to),
                              fontSize: 11.5.h, fontWeight: FontWeight.w700, maxLines: 2, color: AppColors.ff1B1D22),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ] else ...[
            SizedBox(height: 5.h),
            _ChatBubble(text: chat.mine!, mine: true),
            SizedBox(height: 5.h),
            _ChatBubble(text: chat.react!),
            if (chat.canMore) ...[
              SizedBox(height: 7.h),
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: onMore,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.h, vertical: 6.h),
                    decoration: BoxDecoration(color: AppColors.ffEE9B2F, borderRadius: BorderRadius.circular(10.h)),
                    child: AppText.manrope('Tán tiếp ›', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Một câu thoại: của nhân viên (trái, nền kem) hoặc của mình (phải, nền cam).
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, this.mine = false});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 222.h),
        padding: EdgeInsets.fromLTRB(10.h, 6.h, 10.h, 7.h),
        decoration: BoxDecoration(
          color: mine ? AppColors.ffFFE3A1 : AppColors.ffF1E7D2,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.h),
            topRight: Radius.circular(12.h),
            bottomLeft: Radius.circular(mine ? 12.h : 3.h),
            bottomRight: Radius.circular(mine ? 3.h : 12.h),
          ),
        ),
        child: AppText.manrope(text, fontSize: 12.h, fontWeight: FontWeight.w700, maxLines: 4, color: AppColors.ff1B1D22),
      ),
    );
  }
}

/// Đuôi bong bóng thoại chĩa xuống.
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -2)
      ..lineTo(size.width, -2)
      ..lineTo(size.width * 0.15, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.ffFFFBF2);
    canvas.drawPath(
      Path()
        ..moveTo(size.width, -1)
        ..lineTo(size.width * 0.15, size.height)
        ..lineTo(0, -1),
      Paint()
        ..color = AppColors.ff1B1D22
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Một món / dịch vụ: ảnh minh hoạ, tên, chú thích, giá, nút.
class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.art,
    required this.title,
    required this.caption,
    required this.price,
    required this.button,
    required this.enabled,
    required this.onPressed,
    this.accent = AppColors.ffD62828,
  });

  final String art;
  final String title;
  final String caption;
  final int price;
  final String button;
  final bool enabled;
  final VoidCallback onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.h),
      child: Row(
        children: [
          Container(
            width: 36.h,
            height: 36.h,
            padding: EdgeInsets.all(2.h),
            decoration: BoxDecoration(color: AppColors.ffF1E7D2, borderRadius: BorderRadius.circular(9.h)),
            child: Image.asset(art),
          ),
          SizedBox(width: 10.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.manrope(title, fontSize: 13.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                AppText.manrope(caption, fontSize: 10.5.h, fontWeight: FontWeight.w600, color: AppColors.ff6B7280),
              ],
            ),
          ),
          if (price < 0)
            const SizedBox.shrink()
          else if (price == 0)
            AppText.manrope('Miễn phí', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53)
          else ...[
            LixiIcon(height: 18.h),
            SizedBox(width: 4.h),
            AppText.manrope('$price', fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ],
          SizedBox(width: 10.h),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: enabled ? onPressed : null,
            child: Container(
              width: 56.h,
              height: 30.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? accent : AppColors.ffE3E5E9,
                borderRadius: BorderRadius.circular(10.h),
                border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: enabled ? 0.3 : 0.08), width: 1.5.h),
              ),
              child: AppText.manrope(
                button,
                fontSize: 13.h,
                fontWeight: FontWeight.w800,
                color: enabled ? AppColors.ffFFFFFF : AppColors.ff9A9385,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dòng cuối bảng: thanh tỉnh táo hoặc đồng hồ xăng, giờ hiện tại.
class _FooterStatus extends StatelessWidget {
  const _FooterStatus({required this.hud, required this.fuelFirst});

  final HudData? hud;
  final bool fuelFirst;

  @override
  Widget build(BuildContext context) {
    final alert = hud?.alert ?? 100;
    final fuel = hud?.fuel ?? 1;
    Widget bar(String label, double value, Color color, String text) => Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 52.h,
                child: AppText.manrope(label, fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.h),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: value),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8.h,
                      backgroundColor: AppColors.ffE3E5E9,
                      color: color,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 6.h),
              AppText.manrope(text, fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
            ],
          ),
        );
    final alertBar = bar('Tỉnh táo', alert / 100, alert >= 45 ? AppColors.ff1E9C53 : alert >= 25 ? AppColors.ffEE9B2F : AppColors.ffD62828, '$alert%');
    final fuelBar = bar('Xăng', fuel, fuel >= 0.35 ? AppColors.ff1E9C53 : fuel >= 0.12 ? AppColors.ffEE9B2F : AppColors.ffD62828, '${(fuel * 100).round()}%');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [if (fuelFirst) fuelBar else alertBar]),
        SizedBox(height: 5.h),
        Row(children: [if (fuelFirst) alertBar else fuelBar]),
      ],
    );
  }
}

/// Màn hình cột bơm: số lít và số lì xì chạy lên khi đang bơm, đồng hồ bình
/// xăng E — F bên dưới. [bottles]: kệ xăng lẻ (đếm theo chai).
class _PumpDisplay extends StatelessWidget {
  const _PumpDisplay({required this.pump, required this.level, required this.tankLiters, this.bottles = false});

  /// Mức bình trước / sau lần đổ gần nhất (null nếu chưa đổ).
  final (double, double)? pump;

  /// Mức bình hiện tại (khi chưa đổ lần nào).
  final double level;
  final double tankLiters;
  final bool bottles;

  @override
  Widget build(BuildContext context) {
    final (before, after) = pump ?? (level, level);
    final liters = (after - before) * tankLiters;
    return Container(
      padding: EdgeInsets.fromLTRB(12.h, 6.h, 12.h, 7.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.ff1F4E9C, AppColors.ff23408E]),
        borderRadius: BorderRadius.circular(12.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 2.h),
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(pump),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: pump == null ? 1 : 1400),
        curve: Curves.easeOutCubic,
        builder: (context, k, _) {
          final shownLiters = liters * k;
          final level = before + (after - before) * k;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _LedField(label: bottles ? 'SỐ CHAI' : 'SỐ LÍT', value: bottles ? (shownLiters / (GameConfig.fuelBottle * tankLiters)).toStringAsFixed(0) : shownLiters.toStringAsFixed(2), color: AppColors.ffFFB547)),
                  SizedBox(width: 10.h),
                  Expanded(child: _LedField(label: 'BÌNH XĂNG', value: '${(level * 100).round()}%', color: AppColors.ff7CFFB2)),
                ],
              ),
              SizedBox(height: 6.h),
              _TankGauge(level: level),
            ],
          );
        },
      ),
    );
  }
}

/// Ô số LED: nhãn nhỏ, các chữ số trong ô tối.
class _LedField extends StatelessWidget {
  const _LedField({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText.manrope(label, fontSize: 9.h, fontWeight: FontWeight.w800, color: AppColors.ffB8BCC4, letterSpacing: 0.8),
        SizedBox(height: 2.h),
        Container(
          height: 23.h,
          padding: EdgeInsets.symmetric(horizontal: 6.h),
          decoration: BoxDecoration(
            color: AppColors.ff0E1216,
            borderRadius: BorderRadius.circular(6.h),
            border: Border.all(color: AppColors.ff1A2129, width: 1.5.h),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final ch in value.split(''))
                SizedBox(
                  width: ch == '.' ? 6.h : 12.h,
                  child: AppText.manrope(
                    ch,
                    fontSize: 15.h,
                    fontWeight: FontWeight.w800,
                    textAlign: TextAlign.center,
                    color: color,
                    shadow: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 6.h)],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Đồng hồ bình xăng: vạch E — ½ — F, kim là phần tô màu.
class _TankGauge extends StatelessWidget {
  const _TankGauge({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final color = level >= 0.35 ? AppColors.ff4ADE80 : level >= 0.12 ? AppColors.ffFFD166 : AppColors.ffFF5A4E;
    return Row(
      children: [
        AppText.manrope('E', fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ffFF8FAB),
        SizedBox(width: 6.h),
        Expanded(
          child: SizedBox(
            height: 10.h,
            child: CustomPaint(painter: _TankGaugePainter(level, color)),
          ),
        ),
        SizedBox(width: 6.h),
        AppText.manrope('F', fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
      ],
    );
  }
}

class _TankGaugePainter extends CustomPainter {
  const _TankGaugePainter(this.level, this.color);

  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(r, Paint()..color = AppColors.ff0E1216);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * level.clamp(0.0, 1.0), size.height),
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0.75), color]).createShader(Offset.zero & size),
    );
    canvas.restore();
    final tick = Paint()
      ..color = AppColors.ffFFFFFF.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      final long = i == 4;
      canvas.drawLine(Offset(x, long ? 1 : size.height * 0.3), Offset(x, long ? size.height - 1 : size.height * 0.7), tick);
    }
  }

  @override
  bool shouldRepaint(_TankGaugePainter oldDelegate) => oldDelegate.level != level || oldDelegate.color != color;
}

/// Tình trạng lốp ở tiệm vá xe; tiệm sau bãi đinh thì có nhãn "giá Tết".
class _TireStatus extends StatelessWidget {
  const _TireStatus({required this.tire, required this.gouging});

  final TireState tire;
  final bool gouging;

  @override
  Widget build(BuildContext context) {
    final (text, color, glyph) = switch (tire) {
      TireState.ok => ('Lốp còn căng — không cần vá', AppColors.ff1E9C53, RoadGlyph.tire),
      TireState.flat => ('Lốp xẹp — dính đinh rồi', AppColors.ffD62828, RoadGlyph.tireFlat),
      TireState.ruined => ('Chạy lốp xẹp lâu — nát săm', AppColors.ff8E1428, RoadGlyph.tireFlat),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.h, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.h),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5.h),
      ),
      child: Row(
        children: [
          RoadIcon(glyph, size: 22.h, color: color, accent: AppColors.ffFFFBF2),
          SizedBox(width: 8.h),
          Expanded(child: AppText.manrope(text, fontSize: 13.h, fontWeight: FontWeight.w800, color: color)),
          if (gouging)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.h, vertical: 2.h),
              decoration: BoxDecoration(color: AppColors.ffD62828, borderRadius: BorderRadius.circular(6.h)),
              child: AppText.manrope('Giá Tết ×2', fontSize: 10.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- Việc bên lề
/// Thẻ việc bên lề (thay lốp, chờ xăng, thợ vá lưu động): từng bước tích
/// xanh dần, thanh tiến độ, tốn bao nhiêu phút và lì xì.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.state});

  final JobState state;

  @override
  Widget build(BuildContext context) {
    final job = state.job;
    final steps = job.steps;
    final (glyph, color) = switch (job.kind) {
      RoadsideJobKind.spareTire => (RoadGlyph.tire, AppColors.ff1E9C53),
      RoadsideJobKind.fuelDelivery => (RoadGlyph.pump, AppColors.ffEE9B2F),
      RoadsideJobKind.mobileRepair => (RoadGlyph.wrench, AppColors.ff3A78A8),
    };
    return Container(
      width: 330.h,
      padding: EdgeInsets.fromLTRB(14.h, 12.h, 14.h, 12.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFFBF2,
        borderRadius: BorderRadius.circular(18.h),
        border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.3), blurRadius: 16.h, offset: Offset(0, 5.h))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36.h,
                height: 36.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: RoadIcon(glyph, size: 22.h, color: AppColors.ffFFFFFF, accent: color),
              ),
              SizedBox(width: 10.h),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.manrope(job.title, fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                    AppText.manrope(
                      '${job.minutes.round()} phút${job.lixi > 0 ? ' · ${job.lixi} lì xì' : ' · tự làm'}',
                      fontSize: 11.h,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ff6B7280,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          for (var i = 0; i < steps.length; i++) _JobStep(text: steps[i], state: _stepState(i, steps.length), color: color),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.h),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 7.h,
              backgroundColor: AppColors.ffE3E5E9,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 0 chưa tới, 1 đang làm, 2 xong.
  int _stepState(int i, int count) {
    final p = state.progress * count;
    if (p >= i + 1) return 2;
    if (p >= i) return 1;
    return 0;
  }
}

class _JobStep extends StatelessWidget {
  const _JobStep({required this.text, required this.state, required this.color});

  final String text;
  final int state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final done = state == 2;
    final active = state == 1;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 20.h,
            height: 20.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppColors.ff1E9C53 : AppColors.ffFFFFFF,
              border: Border.all(color: done ? AppColors.ff1E9C53 : (active ? color : AppColors.ffCFC8B8), width: 2.h),
            ),
            child: done
                ? Image.asset(Img.icCheck, width: 12.h, height: 12.h, color: AppColors.ffFFFFFF)
                : active
                    ? SizedBox(width: 10.h, height: 10.h, child: CupertinoActivityIndicator(radius: 5.h, color: color))
                    : null,
          ),
          SizedBox(width: 10.h),
          Expanded(
            child: AppText.manrope(
              text,
              fontSize: 13.h,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: state == 0 ? AppColors.ff9A9385 : AppColors.ff1B1D22,
            ),
          ),
        ],
      ),
    );
  }
}
