import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'resource/app_text.dart';
import 'screen/choose_mode/choose_mode_view.dart';
import 'screen/game/game_view.dart';
import 'screen/home/home_view.dart';
import 'screen/plan_trip/plan_trip_view.dart';
import 'screen/rest_stop/rest_stop_view.dart';
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
    case "/game":
      return page(settings, () => GameView());
    case "/chooseMode":
      return page(settings, () => ChooseModeView());
    case "/planTrip":
      return page(settings, () => PlanTripView());
    case "/restStop":
      return page(settings, () => RestStopView());

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
  game,
  chooseMode,
  planTrip,
  restStop,
}

extension AppPageExtension on AppPage {
  String get routeName {
    switch (this) {
      case AppPage.splash:
        return '/${AppPage.splash.name}';
      case AppPage.home:
        return '/${AppPage.home.name}';
      case AppPage.game:
        return '/${AppPage.game.name}';
      case AppPage.chooseMode:
        return '/${AppPage.chooseMode.name}';
      case AppPage.planTrip:
        return '/${AppPage.planTrip.name}';
      case AppPage.restStop:
        return '/${AppPage.restStop.name}';
    }
  }
}
