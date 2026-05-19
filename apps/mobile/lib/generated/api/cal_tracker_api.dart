import 'dart:convert';
import 'dart:io';

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
  }) : _httpClient = httpClient ?? http.Client();

  final ApiConfig config;
  final TokenStorage tokenStorage;
  final http.Client _httpClient;

  Future<Map<String, Object?>> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _post('/v1/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    }, authenticated: false);
  }

  Future<Map<String, Object?>> login({
    required String email,
    required String password,
  }) {
    return _post('/v1/auth/login', {
      'email': email,
      'password': password,
    }, authenticated: false);
  }

  Future<Map<String, Object?>> loginWithGoogle({required String idToken}) {
    return _post('/v1/auth/google/login', {
      'idToken': idToken,
    }, authenticated: false);
  }

  Future<Map<String, Object?>> refresh(String refreshToken) {
    return _post('/v1/auth/refresh', {
      'refreshToken': refreshToken,
    }, authenticated: false);
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
    int? hydrationGoalGlasses,
    String? calorieTargetSource,
  }) {
    return _put('/v1/goals', {
      if (date != null) 'date': date,
      if (calories != null) 'calories': calories,
      if (hydrationGoalGlasses != null)
        'hydrationGoalGlasses': hydrationGoalGlasses,
      if (calorieTargetSource != null)
        'calorieTargetSource': calorieTargetSource,
    });
  }

  Future<Map<String, Object?>> estimateCalories(Map<String, Object?> body) {
    return _post('/v1/goals/calorie-estimate', body);
  }

  Future<Map<String, Object?>> runAgent(String text) {
    return _post('/v1/agent/runs', {'text': text, 'source': 'flutter'});
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

  Future<Map<String, Object?>> runVoiceMeal(
    File audioFile, {
    String? source,
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
          return runVoiceMeal(audioFile, source: source);
        }
      }

      return _decode(response);
    } finally {
      uploadClient.close();
    }
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
    final first = await send();
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
    return send();
  }

  Future<Map<String, String>> _headers({
    bool authenticated = true,
    bool includeContentType = true,
  }) async {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
    };
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

  Map<String, Object?> _decode(http.Response response) {
    final body = _decodeBody(response.body);
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

  Map<String, Object?> _decodeBody(String rawBody) {
    if (rawBody.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }
}
