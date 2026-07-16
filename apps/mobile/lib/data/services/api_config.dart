class ApiConfig {
  const ApiConfig({required this.baseUrl});

  const ApiConfig.fromEnvironment()
      : baseUrl =
            const String.fromEnvironment('API_BASE_URL', defaultValue: '');

  final String baseUrl;

  static const productionFlavor = 'prod';
  static const developmentFlavor = 'dev';
  static const localFlavor = 'local';
  static const localParallelFlavorOne = 'local1';
  static const localParallelFlavorTwo = 'local2';

  static const productionBaseUrl = 'https://api.bettercalories.app';
  static const developmentBaseUrl = 'https://dev-api.bettercalories.app';

  static const _localDebugBaseUrls = <String>{
    'http://10.0.2.2:3000',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
  };

  /// Reads and validates the compile-time API endpoint before app startup.
  ///
  /// Distributed builds accept only the canonical HTTPS origin for their
  /// flavor. Local HTTP is limited to debug builds and explicit loopback or
  /// Android-emulator origins. The thrown error deliberately omits the
  /// configured value so credentials accidentally embedded in a URL are not
  /// echoed to logs.
  static ApiConfig validatedFromEnvironment({
    required String? flavor,
    required bool isRelease,
  }) {
    const config = ApiConfig.fromEnvironment();
    config.validate(flavor: flavor, isRelease: isRelease);
    return config;
  }

  void validate({required String? flavor, required bool isRelease}) {
    if (baseUrl.isEmpty) {
      throw const ApiConfigException('missing_api_base_url');
    }

    final normalizedFlavor = flavor?.trim();
    if (normalizedFlavor == null || normalizedFlavor.isEmpty) {
      throw const ApiConfigException('missing_app_flavor');
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty) {
      throw const ApiConfigException('invalid_api_base_url');
    }

    switch (normalizedFlavor) {
      case productionFlavor:
        if (baseUrl != productionBaseUrl) {
          throw const ApiConfigException('unapproved_production_api_origin');
        }
        return;
      case developmentFlavor:
        if (baseUrl == developmentBaseUrl) return;
        if (!isRelease && _localDebugBaseUrls.contains(baseUrl)) {
          return;
        }
        throw const ApiConfigException('unapproved_development_api_origin');
      case localFlavor:
      case localParallelFlavorOne:
      case localParallelFlavorTwo:
        if (isRelease) {
          throw const ApiConfigException('local_release_is_not_supported');
        }
        if (!_localDebugBaseUrls.contains(baseUrl)) {
          throw const ApiConfigException('unapproved_local_api_origin');
        }
        return;
      default:
        throw const ApiConfigException('unsupported_app_flavor');
    }
  }
}

class ApiConfigException implements Exception {
  const ApiConfigException(this.code);

  final String code;

  @override
  String toString() => 'ApiConfigException($code)';
}
