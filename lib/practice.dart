import 'package:flutter/widgets.dart';

import 'game.dart';

enum AttemptOutcome { solved, timedOut, restarted, interrupted, skipped }

/// A board as seen by the player, including any training constraints.
class PracticeBoard {
  PracticeBoard({
    required this.cards,
    this.anchors = const [],
    this.differences,
    this.milliseconds = 0,
    this.mistakes = 0,
    this.assisted = false,
    this.outcome = AttemptOutcome.solved,
    this.source = 'legacy',
    this.solutionCards = const [],
    this.seed,
    this.recordedAt,
  });

  final List<int> cards;
  final List<int> anchors;
  final int? differences;
  final int milliseconds;
  final int mistakes;
  final bool assisted;
  final AttemptOutcome outcome;
  final String source;
  final List<int> solutionCards;
  final String? seed;
  final int? recordedAt;
  bool get countsForTraining => outcome != AttemptOutcome.interrupted;
  bool get benchmark =>
      outcome == AttemptOutcome.solved &&
      !assisted &&
      anchors.isEmpty &&
      differences == null &&
      source != 'legacy' &&
      source != 'replay';

  String get key {
    final sorted = [...cards]..sort();
    final fixed = [...anchors]..sort();
    return '$sorted/$fixed/$differences';
  }

  int get difficulty =>
      milliseconds +
      mistakes * 5000 +
      (assisted ||
              outcome == AttemptOutcome.restarted ||
              outcome == AttemptOutcome.skipped
          ? 15000
          : 0);

  bool accepts(List<SetCard> trio) =>
      isSet(trio) &&
      (differences == null || differentAttributes(trio) == differences);

  List<SetCard>? get solution {
    final board = cards.map(SetCard.new).toList();
    if (anchors.isNotEmpty) {
      for (final card in board) {
        final trio = [...anchors.map(SetCard.new), card];
        if (accepts(trio)) return trio;
      }
    } else {
      for (var a = 0; a < board.length - 2; a++) {
        for (var b = a + 1; b < board.length - 1; b++) {
          for (var c = b + 1; c < board.length; c++) {
            final trio = [board[a], board[b], board[c]];
            if (accepts(trio)) return trio;
          }
        }
      }
    }
    return null;
  }

  PracticeBoard result(
    int elapsed,
    int errors,
    bool helped, {
    AttemptOutcome outcome = AttemptOutcome.solved,
    String source = 'training',
    List<int> solutionCards = const [],
  }) => PracticeBoard(
    cards: cards,
    anchors: anchors,
    differences: differences,
    milliseconds: elapsed,
    mistakes: errors,
    assisted: helped,
    outcome: outcome,
    source: source,
    solutionCards: solutionCards,
    seed: seed,
    recordedAt: DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, dynamic> toJson() => {
    'outcome': outcome.name,
    'source': source,
    'solutionCards': solutionCards,
    'seed': seed,
    'recordedAt': recordedAt,
    'cards': cards,
    'anchors': anchors,
    'differences': differences,
    'milliseconds': milliseconds,
    'mistakes': mistakes,
    'assisted': assisted,
  };

  factory PracticeBoard.fromJson(Map<String, dynamic> json) {
    final board = PracticeBoard(
      outcome: AttemptOutcome.values.byName(
        json['outcome'] as String? ?? 'solved',
      ),
      source: json['source'] as String? ?? 'legacy',
      solutionCards: (json['solutionCards'] as List? ?? []).cast<int>(),
      seed: json['seed'] as String?,
      recordedAt: json['recordedAt'] as int?,
      cards: (json['cards'] as List).cast<int>(),
      anchors: (json['anchors'] as List).cast<int>(),
      differences: json['differences'] as int?,
      milliseconds: json['milliseconds'] as int,
      mistakes: json['mistakes'] as int,
      assisted: json['assisted'] as bool,
    );
    final all = [...board.cards, ...board.anchors];
    if (board.cards.length != (board.anchors.isEmpty ? 12 : 6) ||
        (board.anchors.isNotEmpty && board.anchors.length != 2) ||
        all.any((id) => id < 0 || id > 80) ||
        all.toSet().length != all.length ||
        (board.differences != null &&
            (board.differences! < 1 || board.differences! > 4)) ||
        (board.solutionCards.isNotEmpty &&
            (board.solutionCards.length != 3 ||
                board.solutionCards.toSet().length != 3 ||
                board.solutionCards.any((id) => !all.contains(id)) ||
                !board.accepts(
                  board.solutionCards.map(SetCard.new).toList(),
                ))) ||
        board.milliseconds < 0 ||
        board.mistakes < 0 ||
        board.solution == null) {
      throw const FormatException('Invalid practice board');
    }
    return board;
  }
}

/// Measures time spent looking at a board, excluding background time.
/// This does not affect the competitive sprint clock.
class BoardClock with WidgetsBindingObserver {
  BoardClock() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _watch = Stopwatch();
  bool _active = false;
  int get milliseconds => _watch.elapsedMilliseconds;
  bool get active => _active;

  void start() {
    _active = true;
    _watch
      ..stop()
      ..reset();
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _watch.start();
    }
  }

  void stop() {
    _active = false;
    _watch.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _active) {
      _watch.start();
    } else {
      _watch.stop();
    }
  }

  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
  }
}
