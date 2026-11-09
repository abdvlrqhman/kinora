/// Base class of every error thrown by this package.
///
/// Switch over the subtypes to tell "TV is off" ([DlnaUnreachableException])
/// from "TV refused the command" ([DlnaSoapFault]).
sealed class DlnaException implements Exception {
  const DlnaException(this.message);

  /// Human-readable description (English, for logs and diagnostics).
  final String message;
}

/// The device did not answer: connection refused/reset, no route, or timeout.
///
/// This is what a TV that was switched off (or left the Wi-Fi) looks like.
final class DlnaUnreachableException extends DlnaException {
  const DlnaUnreachableException(
    super.message, {
    this.uri,
    this.cause,
    this.isTimeout = false,
  });

  /// The URL that was being requested, when there was one.
  final Uri? uri;

  /// The underlying error (socket/HTTP client exception), if any.
  final Object? cause;

  /// True when the request was abandoned because it exceeded its timeout.
  final bool isTimeout;

  @override
  String toString() =>
      'DlnaUnreachableException: $message${uri == null ? '' : ' ($uri)'}';
}

/// The device answered with an unexpected HTTP status that is not a SOAP fault.
final class DlnaHttpException extends DlnaException {
  const DlnaHttpException(super.message, {required this.statusCode, this.uri});

  /// The HTTP status code.
  final int statusCode;

  /// The URL that was requested.
  final Uri? uri;

  @override
  String toString() =>
      'DlnaHttpException: HTTP $statusCode $message${uri == null ? '' : ' ($uri)'}';
}

/// A UPnP control error (`<UPnPError>` inside a SOAP fault).
final class DlnaSoapFault extends DlnaException {
  const DlnaSoapFault({
    required this.action,
    required this.errorCode,
    this.errorDescription,
  }) : super('UPnP error $errorCode');

  /// 401 Invalid Action.
  static const invalidAction = 401;

  /// 402 Invalid Args.
  static const invalidArgs = 402;

  /// 501 Action Failed.
  static const actionFailed = 501;

  /// 701 Transition not available (e.g. Play while TRANSITIONING).
  static const transitionNotAvailable = 701;

  /// 705 Transport is locked.
  static const transportLocked = 705;

  /// 710 Seek mode not supported.
  static const seekModeNotSupported = 710;

  /// 711 Illegal seek target.
  static const illegalSeekTarget = 711;

  /// 714 Illegal MIME-type.
  static const illegalMimeType = 714;

  /// 716 Resource not found.
  static const resourceNotFound = 716;

  /// 718 Invalid InstanceID.
  static const invalidInstanceId = 718;

  /// The SOAP action that failed, e.g. `SetAVTransportURI`.
  final String action;

  /// The UPnP `errorCode`.
  final int errorCode;

  /// The UPnP `errorDescription`, when the device sent one.
  final String? errorDescription;

  @override
  String toString() =>
      'DlnaSoapFault: $action failed with UPnP error $errorCode'
      '${errorDescription == null ? '' : ' ($errorDescription)'}';
}

/// The device answered with something unusable: malformed XML, missing
/// required fields, not a media renderer, or a missing service.
final class DlnaProtocolException extends DlnaException {
  const DlnaProtocolException(super.message, {this.uri});

  /// The URL whose response was unusable, if known.
  final Uri? uri;

  @override
  String toString() =>
      'DlnaProtocolException: $message${uri == null ? '' : ' ($uri)'}';
}
