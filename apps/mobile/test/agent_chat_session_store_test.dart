import 'dart:convert';

import 'package:cal_tracker_mobile/data/services/agent_chat_session_store.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentChatSessionStore', () {
    test('persists active sessions under the active user', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatSessionStore(storage: storage);

      store.activateUser('user-a');
      await store.writeActiveSession(_session('conversation-a'));

      expect(
        (await store.readActiveSession())?.conversationId,
        'conversation-a',
      );

      store.activateUser('user-b');
      expect(await store.readActiveSession(), isNull);

      store.activateUser('user-a');
      expect(
        (await store.readActiveSession())?.conversationId,
        'conversation-a',
      );
    });

    test('clears corrupt active sessions', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatSessionStore(storage: storage);
      store.activateUser('user-a');
      await storage.writeString(
        storageKeyForTest('agent_chat_session:v1', 'user-a', 'active'),
        '{bad json',
      );

      expect(await store.readActiveSession(), isNull);
      expect(storage.values, isEmpty);
    });

    test('clears only active user data', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatSessionStore(storage: storage);

      store.activateUser('user-a');
      await store.writeActiveSession(_session('conversation-a'));
      store.activateUser('user-b');
      await store.writeActiveSession(_session('conversation-b'));

      await store.clearActiveUserData();

      store.activateUser('user-a');
      expect(
        (await store.readActiveSession())?.conversationId,
        'conversation-a',
      );
      store.activateUser('user-b');
      expect(await store.readActiveSession(), isNull);
    });

    test('expires stale sessions and removes them from storage', () async {
      var now = DateTime.utc(2026, 6, 19, 12);
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatSessionStore(
        storage: storage,
        now: () => now,
        maxEntryAge: const Duration(days: 1),
      );
      store.activateUser('user-a');
      await store.writeActiveSession(_session('conversation-a'));

      now = now.add(const Duration(days: 2));

      expect(await store.readActiveSession(), isNull);
      expect(storage.values, isEmpty);
    });

    test('migrates legacy sessions idempotently', () async {
      final now = DateTime.utc(2026, 6, 19, 12);
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatSessionStore(storage: storage, now: () => now);
      store.activateUser('user-a');
      final key = storageKeyForTest(
        'agent_chat_session:v1',
        'user-a',
        'active',
      );
      await storage.writeString(
        key,
        jsonEncode(
            {'schemaVersion': 1, 'payload': _session('legacy').toJson()}),
      );

      expect((await store.readActiveSession())?.conversationId, 'legacy');
      expect(jsonDecode(storage.values[key]!)['schemaVersion'], 2);
      expect((await store.readActiveSession())?.conversationId, 'legacy');
      expect(storage.values, hasLength(1));
    });

    test(
      'logout removes the active session and blocks stale repopulation',
      () async {
        final storage = _MemoryPreferencesStorage();
        final store = AgentChatSessionStore(storage: storage);
        store.activateUser('user-a');
        await store.writeActiveSession(_session('conversation-a'));

        final cleanup = store.clearActiveUserData();
        await store.writeActiveSession(_session('stale'));
        await cleanup;
        await store.clearActiveUserData();

        store.activateUser('user-b');
        expect(await store.readActiveSession(), isNull);
        store.activateUser('user-a');
        expect(await store.readActiveSession(), isNull);
      },
    );
  });
}

AgentChatSession _session(String conversationId) {
  return AgentChatSession(
    conversationId: conversationId,
    lastInteractionAt: DateTime.utc(2026, 6, 19, 12),
    unfinished: true,
  );
}

String storageKeyForTest(String prefix, String userId, String key) {
  return '$prefix:${base64UserForTest(userId)}:$key';
}

String base64UserForTest(String userId) {
  return base64Url.encode(utf8.encode(userId));
}

class _MemoryPreferencesStorage implements AppPreferencesStorage {
  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> readKeys() async => values.keys.toSet();

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    values.removeWhere((key, value) => test(key));
  }
}
