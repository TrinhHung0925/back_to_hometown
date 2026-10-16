import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../common/lixi_icon.dart';
import '../common/shop_glyphs.dart';
import '../model/shop.dart';
import '../model/trip.dart';
import '../resource/app_colors.dart';
import '../resource/app_resource.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';
import '../service/shop_service.dart';

/// Cửa hàng ở trạm dừng nghỉ: hai thẻ "Nâng cấp xe" và "Quà cho cả nhà".
/// Mua bằng lì xì của chuyến đi, lưu ngay.
class ShopDialog extends StatefulWidget {
  const ShopDialog({super.key, required this.progress, this.onChanged, this.initialTab = 0});

  final TripProgress progress;

  /// Gọi sau mỗi lần mua (để màn trạm dừng nghỉ cập nhật lì xì, xăng).
  final VoidCallback? onChanged;
  final int initialTab;

  static Future<void> open(TripProgress progress, {VoidCallback? onChanged, int tab = 0}) =>
      Get.dialog<void>(ShopDialog(progress: progress, onChanged: onChanged, initialTab: tab));

  @override
  State<ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<ShopDialog> {
  late int _tab = widget.initialTab;

  /// Món vừa mua (nảy lên một chút).
  Object? _justBought;

  TripProgress get _p => widget.progress;
  ShopService get _shop => ShopService.shared;

  void _bought(Object item) {
    AudioService.shared.play(AppAudio.sfxConfirm, volume: 0.8);
    AudioService.shared.lixi();
    setState(() => _justBought = item);
    widget.onChanged?.call();
  }

  void _buyUpgrade(Upgrade u) {
    if (_shop.buyUpgrade(_p, u)) _bought(u);
  }

  void _buyGift(Gift g) {
    if (_shop.buyGift(_p, g)) _bought(g);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.ffFFFBF2,
        borderRadius: BorderRadius.circular(20.h),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 700.h,
          // Viền vẽ đè lên mái hiên sọc cho góc bo gọn.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.h),
            border: Border.all(color: AppColors.ff1B1D22, width: 3.h),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16.h, child: const CustomPaint(painter: _AwningPainter())),
              Padding(
                padding: EdgeInsets.fromLTRB(16.h, 6.h, 12.h, 14.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    SizedBox(height: 10.h),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _tab == 0
                          ? _UpgradeGrid(key: const ValueKey('upgrades'), progress: _p, justBought: _justBought, onBuy: _buyUpgrade)
                          : _GiftBoard(key: const ValueKey('gifts'), progress: _p, justBought: _justBought, onBuy: _buyGift),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 36.h,
          height: 36.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.ffD62828, borderRadius: BorderRadius.circular(10.h)),
          child: ShopIcon(ShopGlyph.stall, size: 24.h, color: AppColors.ffFFD166, accent: AppColors.ffD62828),
        ),
        SizedBox(width: 10.h),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText.paytone('Cửa hàng ven đường', fontSize: 20.h, color: AppColors.ffD62828),
            AppText.manrope(
              'Tiêu lì xì nhặt dọc đường',
              fontSize: 10.5.h,
              fontWeight: FontWeight.w700,
              color: AppColors.ff9A9385,
            ),
          ],
        ),
        const Spacer(),
        _Tabs(
          index: _tab,
          labels: const ['Nâng cấp xe', 'Quà cho cả nhà'],
          onChanged: (i) {
            AudioService.shared.click();
            setState(() {
              _tab = i;
              _justBought = null;
            });
          },
        ),
        const Spacer(),
        _Wallet(lixi: _p.lixi),
        SizedBox(width: 10.h),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () {
            AudioService.shared.click();
            Get.back();
          },
          child: Container(
            width: 32.h,
            height: 32.h,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.ff1B1D22, shape: BoxShape.circle),
            child: Image.asset(Img.icClose, width: 13.h, height: 13.h),
          ),
        ),
      ],
    );
  }
}

