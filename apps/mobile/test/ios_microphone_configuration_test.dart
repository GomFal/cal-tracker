import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const englishPurpose =
      'BetterCalories uses the microphone when you choose to log a meal by voice, to transcribe the audio and complete your nutrition log';
  const spanishPurpose =
      'BetterCalories usa el micrófono cuando eliges registrar una comida por voz, para transcribir el audio y completar tu registro nutricional';

  test(
    'iOS declares and packages localized microphone purpose strings',
    () async {
      final infoPlist = await File('ios/Runner/Info.plist').readAsString();
      final englishStrings = await File(
        'ios/Runner/en.lproj/InfoPlist.strings',
      ).readAsString();
      final spanishStrings = await File(
        'ios/Runner/es.lproj/InfoPlist.strings',
      ).readAsString();
      final xcodeProject = await File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsString();

      expect(infoPlist, contains('<key>NSMicrophoneUsageDescription</key>'));
      expect(infoPlist, contains('<string>$englishPurpose</string>'));
      expect(
        englishStrings,
        contains('"NSMicrophoneUsageDescription" = "$englishPurpose";'),
      );
      expect(
        spanishStrings,
        contains('"NSMicrophoneUsageDescription" = "$spanishPurpose";'),
      );
      expect(xcodeProject, contains('InfoPlist.strings in Resources'));
      expect(xcodeProject, contains('path = en.lproj/InfoPlist.strings'));
      expect(xcodeProject, contains('path = es.lproj/InfoPlist.strings'));
    },
  );
}
