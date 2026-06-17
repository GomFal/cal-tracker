import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

import '../../data/services/api_config.dart';
import '../../data/services/secure_token_storage.dart';
import '../../domain/models/nutrition_models.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.code, this.traceId});

  final int statusCode;
  final String message;
  final String? code;
  final String? traceId;

  @override
  String toString() => message;
}

class CalTrackerApiClient {
  CalTrackerApiClient({
    required this.config,
    required this.tokenStorage,
    http.Client? httpClient,
    Future<String?> Function()? localeTagProvider,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _httpClient = httpClient ?? http.Client(),
        _localeTagProvider = localeTagProvider,
        _requestTimeout = requestTimeout;

  final ApiConfig config;
  final TokenStorage tokenStorage;
  static const _largeJsonDecodeThresholdBytes = 64 * 1024;

  final http.Client _httpClient;
  final Future<String?> Function()? _localeTagProvider;
  final Duration _requestTimeout;

  Future<Map<String, Object?>> getHealth() => _get('/v1/health');

  Future<Map<String, Object?>> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _post(
        '/v1/auth/register',
        {
          'email': email,
          'password': password,
          'displayName': displayName,
        },
        authenticated: false);
  }

  Future<Map<String, Object?>> login({
    required String email,
    required String password,
  }) {
    return _post(
        '/v1/auth/login',
        {
          'email': email,
          'password': password,
        },
        authenticated: false);
  }

  Future<Map<String, Object?>> loginWithGoogle({required String idToken}) {
    return _post(
        '/v1/auth/google/login',
        {
          'idToken': idToken,
        },
        authenticated: false);
  }

  Future<Map<String, Object?>> refresh(String refreshToken) {
    return _post(
        '/v1/auth/refresh',
        {
          'refreshToken': refreshToken,
        },
        authenticated: false);
  }

  Future<Map<String, Object?>> getMe() => _get('/v1/auth/me');

  Future<Map<String, Object?>> updateSettings({
    required bool trustedModeEnabled,
  }) {
    return _put('/v1/settings', {'trustedModeEnabled': trustedModeEnabled});
  }

  Future<Map<String, Object?>> updateDailyGoals({
    String? date,
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    Map<String, Object?>? macroFields,
  }) {
    return _put('/v1/goals', {
      if (date != null) 'date': date,
      if (calories != null) 'calories': calories,
      if (hydrationGoalLiters != null)
        'hydrationGoalLiters': hydrationGoalLiters,
      if (calorieTargetSource != null)
        'calorieTargetSource': calorieTargetSource,
      if (macroFields != null) ...macroFields,
    });
  }

  Future<Map<String, Object?>> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) {
    return _put('/v1/hydration/daily', {
      if (date != null) 'date': date,
      'waterConsumedLiters': waterConsumedLiters,
    });
  }

  Future<Map<String, Object?>> estimateCalories(Map<String, Object?> body) {
    return _post('/v1/goals/calorie-estimate', body);
  }

  Future<Map<String, Object?>> runAgent(
    String text, {
    String? activeProposalId,
  }) {
    return _post('/v1/agent/runs', {
      'text': text,
      'source': 'flutter',
      if (activeProposalId != null) 'activeProposalId': activeProposalId,
    });
  }

  Stream<Map<String, Object?>> streamAgentChat(
    String message, {
    String? conversationId,
    String? activeProposalId,
  }) {
    Future<http.BaseRequest> buildRequest() async {
      final request = http.Request('POST', _uri('/v1/agent/chat'));
      request.headers.addAll(await _headers());
      request.body = jsonEncode({
        'message': message,
        'source': 'flutter',
        if (conversationId != null) 'conversationId': conversationId,
        if (activeProposalId != null) 'activeProposalId': activeProposalId,
      });
      return request;
    }

    return _sendSseRequest(buildRequest);
  }

  Future<Map<String, Object?>> searchFoods({
    required String query,
    String? barcode,
    int limit = 10,
  }) {
    return _post('/v1/foods/search', {
      'query': query,
      if (barcode != null) 'barcode': barcode,
      'limit': limit,
    });
  }

  Future<Map<String, Object?>> proposeMeal(String text) {
    return _post('/v1/meals/proposals', {'text': text});
  }

  Future<Map<String, Object?>> commitProposal(
    String proposalId, {
    MealLabel? mealLabel,
  }) {
    return _post('/v1/meals/proposals/$proposalId/commit', {
      if (mealLabel != null) 'mealLabel': mealLabel.toJson(),
    });
  }

  Future<Map<String, Object?>> correctMeal(
    String mealId,
    List<Map<String, Object?>> items,
  ) {
    return _post('/v1/meals/$mealId/correct', {'items': items});
  }

  Future<Map<String, Object?>> correctProposal({
    required String proposalId,
    required List<Map<String, Object?>> items,
  }) {
    return executeAction('correct_meal', {
      'proposalId': proposalId,
      'items': items,
    });
  }

