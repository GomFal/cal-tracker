import 'dart:convert';

import '../repositories/nutrition_repository.dart';
import 'app_preferences_storage.dart';

class AgentChatCacheStore {
  AgentChatCacheStore({
    required StringKeyValueStorage storage,
    DateTime Function()? now,
    Duration maxEntryAge = const Duration(days: 7),
  }) : _storage = storage,
       _now = now ?? DateTime.now,
       _maxEntryAge = maxEntryAge;

  static const _schemaVersion = 1;
  static const _keyPrefix = 'agent_chat_cache:v1';

  final StringKeyValueStorage _storage;
  final DateTime Function() _now;
  final Duration _maxEntryAge;
  String? _activeUserKey;

  void activateUser(String userId) {
    _activeUserKey = base64Url.encode(utf8.encode(userId));
  }

  void deactivateUser() {
    _activeUserKey = null;
  }

  Future<List<AgentConversationSummary>> readConversationSummaries() async {
    final cached = await _read(
      'summaries',
      (payload) =>
          _objectList(payload).map(AgentConversationSummary.fromJson).toList(),
    );
    return cached ?? const [];
  }

  Future<void> writeConversationSummaries(
    List<AgentConversationSummary> conversations,
  ) {
    return _write(
      'summaries',
      conversations.map((conversation) => conversation.toJson()).toList(),
    );
  }

  Future<AgentConversationDetail?> readConversationDetail(
    String conversationId,
  ) {
    return _read('detail:$conversationId', (payload) {
      final object = _objectMap(payload);
      return AgentConversationDetail(
        conversation: AgentConversationSummary.fromJson(
          _objectMap(object['conversation']),
        ),
        messages: _objectList(
          object['messages'],
        ).map(AgentConversationMessage.fromJson).toList(),
      );
    });
  }

  Future<void> writeConversationDetail(AgentConversationDetail detail) {
    return _write('detail:${detail.conversation.id}', detail.toJson());
  }

  Future<void> removeConversation(String conversationId) async {
    final summaries = await readConversationSummaries();
    await writeConversationSummaries(
      summaries
          .where((conversation) => conversation.id != conversationId)
          .toList(),
    );
    final detailKey = _storageKey('detail:$conversationId');
    if (detailKey != null) await _storage.remove(detailKey);
  }

  Future<void> clearActiveUserData() async {
    final userKey = _activeUserKey;
    if (userKey == null) return;
    _activeUserKey = null;
    await _storage.removeWhere(
      (key) => key.startsWith('$_keyPrefix:$userKey:'),
    );
  }

  Future<T?> _read<T>(
    String cacheKey,
    T Function(Object? payload) decode,
  ) async {
    final storageKey = _storageKey(cacheKey);
    if (storageKey == null) return null;
    final raw = await _storage.readString(storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final envelope = _objectMap(jsonDecode(raw));
      if (envelope['schemaVersion'] != _schemaVersion) {
        await _storage.remove(storageKey);
        return null;
      }
      final cachedAtRaw = envelope['cachedAt'];
      if (cachedAtRaw is! String) {
        await _storage.remove(storageKey);
        return null;
      }
      final cachedAt = DateTime.tryParse(cachedAtRaw);
      if (cachedAt == null || _now().difference(cachedAt) > _maxEntryAge) {
        await _storage.remove(storageKey);
        return null;
      }
      return decode(_normalizeJsonValue(envelope['payload']));
    } on Object {
      await _storage.remove(storageKey);
      return null;
    }
  }

  Future<void> _write(String cacheKey, Object? payload) async {
    final storageKey = _storageKey(cacheKey);
    if (storageKey == null) return;
    final envelope = {
      'schemaVersion': _schemaVersion,
      'cachedAt': _now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await _storage.writeString(storageKey, jsonEncode(envelope));
  }

  String? _storageKey(String key) {
    final userKey = _activeUserKey;
    if (userKey == null) return null;
    return '$_keyPrefix:$userKey:$key';
  }
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _normalizeJsonValue(nestedValue)),
    );
  }
  if (value is List) {
    return value.map(_normalizeJsonValue).toList();
  }
  return value;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return Map<String, Object?>.from(value);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected JSON array');
  }
  return value.map(_objectMap).toList();
}
