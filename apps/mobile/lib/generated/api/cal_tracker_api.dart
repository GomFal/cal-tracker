import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

import '../../data/services/api_config.dart';
import '../../data/services/client_metadata_provider.dart';
import '../../data/services/client_telemetry_service.dart';
import '../../data/services/request_id_generator.dart';
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

class ApiCallResult<T> {
  const ApiCallResult({required this.body, required this.requestId});

  final T body;
  final String requestId;
}

class CalTrackerApiClient {
  CalTrackerApiClient({
    required this.config,
    required this.tokenStorage,
    http.Client? httpClient,
    Future<String?> Function()? localeTagProvider,
    ClientMetadataProvider? metadataProvider,
    RequestIdGenerator? requestIdGenerator,
    ClientTelemetryService? telemetryService,
  }) : _httpClient = httpClient ?? http.Client(),
       _localeTagProvider = localeTagProvider,
       _metadataProvider = metadataProvider,
       _requestIdGenerator = requestIdGenerator ?? RequestIdGenerator(),
       _telemetryService = telemetryService;

  final ApiConfig config;
  final TokenStorage tokenStorage;
  final http.Client _httpClient;
  final Future<String?> Function()? _localeTagProvider;
  final ClientMetadataProvider? _metadataProvider;
  final RequestIdGenerator _requestIdGenerator;
  final ClientTelemetryService? _telemetryService;
  String? _lastRequestId;

  /// Most recently generated `X-Request-Id` for diagnostic/telemetry use.
  String? get lastRequestId => _lastRequestId;

  Future<Map<String, Object?>> getHealth() => _get('/v1/health');

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

  Future<Map<String, Object?>> searchFoods({
    required String query,
    String? barcode,
    int limit = 10,
  }) async {
    final result = await searchFoodsWithRequestId(
      query: query,
      barcode: barcode,
      limit: limit,
    );
    return result.body;
  }

  Future<ApiCallResult<Map<String, Object?>>> searchFoodsWithRequestId({
    required String query,
    String? barcode,
    int limit = 10,
  }) {
    return _postWithRequestId('/v1/foods/search', {
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
    const path = '/v1/stt/transcriptions';
    final stopwatch = Stopwatch()..start();
    final traceId = _requestIdGenerator.next();
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(
      await _headers(includeContentType: false, requestId: traceId),
    );
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

      return _decode(
        response,
        route: path,
        method: 'POST',
        requestId: traceId,
        durationMs: stopwatch.elapsed.inMilliseconds,
      );
    } finally {
      uploadClient.close();
    }
  }

  Future<Map<String, Object?>> runVoiceMeal(
    File audioFile, {
    String? source,
    String? activeProposalId,
  }) async {
    const path = '/v1/voice/meal-runs';
    final stopwatch = Stopwatch()..start();
    final traceId = _requestIdGenerator.next();
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(
      await _headers(includeContentType: false, requestId: traceId),
    );
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

      return _decode(
        response,
        route: path,
        method: 'POST',
        requestId: traceId,
        durationMs: stopwatch.elapsed.inMilliseconds,
      );
    } finally {
      uploadClient.close();
    }
  }

  Future<Map<String, Object?>> _get(String path) async {
    final stopwatch = Stopwatch()..start();
    final requestId = _requestIdGenerator.next();
    final response = await _sendWithRefresh(
      () async => _httpClient.get(
        _uri(path),
        headers: await _headers(requestId: requestId),
      ),
    );
    return _decode(
      response,
      route: path,
      method: 'GET',
      requestId: requestId,
      durationMs: stopwatch.elapsed.inMilliseconds,
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) async {
    final result = await _postWithRequestId(
      path,
      body,
      authenticated: authenticated,
    );
    return result.body;
  }

  Future<ApiCallResult<Map<String, Object?>>> _postWithRequestId(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final requestId = _requestIdGenerator.next();
    final response = await _sendWithRefresh(
      () async => _httpClient.post(
        _uri(path),
        headers: await _headers(
          authenticated: authenticated,
          requestId: requestId,
        ),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
    return ApiCallResult<Map<String, Object?>>(
      body: _decode(
        response,
        route: path,
        method: 'POST',
        requestId: requestId,
        durationMs: stopwatch.elapsed.inMilliseconds,
      ),
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> _put(
    String path,
    Map<String, Object?> body,
  ) async {
    final stopwatch = Stopwatch()..start();
    final requestId = _requestIdGenerator.next();
    final response = await _sendWithRefresh(
      () async => _httpClient.put(
        _uri(path),
        headers: await _headers(requestId: requestId),
        body: jsonEncode(body),
      ),
    );
    return _decode(
      response,
      route: path,
      method: 'PUT',
      requestId: requestId,
      durationMs: stopwatch.elapsed.inMilliseconds,
    );
  }

  Future<Map<String, Object?>> _delete(String path) async {
    final stopwatch = Stopwatch()..start();
    final requestId = _requestIdGenerator.next();
    final response = await _sendWithRefresh(
      () async => _httpClient.delete(
        _uri(path),
        headers: await _headers(requestId: requestId),
      ),
    );
    return _decode(
      response,
      route: path,
      method: 'DELETE',
      requestId: requestId,
      durationMs: stopwatch.elapsed.inMilliseconds,
    );
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
    String? requestId,
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
    headers['X-Request-Id'] = requestId ?? _requestIdGenerator.next();
    _lastRequestId = headers['X-Request-Id'];
    await _attachMetadataHeaders(headers);
    return headers;
  }

  Future<void> _attachMetadataHeaders(Map<String, String> headers) async {
    final provider = _metadataProvider;
    if (provider == null) return;
    try {
      final metadata = await provider.read();
      metadata.toHeaderMap().forEach((key, value) {
        headers[key] = value;
      });
    } on Object {
      // Metadata is best-effort. Never let it break a request.
    }
  }

  void _recordApiFailure({
    String? route,
    String? method,
    required int status,
    String? traceId,
    int? durationMs,
    String? errorCode,
  }) {
    final telemetry = _telemetryService;
    if (telemetry == null) return;
    final resolvedTraceId = traceId;
    try {
      telemetry.record(
        ClientTelemetryEvent(
          eventType: 'mobile.api_request_failed',
          flow: route != null && route.contains('/voice')
              ? 'voice_meal'
              : (route != null && route.contains('/stt') ? 'stt' : 'api'),
          surface: 'mobile',
          severity: status >= 500 ? 'error' : 'warning',
          status: 'failure',
          traceId: resolvedTraceId,
          route: route,
          method: method,
          durationMs: durationMs,
          errorCode: errorCode ?? 'http_$status',
          errorMessage: 'HTTP $status',
          metadata: <String, Object?>{
            'status': status,
            if (resolvedTraceId != null) 'requestId': resolvedTraceId,
          },
        ),
      );
    } on Object {
      // Telemetry must never break the API call.
    }
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

  Map<String, Object?> _decode(
    http.Response response, {
    String? route,
    String? method,
    String? requestId,
    int? durationMs,
  }) {
    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final error = body['error'] as Map<String, Object?>?;
    final traceId =
        (error?['traceId'] as String?) ??
        (response.headers['x-request-id'] ?? response.headers['X-Request-Id']);
    _recordApiFailure(
      route: route,
      method: method,
      status: response.statusCode,
      traceId: traceId ?? requestId,
      durationMs: durationMs,
      errorCode: error?['code'] as String?,
    );
    throw ApiException(
      response.statusCode,
      error?['message'] as String? ?? 'We could not complete that request.',
      code: error?['code'] as String?,
      traceId: traceId ?? requestId,
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
