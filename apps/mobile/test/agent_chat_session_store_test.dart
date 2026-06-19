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
