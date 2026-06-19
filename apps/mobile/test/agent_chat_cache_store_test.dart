import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/agent_chat_cache_store.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentChatCacheStore', () {
    test('persists summaries under the active user', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);

      store.activateUser('user-a');
      await store.writeConversationSummaries([_summary('conversation-a')]);

      expect(
        (await store.readConversationSummaries()).single.id,
        'conversation-a',
      );

      store.activateUser('user-b');
      expect(await store.readConversationSummaries(), isEmpty);
    });

    test('persists and removes conversation details', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      store.activateUser('user-a');
      await store.writeConversationSummaries([
        _summary('conversation-a'),
        _summary('conversation-b'),
      ]);
      await store.writeConversationDetail(_detail('conversation-a'));

      expect(
        (await store.readConversationDetail('conversation-a'))
            ?.messages
            .single
            .content,
        'hello',
      );

      await store.removeConversation('conversation-a');

      expect(await store.readConversationDetail('conversation-a'), isNull);
      expect(
        (await store.readConversationSummaries()).map((item) => item.id),
        ['conversation-b'],
      );
    });

    test('expires stale cache entries', () async {
      var now = DateTime.utc(2026, 6, 19);
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatCacheStore(
        storage: storage,
        now: () => now,
        maxEntryAge: const Duration(days: 1),
      );
      store.activateUser('user-a');
      await store.writeConversationDetail(_detail('conversation-a'));
      expect(storage.values, hasLength(1));

      now = now.add(const Duration(days: 2));

      expect(await store.readConversationDetail('conversation-a'), isNull);
      expect(storage.values, isEmpty);
    });
  });
}

AgentConversationSummary _summary(String id) {
  return AgentConversationSummary(
    id: id,
    title: 'Chat $id',
    createdAt: DateTime.utc(2026, 6, 19, 12),
    updatedAt: DateTime.utc(2026, 6, 19, 12, 1),
  );
}

AgentConversationDetail _detail(String id) {
  return AgentConversationDetail(
    conversation: _summary(id),
    messages: [
      AgentConversationMessage(
        id: 'message-$id',
        conversationId: id,
        role: 'user',
        content: 'hello',
        createdAt: DateTime.utc(2026, 6, 19, 12),
        traceId: 'trace-1',
        turnId: '11111111-1111-1111-1111-111111111111',
        inputMode: 'text',
        source: 'flutter',
      ),
    ],
  );
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
