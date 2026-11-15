// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';

import 'data.dart';
import 'leaderboard.dart';
import 'run_ui.dart';

String quizDurationLabel(int seconds) =>
    seconds == 30 ? '30 s' : '${seconds ~/ 60} min';

class QuizLeaderboardScreen extends StatefulWidget {
  const QuizLeaderboardScreen({
    super.key,
    this.player,
    this.seconds = 30,
    this.difficult = false,
    this.api,
  });
  final PlayerData? player;
  final int seconds;
  final bool difficult;
  final OnlineApi? api;

  @override
  State<QuizLeaderboardScreen> createState() => _QuizLeaderboardScreenState();
}

class _QuizLeaderboardScreenState extends State<QuizLeaderboardScreen> {
  late int seconds = widget.seconds;
  late bool difficult = widget.difficult;
  late bool unique = widget.player?.unique ?? true;
  late final api = widget.api ?? OnlineApi();
  Future<List<Map<String, dynamic>>>? scores;

  void refresh() => setState(() => scores = null);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Yes / No high scores'),
      actions: [
        IconButton(
          onPressed: refresh,
          tooltip: 'Refresh scores',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (widget.player case final player?)
                        ListTile(
                          title: Text(
                            player.nickname.isEmpty
                                ? 'No name yet'
                                : 'Playing as ${player.nickname}',
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              if (await editNickname(context, player) &&
                                  mounted) {
                                refresh();
                              }
                            },
                            child: Text(
                              player.nickname.isEmpty ? 'Set name' : 'Change',
                            ),
                          ),
                        ),
                      SegmentedButton<int>(
                        segments: [
                          for (final value in [30, 60, 180])
                            ButtonSegment(
                              value: value,
                              label: Text(quizDurationLabel(value)),
                            ),
                        ],
                        selected: {seconds},
                        onSelectionChanged: (value) {
                          seconds = value.single;
                          refresh();
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Difficult only'),
                        value: difficult,
                        onChanged: (value) {
                          difficult = value;
                          refresh();
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Only each player’s best'),
                        value: unique,
                        onChanged: (value) {
                          unique = value;
                          widget.player?.setUnique(value);
                          refresh();
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Top 100 · correct − wrong\nTies favor fewer mistakes.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: RunScoreList<Map<String, dynamic>>(
                  future: scores ??= api.quizScores(
                    seconds: seconds,
                    difficult: difficult,
                    unique: unique,
                  ),
                  buildRow: (row, i) {
                    return ListTile(
                      leading: Text('${i + 1}'),
                      title: Text(row['name'] as String),
                      subtitle: Text(
                        '${row['correct']} correct · ${row['mistakes']} wrong',
                      ),
                      trailing: Text(
                        '${row['score']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
