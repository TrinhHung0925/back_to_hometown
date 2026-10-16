import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/shop_glyphs.dart';
import '../../model/shop.dart';
import '../../resource/app_colors.dart';
import '../../resource/app_resource.dart';
import '../../resource/app_text.dart';

/// Về tới cổng: cả nhà bước ra xong thì lần lượt bà, bố, mẹ, em nói một câu
/// (bong bóng lời trên đầu) theo món quà mình mang về — không có quà thì một
/// câu chào ấm áp. Nói xong, trên đầu người được quà còn lơ lửng một nhãn quà.
class GiftReactions extends StatelessWidget {
  const GiftReactions({super.key, required this.gifts, required this.seconds, required this.heads});

  final List<Gift> gifts;

  /// Giây kể từ lúc xe dừng trước cổng.
  final double seconds;

  /// Đỉnh ảnh từng người trên màn hình và chiều cao ảnh (điểm ảnh), theo
  /// [FamilyMember.art]; thiếu người nào (không ra cổng) thì bỏ qua người đó.
  final Map<String, (Offset, double)> heads;

  /// Đỉnh đầu nằm ở đâu trong ảnh người (phần trên là tay giơ vẫy).
  static double _headTop(FamilyMember m) => switch (m) {
        FamilyMember.grandma => 0.03,
        FamilyMember.dad => 0.11,
        FamilyMember.mom => 0.055,
        FamilyMember.kid => 0.08,
      };

  Offset _head(FamilyMember m) {
    final (top, h) = heads[m.art]!;
    return top + Offset(0, h * _headTop(m));
  }

  /// Bắt đầu nói sau khi cả nhà đã bước ra tới ngõ; mỗi người nói bấy nhiêu giây.
  static const double start = 2.1;
  static const double each = 2.8;
  static const double fade = 0.28;

  Gift? _giftOf(FamilyMember m) {
    for (final g in gifts) {
      if (g.member == m) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final speakers = [for (final m in FamilyMember.values) if (heads.containsKey(m.art)) m];
    if (speakers.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final children = <Widget>[];
      for (final (i, m) in speakers.indexed) {
        final head = _head(m);
        final gift = _giftOf(m);
        final t = seconds - start - i * each;
        if (t > each && gift != null) children.add(_tag(head, gift, t - each));
      }
      for (final (i, m) in speakers.indexed) {
        final t = seconds - start - i * each;
        if (t < 0 || t > each) continue;
        final k = (min(t, each - t) / fade).clamp(0.0, 1.0);
        children.add(_bubble(box.biggest, _head(m), m, _giftOf(m), Curves.easeOut.transform(k)));
      }
      return Stack(children: children);
    });
  }

  /// Nhãn quà nhỏ lơ lửng trên đầu sau khi đã nói (nhấp nhô nhẹ).
  Widget _tag(Offset head, Gift gift, double t) {
    final size = 30.h;
    final appear = Curves.easeOutBack.transform((t / 0.4).clamp(0.0, 1.0));
    final bob = sin((seconds + gift.index) * 2.4) * 2.h;
    return Positioned(
      left: head.dx - size / 2,
      top: head.dy - size - 6.h + bob,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Transform.scale(
          scale: appear,
          child: Container(
            padding: EdgeInsets.all(2.h),
            decoration: BoxDecoration(
              color: AppColors.ffFFFBF2,
              shape: BoxShape.circle,
              border: Border.all(color: gift.favorite ? AppColors.ffD94A72 : AppColors.ffFFD166, width: 2.h),
              boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.25), blurRadius: 4.h, offset: Offset(0, 2.h))],
            ),
            child: Image.asset(Img.shopItem(gift.art), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _bubble(Size screen, Offset head, FamilyMember m, Gift? gift, double k) {
    final width = 232.h;
    final tail = 12.h;
    final left = (head.dx - width / 2).clamp(8.h, screen.width - width - 8.h);
    return Positioned(
      left: left,
      bottom: screen.height - head.dy + 4.h + (1 - k) * 10.h,
      width: width,
      child: IgnorePointer(
        child: Opacity(
          opacity: k,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(8.h, 7.h, 10.h, 8.h),
                decoration: BoxDecoration(
                  color: AppColors.ffFFFBF2,
                  borderRadius: BorderRadius.circular(14.h),
                  border: Border.all(color: AppColors.ff1B1D22, width: 2.h),
                  boxShadow: [BoxShadow(color: AppColors.ff000000.withValues(alpha: 0.3), blurRadius: 10.h, offset: Offset(0, 4.h))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (gift != null) ...[
                      Container(
                        width: 44.h,
                        height: 44.h,
                        padding: EdgeInsets.all(2.h),
                        decoration: BoxDecoration(
                          gradient: const RadialGradient(colors: [AppColors.ffFFFFFF, AppColors.ffF1E7D2]),
                          borderRadius: BorderRadius.circular(10.h),
                        ),
                        child: Image.asset(Img.shopItem(gift.art), fit: BoxFit.contain),
                      ),
                      SizedBox(width: 8.h),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              AppText.paytone(m.title, fontSize: 14.h, color: AppColors.ffD62828),
                              const Spacer(),
                              if (gift != null) _Points(gift: gift),
                            ],
                          ),
                          SizedBox(height: 2.h),
                          AppText.manrope(
                            '“${gift?.reaction ?? m.greeting}”',
                            fontSize: 12.h,
                            fontWeight: FontWeight.w700,
                            maxLines: 3,
                            lineHeight: 1.25,
                            color: AppColors.ff1B1D22,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Đuôi bong bóng chĩa xuống đầu người nói.
              Align(
                alignment: Alignment(((head.dx - left) / width * 2 - 1).clamp(-0.85, 0.85), 0),
                child: Transform.translate(
                  offset: Offset(0, -2.h),
                  child: SizedBox(width: tail * 1.4, height: tail, child: const CustomPaint(painter: _TailPainter())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Điểm thưởng của món quà (món ưng nhất có tim hồng).
class _Points extends StatelessWidget {
  const _Points({required this.gift});

  final Gift gift;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(5.h, 1.h, 6.h, 1.h),
      decoration: BoxDecoration(color: AppColors.ffFFD166, borderRadius: BorderRadius.circular(8.h)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gift.favorite) ...[
            ShopIcon(ShopGlyph.heart, size: 10.h, color: AppColors.ffD94A72, accent: AppColors.ffFFB3C7),
            SizedBox(width: 3.h),
          ],
          AppText.manrope('+${gift.bonus}', fontSize: 10.5.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.42, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.ffFFFBF2);
    canvas.drawPath(
      Path()
        ..moveTo(0, 1)
        ..lineTo(size.width * 0.42, size.height)
        ..lineTo(size.width, 1),
      Paint()
        ..color = AppColors.ff1B1D22
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
