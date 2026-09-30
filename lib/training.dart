import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'card_view.dart';
import 'data.dart';
import 'game.dart';
import 'practice.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, this.player});
  final PlayerData? player;
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int differences = 4;
  bool completePair = false;
  bool reviewing = false;
  PracticeBoard? exercise;
  List<PracticeBoard> reviewQueue = [];
  int reviewIndex = 0;
  final selected = <int>{};
  final clock = BoardClock();
  Timer? advance;
  String feedback = '';
  bool solved = false;
  bool hinted = false;
  bool recorded = false;
  bool storageFailed = false;
  int mistakes = 0;
  int completed = 0;

  String get prompt => exercise!.anchors.isNotEmpty
      ? 'Choose the missing third card.'
      : exercise!.differences == null
      ? 'Find any set on this board.'
      : exercise!.differences == 4
      ? 'Find a set with everything different.'
      : 'Find a set with ${exercise!.differences} different features.';

  void start({bool review = false}) {
    reviewing = review;
    reviewQueue = review ? widget.player!.slowBoards : [];
    reviewIndex = 0;
    completed = 0;
    next();
  }

  void next() {
    advance?.cancel();
    setState(() {
      if (reviewing) {
        exercise = reviewQueue[reviewIndex++ % reviewQueue.length];
      } else {
        final generated = TrainingExercise(
          differences: differences,
          completePair: completePair,
        );
        exercise = PracticeBoard(
          cards: generated.board.map((c) => c.id).toList(),
          anchors: completePair
              ? generated.solution.take(2).map((c) => c.id).toList()
              : const [],
          differences: differences,
        );
      }
      selected.clear();
      solved = false;
      hinted = false;
      recorded = false;
      mistakes = 0;
      feedback = prompt;
      clock.start();
    });
  }

  void remember({bool skipped = false}) {
    if (recorded || exercise == null) return;
    recorded = true;
    clock.stop();
    widget.player
        ?.recordPractice(
          exercise!.result(clock.milliseconds, mistakes, hinted || skipped),
        )
        .catchError((Object error) {
          if (mounted) setState(() => storageFailed = true);
        });
  }

  void quit() {
    advance?.cancel();
    // Preserve a board that was proving difficult when the player quit.
    if (clock.milliseconds >= 10000 || mistakes > 0 || hinted) remember();
    clock.stop();
    setState(() => exercise = null);
  }

  void pick(SetCard card) {
    if (solved) return;
    setState(() {
      if (selected.remove(card.id)) return;
      selected.add(card.id);
      final pair = exercise!.anchors.isNotEmpty;
      if (!pair && selected.length < 3) return;
      final cards = pair
          ? [...exercise!.anchors.map(SetCard.new), card]
          : selected.map(SetCard.new).toList();
      solved = exercise!.accepts(cards);
      if (solved) {
        completed++;
        remember();
        feedback = 'Yes! Next board…';
        advance = Timer(const Duration(milliseconds: 650), () {
          if (mounted) next();
        });
      } else {
        mistakes++;
        feedback = isSet(cards)
            ? 'Valid set — aim for ${exercise!.differences} different features.'
            : 'Not a set. Try again.';
        selected.clear();
      }
    });
  }

  void hint() => setState(() {
    hinted = true;
    final solution = exercise!.solution!;
    final card = solution[exercise!.anchors.isNotEmpty ? 2 : 0];
    feedback = 'Look for ${card.description}.';
  });

  @override
  void dispose() {
    advance?.cancel();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: exercise == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) quit();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          reviewing && exercise != null ? 'Cards I was slow on' : 'Training',
        ),
        leading: exercise == null
            ? null
            : IconButton(
                onPressed: quit,
                tooltip: 'Quit training',
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          if (exercise != null)
            TextButton(onPressed: quit, child: const Text('Quit')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: exercise == null ? setup() : playing(),
          ),
        ),
      ),
    ),
  );

  Widget setup() {
    final saved = widget.player?.slowBoards.length ?? 0;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          'What would you like to work on?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose a focus, then keep playing new boards until you quit. No timer to beat, no high scores.',
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<int>(
          initialValue: differences,
          isExpanded: true,
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
          onChanged: (value) => setState(() => differences = value!),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Find the third card'),
          subtitle: const Text(
            'Start with two cards instead of searching a full board.',
          ),
          value: completePair,
          onChanged: (value) => setState(() => completePair = value),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: start, child: const Text('Start training')),
        const SizedBox(height: 32),
        Text(
          'Cards I was slow on',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Revisit your 20 hardest boards from the last 100 saved boards, including sprints, races and training. Slower solves, mistakes, hints and skips move a board up the list. Your latest attempt updates its place.',
        ),
        const SizedBox(height: 8),
        Text(
          widget.player == null || storageFailed
              ? 'Device storage is unavailable; new boards cannot be remembered.'
              : saved == 0
              ? 'Play a few boards first. They will be remembered only on this device.'
              : '$saved boards ready to revisit. Saved only on this device.',
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: saved == 0 ? null : () => start(review: true),
          child: const Text('Practice these cards'),
        ),
      ],
    );
  }

  Widget playing() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Column(
      children: [
        SizedBox(
          height: 52,
          child: Center(
            child: Semantics(
              liveRegion: true,
              child: Text(feedback, textAlign: TextAlign.center),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final choices = FittedCardBoard(
                cards: exercise!.cards,
                selected: {
                  ...selected,
                  if (hinted)
                    exercise!.solution![exercise!.anchors.isEmpty ? 0 : 2].id,
                },
                onTap: pick,
              );
              if (exercise!.anchors.isEmpty) return choices;
              final anchors = FittedCardBoard(
                cards: exercise!.anchors,
                columns: 2,
              );
              if (constraints.maxWidth > constraints.maxHeight * 1.4) {
                return Row(
                  children: [
                    Expanded(flex: 2, child: anchors),
                    const VerticalDivider(width: 24),
                    Expanded(flex: 3, child: choices),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: anchors),
                  const Divider(height: 20),
                  Expanded(flex: 2, child: choices),
                ],
              );
            },
          ),
        ),
        SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$completed completed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: solved ? null : hint,
                child: const Text('Hint'),
              ),
              TextButton(
                onPressed: solved
                    ? null
                    : () {
                        remember(skipped: true);
                        next();
                      },
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The same portrait cards and spacing as the sprint, sized to the whole board.
class FittedCardBoard extends StatelessWidget {
  const FittedCardBoard({
    super.key,
    required this.cards,
    this.selected = const {},
    this.onTap,
    this.columns,
  });
  final List<int> cards;
  final Set<int> selected;
  final ValueChanged<SetCard>? onTap;
  final int? columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count =
          columns ??
          (constraints.maxWidth > 500
              ? (constraints.maxHeight < 330 ? 6 : 4)
              : 3);
      final rows = (cards.length / count).ceil();
      const gap = 10.0;
      final width = max(
        0.0,
        min(
          (constraints.maxWidth - (count - 1) * gap) / count,
          min(140.0, (constraints.maxHeight - (rows - 1) * gap) / rows * 2 / 3),
        ),
      );
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: count * width + (count - 1) * gap,
          child: GridView.count(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: count,
            childAspectRatio: 2 / 3,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            children: [
              for (final id in cards)
                CardView(
                  key: ValueKey('training-card-$id'),
                  card: SetCard(id),
                  selected: selected.contains(id),
                  onTap: onTap == null ? null : () => onTap!(SetCard(id)),
                ),
            ],
          ),
        ),
      );
    },
  );
}
