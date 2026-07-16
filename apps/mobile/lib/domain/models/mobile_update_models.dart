class MobileUpdateManifest {
  const MobileUpdateManifest({
    required this.channel,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.publishedAt,
    this.sha256,
    this.sizeBytes,
  });

  final String channel;
  final String packageName;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String publishedAt;
  final String? sha256;
  final int? sizeBytes;

  factory MobileUpdateManifest.fromJson(Map<String, Object?> json) {
    const requiredKeys = <String>{
      'channel',
      'packageName',
      'versionName',
      'versionCode',
      'apkUrl',
      'publishedAt',
    };
    final keys = json.keys.toSet();
    if (!keys.containsAll(requiredKeys)) {
      throw const FormatException('Invalid mobile update manifest schema');
    }

    final publishedAt = _string(json, 'publishedAt');
    final parsedPublishedAt = DateTime.tryParse(publishedAt);
    if (parsedPublishedAt == null || !parsedPublishedAt.isUtc) {
      throw const FormatException(
        'Invalid mobile update manifest: invalid publishedAt',
      );
    }

    final sha256 = _nullableString(json, 'sha256');
    if (sha256 != null && !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException(
        'Invalid mobile update manifest: invalid sha256',
      );
    }

    final sizeBytes =
        json['sizeBytes'] == null ? null : _positiveInt(json, 'sizeBytes');

    return MobileUpdateManifest(
      channel: _string(json, 'channel'),
      packageName: _string(json, 'packageName'),
      versionName: _string(json, 'versionName'),
      versionCode: _positiveInt(json, 'versionCode'),
      apkUrl: _string(json, 'apkUrl'),
      publishedAt: publishedAt,
      sha256: sha256,
      sizeBytes: sizeBytes,
    );
  }
}

class MobileUpdateCheck {
  const MobileUpdateCheck({
    required this.installedVersionName,
    required this.installedVersionCode,
    required this.manifest,
  });

  final String installedVersionName;
  final int installedVersionCode;
  final MobileUpdateManifest manifest;

  bool get updateAvailable => manifest.versionCode > installedVersionCode;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid mobile update manifest: missing $key');
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid mobile update manifest: invalid $key');
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid mobile update manifest: missing $key');
}

int _positiveInt(Map<String, Object?> json, String key) {
  final value = _int(json, key);
  if (value > 0) return value;
  throw FormatException('Invalid mobile update manifest: invalid $key');
}
