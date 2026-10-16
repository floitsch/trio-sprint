// Copyright (C) 2026 Toit contributors.
import 'package:flutter/material.dart';

import 'card_board.dart';
import 'data.dart';
import 'game.dart';
import 'practice.dart';

String seconds(num milliseconds) =>
    '${(milliseconds / 1000).toStringAsFixed(2)} s';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.player});
  final PlayerData player;
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  String? source;
  @override
  Widget build(BuildContext context) {
    final history = widget.player.attemptsHistory;
    final records = history
        .where((a) => source == null || a.source == source)
        .toList();
    final solved = records
        .where((a) => a.outcome == AttemptOutcome.solved)
        .toList();
    final unassisted = solved.where((a) => !a.assisted).toList()
      ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    final median = medianMilliseconds(unassisted.map((a) => a.milliseconds));
    final sources = history.map((a) => a.source).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Saved on this device from now on. Earlier training history cannot identify solved sets reliably.',
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
            title: const Text('Solved sets'),
            trailing: Text('${solved.length}'),
          ),
          ListTile(
            title: const Text('Solved with hints'),
            trailing: Text('${solved.where((a) => a.assisted).length}'),
          ),
          ListTile(
            title: const Text('Median solving time (unassisted)'),
            trailing: Text(median == null ? '—' : seconds(median)),
          ),
          if (unassisted.isNotEmpty)
            ListTile(
              title: const Text('Fastest ever set (unassisted)'),
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
          const Text('Recent attempts', style: TextStyle(fontSize: 20)),
          for (final record in records.reversed.take(100))
            ListTile(
              title: Text(
                '${outcomeLabel(record.outcome)} · ${sourceLabel(record.source)}',
              ),
              subtitle: Text(
                '${seconds(record.milliseconds)} · ${record.mistakes} mistakes${record.assisted ? ' · assisted' : ''}',
              ),
              onTap: () => review(record, 'Saved board'),
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