  Future<Map<String, Object?>> deleteMeal(
    String mealId, {
    bool confirmed = false,
  }) {
    final suffix = confirmed ? '?confirmationToken=DELETE' : '';
    return _delete('/v1/meals/$mealId$suffix');
  }

  Future<Map<String, Object?>> getDailySummary({String? date}) {
    return _get('/v1/summary/daily${date == null ? '' : '?date=$date'}');
  }

  Future<Map<String, Object?>> getMealHistory() => _get('/v1/meals');

  Future<Map<String, Object?>> getTemplates() => _get('/v1/meal-templates');

  Future<Map<String, Object?>> createTemplate(Map<String, Object?> body) {
    return _post('/v1/meal-templates', body);
  }

  Future<Map<String, Object?>> updateTemplate(
    String templateId,
    Map<String, Object?> body,
  ) {
    return _put('/v1/meal-templates/$templateId', body);
  }

  Future<Map<String, Object?>> deleteTemplate(String templateId) {
    return _delete('/v1/meal-templates/$templateId');
  }

  Future<Map<String, Object?>> draftUsualMeal(String text) {
    return _post('/v1/meal-templates/draft', {'text': text});
  }

  Future<Map<String, Object?>> getUsualFoods() => _get('/v1/usual-foods');

  Future<Map<String, Object?>> createUsualFood(Map<String, Object?> body) {
    return _post('/v1/usual-foods', body);
  }

  Future<Map<String, Object?>> updateUsualFood(
    String foodId,
    Map<String, Object?> body,
  ) {
    return _put('/v1/usual-foods/$foodId', body);
  }

  Future<Map<String, Object?>> deleteUsualFood(String foodId) {
    return _delete('/v1/usual-foods/$foodId');
  }

  Future<Map<String, Object?>> draftUsualFood(String text) {
    return _post('/v1/usual-foods/draft', {'text': text});
  }

  Future<Map<String, Object?>> executeAction(
    String actionId,
    Map<String, Object?> input,
  ) {
    return _post('/v1/actions/$actionId/execute', {
      'input': input,
      'source': 'flutter',
    });
  }

