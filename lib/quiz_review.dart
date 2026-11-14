// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';

import 'card_board.dart';
import 'game.dart';

class QuizReviewTrio {
  QuizReviewTrio({required List<int> cards, this.answer})
    : cards = List.unmodifiable(cards);

  final List<int> cards;
  final bool? answer;
  bool get expected => isSet(cards.map(SetCard.new).toList());
  bool get wrong => answer != null && answer != expected;
  String get status => answer == null
      ? 'Unanswered'
      : wrong
      ? 'Wrong'
      : 'Correct';
}

class QuizReviewScreen extends StatefulWidget {
  const QuizReviewScreen({super.key, required this.trios});
  final List<QuizReviewTrio> trios;

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  bool wrongOnly = false;
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var i = 0; i < widget.trios.length; i++)
        if (!wrongOnly || widget.trios[i].wrong) i,
    ];
    final originalIndex = visible.isEmpty ? null : visible[index];
    final trio = originalIndex == null ? null : widget.trios[originalIndex];
    final wrongCount = widget.trios.where((trio) => trio.wrong).length;
    final details = trio == null
        ? null
        : SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trio ${originalIndex! + 1} of ${widget.trios.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      trio.answer == null
                          ? Icons.hourglass_empty
                          : trio.wrong
                          ? Icons.close
                          : Icons.check,
                      color: trio.answer == null
                          ? null
                          : trio.wrong
                          ? Theme.of(context).colorScheme.error
                          : const Color(0xFF397B63),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trio.status,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  trio.answer == null
                      ? 'You did not answer this trio.'
                      : 'Your answer: ${trio.answer! ? 'Yes' : 'No'}',
                ),
                Text(
                  'Correct answer: ${trio.expected ? 'Yes — this is a set.' : 'No — this is not a set.'}',
                ),
                const SizedBox(height: 12),
                Text(
                  explainTrio(trio.cards.map(SetCard.new).toList()),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Review trios')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Wrong only'),
                  subtitle: Text(
                    '$wrongCount wrong ${wrongCount == 1 ? 'answer' : 'answers'}',
                  ),
                  value: wrongOnly,
                  onChanged: (value) => setState(() {
                    wrongOnly = value;
                    index = 0;
                  }),
                ),
                Expanded(
                  child: trio == null
                      ? Center(
                          child: Text(
                            wrongOnly
                                ? 'No wrong answers.'
                                : 'No trios to review.',
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final cards = Padding(
                              padding: const EdgeInsets.all(12),
                              child: CardBoard(cards: trio.cards, columns: 3),
                            );
                            if (constraints.maxWidth >
                                constraints.maxHeight * 1.3) {
                              return Row(
                                children: [
                                  Expanded(child: cards),
                                  Expanded(child: details!),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                Expanded(flex: 3, child: cards),
                                Flexible(flex: 2, child: details!),
                              ],
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous trio',
                        onPressed: index == 0 || visible.isEmpty
                            ? null
                            : () => setState(() => index--),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        visible.isEmpty
                            ? '0 / 0'
                            : '${index + 1} / ${visible.length}',
                      ),
                      IconButton(
                        tooltip: 'Next trio',
                        onPressed: index + 1 >= visible.length
                            ? null
                            : () => setState(() => index++),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
