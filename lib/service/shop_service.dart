import 'dart:math';

import '../model/shop.dart';
import '../model/trip.dart';
import 'trip_service.dart';

/// Cửa hàng ở trạm dừng nghỉ: mua nâng cấp xe, quà Tết cho cả nhà bằng lì xì
/// của chuyến đi đang chơi (lưu ngay sau khi mua).
class ShopService {
  static final ShopService shared = ShopService._internal();

  factory ShopService() => shared;

  ShopService._internal();

  /// Mua nâng cấp [upgrade]. Trả về false nếu đã có hoặc không đủ lì xì.
  bool buyUpgrade(TripProgress progress, Upgrade upgrade, {bool save = true}) {
    if (!canBuyUpgrade(progress, upgrade)) return false;
    progress.lixi -= upgrade.priceFor(progress.plan.vehicle);
    if (upgrade == Upgrade.extraTank) progress.fuel = withExtraTank(progress.fuel);
    progress.upgrades.add(upgrade);
    if (save) TripService.shared.save(progress);
    return true;
  }

  bool canBuyUpgrade(TripProgress progress, Upgrade upgrade) =>
      !progress.upgrades.contains(upgrade) && progress.lixi >= upgrade.priceFor(progress.plan.vehicle);

  /// Mua quà [gift] (mỗi người nhà một món). Trả về false nếu người đó đã
  /// có quà hoặc không đủ lì xì.
  bool buyGift(TripProgress progress, Gift gift, {bool save = true}) {
    if (!canBuyGift(progress, gift)) return false;
    progress
      ..lixi -= gift.price
      ..gifts.add(gift);
    if (save) TripService.shared.save(progress);
    return true;
  }

  bool canBuyGift(TripProgress progress, Gift gift) => giftFor(progress, gift.member) == null && progress.lixi >= gift.price;

  /// Quà đã mua cho [member] (null nếu chưa).
  Gift? giftFor(TripProgress progress, FamilyMember member) {
    for (final g in progress.gifts) {
      if (g.member == member) return g;
    }
    return null;
  }

  /// Mức bình sau khi lắp can xăng phụ đổ đầy sẵn: lượng xăng cũ cộng thêm
  /// can đầy, tính theo dung tích mới (lớn hơn).
  static double withExtraTank(double level) {
    const k = Perks.fuelCapacityExtraTank;
    return min(1.0, (level + (k - 1)) / k);
  }
}
