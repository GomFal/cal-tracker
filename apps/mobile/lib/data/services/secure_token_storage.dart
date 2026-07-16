import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredTokens {
  const StoredTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

abstract interface class TokenStorage {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage();

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );
  static const _legacyIosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    synchronizable: false,
  );
  static const _storage = FlutterSecureStorage(iOptions: _iosOptions);
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static bool _iosAccessibilityMigrated = false;
  static Future<void>? _iosAccessibilityMigration;

  @override
  Future<StoredTokens?> read() async {
    final accessToken = await _storage.read(
      key: _accessTokenKey,
      iOptions: _iosOptions,
    );
    final refreshToken = await _storage.read(
      key: _refreshTokenKey,
      iOptions: _iosOptions,
    );
    if (accessToken == null || refreshToken == null) {
      if (accessToken != null || refreshToken != null) await clear();
      _iosAccessibilityMigrated = true;
      return null;
    }
    final tokens = StoredTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _migrateLegacyTokenAccessibility(tokens);
    return tokens;
  }

  @override
  Future<void> write(StoredTokens tokens) async {
    await _storage.write(
      key: _accessTokenKey,
      value: tokens.accessToken,
      iOptions: _iosOptions,
    );
    await _storage.write(
      key: _refreshTokenKey,
      value: tokens.refreshToken,
      iOptions: _iosOptions,
    );
    _iosAccessibilityMigrated = true;
  }

  @override
  Future<void> clear() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final operation in [
      () => _storage.delete(key: _accessTokenKey, iOptions: _iosOptions),
      () => _storage.delete(key: _accessTokenKey, iOptions: _legacyIosOptions),
      () => _storage.delete(key: _refreshTokenKey, iOptions: _iosOptions),
      () => _storage.delete(
            key: _refreshTokenKey,
            iOptions: _legacyIosOptions,
          ),
    ]) {
      try {
        await operation();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    _iosAccessibilityMigrated = firstError == null;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<void> _migrateLegacyTokenAccessibility(StoredTokens tokens) async {
    if (_iosAccessibilityMigrated) return;
    final inFlight = _iosAccessibilityMigration;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final migration = write(tokens);
    _iosAccessibilityMigration = migration;
    try {
      await migration;
    } finally {
      if (identical(_iosAccessibilityMigration, migration)) {
        _iosAccessibilityMigration = null;
      }
    }
  }
}
