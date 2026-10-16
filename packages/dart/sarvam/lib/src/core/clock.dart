import 'dart:async';

/// Clock abstraction for time retrieval and sleeping.
/// Allows deterministic testing with mock clocks.
abstract interface class Clock {
  /// Returns the current time.
  DateTime now();

  /// Asynchronously sleeps for the specified [duration].
  Future<void> sleep(Duration duration);
}

/// Default system clock backed by [DateTime.now] and [Future.delayed].
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}

/// Controllable mock clock for deterministic testing without real time delays.
class MockClock implements Clock {
  DateTime _currentTime;
  final List<Duration> recordedSleeps = <Duration>[];

  MockClock({DateTime? initialTime})
      : _currentTime =
            initialTime ?? DateTime.fromMillisecondsSinceEpoch(1700000000000);

  @override
  DateTime now() => _currentTime;

  @override
  Future<void> sleep(Duration duration) async {
    recordedSleeps.add(duration);
    _currentTime = _currentTime.add(duration);
  }

  void advance(Duration duration) {
    _currentTime = _currentTime.add(duration);
  }
}
