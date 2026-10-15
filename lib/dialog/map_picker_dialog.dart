import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../model/map_theme.dart';
import '../resource/app_colors.dart';
import '../resource/app_resource.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';
import '../service/local_service.dart';

/// Chọn bản đồ (cảnh hai bên đường) và trời (theo giờ / ngày / đêm). Lưu
/// ngay khi chọn; áp cho các chặng sắp chơi.
class MapPickerDialog extends StatefulWidget {
  const MapPickerDialog({super.key, this.note});

  /// Ghi chú dưới tiêu đề (ví dụ đang chơi dở: đổi bản đồ thì chơi lại chặng).
  final String? note;

  /// Mở hộp chọn; trả về khi đóng.
  static Future<void> open({String? note}) => Get.dialog<void>(MapPickerDialog(note: note));

  /// Dòng tóm tắt lựa chọn hiện tại, ví dụ "Tự động · Theo giờ".
  static String summary() => '${LocalService.shared.getMapTheme().title} · ${LocalService.shared.getSkyMode().title}';

  @override
  State<MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<MapPickerDialog> {
  MapTheme _theme = LocalService.shared.getMapTheme();
  SkyMode _sky = LocalService.shared.getSkyMode();

  void _pickTheme(MapTheme theme) {
    AudioService.shared.click();
    setState(() => _theme = theme);
    LocalService.shared.saveMapTheme(theme);
  }

  void _pickSky(SkyMode sky) {
    AudioService.shared.click();
    setState(() => _sky = sky);
    LocalService.shared.saveSkyMode(sky);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(18.h),
        child: Container(
          width: 660.h,
          padding: EdgeInsets.fromLTRB(18.h, 14.h, 14.h, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.manrope('Chọn bản đồ', fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                        if (widget.note != null)
                          AppText.manrope(widget.note!, fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ffD62828),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () {
                      AudioService.shared.click();
                      Get.back();
                    },
                    child: Container(
                      width: 30.h,
                      height: 30.h,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.ff1B1D22, shape: BoxShape.circle),
                      child: Image.asset(Img.icClose, width: 12.h, height: 12.h),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  for (final theme in MapTheme.values) ...[
                    if (theme != MapTheme.values.first) SizedBox(width: 8.h),
                    Expanded(child: _ThemeCard(theme: theme, selected: theme == _theme, onTap: () => _pickTheme(theme))),
                  ],
                ],
              ),
              SizedBox(height: 12.h),
              AppText.manrope('TRỜI', fontSize: 11.h, fontWeight: FontWeight.w800, letterSpacing: 1.2.h, color: AppColors.ff9A9385),
              SizedBox(height: 6.h),
              Row(
                children: [
                  for (final sky in SkyMode.values) ...[
                    if (sky != SkyMode.values.first) SizedBox(width: 8.h),
                    Expanded(child: SkyChip(sky: sky, selected: sky == _sky, onTap: () => _pickSky(sky))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thẻ một bản đồ: ảnh chụp cảnh, tên, mô tả ngắn.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  final MapTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.all(3.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.ffD62828 : AppColors.ffF2F3F5,
          borderRadius: BorderRadius.circular(14.h),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11.h),
              child: AspectRatio(aspectRatio: 1.25, child: _preview()),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(6.h, 6.h, 6.h, 5.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(theme.title,
                      fontSize: 13.5.h, fontWeight: FontWeight.w800, color: selected ? AppColors.ffFFFFFF : AppColors.ff1B1D22),
                  SizedBox(height: 1.h),
                  AppText.manrope(
                    theme.subtitle,
                    fontSize: 9.5.h,
                    fontWeight: FontWeight.w600,
                    maxLines: 2,
                    color: selected ? AppColors.ffFFFFFF.withValues(alpha: 0.85) : AppColors.ff6B7280,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Tự động": ghép bốn ảnh nhỏ; còn lại một ảnh.
  Widget _preview() {
    if (theme == MapTheme.auto) {
      final parts = [MapTheme.delta, MapTheme.coast, MapTheme.mountain, MapTheme.mekong];
      return Column(
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++) Expanded(child: _image(parts[row * 2 + col])),
                ],
              ),
            ),
        ],
      );
    }
    return _image(theme);
  }

  Widget _image(MapTheme t) => Image.asset(
        Img.mapPreview(t.name),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: _fallback(t)),
      );

  static Color _fallback(MapTheme t) => switch (t) {
        MapTheme.coast => const Color(0xff4E9CB5),
        MapTheme.mountain => const Color(0xff3D5636),
        MapTheme.mekong => const Color(0xffC9A74A),
        _ => const Color(0xff6F8248),
      };
}

/// Hai màu chấm bầu trời của một lựa chọn trời.
(Color, Color) skyColors(SkyMode sky) => switch (sky) {
      SkyMode.clock => (const Color(0xff7FB2E5), const Color(0xff27324F)),
      SkyMode.day => (const Color(0xff8EC5F0), const Color(0xffFCE7B2)),
      SkyMode.night => (const Color(0xff0E1630), const Color(0xff2E3B66)),
    };

/// Một lựa chọn trời: chấm màu bầu trời, tên, mô tả ([compact] bỏ mô tả).
class SkyChip extends StatelessWidget {
  const SkyChip({super.key, required this.sky, required this.selected, required this.onTap, this.compact = false});

  final SkyMode sky;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (a, b) = skyColors(sky);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.fromLTRB(8.h, 7.h, 10.h, 7.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.ffD62828 : AppColors.ffF2F3F5,
          borderRadius: BorderRadius.circular(12.h),
        ),
        child: Row(
          children: [
            Container(
              width: 28.h,
              height: 28.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: AppColors.ffFFFFFF, width: 2.h),
              ),
            ),
            SizedBox(width: 8.h),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.manrope(sky.title,
                      fontSize: 13.h, fontWeight: FontWeight.w800, maxLines: 1, color: selected ? AppColors.ffFFFFFF : AppColors.ff1B1D22),
                  if (!compact)
                    AppText.manrope(sky.subtitle,
                      fontSize: 9.5.h,
                      fontWeight: FontWeight.w600,
                      maxLines: 1,
                      color: selected ? AppColors.ffFFFFFF.withValues(alpha: 0.85) : AppColors.ff6B7280),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dòng "Bản đồ · Tự động · Theo giờ — Đổi ›" (menu tạm dừng); bấm để mở
/// [MapPickerDialog]. [compact]: hai dòng nhỏ "Bản đồ" / "Tự động ›" để
/// đứng cạnh [SkySwitch].
class MapRow extends StatelessWidget {
  const MapRow({super.key, required this.summary, required this.onPressed, this.compact = false});

  final String summary;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        height: compact ? 36.h : 30.h,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8.h : 10.h),
        decoration: BoxDecoration(color: AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(10.h)),
        child: compact
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.manrope('Bản đồ', fontSize: 9.5.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
                        AppText.manrope(summary, fontSize: 12.5.h, fontWeight: FontWeight.w800, maxLines: 1, color: AppColors.ff1B1D22),
                      ],
                    ),
                  ),
                  AppText.manrope('›', fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ffD62828),
                ],
              )
            : Row(
                children: [
                  AppText.manrope('Bản đồ', fontSize: 11.h, fontWeight: FontWeight.w700, color: AppColors.ff6B7280),
                  SizedBox(width: 8.h),
                  Expanded(child: AppText.manrope(summary, fontSize: 12.5.h, fontWeight: FontWeight.w800, maxLines: 1, color: AppColors.ff1B1D22)),
                  AppText.manrope('Đổi ›', fontSize: 12.h, fontWeight: FontWeight.w800, color: AppColors.ffD62828),
                ],
              ),
      ),
    );
  }
}