/// Nút chọn thẻ kiểu viên thuốc, thẻ đang chọn nền đỏ.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.labels, required this.onChanged});

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(3.h),
      decoration: BoxDecoration(color: AppColors.ffF1E7D2, borderRadius: BorderRadius.circular(14.h)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: i == index ? null : () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 30.h,
                padding: EdgeInsets.symmetric(horizontal: 14.h),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index ? AppColors.ffD62828 : AppColors.ffF1E7D2,
                  borderRadius: BorderRadius.circular(11.h),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShopIcon(
                      i == 0 ? ShopGlyph.stall : ShopGlyph.gift,
                      size: 15.h,
                      color: i == index ? AppColors.ffFFD166 : AppColors.ff7A4A35,
                      accent: i == index ? AppColors.ffD62828 : AppColors.ffF1E7D2,
                    ),
                    SizedBox(width: 6.h),
                    AppText.manrope(
                      labels[i],
                      fontSize: 13.h,
                      fontWeight: FontWeight.w800,
                      color: i == index ? AppColors.ffFFFFFF : AppColors.ff7A4A35,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ví lì xì đang có.
class _Wallet extends StatelessWidget {
  const _Wallet({required this.lixi});

  final int lixi;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      padding: EdgeInsets.symmetric(horizontal: 10.h),
      decoration: BoxDecoration(
        color: AppColors.ffFFF4D6,
        borderRadius: BorderRadius.circular(12.h),
        border: Border.all(color: AppColors.ffFFD166, width: 1.5.h),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LixiIcon(height: 19.h),
          SizedBox(width: 6.h),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: AppText.manrope('$lixi', key: ValueKey(lixi), fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Nâng cấp xe
class _UpgradeGrid extends StatelessWidget {
  const _UpgradeGrid({super.key, required this.progress, required this.justBought, required this.onBuy});

  final TripProgress progress;
  final Object? justBought;
  final ValueChanged<Upgrade> onBuy;

  @override
  Widget build(BuildContext context) {
    final kind = progress.plan.vehicle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final u in Upgrade.values) ...[
          if (u != Upgrade.values.first) SizedBox(width: 8.h),
          Expanded(
            child: _UpgradeCard(
              title: u.titleFor(kind),
              detail: u.detail,
              effect: u.effect,
              art: u.art,
              price: u.priceFor(kind),
              owned: progress.upgrades.contains(u),
              lixi: progress.lixi,
              pop: identical(justBought, u),
              onBuy: () => onBuy(u),
            ),
          ),
        ],
      ],
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.title,
    required this.detail,
    required this.effect,
    required this.art,
    required this.price,
    required this.owned,
    required this.lixi,
    required this.pop,
    required this.onBuy,
  });

  final String title;
  final String detail;
  final String effect;
  final String art;
  final int price;
  final bool owned;
  final int lixi;
  final bool pop;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: 226.h,
      padding: EdgeInsets.all(6.h),
      decoration: BoxDecoration(
        color: owned ? AppColors.ffE6F4EC : AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(14.h),
        border: Border.all(color: owned ? AppColors.ff1E9C53 : AppColors.ffE9DFC6, width: 2.h),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ArtTile(art: art, height: 84.h, owned: owned, pop: pop),
          SizedBox(height: 6.h),
          AppText.manrope(title, fontSize: 13.5.h, fontWeight: FontWeight.w800, maxLines: 1, color: AppColors.ff1B1D22, padding: EdgeInsets.symmetric(horizontal: 2.h)),
          SizedBox(height: 2.h),
          Expanded(
            child: AppText.manrope(
              detail,
              fontSize: 10.5.h,
              fontWeight: FontWeight.w600,
              maxLines: 3,
              lineHeight: 1.3,
              color: AppColors.ff6B7280,
              padding: EdgeInsets.symmetric(horizontal: 2.h),
            ),
          ),
          Container(
            margin: EdgeInsets.only(bottom: 5.h),
            padding: EdgeInsets.symmetric(horizontal: 6.h, vertical: 2.h),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: owned ? AppColors.ff1E9C53.withValues(alpha: 0.14) : AppColors.ffFFF4D6,
              borderRadius: BorderRadius.circular(7.h),
            ),
            child: AppText.manrope(effect, fontSize: 11.h, fontWeight: FontWeight.w800, maxLines: 1, color: owned ? AppColors.ff1E9C53 : AppColors.ff7A4A35),
          ),
          _BuyButton(price: price, owned: owned, lixi: lixi, ownedLabel: 'Đã lắp', onBuy: onBuy),
        ],
      ),
    );
  }
}

