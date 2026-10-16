import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../game/logic/missions.dart';
import '../resource/app_colors.dart';
import '../resource/app_text.dart';
import 'lixi_icon.dart';
import 'shop_glyphs.dart';

/// Một dòng nhiệm vụ phụ: icon, tên, dòng phụ (cách làm hoặc tiến độ), thưởng.
/// Có [check] thì hiện trạng thái (đang làm / xong / hỏng).
class MissionRow extends StatelessWidget {
  const MissionRow({super.key, required this.mission, this.check, this.dark = false, this.showDetail = true});

  final Mission mission;
  final MissionCheck? check;

  /// Nền tối (bảng kết quả trên nền game).
  final bool dark;

  /// Hiện dòng phụ (cách làm / tiến độ).
  final bool showDetail;

  @override
  Widget build(BuildContext context) {
    final state = check?.state;
    final failed = state == MissionState.failed;
    final done = state == MissionState.done;
    final ink = dark ? AppColors.ffFFFFFF : AppColors.ff1B1D22;
    final sub = dark ? AppColors.ffFFFFFF.withValues(alpha: 0.7) : AppColors.ff6B7280;
    final tile = done
        ? AppColors.ff1E9C53.withValues(alpha: 0.16)
        : failed
            ? AppColors.ffB8BCC4.withValues(alpha: 0.3)
            : AppColors.ffFFD166.withValues(alpha: 0.38);
    return Opacity(
      opacity: failed ? 0.62 : 1,
      child: Row(
        children: [
          Container(
            width: showDetail ? 30.h : 26.h,
            height: showDetail ? 30.h : 26.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(8.h)),
            child: MissionIcon(mission.kind, size: showDetail ? 19.h : 17.h, color: failed ? AppColors.ff6B7280 : ink),
          ),
          SizedBox(width: 8.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText.manrope(
                  mission.title,
                  fontSize: 13.h,
                  fontWeight: FontWeight.w800,
                  maxLines: 1,
                  color: ink,
                  decoration: failed ? TextDecoration.lineThrough : null,
                ),
                if (showDetail)
                  AppText.manrope(
                    check?.progress ?? mission.detail,
                    fontSize: 10.5.h,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    color: done ? (dark ? AppColors.ff7CFFB2 : AppColors.ff1E9C53) : sub,
                  ),
              ],
            ),
          ),
          SizedBox(width: 6.h),
          _Reward(reward: mission.reward, state: state, dark: dark),
        ],
      ),
    );
  }
}

/// Thưởng lì xì; có trạng thái thì kèm dấu tích xanh / gạch chéo.
class _Reward extends StatelessWidget {
  const _Reward({required this.reward, required this.state, required this.dark});

  final int reward;
  final MissionState? state;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final done = state == MissionState.done;
    final failed = state == MissionState.failed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(6.h, 3.h, 8.h, 3.h),
          decoration: BoxDecoration(
            color: done ? AppColors.ffFFD166 : (dark ? AppColors.ffFFFFFF.withValues(alpha: 0.12) : AppColors.ffFFF4D6),
            borderRadius: BorderRadius.circular(10.h),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LixiIcon(height: 15.h),
              SizedBox(width: 4.h),
              AppText.manrope(
                '+$reward',
                fontSize: 12.5.h,
                fontWeight: FontWeight.w800,
                color: done || !dark ? AppColors.ff1B1D22 : AppColors.ffFFFFFF,
                decoration: failed ? TextDecoration.lineThrough : null,
              ),
            ],
          ),
        ),
        if (state != null) ...[
          SizedBox(width: 6.h),
          Container(
            width: 22.h,
            height: 22.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? AppColors.ff1E9C53
                  : failed
                      ? AppColors.ffB4231E
                      : AppColors.ffFFFFFF.withValues(alpha: dark ? 0.16 : 1),
              shape: BoxShape.circle,
              border: state == MissionState.active ? Border.all(color: AppColors.ffEE9B2F, width: 2.h) : null,
            ),
            child: done || failed
                ? ShopIcon(done ? ShopGlyph.check : ShopGlyph.cross, size: 14.h, color: AppColors.ffFFFFFF)
                : Container(
                    width: 7.h,
                    height: 7.h,
                    decoration: const BoxDecoration(color: AppColors.ffEE9B2F, shape: BoxShape.circle),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Nhãn nhỏ viết hoa đầu mục ("NHIỆM VỤ PHỤ").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = AppColors.ff9A9385, this.trailing});

  final String text;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShopIcon(ShopGlyph.flag, size: 13.h, color: color, accent: AppColors.ffFFFFFF),
        SizedBox(width: 5.h),
        AppText.manrope(text, fontSize: 11.h, fontWeight: FontWeight.w800, letterSpacing: 1.2.h, color: color),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}
