import 'package:flutter/material.dart';

import 'card_view.dart';
import 'game.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int differences = 4;
  bool completePair = false;
  late TrainingExercise exercise = makeExercise();
  final selected = <int>{};
  String feedback = 'Find a set with all four features different.';
  bool solved = false;
  bool hinted = false;
  int completed = 0;
  TrainingExercise makeExercise() =>
      TrainingExercise(differences: differences, completePair: completePair);
  void next() => setState(() {
    exercise = makeExercise();
    selected.clear();
    solved = false;
    hinted = false;
    feedback = completePair
        ? 'Choose the missing third card.'
        : 'Find a set with $differences different features.';
  });
  void pick(SetCard card) {
    if (solved) return;
    setState(() {
      if (selected.remove(card.id)) return;
      selected.add(card.id);
      if (!completePair && selected.length < 3) return;
      final cards = completePair
          ? [...exercise.solution.take(2), card]
          : exercise.board.where((c) => selected.contains(c.id)).toList();
      solved = exercise.accepts(cards);
      if (solved) completed++;
      feedback =
          '${solved
              ? 'Yes!'
              : isSet(cards)
              ? 'Valid set, but aim for $differences different features.'
              : 'Try again.'}\n${explainTrio(cards)}';
      if (!solved) selected.clear();
    });
  }

  void hint() => setState(() {
    hinted = true;
    final card = exercise.solution[completePair ? 2 : 0];
    feedback = 'Look for ${card.description}.';
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Training')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Practice at your own pace. Training never enters the leaderboard.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Find the third card'),
              value: completePair,
              onChanged: (value) {
                completePair = value;
                next();
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: differences,
              decoration: const InputDecoration(
                labelText: 'Features that must be all different',
              ),
              items: [
                for (var i = 1; i <= 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      i == 4
                          ? '4 — everything different'
                          : '$i different, ${4 - i} same',
                    ),
                  ),
              ],
              onChanged: (value) {
                differences = value!;
                next();
              },
            ),
            if (completePair)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  height: 144,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final card in exercise.solution.take(2))
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: CardView(card: card),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(feedback, textAlign: TextAlign.center),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 500 ? 6 : 3,
                childAspectRatio: 2 / 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final card in exercise.board)
                    CardView(
                      card: card,
                      selected:
                          selected.contains(card.id) ||
                          (hinted &&
                              card.id ==
                                  exercise.solution[completePair ? 2 : 0].id),
                      onTap: () => pick(card),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                TextButton(
                  onPressed: solved ? null : hint,
                  child: const Text('Hint'),
                ),
                FilledButton(
                  onPressed: next,
                  child: Text(solved ? 'Next exercise' : 'Skip'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('$completed completed', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
