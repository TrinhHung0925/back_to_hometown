import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../game/logic/trip_clock.dart';
import '../model/trip.dart';
import '../resource/app_colors.dart';
import '../resource/app_resource.dart';
import '../resource/app_text.dart';
import '../service/audio_service.dart';

/// Kỷ lục từng tuyến về quê (điểm cao nhất mỗi tuyến + loại xe).
class RecordsDialog extends StatelessWidget {
  const RecordsDialog({super.key, required this.records});

  final List<TripRecord> records;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.ffFFFFFF,
        borderRadius: BorderRadius.circular(18.h),
        child: Container(
          width: 460.h,
          height: 320.h,
          padding: EdgeInsets.fromLTRB(18.h, 14.h, 18.h, 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Image.asset(Img.icStar, width: 24.h, height: 24.h, color: AppColors.ffFFD166),
                  SizedBox(width: 8.h),
                  Expanded(
                    child: AppText.paytone('Kỷ lục về quê', fontSize: 22.h, color: AppColors.ffD62828),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () {
                      AudioService.shared.click();
                      Get.back();
                    },
                    child: Container(
                      width: 34.h,
                      height: 34.h,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.ff1B1D22, shape: BoxShape.circle),
                      child: Image.asset(Img.icClose, width: 14.h, height: 14.h),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: AppText.manrope(
                          'Chưa có kỷ lục nào.\nVề tới nhà trước giao thừa để ghi điểm!',
                          fontSize: 14.h,
                          maxLines: 3,
                          textAlign: TextAlign.center,
                          color: AppColors.ff6B7280,
                        ),
                      )
                    : ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (_, _) => Container(height: 1.h, color: AppColors.ffE3E5E9),
                        itemBuilder: (context, i) {
                          final r = records[i];
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28.h,
                                  child: AppText.manrope('${i + 1}', fontSize: 16.h, fontWeight: FontWeight.w800, color: AppColors.ff6B7280),
                                ),
                                SizedBox(
                                  width: 44.h,
                                  child: RotatedBox(
                                    quarterTurns: 1,
                                    child: Image.asset(
                                      Img.player(r.vehicle),
                                      height: 36.h,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8.h),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AppText.manrope('${r.fromName} → ${r.toName}', fontSize: 14.h, fontWeight: FontWeight.w800, color: AppColors.ff1B1D22),
                                      AppText.manrope(
                                        '${r.km.round()} km · về lúc ${TripClock(minutes: r.arrivedMinutes).label}',
                                        fontSize: 11.h,
                                        color: AppColors.ff6B7280,
                                      ),
                                    ],
                                  ),
                                ),
                                AppText.manrope('${r.score}', fontSize: 18.h, fontWeight: FontWeight.w800, color: AppColors.ffD62828),
                              ],
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
