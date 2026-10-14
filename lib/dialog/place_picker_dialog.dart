import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../model/place.dart';
import '../resource/app_colors.dart';
import '../resource/app_resource.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';

/// Danh sách điểm chia theo miền (bắc → nam), có ô tìm theo tên điểm hoặc tên
/// tỉnh cũ, không cần gõ dấu.
class PlacePickerDialog extends StatefulWidget {
  const PlacePickerDialog({super.key, required this.title, required this.places, this.selectedId});

  final String title;
  final List<Place> places;
  final String? selectedId;

  /// Bỏ dấu tiếng Việt để tìm "da nang" ra "Đà Nẵng".
  static String fold(String s) {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    final out = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      out.write(groups.entries.where((e) => e.value.contains(ch)).map((e) => e.key).firstOrNull ?? ch);
    }
    return out.toString();
  }

  /// Các điểm khớp [query]: khớp tên trước, khớp tên tỉnh cũ sau, mỗi nhóm
  /// theo thứ tự bắc → nam. Gõ chữ cái đầu cũng được ("hcm", "bmt").
  static List<Place> search(List<Place> places, String query) {
    final q = fold(query.trim()).replaceAll(RegExp(r'\s+'), ' ');
    final sorted = [...places]..sort((a, b) => a.y.compareTo(b.y));
    if (q.isEmpty) return sorted;
    String initials(String s) => fold(s).split(RegExp(r'[\s.–-]+')).where((w) => w.isNotEmpty).map((w) => w[0]).join();
    bool byName(Place p) => fold(p.name).contains(q) || (q.length >= 2 && !q.contains(' ') && initials(p.name).contains(q));
    bool byRegion(Place p) => p.region != null && fold(p.region!).contains(q);
    return [...sorted.where(byName), ...sorted.where((p) => !byName(p) && byRegion(p))];
  }

  @override
  State<PlacePickerDialog> createState() => _PlacePickerDialogState();
}

class _PlacePickerDialogState extends State<PlacePickerDialog> {
  final _scroll = ScrollController();
  String _query = '';

  double get _rowH => 34.h;
  double get _headerH => 30.h;

  /// Danh sách đầy đủ: tiêu đề miền ([PlaceZone]) xen giữa các điểm ([Place]).
  late final List<Object> _grouped = [
    for (final zone in PlaceZone.values) ...[
      zone,
      ...(widget.places.where((p) => p.zone == zone).toList()..sort((a, b) => a.y.compareTo(b.y))),
    ],
  ];

  @override
  void initState() {
    super.initState();
    // Mở danh sách ngay ở điểm đang chọn (đặt khoảng giữa khung).
    final index = _grouped.indexWhere((e) => e is Place && e.id == widget.selectedId);
    if (index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final top = _grouped.take(index).fold<double>(0, (sum, e) => sum + (e is Place ? _rowH : _headerH));
        final target = top - (_scroll.position.viewportDimension - _rowH) / 2;
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _pick(Place place) {
    AudioService.shared.click();
    Get.back(result: place.id);
  }

  @override
  Widget build(BuildContext context) {
    final List<Object> entries = _query.trim().isEmpty ? _grouped : PlacePickerDialog.search(widget.places, _query);
    return Center(
      child: Material(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(18.h),
        child: Container(
          width: 380.h,
          height: 330.h,
          padding: EdgeInsets.fromLTRB(18.h, 14.h, 14.h, 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppText.manrope(widget.title, fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
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
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.only(right: 4.h),
                child: CupertinoSearchTextField(
                  placeholder: 'Tìm thành phố hoặc tỉnh…',
                  onChanged: (value) {
                    setState(() => _query = value);
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                  style: TextStyle(fontSize: 14.h, fontFamily: 'Manrope', color: AppColors.ff1B1D22),
                ),
              ),
              SizedBox(height: 4.h),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: AppText.manrope(
                          'Không tìm thấy “${_query.trim()}”',
                          fontSize: 14.h,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ff6B7280,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.only(right: 4.h, bottom: 4.h),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => switch (entries[i]) {
                          final PlaceZone zone => _ZoneHeader(zone: zone, height: _headerH),
                          final Place place => _PlaceRow(
                              place: place,
                              height: _rowH,
                              selected: place.id == widget.selectedId,
                              onTap: () => _pick(place),
                            ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề miền: chữ hoa nhỏ, giãn chữ, kèm vạch mảnh.
class _ZoneHeader extends StatelessWidget {
  const _ZoneHeader({required this.zone, required this.height});

  final PlaceZone zone;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6.h, 10.h, 0, 0),
        child: Row(
          children: [
            AppText.manrope(
              zone.title.toUpperCase(),
              fontSize: 11.h,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2.h,
              color: AppColors.ff9A9385,
            ),
            SizedBox(width: 10.h),
            Expanded(child: Container(height: 1.h, color: AppColors.ffE3E5E9)),
          ],
        ),
      ),
    );
  }
}

/// Một dòng: tên điểm, tỉnh cũ mờ bên cạnh; điểm đang chọn tô đỏ.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.height, required this.selected, required this.onTap});

  final Place place;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final region = place.region;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: 6.h),
        decoration: selected
            ? BoxDecoration(color: AppColors.ffFFF4D6, borderRadius: BorderRadius.circular(8.h))
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppText.manrope(
              place.name,
              fontSize: 15.h,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.ffD62828 : AppColors.ff1B1D22,
            ),
            if (region != null) ...[
              SizedBox(width: 8.h),
              Flexible(
                child: AppText.manrope(region, fontSize: 12.h, fontWeight: FontWeight.w600, color: AppColors.ff9A9385),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
