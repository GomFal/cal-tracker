import 'dart:convert';

import 'app_preferences_storage.dart';

class AgentChatSession {
  const AgentChatSession({
    required this.conversationId,
    required this.lastInteractionAt,
    required this.unfinished,
    this.lastCompletedAt,
  });

  final String conversationId;
  final DateTime lastInteractionAt;
  final DateTime? lastCompletedAt;
  final bool unfinished;

  factory AgentChatSession.fromJson(Map<String, Object?> json) {
    return AgentChatSession(
      conversationId: json['conversationId'] as String,
      lastInteractionAt: DateTime.parse(json['lastInteractionAt'] as String),
      lastCompletedAt: json['lastCompletedAt'] is String
          ? DateTime.parse(json['lastCompletedAt'] as String)
          : null,
      unfinished: json['unfinished'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
        'conversationId': conversationId,
        'lastInteractionAt': lastInteractionAt.toUtc().toIso8601String(),
        if (lastCompletedAt != null)
          'lastCompletedAt': lastCompletedAt!.toUtc().toIso8601String(),
        'unfinished': unfinished,
      };
}

class AgentChatSessionStore {
  AgentChatSessionStore({required AppPreferencesStorage storage})
      : _storage = storage;

  static const _schemaVersion = 1;
  static const _keyPrefix = 'agent_chat_session:v1';

  final AppPreferencesStorage _storage;
  String? _activeUserKey;

  void activateUser(String userId) {
    _activeUserKey = base64Url.encode(utf8.encode(userId));
  }

  void deactivateUser() {
    _activeUserKey = null;
  }

  Future<AgentChatSession?> readActiveSession() async {
    final storageKey = _storageKey('active');
    if (storageKey == null) return null;
    final raw = await _storage.readString(storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final envelope = _objectMap(jsonDecode(raw));
      if (envelope['schemaVersion'] != _schemaVersion) {
        await _storage.remove(storageKey);
        return null;
      }
      return AgentChatSession.fromJson(_objectMap(envelope['payload']));
    } on Object {
      await _storage.remove(storageKey);
      return null;
    }
  }

  Future<void> writeActiveSession(AgentChatSession session) async {
    final storageKey = _storageKey('active');
    if (storageKey == null) return;
    final envelope = {
      'schemaVersion': _schemaVersion,
      'payload': session.toJson(),
    };
    await _storage.writeString(storageKey, jsonEncode(envelope));
  }

  Future<void> clearActiveSession() async {
    final storageKey = _storageKey('active');
    if (storageKey == null) return;
    await _storage.remove(storageKey);
  }

  Future<void> clearActiveUserData() async {
    final userKey = _activeUserKey;
    if (userKey == null) return;
    await _storage.removeWhere(
      (key) => key.startsWith('$_keyPrefix:$userKey:'),
    );
  }

  String? _storageKey(String key) {
    final userKey = _activeUserKey;
    if (userKey == null) return null;
    return '$_keyPrefix:$userKey:$key';
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return value.map((key, nested) => MapEntry(key.toString(), nested));
}
