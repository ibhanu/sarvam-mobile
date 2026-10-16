import 'dart:async';

import 'clock.dart';
import 'exceptions.dart';

/// Lightweight cancellation token for cancelling long-running asynchronous polling jobs.
class CancellationToken {
  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation of the associated job.
  void cancel() {
    _isCancelled = true;
  }
}

/// Thrown when a polling operation is explicitly cancelled by the caller.
class JobCancelledException implements Exception {
  final String message;

  const JobCancelledException([this.message = 'Job polling was cancelled']);

  @override
  String toString() => 'JobCancelledException: $message';
}

/// Generic cancellable polling helper using an injectable [Clock] for deterministic delays.
class JobPoller {
  final Clock clock;

  const JobPoller({this.clock = const SystemClock()});

  /// Repeatedly calls [pollFn] at [pollInterval] intervals until [isComplete] returns true,
  /// [isFailed] returns true, [timeout] is exceeded, or cancellation is requested.
  Future<T> waitUntilComplete<T>({
    required Future<T> Function() pollFn,
    required bool Function(T status) isComplete,
    bool Function(T status)? isFailed,
    String Function(T status)? failureMessage,
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    CancellationToken? cancellationToken,
    bool Function()? isCancelled,
  }) async {
    final startTime = clock.now();

    while (true) {
      if (cancellationToken?.isCancelled == true ||
          (isCancelled != null && isCancelled())) {
        throw const JobCancelledException('Job polling cancelled by caller');
      }

      final status = await pollFn();

      if (isComplete(status)) {
        return status;
      }

      if (isFailed != null && isFailed(status)) {
        final msg = failureMessage != null
            ? failureMessage(status)
            : 'Job failed with status: $status';
        throw ServerException(message: msg);
      }

      final elapsed = clock.now().difference(startTime);
      if (elapsed >= timeout) {
        throw TimeoutException(
          message:
              'Job polling timed out after ${timeout.inSeconds} seconds (${elapsed.inSeconds}s elapsed)',
          phase: TimeoutPhase.total,
        );
      }

      await clock.sleep(pollInterval);
    }
  }
}
