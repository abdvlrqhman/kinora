/// Base type of every error thrown by this package.
sealed class SwarmException implements Exception {
  const SwarmException(this.message);

  /// Human readable description.
  final String message;
}

/// A magnet link or info hash could not be parsed.
final class MagnetFormatException extends SwarmException {
  /// Creates the error for [input].
  const MagnetFormatException(super.message, this.input);

  /// The rejected text.
  final String input;

  @override
  String toString() => 'MagnetFormatException: $message ("$input")';
}
