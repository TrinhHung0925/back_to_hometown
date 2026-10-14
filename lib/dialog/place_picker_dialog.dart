import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../model/place.dart';
import '../resource/app_colors.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';

/// Danh sách điểm (bắc → nam) có ô tìm theo tên, không cần gõ dấu.
class PlacePickerDialog extends StatefulWidget {
  const PlacePickerDialog({super.key, required this.title, required this.places, this.selectedId});

  final String title;
  final List<Place> places;
  final String? selectedId;

  @override
  State<PlacePickerDialog> createState() => _PlacePickerDialogState();
}

class _PlacePickerDialogState extends State<PlacePickerDialog> {
  String _query = '';

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
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final base = groups.entries.where((e) => e.value.contains(ch)).map((e) => e.key).firstOrNull;
      out.write(base ?? ch);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final q = fold(_query.trim());
    final items = [...widget.places]..sort((a, b) => a.y.compareTo(b.y));
    final filtered = q.isEmpty ? items : items.where((p) => fold(p.name).contains(q)).toList();
    return Center(
      child: Material(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(18.h),
        child: Container(
          width: 380.h,
          height: 330.h,
          padding: EdgeInsets.fromLTRB(18.h, 16.h, 18.h, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText.manrope(widget.title, fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
              SizedBox(height: 10.h),
              CupertinoSearchTextField(
                placeholder: 'Tìm thành phố…',
                onChanged: (value) => setState(() => _query = value),
                style: TextStyle(fontSize: 14.h, fontFamily: 'Manrope', color: AppColors.ff1B1D22),
              ),
              SizedBox(height: 8.h),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final place = filtered[i];
                    final selected = place.id == widget.selectedId;
                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () {
                        AudioService.shared.click();
                        Get.back(result: place.id);
                      },
                      child: AppText.manrope(
                        place.name,
                        fontSize: 15.h,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? AppColors.ffD62828 : AppColors.ff1B1D22,
                        padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 6.h),
                      ),
                    );
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