/// Ô ảnh minh hoạ nền kem; đã mua thì gắn dấu tích xanh góc trên.
class _ArtTile extends StatelessWidget {
  const _ArtTile({required this.art, required this.height, this.owned = false, this.pop = false, this.dim = false});

  final String art;
  final double height;
  final bool owned;
  final bool pop;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: const RadialGradient(colors: [AppColors.ffFFFBF2, AppColors.ffF1E7D2], radius: 0.85),
        borderRadius: BorderRadius.circular(10.h),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(pop),
              tween: Tween(begin: pop ? 0.75 : 1, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, k, child) => Transform.scale(scale: k, child: child),
              child: Padding(
                padding: EdgeInsets.all(height * 0.04),
                child: Opacity(
                  opacity: dim ? 0.45 : 1,
                  child: Image.asset(
                    Img.shopItem(art),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Center(child: ShopIcon(ShopGlyph.gift, size: height * 0.5, color: AppColors.ffD62828, accent: AppColors.ffFFD166)),
                  ),
                ),
              ),
            ),
          ),
          if (owned)
            Positioned(
              right: 4.h,
              top: 4.h,
              child: Container(
                width: 20.h,
                height: 20.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.ff1E9C53,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ffFFFFFF, width: 1.5.h),
                ),
                child: ShopIcon(ShopGlyph.check, size: 12.h, color: AppColors.ffFFFFFF),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nút giá: đủ lì xì thì đỏ "Mua", thiếu thì xám ghi còn thiếu bao nhiêu,
/// đã có thì xanh.
class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.price, required this.owned, required this.lixi, required this.ownedLabel, required this.onBuy});

  final int price;
  final bool owned;
  final int lixi;
  final String ownedLabel;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final can = !owned && lixi >= price;
    final Widget label;
    if (owned) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShopIcon(ShopGlyph.check, size: 13.h, color: AppColors.ff1E9C53),
          SizedBox(width: 4.h),
          AppText.manrope(ownedLabel, fontSize: 12.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53),
        ],
      );
    } else {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LixiIcon(height: 15.h),
          SizedBox(width: 4.h),
          AppText.manrope('$price', fontSize: 13.5.h, fontWeight: FontWeight.w800, color: can ? AppColors.ffFFFFFF : AppColors.ff6B7280),
          SizedBox(width: 6.h),
          AppText.manrope(
            can ? 'Mua' : 'Thiếu ${price - lixi}',
            fontSize: 12.h,
            fontWeight: FontWeight.w800,
            color: can ? AppColors.ffFFFFFF : AppColors.ff9A9385,
          ),
        ],
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: can ? onBuy : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: owned
              ? AppColors.ffFFFFFF
              : can
                  ? AppColors.ffD62828
                  : AppColors.ffE3E5E9,
          borderRadius: BorderRadius.circular(10.h),
          border: Border.all(
            color: owned ? AppColors.ff1E9C53.withValues(alpha: 0.5) : AppColors.ff1B1D22.withValues(alpha: can ? 0.3 : 0.06),
            width: 1.5.h,
          ),
        ),
        child: label,
      ),
    );
  }
}

// ------------------------------------------------------- Quà cho cả nhà
class _GiftBoard extends StatelessWidget {
  const _GiftBoard({super.key, required this.progress, required this.justBought, required this.onBuy});

  final TripProgress progress;
  final Object? justBought;
  final ValueChanged<Gift> onBuy;

