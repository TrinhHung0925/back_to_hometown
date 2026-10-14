import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'route.dart';
import 'service/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await AudioService.shared.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // Game chỉ chạy màn ngang nên khung thiết kế là ngang (884×390),
      // khác mặc định dọc 390×884 trong flutter_architecture.md.
      designSize: const Size(884, 390),
      minTextAdapt: true,
      // Tắt: splitScreenMode ép chiều cao tối thiểu 700 (dành cho màn dọc),
      // màn ngang cao ~400 sẽ bị phóng mọi kích thước .h lên ~1.8 lần.
      splitScreenMode: false,
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          defaultTransition: Transition.rightToLeft,
          transitionDuration: const Duration(milliseconds: 200),
          initialRoute: AppPage.splash.routeName,
          textDirection: TextDirection.ltr,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
              child: child!,
            );
          },
          onGenerateRoute: generateRoute,
        );
      },
    );
  }
}
