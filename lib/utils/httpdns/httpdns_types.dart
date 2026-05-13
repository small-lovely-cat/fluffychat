/// Supported HTTPDNS provider options.
enum HttpDnsProvider {
  none('none', 'Disabled'),
  aliyun('aliyun', 'Aliyun HTTPDNS'),
  volcengine('volcengine', 'Volcengine HTTPDNS');

  final String storageValue;
  final String displayName;

  const HttpDnsProvider(this.storageValue, this.displayName);

  /// Restores a provider enum from persisted storage.
  ///
  /// Parameters:
  ///   value: The raw provider id stored in shared preferences.
  /// Returns:
  ///   The matching provider, or [HttpDnsProvider.none] if unknown.
  static HttpDnsProvider fromStorage(String? value) =>
      HttpDnsProvider.values.firstWhere(
        (provider) => provider.storageValue == value,
        orElse: () => HttpDnsProvider.none,
      );
}

/// Native HTTPDNS bridge status exposed to Flutter.
class HttpDnsStatus {
  final bool platformSupported;
  final bool credentialsConfigured;
  final HttpDnsProvider selectedProvider;
  final HttpDnsProvider effectiveProvider;
  final String? message;

  const HttpDnsStatus({
    required this.platformSupported,
    required this.credentialsConfigured,
    required this.selectedProvider,
    required this.effectiveProvider,
    this.message,
  });

  const HttpDnsStatus.initial()
    : platformSupported = false,
      credentialsConfigured = false,
      selectedProvider = HttpDnsProvider.none,
      effectiveProvider = HttpDnsProvider.none,
      message = null;

  /// Whether the selected provider is currently active for requests.
  bool get isActive =>
      platformSupported &&
      credentialsConfigured &&
      effectiveProvider != HttpDnsProvider.none;

  /// Builds a status object from the native bridge payload.
  ///
  /// Parameters:
  ///   rawStatus: The raw status map returned by the platform channel.
  /// Returns:
  ///   A parsed [HttpDnsStatus] object.
  factory HttpDnsStatus.fromMap(Map<Object?, Object?>? rawStatus) {
    final status = rawStatus ?? const <Object?, Object?>{};
    return HttpDnsStatus(
      platformSupported: status['platformSupported'] as bool? ?? false,
      credentialsConfigured: status['credentialsConfigured'] as bool? ?? false,
      selectedProvider: HttpDnsProvider.fromStorage(
        status['selectedProvider'] as String?,
      ),
      effectiveProvider: HttpDnsProvider.fromStorage(
        status['effectiveProvider'] as String?,
      ),
      message: status['message'] as String?,
    );
  }
}