  @override
  Widget build(BuildContext context) {
    final bonus = Gift.bonusOf(progress.gifts);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 216.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in FamilyMember.values) ...[
                if (m != FamilyMember.values.first) SizedBox(width: 8.h),
                Expanded(
                  child: _MemberColumn(
                    member: m,
                    chosen: ShopService.shared.giftFor(progress, m),
                    lixi: progress.lixi,
                    justBought: justBought,
                    onBuy: onBuy,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 7.h),
        Row(
          children: [
            ShopIcon(ShopGlyph.heart, size: 13.h, color: AppColors.ffD94A72, accent: AppColors.ffFFB3C7),
            SizedBox(width: 5.h),
            Expanded(
              child: AppText.manrope(
                'Mỗi người một món, về tới nhà được cộng điểm · đúng món ưng ý thêm điểm · đủ quà cả nhà +${Gift.wholeFamilyBonus}',
                fontSize: 10.5.h,
                fontWeight: FontWeight.w700,
                maxLines: 1,
                color: AppColors.ff7A4A35,
              ),
            ),
            if (bonus > 0) ...[
              SizedBox(width: 8.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.h, vertical: 2.h),
                decoration: BoxDecoration(color: AppColors.ffFFD166, borderRadius: BorderRadius.circular(8.h)),
                child: AppText.manrope('+$bonus điểm', fontSize: 11.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Cột một người nhà: chân dung, tên, gợi ý sở thích, ba món quà để chọn.
class _MemberColumn extends StatelessWidget {
  const _MemberColumn({required this.member, required this.chosen, required this.lixi, required this.justBought, required this.onBuy});

  final FamilyMember member;
  final Gift? chosen;
  final int lixi;
  final Object? justBought;
  final ValueChanged<Gift> onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(6.h, 6.h, 6.h, 6.h),
      decoration: BoxDecoration(
        color: chosen != null ? AppColors.ffE6F4EC : AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(14.h),
        border: Border.all(color: chosen != null ? AppColors.ff1E9C53 : AppColors.ffE9DFC6, width: 2.h),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Portrait(member: member, size: 38.h),
              SizedBox(width: 6.h),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.paytone(member.title, fontSize: 16.h, color: AppColors.ffD62828),
                    AppText.manrope(member.hint, fontSize: 9.5.h, fontWeight: FontWeight.w600, maxLines: 2, lineHeight: 1.2, color: AppColors.ff6B7280),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          for (final g in Gift.optionsFor(member)) ...[
            SizedBox(height: 4.h),
            SizedBox(
              height: 46.h,
              child: _GiftOption(
                gift: g,
                state: chosen == null ? (lixi >= g.price ? _GiftState.open : _GiftState.broke) : (chosen == g ? _GiftState.mine : _GiftState.other),
                pop: identical(justBought, g),
                onBuy: () => onBuy(g),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _GiftState { open, broke, mine, other }

class _GiftOption extends StatelessWidget {
  const _GiftOption({required this.gift, required this.state, required this.pop, required this.onBuy});

  final Gift gift;
  final _GiftState state;
  final bool pop;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final mine = state == _GiftState.mine;
    final faded = state == _GiftState.other;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: state == _GiftState.open ? onBuy : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.fromLTRB(3.h, 3.h, 5.h, 3.h),
        decoration: BoxDecoration(
          color: mine ? AppColors.ffFFFFFF : AppColors.ffFFFBF2,
          borderRadius: BorderRadius.circular(10.h),
          border: Border.all(color: mine ? AppColors.ff1E9C53 : AppColors.ffF1E7D2, width: 1.5.h),
        ),
        child: Row(
          children: [
            SizedBox(width: 38.h, child: _ArtTile(art: gift.art, height: 38.h, pop: pop, dim: faded)),
            SizedBox(width: 5.h),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(
                    gift.title,
                    fontSize: 11.h,
                    fontWeight: FontWeight.w800,
                    maxLines: 1,
                    color: faded ? AppColors.ff9A9385 : AppColors.ff1B1D22,
                  ),
                  SizedBox(height: 2.h),
                  _priceLine(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceLine() {
    switch (state) {
      case _GiftState.mine:
        return Row(
          children: [
            ShopIcon(ShopGlyph.check, size: 11.h, color: AppColors.ff1E9C53),
            SizedBox(width: 3.h),
            Flexible(child: AppText.manrope('+${gift.bonus} điểm', fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1E9C53)),
            if (gift.favorite) ...[
              SizedBox(width: 3.h),
              ShopIcon(ShopGlyph.heart, size: 11.h, color: AppColors.ffD94A72, accent: AppColors.ffFFB3C7),
            ],
          ],
        );
      case _GiftState.other:
        return AppText.manrope('—', fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ffB8BCC4);
      case _GiftState.open:
      case _GiftState.broke:
        final can = state == _GiftState.open;
        return Container(
          padding: EdgeInsets.fromLTRB(4.h, 1.5.h, 6.h, 1.5.h),
          decoration: BoxDecoration(
            color: can ? AppColors.ffD62828 : AppColors.ffE3E5E9,
            borderRadius: BorderRadius.circular(7.h),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LixiIcon(height: 12.h),
              SizedBox(width: 3.h),
              AppText.manrope(
                can ? '${gift.price} · Mua' : '${gift.price}',
                fontSize: 10.5.h,
                fontWeight: FontWeight.w800,
                color: can ? AppColors.ffFFFFFF : AppColors.ff6B7280,
              ),
            ],
          ),
        );
    }
  }
}

/// Chân dung người nhà (cắt phần đầu, vai từ ảnh người ra cổng đón).
class _Portrait extends StatelessWidget {
  const _Portrait({required this.member, required this.size});

  final FamilyMember member;
  final double size;

  /// Phần đầu nằm ở đâu trong ảnh người đứng (tâm x, tâm y theo tỉ lệ ảnh, bề ngang khung / ảnh).
  (double, double, double) get _crop => switch (member) {
        FamilyMember.grandma => (0.48, 0.1, 0.5),
        FamilyMember.dad => (0.5, 0.19, 0.38),
        FamilyMember.mom => (0.5, 0.135, 0.44),
        FamilyMember.kid => (0.5, 0.18, 0.6),
      };

  @override
  Widget build(BuildContext context) {
    final (cx, cy, frac) = _crop;
    final imgW = size / frac;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.ffFFE3A1, AppColors.ffF7A440]),
        border: Border.all(color: AppColors.ffFFFFFF, width: 2.h),
        boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.15), blurRadius: 4.h, offset: Offset(0, 1.5.h))],
      ),
      child: ClipOval(
        child: LayoutBuilder(builder: (context, box) {
          return OverflowBox(
            maxWidth: imgW,
            maxHeight: double.infinity,
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(box.maxWidth / 2 - imgW * cx, box.maxHeight / 2 - imgW * cy * _aspect),
              child: Image.asset(Img.driverArt('${member.art}_1'), width: imgW, fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
            ),
          );
        }),
      ),
    );
  }

  /// Cao / rộng ảnh người (để đổi tỉ lệ dọc sang điểm ảnh).
  double get _aspect => switch (member) {
        FamilyMember.grandma => 443 / 196,
        FamilyMember.dad => 569 / 306,
        FamilyMember.mom => 490 / 244,
        FamilyMember.kid => 392 / 164,
      };
}

/// Mái hiên sọc đỏ trắng, mép dưới lượn vỏ sò (như mái quán ven đường).
class _AwningPainter extends CustomPainter {
  const _AwningPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stripe = size.height * 1.7;
    final n = (size.width / stripe).ceil();
    final body = size.height * 0.6;
    for (var i = 0; i < n; i++) {
      final x = i * stripe;
      final paint = Paint()..color = i.isEven ? AppColors.ffD62828 : AppColors.ffFFFFFF;
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, body), paint);
      canvas.drawArc(Rect.fromLTWH(x, body - stripe / 2, stripe, stripe), 0, pi, true, paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, body),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ff000000.withValues(alpha: 0.2), AppColors.ff000000.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, body)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
