import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'resource/app_text.dart';
import 'screen/home/home_view.dart';
import 'screen/splash/splash_view.dart';

Route<dynamic> generateRoute(RouteSettings settings) {
  GetPageRoute page(RouteSettings settings, Widget Function() genPage, [Bindings? bindings]) {
    var page = GetPage(
      name: settings.name!,
      page: genPage,
      arguments: settings.arguments,
      binding: bindings,
    );
    return PageRedirect(route: page, unknownRoute: page).page();
  }

  switch (settings.name) {
    case "/splash":
      return page(settings, () => SplashView());
    case "/home":
      return page(settings, () => HomeView());

    default:
      return page(
        settings,
        () => Scaffold(
          appBar: AppBar(title: AppText.manrope('404')),
          body: Center(child: AppText.manrope('No route defined for ${settings.name}')),
        ),
      );
  }
}

enum AppPage {
  splash,
  home,
}

extension AppPageExtension on AppPage {
  String get routeName {
    switch (this) {
      case AppPage.splash:
        return '/${AppPage.splash.name}';
      case AppPage.home:
        return '/${AppPage.home.name}';
    }
  }
}
