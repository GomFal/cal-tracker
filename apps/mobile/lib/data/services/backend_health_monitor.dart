class BackendHealthMonitor {
  BackendHealthMonitor({
    DateTime Function()? now,
    Duration healthyFor = const Duration(minutes: 2),
  }) : _now = now ?? DateTime.now,
       _healthyFor = healthyFor;

  final DateTime Function() _now;
  final Duration _healthyFor;
  DateTime? _lastSuccessAt;

  bool get isLikelyHealthy {
    final lastSuccessAt = _lastSuccessAt;
    if (lastSuccessAt == null) return false;
    return _now().difference(lastSuccessAt) <= _healthyFor;
  }

  void recordSuccess() {
    _lastSuccessAt = _now();
  }

  Future<bool> check(Future<void> Function() ping) async {
    try {
      await ping();
      recordSuccess();
      return true;
    } on Object {
      return false;
    }
  }
}
