import 'dart:convert';
import 'dart:io';

import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends Accept-Language from localeTagProvider', () async {
    var localeTag = 'en';
    final seenHeaders = <Map<String, String>>[];
    final client = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: _MemoryTokenStorage(),
      localeTagProvider: () async => localeTag,
      httpClient: MockClient((request) async {
        seenHeaders.add(request.headers);
        return http.Response(jsonEncode(<String, Object?>{}), 200);
      }),
    );

    await client.runAgent('100 grams rice');
    localeTag = 'pt-BR';
    await client.runAgent('100 gramas arroz');

    expect(seenHeaders[0][HttpHeaders.acceptLanguageHeader], 'en');
    expect(seenHeaders[1][HttpHeaders.acceptLanguageHeader], 'pt-BR');
  });

  test('omits Accept-Language when no localeTagProvider is supplied', () async {
    Map<String, String>? seenHeaders;
    final client = CalTrackerApiClient(
      config: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: _MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        seenHeaders = request.headers;
        return http.Response(jsonEncode(<String, Object?>{}), 200);
      }),
    );

    await client.runAgent('100 grams rice');

    expect(seenHeaders, isNotNull);
    expect(seenHeaders, isNot(contains(HttpHeaders.acceptLanguageHeader)));
  });
}

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}
