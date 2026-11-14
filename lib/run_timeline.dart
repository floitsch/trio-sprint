// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';

import 'game.dart';
import 'practice.dart';
import 'statistics.dart';

/// Wall-clock intervals between solves, including time spent on mistakes.
class RunTimeline extends StatelessWidget {
  const RunTimeline({
    super.key,
    required this.setTimes,
    this.unfinished,
    this.boards = const [],
    this.unfinishedBoard,
  });

  final List<Duration> setTimes;
  final Duration? unfinished;
  final List<PracticeBoard> boards;
  final PracticeBoard? unfinishedBoard;

  static const colors = [
    Color(0xFF397B63),
    Color(0xFF7659A6),
    Color(0xFFB55347),
    Color(0xFF426FA8),
    Color(0xFF997020),
  ];

  @override
  Widget build(BuildContext context) {
    final intervals = [...setTimes, ?unfinished];
    if (intervals.isEmpty) return const SizedBox.shrink();
    String label(int i) =>
        i < setTimes.length ? 'Set ${i + 1}' : 'Unsolved board';
    Color color(int i) => i < setTimes.length
        ? colors[i % colors.length]
        : const Color(0xFF90969C);

    return Semantics(
      button: true,
      label: 'Show individual set times and boards',
      child: InkWell(
        key: const ValueKey('run-timeline'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set times',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Time between sets, including mistakes and time away.',
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: intervals.length,
                    itemBuilder: (context, i) {
                      final board = i < setTimes.length
                          ? (i < boards.length ? boards[i] : null)
                          : unfinishedBoard;
                      return ListTile(
                        onTap: board == null
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BoardReviewScreen(
                                    board: board,
                                    title: label(i),
                                    showSolution: i < setTimes.length,
                                  ),
                                ),
                              ),
                        leading: CircleAvatar(
                          backgroundColor: color(i),
                          foregroundColor: Colors.white,
                          child: i < setTimes.length
                              ? Text('${i + 1}')
                              : const Icon(Icons.hourglass_empty),
                        ),
                        title: Text(label(i)),
                        subtitle: board == null
                            ? null
                            : const Text('Tap to review cards'),
                        trailing: Text('${formatTime(intervals[i])} s'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      for (var i = 0; i < intervals.length; i++)
                        Expanded(
                          flex: intervals[i].inMicroseconds.clamp(
                            1,
                            86400000000,
                          ),
                          child: Tooltip(
                            message:
                                '${label(i)}: ${formatTime(intervals[i])} s',
                            child: Container(color: color(i)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Set times · tap for details'),
            ],
          ),
        ),
      ),
    );
  }
}
