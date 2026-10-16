import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/shop_glyphs.dart';
import '../../model/shop.dart';
import '../../model/trip.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';
import '../../service/audio_service.dart';

/// Nút "Cửa hàng" ở trạm dừng nghỉ (cùng cỡ AppButton, icon sạp hàng vẽ bằng code).
class ShopButton extends StatelessWidget {
  const ShopButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        AudioService.shared.click();
        onPressed();
      },
      child: Container(
        height: 44.h,
        padding: EdgeInsets.symmetric(horizontal: 18.h),
        decoration: BoxDecoration(
          color: AppColors.ffD62828,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: AppColors.ff1B1D22.withValues(alpha: 0.35), width: 2.h),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShopIcon(ShopGlyph.stall, size: 24.h, color: AppColors.ffFFD166, accent: AppColors.ffD62828),
            SizedBox(width: 8.h),
            Flexible(child: AppText.manrope('Cửa hàng', fontSize: 15.h, fontWeight: FontWeight.w800, color: AppColors.ffFFFFFF)),
          ],
        ),
      ),
    );
  }
}

/// Hàng đồ đang mang theo trên thẻ chuyến đi: nâng cấp đã lắp, quà Tết đã
/// mua. Chưa có gì thì nhắc ghé cửa hàng.
class CarriedItems extends StatelessWidget {
  const CarriedItems({super.key, required this.progress, required this.onOpen});

  final TripProgress progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final upgrades = [for (final u in Upgrade.values) if (progress.upgrades.contains(u)) u];
    final gifts = progress.gifts;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () {
        AudioService.shared.click();
        onOpen();
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(8.h, 3.h, 8.h, 3.h),
        decoration: BoxDecoration(
          color: AppColors.ffFFFBF2,
          borderRadius: BorderRadius.circular(12.h),
          border: Border.all(color: AppColors.ffF1E7D2, width: 1.5.h),
        ),
        child: Row(
          children: [
            if (upgrades.isEmpty && gifts.isEmpty) ...[
              ShopIcon(ShopGlyph.gift, size: 22.h, color: AppColors.ffD62828, accent: AppColors.ffFFD166),
              SizedBox(width: 8.h),
              Expanded(
                child: AppText.manrope(
                  'Lì xì nhặt được đổi được lốp tốt, đèn LED… và quà Tết cho cả nhà',
                  fontSize: 11.5.h,
                  fontWeight: FontWeight.w700,
                  maxLines: 2,
                  color: AppColors.ff7A4A35,
                ),
              ),
            ] else ...[
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  // Không đủ chỗ thì bớt ảnh, thay bằng ô "+n".
                  final total = upgrades.length + gifts.length;
                  final divider = upgrades.isNotEmpty && gifts.isNotEmpty ? 12.h : 0.0;
                  // Nhiều đồ thì thu nhỏ ảnh một chút trước khi phải bớt.
                  final size = total * 29.h + divider <= box.maxWidth ? 26.h : 23.h;
                  final slot = size + 3.h;
                  final fit = ((box.maxWidth - divider) / slot).floor();
                  final show = total <= fit ? total : max(0, fit - 1);
                  final ups = upgrades.take(show).toList();
                  final gs = gifts.take(max(0, show - ups.length)).toList();
                  return Row(
                    children: [
                      for (final u in ups) _Thumb(art: u.art, size: size),
                      if (ups.isNotEmpty && gs.isNotEmpty)
                        Container(width: 1.5.h, height: 22.h, margin: EdgeInsets.symmetric(horizontal: 5.h), color: AppColors.ffE9DFC6),
                      for (final g in gs) _Thumb(art: g.art, gift: true, size: size),
                      if (show < total)
                        Container(
                          width: size,
                          height: size,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.ffF1E7D2, borderRadius: BorderRadius.circular(8.h)),
                          child: AppText.manrope('+${total - show}', fontSize: 11.h, fontWeight: FontWeight.w800, color: AppColors.ff7A4A35),
                        ),
                    ],
                  );
                }),
              ),
              // Bao nhiêu người nhà đã có quà.
              Container(
                padding: EdgeInsets.fromLTRB(5.h, 2.h, 7.h, 2.h),
                decoration: BoxDecoration(
                  color: gifts.length == FamilyMember.values.length ? AppColors.ffE6F4EC : AppColors.ffF1E7D2,
                  borderRadius: BorderRadius.circular(8.h),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShopIcon(ShopGlyph.gift, size: 13.h, color: AppColors.ffD62828, accent: AppColors.ffFFD166),
                    SizedBox(width: 3.h),
                    AppText.manrope(
                      '${gifts.length}/${FamilyMember.values.length}',
                      fontSize: 11.h,
                      fontWeight: FontWeight.w800,
                      color: gifts.length == FamilyMember.values.length ? AppColors.ff1E9C53 : AppColors.ff7A4A35,
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(width: 6.h),
            Image.asset(Img.icArrow, width: 12.h, height: 12.h, color: AppColors.ffD62828),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.art, required this.size, this.gift = false});

  final String art;
  final bool gift;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.only(right: 3.h),
      padding: EdgeInsets.all(2.h),
      decoration: BoxDecoration(
        color: gift ? AppColors.ffFFE3A1.withValues(alpha: 0.6) : AppColors.ffF1E7D2,
        borderRadius: BorderRadius.circular(8.h),
      ),
      child: Image.asset(
        Img.shopItem(art),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => ShopIcon(ShopGlyph.gift, size: 20.h, color: AppColors.ffD62828, accent: AppColors.ffFFD166),
      ),
    );
  }
}
