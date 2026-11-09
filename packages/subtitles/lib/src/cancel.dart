import 'dart:async';

import 'errors.dart';

/// Cooperative cancellation for searches and downloads.
///
/// A token created with a `parent` is cancelled when the parent is.
final class CancelToken {
  /// Creates a token, optionally linked to a [parent].
  CancelToken({CancelToken? parent}) {
    parent?.whenCancelled.then((_) => cancel());
  }

  final Completer<void> _done = Completer<void>();

  /// Whether [cancel] was called (here or on a parent).
  bool get isCancelled => _done.isCompleted;

  /// Completes when the token is cancelled.
  Future<void> get whenCancelled => _done.future;

  /// Cancels every operation using this token. Idempotent.
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }

  /// Throws [SubtitleCancelledException] when cancelled.
  void throwIfCancelled({String? providerId}) {
    if (isCancelled) throw SubtitleCancelledException(providerId: providerId);
  }
}
