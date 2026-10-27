// Copyright (C) 2026 Toit contributors.
import 'package:flutter/material.dart';

import 'card_board.dart';
import 'data.dart';
import 'game.dart';
import 'practice.dart';
import 'run_history.dart';

String seconds(num milliseconds) =>
    '${(milliseconds / 1000).toStringAsFixed(2)} s';

enum StatisticsPeriod {
  all('All time'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days'),
  quarter('Last 90 days'),
  custom('Custom dates');

  const StatisticsPeriod(this.label);
  final String label;
}

String statisticsDate(BuildContext context, int? timestamp) => timestamp == null
    ? 'Date unavailable'
    : MaterialLocalizations.of(context)
          .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(timestamp));

String runScore(RunRecord run) {
  if (!run.completed) return 'Abandoned';
  if (run.mode.timed) return '${run.sets} sets';
  return run.milliseconds == null ? 'Completed' : seconds(run.milliseconds!);
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.player});
  final PlayerData player;
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  String? source;
  StatisticsPeriod period = StatisticsPeriod.all;
  DateTimeRange? customRange;

  Future<void> selectPeriod(StatisticsPeriod value) async {
    if (value == StatisticsPeriod.custom) {
      final today = DateUtils.dateOnly(DateTime.now());
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: today,
        initialDateRange:
            customRange ??
            DateTimeRange(
              start: DateTime(today.year, today.month, today.day - 29),
              end: today,
            ),
      );
      if (!mounted || range == null) return;
      customRange = range;
    }
    setState(() => period = value);
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.player.attemptsHistory;
    final runHistory = widget.player.runHistory;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final days = switch (period) {
      StatisticsPeriod.today => 1,
      StatisticsPeriod.week => 7,
      StatisticsPeriod.month => 30,
      StatisticsPeriod.quarter => 90,
      _ => null,
    };
    final start = days == null
        ? customRange?.start
        : DateTime(today.year, today.month, today.day - days + 1);
    final endDate = period == StatisticsPeriod.custom
        ? customRange?.end
        : today;
    final end = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day + 1);
    bool inPeriod(int? timestamp) =>
        period == StatisticsPeriod.all ||
        (timestamp != null &&
            timestamp >= start!.millisecondsSinceEpoch &&
            timestamp < end!.millisecondsSinceEpoch);
    final records = history
        .where(
          (a) =>
              (source == null || a.source == source) && inPeriod(a.recordedAt),
        )
        .toList();
    final runs = runHistory
        .where(
          (r) =>
              (source == null || r.source == source) && inPeriod(r.recordedAt),
        )
        .toList();
    final completedRuns = runs.where((r) => r.completed).toList();
    final timedRuns = {
      for (final mode in RunMode.values.where((m) => m.timed))
        mode: completedRuns.where((r) => r.mode == mode).toList(),
    };
    final solved = records
        .where((a) => a.outcome == AttemptOutcome.solved)
        .toList();
    final unassisted = solved.where((a) => !a.assisted).toList()
      ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    final median = medianMilliseconds(unassisted.map((a) => a.milliseconds));
    final sources = {
      ...history.map((a) => a.source),
      ...runHistory.map((r) => r.source),
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Statistics are saved on this device. Choose a mode and date range to compare your progress.',
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Time period'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<StatisticsPeriod>(
                value: period,
                isExpanded: true,
                items: [
                  for (final value in StatisticsPeriod.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) selectPeriod(value);
                },
              ),
            ),
          ),
          if (period == StatisticsPeriod.custom)
            TextButton(
              onPressed: () => selectPeriod(StatisticsPeriod.custom),
              child: Text(
                '${statisticsDate(context, customRange!.start.millisecondsSinceEpoch)} – '
                '${statisticsDate(context, customRange!.end.millisecondsSinceEpoch)}',
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All modes'),
                selected: source == null,
                onSelected: (_) => setState(() => source = null),
              ),
              for (final value in sources)
                ChoiceChip(
                  label: Text(sourceLabel(value)),
                  selected: source == value,
                  onSelected: (_) => setState(() => source = value),
                ),
            ],
          ),
          ListTile(
            title: const Text('Completed runs'),
            trailing: Text('${completedRuns.length}'),
          ),
          for (final entry in timedRuns.entries)
            if (entry.value.isNotEmpty)
              ListTile(
                title: Text('${sourceLabel(entry.key.prefix)} · average score'),
                subtitle: Text('${entry.value.length} completed runs'),
                trailing: Text(
                  '${(entry.value.fold<int>(0, (sum, r) => sum + r.sets) / entry.value.length).toStringAsFixed(1)} sets',
                ),
              ),
          ListTile(
            title: const Text('Solved sets'),
            trailing: Text('${solved.length}'),
          ),
          ListTile(
            title: const Text('Solved with hints'),
            subtitle: const Text(
              'Hints are available in Training, including Cards I was slow on.',
            ),
            trailing: Text('${solved.where((a) => a.assisted).length}'),
          ),
          ListTile(
            title: const Text('Median solving time (unassisted)'),
            trailing: Text(median == null ? '—' : seconds(median)),
          ),
          if (unassisted.isNotEmpty)
            ListTile(
              title: Text(
                period == StatisticsPeriod.all
                    ? 'Fastest ever set (unassisted)'
                    : 'Fastest set (unassisted)',
              ),
              subtitle: const Text('View the layout and your solution'),
              trailing: Text(seconds(unassisted.first.milliseconds)),
              onTap: () => review(unassisted.first, 'Fastest set'),
            ),
          for (final outcome in AttemptOutcome.values.where(
            (o) => o != AttemptOutcome.solved,
          ))
            ListTile(
              title: Text(outcomeLabel(outcome)),
              trailing: Text(
                '${records.where((a) => a.outcome == outcome).length}',
              ),
            ),
          const Text(
            'Times measure active viewing and exclude time in the background. Unfinished attempts never enter solving-time statistics. Training and replays can be filtered separately.',
          ),
          const SizedBox(height: 16),
          const Text('Recent runs', style: TextStyle(fontSize: 20)),
          if (runs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No runs in this period.'),
            ),
          for (final run in runs.take(100))
            ListTile(
              title: Text(
                '${sourceLabel(run.seed.split('-').first)}${run.source == 'replay' ? ' · Practice replay' : ''}',
              ),
              subtitle: Text(
                [
                  statisticsDate(context, run.recordedAt),
                  run.seed,
                  '${run.mistakes} mistakes',
                  if (run.completed &&
                      run.mode.timed &&
                      run.sets > 0 &&
                      run.milliseconds != null)
                    'Last set at ${seconds(run.milliseconds!)}',
                  if (run.completed && run.activeTimeOnly) 'Active time only',
                ].join(' · '),
              ),
              trailing: Text(runScore(run)),
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Individual board attempts'),
            tilePadding: EdgeInsets.zero,
            children: [
              if (records.isEmpty)
                const ListTile(
                  title: Text('No board attempts in this period.'),
                ),
              for (final record in records.reversed.take(100))
                ListTile(
                  title: Text(
                    '${outcomeLabel(record.outcome)} · ${sourceLabel(record.source)}',
                  ),
                  subtitle: Text(
                    '${statisticsDate(context, record.recordedAt)} · ${seconds(record.milliseconds)} · ${record.mistakes} mistakes${record.assisted ? ' · assisted' : ''}',
                  ),
                  onTap: () => review(record, 'Saved board'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void review(PracticeBoard board, String title) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BoardReviewScreen(board: board, title: title),
    ),
  );
}

String sourceLabel(String source) => switch (source) {
  's2' => 'Five-set sprint',
  's1' => 'Legacy sprint',
  '1m' => '1 minute',
  '3m' => '3 minutes',
  'race' => 'Race',
  'training' => 'Training',
  'review' => 'Difficult-card training',
  'replay' => 'Practice replay',
  _ => source,
};

String outcomeLabel(AttemptOutcome outcome) => switch (outcome) {
  AttemptOutcome.solved => 'Solved',
  AttemptOutcome.timedOut => 'Timed out',
  AttemptOutcome.restarted => 'Restarted / too slow',
  AttemptOutcome.interrupted => 'Interrupted',
  AttemptOutcome.skipped => 'Skipped',
};

class BoardReviewScreen extends StatefulWidget {
  const BoardReviewScreen({
    super.key,
    required this.board,
    required this.title,
  });
  final PracticeBoard board;
  final String title;
  @override
  State<BoardReviewScreen> createState() => _BoardReviewScreenState();
}

class _BoardReviewScreenState extends State<BoardReviewScreen> {
  bool reveal = false;
  final selected = <int>{};
  String feedback = '';
  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final solution = board.solutionCards.isEmpty
        ? board.solution!.map((c) => c.id).toSet()
        : board.solutionCards.toSet();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Explore this board freely. This review does not change your score or statistics.',
              ),
            ),
            if (board.anchors.isNotEmpty)
              SizedBox(height: 100, child: CardBoard(cards: board.anchors)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CardBoard(
                  cards: board.cards,
                  selected: reveal ? solution : selected,
                  onTap: reveal
                      ? null
                      : (card) => setState(() {
                          if (!selected.remove(card.id)) selected.add(card.id);
                          if (selected.length + board.anchors.length == 3) {
                            feedback =
                                board.accepts(
                                  [
                                    ...board.anchors,
                                    ...selected,
                                  ].map(SetCard.new).toList(),
                                )
                                ? 'That’s a set!'
                                : 'Not a matching set. Try again.';
                            selected.clear();
                          }
                        }),
                ),
              ),
            ),
            Text(feedback),
            TextButton(
              onPressed: () => setState(() => reveal = !reveal),
              child: Text(reveal ? 'Hide solution' : 'Show solution'),
            ),
          ],
        ),
      ),
    );
  }
}
