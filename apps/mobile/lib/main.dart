import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'app/app.dart';
import 'app_intents/better_calories_app_intents.dart';

@pragma('vm:entry-point')
Future<void> appIntentsMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeBetterCaloriesAppIntents();
}

Future<void> main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  initializeBetterCaloriesAppIntents();

  runApp(const CalTrackerBootstrap());
}
