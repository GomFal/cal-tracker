import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

import 'app/app.dart';
import 'data/services/api_config.dart';

const _e2eApiConfig = ApiConfig(baseUrl: 'http://10.0.2.2:3000');

Future<void> main() async {
  enableFlutterDriverExtension();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CalTrackerBootstrap(apiConfig: _e2eApiConfig));
}
