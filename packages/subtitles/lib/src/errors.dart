/// Every error this package throws on purpose.
///
/// Switch over it exhaustively to show a precise message per case.
sealed class SubtitleException implements Exception {
  const SubtitleException(this.message, {this.providerId});

  /// Human-readable description (English, safe to log: never contains keys).
  final String message;

  /// The provider involved, when there is one.
  final String? providerId;

  @override
  String toString() =>
      '$runtimeType(${providerId == null ? '' : '$providerId: '}$message)';
}

/// Connection failure or request timeout.
final class SubtitleNetworkException extends SubtitleException {
  const SubtitleNetworkException(
    super.message, {
    super.providerId,
    this.isTimeout = false,
  });

  /// True when the per-request or per-provider deadline expired.
  final bool isTimeout;
}

/// Missing, invalid or rejected credentials (HTTP 401/403 or login failure).
final class SubtitleAuthException extends SubtitleException {
  const SubtitleAuthException(super.message, {super.providerId});
}

/// The provider throttled us and the wait is longer than we retry for.
final class SubtitleRateLimitException extends SubtitleException {
  const SubtitleRateLimitException(
    super.message, {
    super.providerId,
    this.retryAfter,
  });

  /// How long the provider asked us to wait, when it said.
  final Duration? retryAfter;
}

/// The account's download quota is used up.
final class SubtitleQuotaException extends SubtitleException {
  const SubtitleQuotaException(super.message, {super.providerId, this.resetAt});

  /// When the quota renews, when the provider said.
  final DateTime? resetAt;
}

/// Any other non-success HTTP status.
final class SubtitleHttpException extends SubtitleException {
  const SubtitleHttpException(
    super.message, {
    super.providerId,
    required this.statusCode,
  });

  /// The HTTP status code.
  final int statusCode;
}

/// The provider answered with something we cannot read (bad JSON, wrong shape).
final class SubtitleResponseException extends SubtitleException {
  const SubtitleResponseException(super.message, {super.providerId});
}

/// Subtitle content we cannot decode or parse.
final class SubtitleFormatException extends SubtitleException {
  const SubtitleFormatException(super.message, {super.providerId});
}

/// An archive we cannot open (RAR, 7z) or that holds no usable subtitle.
final class SubtitleArchiveException extends SubtitleException {
  const SubtitleArchiveException(
    super.message, {
    super.providerId,
    this.unsupportedFormat,
  });

  /// `rar` or `7z` when the archive type itself is unsupported.
  final String? unsupportedFormat;
}

/// The operation was cancelled through a `CancelToken`.
final class SubtitleCancelledException extends SubtitleException {
  const SubtitleCancelledException({super.providerId}) : super('cancelled');
}
