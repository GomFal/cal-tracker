import 'package:cal_tracker_mobile/data/services/mobile_update_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'app.bettercalories/mobile_update_installer.test',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the native capability and permission settings methods', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'canInstallPackages') return true;
      return null;
    });
    final installer = AndroidMobileUpdateInstaller(
      channel: channel,
      supported: true,
    );

    expect(await installer.canInstallPackages(), isTrue);
    await installer.openInstallPermissionSettings();

    expect(methods, [
      'canInstallPackages',
      'openInstallPermissionSettings',
    ]);
  });

  test('passes only the private file and verified expectations to Android',
      () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return null;
    });
    final installer = AndroidMobileUpdateInstaller(
      channel: channel,
      supported: true,
    );

    await installer.installApk(
      filePath: '/private/cache/mobile_updates/bettercalories-update-27.apk',
      expectedVersionCode: 27,
      expectedSha256: 'a' * 64,
      expectedSizeBytes: 123456,
    );

    expect(capturedCall?.method, 'installApk');
    expect(capturedCall?.arguments, {
      'filePath': '/private/cache/mobile_updates/bettercalories-update-27.apk',
      'expectedVersionCode': 27,
      'expectedSha256': 'a' * 64,
      'expectedSizeBytes': 123456,
    });
  });

  test('does not invoke platform methods when Android is unsupported',
      () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return null;
    });
    final installer = AndroidMobileUpdateInstaller(
      channel: channel,
      supported: false,
    );

    expect(await installer.canInstallPackages(), isFalse);
    await expectLater(
      installer.installApk(
        filePath: '/tmp/update.apk',
        expectedVersionCode: 2,
        expectedSha256: 'a' * 64,
        expectedSizeBytes: 1,
      ),
      throwsA(isA<MobileUpdateInstallerException>()),
    );
    expect(invoked, isFalse);
  });
}
