import 'dart:convert';

import '../repositories/nutrition_repository.dart';
import 'app_preferences_storage.dart';

class AgentChatCacheStore {
  AgentChatCacheStore({
    required AppPreferencesStorage storage,
    DateTime Function()? now,
    Duration maxEntryAge = const Duration(days: 7),
  })  : _storage = storage,
        _now = now ?? DateTime.now,
        _maxEntryAge = maxEntryAge;

  static const _schemaVersion = 1;
  static const _keyPrefix = 'agent_chat_cache:v1';

  final AppPreferencesStorage _storage;
  final DateTime Function() _now;
  final Duration _maxEntryAge;
  String? _activeUserKey;
  int _generation = 0;
  final Map<String, Set<String>> _deletedConversationIdsByUser = {};
  final Set<String> _loadedDeletionUsers = {};

  void activateUser(String userId) {
    _activeUserKey = base64Url.encode(utf8.encode(userId));
    _generation++;
  }

  void deactivateUser() {
    _activeUserKey = null;
    _generation++;
  }

  Future<List<AgentConversationSummary>> readConversationSummaries() async {
    final context = _context();
    if (context == null) return const [];
    await _loadDeletedConversationIds(context);
    final cached = await _read(
      context,
      'summaries',
      (payload) =>
          _objectList(payload).map(AgentConversationSummary.fromJson).toList(),
    );
    final deleted = _deletedFor(context);
    return (cached ?? const [])
        .where((conversation) => !deleted.contains(conversation.id))
        .toList();
  }

  Future<void> writeConversationSummaries(
    List<AgentConversationSummary> conversations,
  ) async {
    final context = _context();
    if (context == null) return;
    await _loadDeletedConversationIds(context);
    if (!_isCurrent(context)) return;
    final deleted = _deletedFor(context);
    await _write(
      context,
      'summaries',
      conversations
          .where((conversation) => !deleted.contains(conversation.id))
          .map((conversation) => conversation.toJson())
          .toList(),
    );
  }

  Future<AgentConversationDetail?> readConversationDetail(
    String conversationId,
  ) async {
    final context = _context();
    if (context == null) return null;
    await _loadDeletedConversationIds(context);
    if (_deletedFor(context).contains(conversationId) || !_isCurrent(context)) {
      return null;
    }
    return _read(context, 'detail:$conversationId', (payload) {
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

  Future<void> writeConversationDetail(AgentConversationDetail detail) async {
    final context = _context();
    if (context == null) return;
    final id = detail.conversation.id;
    await _loadDeletedConversationIds(context);
    if (_deletedFor(context).contains(id) || !_isCurrent(context)) return;
    await _write(context, 'detail:$id', detail.toJson());
    // A DELETE may have completed while the stale write was in flight.
    if (_deletedFor(context).contains(id) || !_isCurrent(context)) {
      await _storage.remove(_storageKey(context, 'detail:$id'));
    }
  }

  Future<void> removeConversation(String conversationId) async {
    final context = _context();
    if (context == null) return;
    await _loadDeletedConversationIds(context);
    _deletedFor(context).add(conversationId);
    await _persistDeletedConversationIds(context);
    final cached = await _read(
      context,
      'summaries',
      (payload) =>
          _objectList(payload).map(AgentConversationSummary.fromJson).toList(),
      allowInactive: true,
    );
    if (cached != null) {
      await _write(
        context,
        'summaries',
        cached
            .where((conversation) => conversation.id != conversationId)
            .map((conversation) => conversation.toJson())
            .toList(),
        allowInactive: true,
      );
    }
    await _storage.remove(_storageKey(context, 'detail:$conversationId'));
  }

  Future<void> restoreConversationAfterFailedDeletion(
    String conversationId,
    AgentConversationSummary? summary,
  ) async {
    final context = _context();
    if (context == null) return;
    await _loadDeletedConversationIds(context);
    if (!_isCurrent(context)) return;
    _deletedFor(context).remove(conversationId);
    await _persistDeletedConversationIds(context);
    if (summary == null) return;
    final cached = await readConversationSummaries();
    if (cached.any((item) => item.id == summary.id)) return;
    await writeConversationSummaries([...cached, summary]);
  }

  Future<bool> isConversationDeleted(String conversationId) async {
    final context = _context();
    if (context == null) return false;
    await _loadDeletedConversationIds(context);
    return _isCurrent(context) && _deletedFor(context).contains(conversationId);
  }

  Future<List<AgentConversationSummary>> excludeDeletedConversations(
    List<AgentConversationSummary> conversations,
  ) async {
    final context = _context();
    if (context == null) return const [];
    await _loadDeletedConversationIds(context);
    if (!_isCurrent(context)) return const [];
    final deleted = _deletedFor(context);
    return conversations
        .where((conversation) => !deleted.contains(conversation.id))
        .toList();
  }

  Future<void> clearActiveUserData() async {
    final context = _context();
    if (context == null) return;
    await _storage.removeWhere(
      (key) => key.startsWith('$_keyPrefix:${context.userKey}:'),
    );
    _deletedConversationIdsByUser.remove(context.userKey);
    _loadedDeletionUsers.remove(context.userKey);
  }

  Future<T?> _read<T>(
    _CacheContext context,
    String cacheKey,
    T Function(Object? payload) decode, {
    bool allowInactive = false,
  }) async {
    final storageKey = _storageKey(context, cacheKey);
    final raw = await _storage.readString(storageKey);
    if (!allowInactive && !_isCurrent(context)) return null;
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

  Future<void> _write(
    _CacheContext context,
    String cacheKey,
    Object? payload, {
    bool allowInactive = false,
  }) async {
    if (!allowInactive && !_isCurrent(context)) return;
    final storageKey = _storageKey(context, cacheKey);
    final envelope = {
      'schemaVersion': _schemaVersion,
      'cachedAt': _now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await _storage.writeString(storageKey, jsonEncode(envelope));
    if (!allowInactive && !_isCurrent(context)) {
      await _storage.remove(storageKey);
    }
  }

  _CacheContext? _context() {
    final userKey = _activeUserKey;
    return userKey == null ? null : _CacheContext(userKey, _generation);
  }

  bool _isCurrent(_CacheContext context) =>
      _activeUserKey == context.userKey && _generation == context.generation;

  String _storageKey(_CacheContext context, String key) =>
      '$_keyPrefix:${context.userKey}:$key';

  Set<String> _deletedFor(_CacheContext context) =>
      _deletedConversationIdsByUser.putIfAbsent(context.userKey, () => {});

  Future<void> _loadDeletedConversationIds(_CacheContext context) async {
    if (_loadedDeletionUsers.contains(context.userKey)) return;
    final key = _storageKey(context, 'deleted-conversations');
    final raw = await _storage.readString(key);
    final deleted = _deletedFor(context);
    try {
      final decoded = raw == null ? const <Object?>[] : jsonDecode(raw);
      if (decoded is List) {
        deleted.addAll(decoded.whereType<String>());
      }
    } on Object {
      await _storage.remove(key);
    }
    _loadedDeletionUsers.add(context.userKey);
  }

  Future<void> _persistDeletedConversationIds(_CacheContext context) async {
    final key = _storageKey(context, 'deleted-conversations');
    await _storage.writeString(
      key,
      jsonEncode(_deletedFor(context).toList()..sort()),
    );
  }
}

class _CacheContext {
  const _CacheContext(this.userKey, this.generation);

  final String userKey;
  final int generation;
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