/// Ba nút trời liền nhau — Theo giờ / Ngày / Đêm — bấm là chọn luôn.
class SkySwitch extends StatelessWidget {
  const SkySwitch({super.key, required this.value, required this.onChanged});

  final SkyMode value;
  final ValueChanged<SkyMode> onChanged;

  static String _label(SkyMode sky) => switch (sky) {
        SkyMode.clock => 'Theo giờ',
        SkyMode.day => 'Ngày',
        SkyMode.night => 'Đêm',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36.h,
      padding: EdgeInsets.all(3.h),
      decoration: BoxDecoration(color: AppColors.ffF2F3F5, borderRadius: BorderRadius.circular(10.h)),
      child: Row(
        children: [
          for (final sky in SkyMode.values)
            Expanded(
              flex: sky == SkyMode.clock ? 14 : 10,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  AudioService.shared.click();
                  onChanged(sky);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: sky == value ? AppColors.ffD62828 : AppColors.ffF2F3F5,
                    borderRadius: BorderRadius.circular(8.h),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 11.h,
                        height: 11.h,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [skyColors(sky).$1, skyColors(sky).$2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: AppColors.ffFFFFFF, width: 1.5.h),
                        ),
                      ),
                      SizedBox(width: 3.h),
                      AppText.manrope(
                        _label(sky),
                        fontSize: 11.h,
                        fontWeight: FontWeight.w800,
                        maxLines: 1,
                        color: sky == value ? AppColors.ffFFFFFF : AppColors.ff1B1D22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hàng "Bản đồ ›" + [SkySwitch] trên bảng lên lộ trình và trạm dừng nghỉ.
class MapSkyRow extends StatelessWidget {
  const MapSkyRow({super.key, required this.theme, required this.sky, required this.onPickMap, required this.onSky});

  final MapTheme theme;
  final SkyMode sky;
  final VoidCallback onPickMap;
  final ValueChanged<SkyMode> onSky;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 8, child: MapRow(summary: theme.title, onPressed: onPickMap, compact: true)),
        SizedBox(width: 6.h),
        Expanded(flex: 19, child: SkySwitch(value: sky, onChanged: onSky)),
      ],
    );
  }
}
