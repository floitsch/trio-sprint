// Copyright (C) 2026 Florian Loitsch.
import 'dart:async';

import 'package:flutter/widgets.dart';

enum RunPhase { ready, countdown, playing, finished }

/// Owns the lifecycle and clocks shared by sprint and recognition runs.
class RunSession extends ChangeNotifier with WidgetsBindingObserver {
  RunSession({Stopwatch? stopwatch}) : watch = stopwatch ?? Stopwatch() {
    WidgetsBinding.instance.addObserver(this);
  }

  final Stopwatch watch;
  final elapsed = ValueNotifier(Duration.zero);
  RunPhase _phase = RunPhase.ready;
  RunPhase get phase => _phase;
  bool get active => phase == RunPhase.countdown || phase == RunPhase.playing;
  int countdown = 2;
  bool resultsLocked = false;
  Duration? _limit;
  Duration? get remaining {
    final limit = _limit;
    if (limit == null) return null;
    return elapsed.value >= limit ? Duration.zero : limit - elapsed.value;
  }

  Timer? _countdown;
  Timer? _ticker;
  Timer? _deadline;
  Timer? _resultLock;
  int _generation = 0;
  VoidCallback? _onLimit;
  bool Function()? _canExpire;

  void start({
    Duration? limit,
    VoidCallback? onPlaying,
    VoidCallback? onLimit,
    bool Function()? canExpire,
  }) {
    stop();
    final generation = _generation;
    _limit = limit;
    _onLimit = onLimit;
    _canExpire = canExpire;
    watch.reset();
    elapsed.value = Duration.zero;
    countdown = 2;
    _phase = RunPhase.countdown;
    notifyListeners();
    if (generation != _generation) return;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (generation != _generation) {
        timer.cancel();
        return;
      }
      if (countdown > 1) {
        countdown--;
      } else {
        timer.cancel();
        _phase = RunPhase.playing;
        watch.start();
        onPlaying?.call();
        if (generation != _generation || phase != RunPhase.playing) return;
        if (limit != null) _deadline = Timer(limit, _expire);
        _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
          elapsed.value = watch.elapsed;
          checkLimit();
        });
      }
      notifyListeners();
    });
  }

  /// Also checks elapsed time on taps and resume, when timers may be late.
  bool checkLimit() {
    if (phase != RunPhase.playing ||
        _limit == null ||
        watch.elapsed < _limit!) {
      return false;
    }
    _expire();
    return true;
  }

  void _expire() {
    if (phase == RunPhase.playing && (_canExpire?.call() ?? true)) {
      _onLimit?.call();
    }
  }

  /// Stops clocks without changing the page while a run is being prepared.
  void stop() {
    _generation++;
    _countdown?.cancel();
    _ticker?.cancel();
    _deadline?.cancel();
    _resultLock?.cancel();
    resultsLocked = false;
    watch.stop();
  }

  void reset() {
    stop();
    _phase = RunPhase.ready;
    notifyListeners();
  }

  /// Shows the next countdown while a completed score is persisted locally.
  void waitForRetry() {
    stop();
    countdown = 2;
    _phase = RunPhase.countdown;
    notifyListeners();
  }

  void finish({bool lockInput = false, Duration? shownElapsed}) {
    stop();
    elapsed.value = shownElapsed ?? watch.elapsed;
    _phase = RunPhase.finished;
    resultsLocked = lockInput;
    if (lockInput) {
      _resultLock = Timer(const Duration(seconds: 1), () {
        resultsLocked = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkLimit();
  }

  @override
  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
    elapsed.dispose();
    super.dispose();
  }
}
