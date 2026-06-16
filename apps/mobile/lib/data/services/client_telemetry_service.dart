import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'client_metadata_provider.dart';
import 'secure_token_storage.dart';

/// A single client-emitted telemetry event.
///
/// The fields mirror the backend `POST /v1/telemetry/client-events` contract
/// described in `specs/admin-telemetry-panel-plan.md`. Sending is best-effort
/// and asynchronous; failures must never break product UX.
@immutable
class ClientTelemetryEvent {
  const ClientTelemetryEvent({
    required this.eventType,
    required this.severity,
    required this.surface,
    this.flow,
    this.status,
    this.traceId,
    this.route,
    this.method,
    this.actionId,
    this.durationMs,
    this.errorCode,
    this.errorMessage,
    this.locale,
    this.metadata = const <String, Object?>{},
  });

  final String eventType;
  final String severity; // info | warning | error
  final String surface; // mobile | agent | stt | db | admin | backend
  final String? flow;
  final String? status; // success | failure | partial | abandoned
  final String? traceId;
  final String? route;
  final String? method;
  final String? actionId;
  final int? durationMs;
  final String? errorCode;
  final String? errorMessage;
  final String? locale;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    final meta = <String, Object?>{};
    metadata.forEach((key, value) {
      meta[key] = value;
    });
    return <String, Object?>{
      'eventType': eventType,
      'severity': severity,
      'surface': surface,
      if (flow != null) 'flow': flow,
      if (status != null) 'status': status,
      if (traceId != null) 'traceId': traceId,
      if (route != null) 'route': route,
      if (method != null) 'method': method,
      if (actionId != null) 'actionId': actionId,
      if (durationMs != null) 'durationMs': durationMs,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': _truncate(errorMessage!, 200),
      if (locale != null) 'locale': locale,
      'metadata': meta,
    };
  }
}

typedef TelemetryHttpSender = Future<http.Response> Function(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
});

/// Sender contract that lets the service be unit tested without HTTP.
typedef TelemetryJsonSender = Future<void> Function(
  Uri uri,
  Map<String, Object?> json,
);

/// Maximum events flushed in a single ingestion call.
const int kDefaultMaxBatchSize = 50;

/// Maximum number of events kept in the in-memory buffer.
const int kDefaultMaxBufferSize = 200;

/// Interval between background flushes.
const Duration kDefaultFlushInterval = Duration(seconds: 30);

class ClientTelemetryService {
  ClientTelemetryService({
    required ApiConfig apiConfig,
    required TokenStorage tokenStorage,
    required ClientMetadataProvider metadataProvider,
    Future<String?> Function()? localeTagProvider,
    TelemetryHttpSender? httpSender,
    Future<String?> Function()? sessionIdProvider,
    Duration flushInterval = kDefaultFlushInterval,
    int maxBatchSize = kDefaultMaxBatchSize,
    int maxBufferSize = kDefaultMaxBufferSize,
  })  : _apiConfig = apiConfig,
        _tokenStorage = tokenStorage,
        _metadataProvider = metadataProvider,
        _localeTagProvider = localeTagProvider,
        _sessionIdProvider = sessionIdProvider,
        _flushInterval = flushInterval,
        _maxBatchSize = maxBatchSize,
        _maxBufferSize = maxBufferSize,
        _httpSender = httpSender ?? _defaultHttpSender;

  final ApiConfig _apiConfig;
  final TokenStorage _tokenStorage;
  final ClientMetadataProvider _metadataProvider;
  final Future<String?> Function()? _localeTagProvider;
  final Future<String?> Function()? _sessionIdProvider;
  final Duration _flushInterval;
  final int _maxBatchSize;
  final int _maxBufferSize;
  final TelemetryHttpSender _httpSender;

  bool _disposed = false;
  Timer? _flushTimer;
  final List<ClientTelemetryEvent> _buffer = <ClientTelemetryEvent>[];

  /// Start the periodic background flusher. Safe to call once.
  void start() {
    if (_disposed) return;
    _flushTimer ??= Timer.periodic(_flushInterval, (_) {
      unawaited(flush());
    });
  }

  /// Enqueue a telemetry event for delivery.
  ///
  /// Failures inside the queue (e.g. serialization issues) are swallowed.
  /// When the buffer is full the oldest event is dropped to bound memory.
  void record(ClientTelemetryEvent event) {
    if (_disposed) return;
    _buffer.add(event);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }
  }

  /// Drain the queue and POST pending events. Never throws.
  Future<void> flush() async {
    if (_disposed) return;
    if (_buffer.isEmpty) return;
    final batchSize = math.min(_buffer.length, _maxBatchSize);
    final batch = List<ClientTelemetryEvent>.from(_buffer.take(batchSize));
    _buffer.removeRange(0, batchSize);
    try {
      final json = <String, Object?>{
        'events': batch.map((event) => event.toJson()).toList(),
      };
      final uri = Uri.parse('${_apiConfig.baseUrl}/v1/telemetry/client-events');
      await _send(uri, json);
    } on Object {
      // Telemetry must never break the app. Drop the batch on failure.
    }
  }

  /// Stop the periodic flusher. Pending events are dropped; call [flush]
  /// first if durable delivery matters.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  @visibleForTesting
  int get pendingCount => _buffer.length;

  Future<void> _send(Uri uri, Map<String, Object?> json) async {
    final headers = await _headers();
    await _httpSender(
      uri,
      headers: headers,
      body: jsonEncode(json),
    );
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'content-type': 'application/json; charset=UTF-8',
      'accept': 'application/json',
    };
    final tokens = await _tokenStorage.read();
    if (tokens != null) {
      headers['authorization'] = 'Bearer ${tokens.accessToken}';
    }
    try {
      final metadata = await _metadataProvider.read();
      metadata.toHeaderMap().forEach((key, value) {
        headers[key] = value;
      });
      final provider = _sessionIdProvider;
      final sessionId = provider != null
          ? await provider()
          : metadata.sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        headers['X-Client-Session-Id'] = sessionId;
      }
      final locale = await _localeTagProvider?.call();
      if (locale != null && locale.isNotEmpty) {
        headers['accept-language'] = locale;
      }
    } on Object {
      // Telemetry headers are optional.
    }
    return headers;
  }
}

Future<http.Response> _defaultHttpSender(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
}) {
  // Late import: http package is always available on supported platforms.
  return http.post(uri, headers: headers, body: body).timeout(
        const Duration(seconds: 5),
        onTimeout: () => http.Response('', 408),
      );
}

String _truncate(String value, int max) {
  if (value.length <= max) return value;
  return value.substring(0, math.min(max, value.length));
}
