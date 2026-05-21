class MobileUpdateManifest {
  const MobileUpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.publishedAt,
    this.sha256,
    this.sizeBytes,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String publishedAt;
  final String? sha256;
  final int? sizeBytes;

  factory MobileUpdateManifest.fromJson(Map<String, Object?> json) {
    return MobileUpdateManifest(
      versionName: _string(json, 'versionName'),
      versionCode: _int(json, 'versionCode'),
      apkUrl: _string(json, 'apkUrl'),
      publishedAt: _string(json, 'publishedAt'),
      sha256: _nullableString(json, 'sha256'),
      sizeBytes: json['sizeBytes'] == null ? null : _int(json, 'sizeBytes'),
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
  return value is String && value.isNotEmpty ? value : null;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.parse(value);
  throw FormatException('Invalid mobile update manifest: missing $key');
}