  Future<Map<String, Object?>> transcribeAudio(
    File audioFile, {
    String? source,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/v1/stt/transcriptions'),
    );
    request.headers.addAll(await _headers(includeContentType: false));
    request.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        audioFile.path,
        contentType: _detectContentType(audioFile.path),
      ),
    );
    if (source != null) {
      request.fields['source'] = source;
    }

    // Use a dedicated client with longer timeouts for file uploads.
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 120);
    final uploadClient = IOClient(ioClient);

    try {
      final streamedResponse = await uploadClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        final tokens = await tokenStorage.read();
        if (tokens != null) {
          final refreshed = await refresh(tokens.refreshToken);
          await tokenStorage.write(
            StoredTokens(
              accessToken: refreshed['accessToken'] as String,
              refreshToken: refreshed['refreshToken'] as String,
            ),
          );
          return transcribeAudio(audioFile, source: source);
        }
      }

      return _decode(response);
    } finally {
      uploadClient.close();
    }
  }

  Stream<Map<String, Object?>> streamAgentChatAudio(
    File audioFile, {
    String? conversationId,
    String? activeProposalId,
  }) {
    Future<http.BaseRequest> buildRequest() async {
      final request = http.MultipartRequest(
        'POST',
        _uri('/v1/agent/chat/audio'),
      );
      request.headers.addAll(await _headers(includeContentType: false));
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audioFile.path,
          contentType: _detectContentType(audioFile.path),
        ),
      );
      request.fields['source'] = 'flutter';
      if (conversationId != null) {
        request.fields['conversationId'] = conversationId;
      }
      if (activeProposalId != null) {
        request.fields['activeProposalId'] = activeProposalId;
      }
      return request;
    }

    return _sendSseRequest(buildRequest);
  }

  Future<Map<String, Object?>> runVoiceMeal(
    File audioFile, {
    String? source,
    String? activeProposalId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/voice/meal-runs'));
    request.headers.addAll(await _headers(includeContentType: false));
    request.files.add(
      await http.MultipartFile.fromPath(
        'audio',
        audioFile.path,
        contentType: _detectContentType(audioFile.path),
      ),
    );
    if (source != null) {
      request.fields['source'] = source;
    }
    if (activeProposalId != null) {
      request.fields['activeProposalId'] = activeProposalId;
    }

    // Use a dedicated client with longer timeouts for file uploads.
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 120);
    final uploadClient = IOClient(ioClient);

    try {
      final streamedResponse = await uploadClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        final tokens = await tokenStorage.read();
        if (tokens != null) {
          final refreshed = await refresh(tokens.refreshToken);
          await tokenStorage.write(
            StoredTokens(
              accessToken: refreshed['accessToken'] as String,
              refreshToken: refreshed['refreshToken'] as String,
            ),
          );
          return runVoiceMeal(
            audioFile,
            source: source,
            activeProposalId: activeProposalId,
          );
        }
      }

      return _decode(response);
    } finally {
      uploadClient.close();
    }
  }

  Stream<Map<String, Object?>> _sendSseRequest(
    Future<http.BaseRequest> Function() buildRequest,
  ) async* {
    var response = await _httpClient.send(await buildRequest());
    if (response.statusCode == 401) {
      final tokens = await tokenStorage.read();
      if (tokens != null) {
        final refreshed = await refresh(tokens.refreshToken);
        await tokenStorage.write(
          StoredTokens(
            accessToken: refreshed['accessToken'] as String,
            refreshToken: refreshed['refreshToken'] as String,
          ),
        );
        response = await _httpClient.send(await buildRequest());
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await http.Response.fromStream(response);
      await _decode(body);
      return;
    }

    final pending = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final event in _parseSseEvents(chunk, pending)) {
        yield event;
      }
    }
    final lastEvent = _parsePendingSseEvent(pending);
    if (lastEvent != null) yield lastEvent;
  }

  Iterable<Map<String, Object?>> _parseSseEvents(
    String chunk,
    StringBuffer pending,
  ) sync* {
    pending.write(chunk);
    final raw = pending.toString();
    final parts = raw.split('\n\n');
    pending.clear();
    if (parts.isNotEmpty) pending.write(parts.removeLast());
    for (final part in parts) {
      final event = _decodeSseEvent(part);
      if (event != null) yield event;
    }
  }

  Map<String, Object?>? _parsePendingSseEvent(StringBuffer pending) {
    final raw = pending.toString();
    pending.clear();
    return _decodeSseEvent(raw);
  }

  Map<String, Object?>? _decodeSseEvent(String raw) {
    final dataLines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (dataLines.isEmpty) return null;
    final decoded = jsonDecode(dataLines.join('\n'));
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Future<Map<String, Object?>> _get(String path) async {
    final response = await _sendWithRefresh(
      () async => _httpClient.get(_uri(path), headers: await _headers()),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) async {
    final response = await _sendWithRefresh(
      () async => _httpClient.post(
        _uri(path),
        headers: await _headers(authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _put(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _sendWithRefresh(
      () async => _httpClient.put(
        _uri(path),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _delete(String path) async {
    final response = await _sendWithRefresh(
      () async => _httpClient.delete(_uri(path), headers: await _headers()),
    );
    return _decode(response);
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function() send, {
    bool authenticated = true,
  }) async {
    final first = await _withRequestTimeout(send());
    if (!authenticated || first.statusCode != 401) return first;

    final tokens = await tokenStorage.read();
    if (tokens == null) return first;
    final refreshed = await refresh(tokens.refreshToken);
    await tokenStorage.write(
      StoredTokens(
        accessToken: refreshed['accessToken'] as String,
        refreshToken: refreshed['refreshToken'] as String,
      ),
    );
    return _withRequestTimeout(send());
  }

  Future<http.Response> _withRequestTimeout(Future<http.Response> request) {
    return request.timeout(
      _requestTimeout,
      onTimeout: () => throw const ApiException(
        408,
        'The request took too long. Please try again.',
        code: 'request_timeout',
      ),
    );
  }

  Future<Map<String, String>> _headers({
    bool authenticated = true,
    bool includeContentType = true,
  }) async {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
    };
    final localeTag = (await _localeTagProvider?.call())?.trim();
    if (localeTag != null && localeTag.isNotEmpty) {
      headers[HttpHeaders.acceptLanguageHeader] = localeTag;
    }
    if (includeContentType) {
      headers[HttpHeaders.contentTypeHeader] =
          'application/json; charset=UTF-8';
    }
    if (authenticated) {
      final tokens = await tokenStorage.read();
      if (tokens != null) {
        headers[HttpHeaders.authorizationHeader] =
            'Bearer ${tokens.accessToken}';
      }
    }
    return headers;
  }

  static MediaType _detectContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'm4a':
        return MediaType('audio', 'm4a');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'webm':
        return MediaType('audio', 'webm');
      case 'ogg':
        return MediaType('audio', 'ogg');
      case 'mp4':
        return MediaType('audio', 'mp4');
      default:
        return MediaType('audio', 'm4a');
    }
  }

  Future<Map<String, Object?>> _decode(http.Response response) async {
    final body = await _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final error = body['error'] as Map<String, Object?>?;
    throw ApiException(
      response.statusCode,
      error?['message'] as String? ?? 'We could not complete that request.',
      code: error?['code'] as String?,
      traceId: error?['traceId'] as String?,
    );
  }

  Uri _uri(String path) => Uri.parse('${config.baseUrl}$path');

  Future<Map<String, Object?>> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) return Future.value(<String, Object?>{});
    if (rawBody.length >= _largeJsonDecodeThresholdBytes) {
      return compute(_decodeJsonMap, rawBody);
    }
    return Future.value(_decodeJsonMap(rawBody));
  }

  static Map<String, Object?> _decodeJsonMap(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }
}
