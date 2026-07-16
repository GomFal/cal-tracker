import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads and rewrites a complete legacy token pair', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'legacy-access',
      'refresh_token': 'legacy-refresh',
    });

    final tokens = await const SecureTokenStorage().read();

    expect(tokens?.accessToken, 'legacy-access');
    expect(tokens?.refreshToken, 'legacy-refresh');
    expect(
      await const FlutterSecureStorage().read(key: 'access_token'),
      'legacy-access',
    );
    expect(
      await const FlutterSecureStorage().read(key: 'refresh_token'),
      'legacy-refresh',
    );
  });

  test('clears a partial legacy session instead of restoring it', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'orphaned-access',
    });

    expect(await const SecureTokenStorage().read(), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'access_token'),
      isNull,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'refresh_token'),
      isNull,
    );
  });

  test('clear removes both tokens', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'access',
      'refresh_token': 'refresh',
    });

    await const SecureTokenStorage().clear();

    expect(
      await const FlutterSecureStorage().read(key: 'access_token'),
      isNull,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'refresh_token'),
      isNull,
    );
  });
}
