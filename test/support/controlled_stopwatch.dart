// Copyright (C) 2026 Florian Loitsch.
class ControlledStopwatch implements Stopwatch {
  Duration value = Duration.zero;
  @override
  bool isRunning = false;
  @override
  Duration get elapsed => value;
  @override
  int get elapsedMilliseconds => value.inMilliseconds;
  @override
  int get elapsedMicroseconds => value.inMicroseconds;
  @override
  int get elapsedTicks => value.inMicroseconds;
  @override
  int get frequency => 1000000;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
  @override
  void reset() => value = Duration.zero;
}
