import 'dart:async';
import 'dart:convert';

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
        (await store.readConversationDetail(
          'conversation-a',
        ))
            ?.messages
            .single
            .content,
        'hello',
      );

      await store.removeConversation('conversation-a');

      expect(await store.readConversationDetail('conversation-a'), isNull);
      expect((await store.readConversationSummaries()).map((item) => item.id), [
        'conversation-b',
      ]);
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

    test('a tombstone loaded for user A cannot contaminate user B', () async {
      final storage = _BlockingPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      final userA = base64Url.encode(utf8.encode('user-a'));
      final deletionKey = 'agent_chat_cache:v1:$userA:deleted-conversations';
      storage.values[deletionKey] = jsonEncode(['conversation-a']);
      storage.blockNextRead(deletionKey);

      store.activateUser('user-a');
      final staleRead = store.readConversationSummaries();
      await storage.readStarted;
      store.activateUser('user-b');
      storage.resumeRead();

      expect(await staleRead, isEmpty);
      await store.writeConversationDetail(_detail('conversation-a'));
      expect(await store.readConversationDetail('conversation-a'), isNotNull);
    });

    test('a stale write for user A never writes under user B', () async {
      final storage = _BlockingPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      final userA = base64Url.encode(utf8.encode('user-a'));
      final userB = base64Url.encode(utf8.encode('user-b'));
      final detailA = 'agent_chat_cache:v1:$userA:detail:conversation-a';
      final detailB = 'agent_chat_cache:v1:$userB:detail:conversation-a';

      store.activateUser('user-a');
      storage.blockNextWrite(detailA);
      final staleWrite =
          store.writeConversationDetail(_detail('conversation-a'));
      await storage.writeStarted;
      store.activateUser('user-b');
      storage.resumeWrite();
      await staleWrite;

      expect(storage.values.containsKey(detailA), isFalse);
      expect(storage.values.containsKey(detailB), isFalse);
      await store.writeConversationDetail(_detail('conversation-a'));
      expect(storage.values.containsKey(detailB), isTrue);
    });

    test('delete keeps its user snapshot when the active user switches',
        () async {
      final storage = _BlockingPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      final userA = base64Url.encode(utf8.encode('user-a'));
      final userB = base64Url.encode(utf8.encode('user-b'));
      final detailA = 'agent_chat_cache:v1:$userA:detail:conversation-a';
      final detailB = 'agent_chat_cache:v1:$userB:detail:conversation-b';
      final deletionA = 'agent_chat_cache:v1:$userA:deleted-conversations';

      store.activateUser('user-a');
      await store.writeConversationDetail(_detail('conversation-a'));
      store.activateUser('user-b');
      await store.writeConversationDetail(_detail('conversation-b'));
      store.activateUser('user-a');
      storage.blockNextWrite(deletionA);
      final deletion = store.removeConversation('conversation-a');
      await storage.writeStarted;
      store.activateUser('user-b');
      storage.resumeWrite();
      await deletion;

      expect(storage.values.containsKey(detailA), isFalse);
      expect(storage.values.containsKey(detailB), isTrue);
      expect(
          jsonDecode(storage.values[deletionA]!), contains('conversation-a'));
    });

    test('failed deletion removes tombstone even without a cached summary',
        () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage)
        ..activateUser('user-a');
      await store.removeConversation('active-conversation');
      expect(await store.isConversationDeleted('active-conversation'), isTrue);

      await store.restoreConversationAfterFailedDeletion(
        'active-conversation',
        null,
      );

      expect(await store.isConversationDeleted('active-conversation'), isFalse);
    });

    test(
      'logout removes summaries and details without stale repopulation',
      () async {
        final storage = _MemoryPreferencesStorage();
        final store = AgentChatCacheStore(storage: storage);
        store.activateUser('user-a');
        await store.writeConversationSummaries([_summary('conversation-a')]);
        await store.writeConversationDetail(_detail('conversation-a'));

        final cleanup = store.clearActiveUserData();
        await store.writeConversationSummaries([_summary('stale')]);
        await store.writeConversationDetail(_detail('stale'));
        await cleanup;
        await store.clearActiveUserData();

        store.activateUser('user-b');
        expect(await store.readConversationSummaries(), isEmpty);
        expect(await store.readConversationDetail('conversation-a'), isNull);
        store.activateUser('user-a');
        expect(await store.readConversationSummaries(), isEmpty);
        expect(await store.readConversationDetail('conversation-a'), isNull);
        expect(await store.readConversationDetail('stale'), isNull);
      },
    );

    test('logout removes a write that completes after cleanup starts',
        () async {
      final storage = _BlockingPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      final userA = base64Url.encode(utf8.encode('user-a'));
      final detailA = 'agent_chat_cache:v1:$userA:detail:conversation-a';

      store.activateUser('user-a');
      storage.blockNextWrite(detailA);
      final staleWrite =
          store.writeConversationDetail(_detail('conversation-a'));
      await storage.writeStarted;
      final cleanup = store.clearActiveUserData();
      storage.resumeWrite();
      await Future.wait([staleWrite, cleanup]);

      store.activateUser('user-a');
      expect(await store.readConversationDetail('conversation-a'), isNull);
      expect(storage.values.containsKey(detailA), isFalse);
    });

    test('removes corrupt conversation cache', () async {
      final storage = _MemoryPreferencesStorage();
      final store = AgentChatCacheStore(storage: storage);
      store.activateUser('user-a');
      await storage.writeString(
        'agent_chat_cache:v1:${base64UserForTest('user-a')}:summaries',
        '{bad json',
      );

      expect(await store.readConversationSummaries(), isEmpty);
      expect(storage.values, isEmpty);
    });
  });
}

String base64UserForTest(String userId) {
  return base64Url.encode(utf8.encode(userId));
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

class _BlockingPreferencesStorage extends _MemoryPreferencesStorage {
  String? _blockedReadKey;
  String? _blockedWriteKey;
  Completer<void>? _readStarted;
  Completer<void>? _writeStarted;
  Completer<void>? _readGate;
  Completer<void>? _writeGate;

  Future<void> get readStarted => _readStarted!.future;
  Future<void> get writeStarted => _writeStarted!.future;

  void blockNextRead(String key) {
    _blockedReadKey = key;
    _readStarted = Completer<void>();
    _readGate = Completer<void>();
  }

  void blockNextWrite(String key) {
    _blockedWriteKey = key;
    _writeStarted = Completer<void>();
    _writeGate = Completer<void>();
  }

  void resumeRead() => _readGate!.complete();
  void resumeWrite() => _writeGate!.complete();

  @override
  Future<String?> readString(String key) async {
    if (key == _blockedReadKey) {
      _blockedReadKey = null;
      _readStarted!.complete();
      await _readGate!.future;
    }
    return super.readString(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (key == _blockedWriteKey) {
      _blockedWriteKey = null;
      _writeStarted!.complete();
      await _writeGate!.future;
    }
    await super.writeString(key, value);
  }
}
