/// Base type of every error thrown by this package.
///
/// The hierarchy is sealed so callers can `switch` over it exhaustively.
sealed class StremioException implements Exception {
  const StremioException(this.message, {this.uri});

  /// Human readable description.
  final String message;

  /// Request URL the error relates to, when there is one.
  final Uri? uri;

  @override
  String toString() =>
      uri == null ? '$_kind: $message' : '$_kind: $message ($uri)';

  String get _kind;
}

/// The text given as an addon URL cannot be turned into a manifest URL.
final class InvalidAddonUrlException extends StremioException {
  /// Creates the error for [input].
  const InvalidAddonUrlException(this.input, String message) : super(message);

  /// The rejected input.
  final String input;

  @override
  String get _kind => 'InvalidAddonUrlException';
}

/// The addon answered with a non-2xx HTTP status.
final class AddonHttpException extends StremioException {
  /// Creates the error for [statusCode].
  const AddonHttpException(this.statusCode, Uri uri)
    : super('HTTP $statusCode', uri: uri);

  /// HTTP status code of the final attempt.
  final int statusCode;

  @override
  String get _kind => 'AddonHttpException';
}

/// The addon could not be reached (DNS, TCP, TLS, connection reset).
final class AddonNetworkException extends StremioException {
  /// Creates the error.
  const AddonNetworkException(super.message, {required Uri super.uri});

  @override
  String get _kind => 'AddonNetworkException';
}

/// No answer within the allowed time (after retries).
final class AddonTimeoutException extends StremioException {
  /// Creates the error for a request that ran longer than [timeout].
  AddonTimeoutException(this.timeout, {super.uri})
    : super('no answer within ${timeout.inMilliseconds} ms');

  /// The limit that was exceeded.
  final Duration timeout;

  @override
  String get _kind => 'AddonTimeoutException';
}

/// The response is not valid JSON or does not match the addon protocol.
final class AddonResponseException extends StremioException {
  /// Creates the error.
  const AddonResponseException(super.message, {super.uri});

  @override
  String get _kind => 'AddonResponseException';
}

/// The caller cancelled the request.
final class AddonCancelledException extends StremioException {
  /// Creates the error.
  const AddonCancelledException({super.uri}) : super('cancelled');

  @override
  String get _kind => 'AddonCancelledException';
}

/// A debrid-backed addon rejected the user's API key or token and returned
/// only placeholder streams instead of results.
final class DebridKeyRejectedException extends StremioException {
  /// Creates the error.
  const DebridKeyRejectedException(super.message, {super.uri});

  @override
  String get _kind => 'DebridKeyRejectedException';
}
