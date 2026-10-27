// Copyright (C) 2026 Toit contributors.
import 'game.dart';
import 'practice.dart';

/// A solo run, including practice replays and runs stopped before completion.
class RunRecord {
  const RunRecord({
    required this.id,
    required this.seed,
    required this.source,
    required this.completed,
    required this.sets,
    required this.mistakes,
    this.milliseconds,
    this.recordedAt,
    this.activeTimeOnly = false,
  });

  final String id;
  final String seed;
  final String source;
  final bool completed;
  final int sets;
  final int mistakes;
  // Sprint finish time, or the time of the last set in a timed run.
  final int? milliseconds;
  final int? recordedAt;
  final bool activeTimeOnly;
  RunMode get mode => RunMode.of(seed);

  Map<String, dynamic> toJson() => {
    'id': id,
    'seed': seed,
    'source': source,
    'completed': completed,
    'sets': sets,
    'mistakes': mistakes,
    'milliseconds': milliseconds,
    'recordedAt': recordedAt,
  };

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
    id: json['id'] as String,
    seed: json['seed'] as String,
    source: json['source'] as String,
    completed: json['completed'] as bool,
    sets: json['sets'] as int,
    mistakes: json['mistakes'] as int,
    milliseconds: json['milliseconds'] as int?,
    recordedAt: json['recordedAt'] as int?,
  );
}

/// Recover older runs from terminal board outcomes without counting an
/// abandoned timed run's solved boards as a completed score.
List<RunRecord> restoreRunHistory(
  List<RunRecord> saved,
  List<PracticeBoard> attempts,
  List<Map<String, dynamic>> scores,
) {
  final runs = [...saved];
  final savedIds = saved.map((r) => r.id).toSet();
  final scoresBySeed = {for (final score in scores) score['seed']: score};
  var boards = <PracticeBoard>[];
  var group = 0;

  void flush() {
    if (boards.isEmpty) return;
    final first = boards.first;
    final last = boards.last;
    final mode = RunMode.of(first.seed!);
    final sets = boards.where((b) => b.outcome == AttemptOutcome.solved).length;
    final completed = mode.timed
        ? last.outcome == AttemptOutcome.timedOut
        : sets == 5;
    final score = completed && first.source != 'replay'
        ? scoresBySeed[first.seed]
        : null;
    runs.add(
      RunRecord(
        id: first.runId ?? 'history-${group++}',
        seed: first.seed!,
        source: first.source,
        completed: completed,
        sets: sets,
        mistakes: boards.fold(0, (sum, b) => sum + b.mistakes),
        milliseconds:
            score?['milliseconds'] as int? ??
            (mode.timed
                ? null
                : boards.fold<int>(0, (sum, b) => sum + b.milliseconds)),
        recordedAt: last.recordedAt,
        activeTimeOnly: score == null && !mode.timed,
      ),
    );
    boards = [];
  }

  for (final board in attempts) {
    if (board.seed == null ||
        !{'s1', 's2', '1m', '3m', 'replay'}.contains(board.source) ||
        savedIds.contains(board.runId)) {
      flush();
      continue;
    }
    if (boards.isNotEmpty &&
        (boards.first.seed != board.seed ||
            boards.first.source != board.source ||
            boards.first.runId != board.runId)) {
      flush();
    }
    boards.add(board);
    if (board.outcome != AttemptOutcome.solved ||
        (!RunMode.of(board.seed!).timed && boards.length == 5)) {
      flush();
    }
  }
  flush();

  // Public-score outbox entries predate board history on some devices. They
  // have no timestamps, so they can only appear in the all-time view.
  final completedSeeds = runs
      .where((r) => r.completed && r.source != 'replay')
      .map((r) => r.seed)
      .toSet();
  for (final score in scores) {
    final seed = score['seed'] as String;
    if (completedSeeds.contains(seed)) continue;
    runs.add(
      RunRecord(
        id: 'score-$seed',
        seed: seed,
        source: seed.split('-').first,
        completed: true,
        sets: (score['solutions'] as List).length,
        mistakes: score['mistakes'] as int,
        milliseconds: score['milliseconds'] as int,
      ),
    );
  }
  runs.sort((a, b) => (b.recordedAt ?? 0).compareTo(a.recordedAt ?? 0));
  return runs;
}
