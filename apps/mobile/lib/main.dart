import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'app/app.dart';
import 'data/services/api_config.dart';

Future<void> main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final apiConfig = ApiConfig.validatedFromEnvironment(
    flavor: appFlavor,
    isRelease: kReleaseMode,
  );
  runApp(CalTrackerBootstrap(apiConfig: apiConfig));
}
