import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_view.dart';
import 'game.dart';

/// Fits every card inside the available viewport, choosing the arrangement
/// with the largest portrait cards. Clock ticks must not rebuild this widget.
class CardBoard extends StatelessWidget {
  const CardBoard({
    super.key,
    required this.cards,
    this.selected = const {},
    this.onTap,
    this.columns,
    this.keyPrefix = 'card',
  });

  final List<int> cards;
  final Set<int> selected;
  final ValueChanged<SetCard>? onTap;
  final int? columns;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (cards.isEmpty) return const SizedBox.shrink();
      const gap = 8.0;
      double widthFor(int count) {
        final rows = (cards.length / count).ceil();
        return math.max(
          0.0,
          math.min(
            (constraints.maxWidth - (count - 1) * gap) / count,
            (constraints.maxHeight - (rows - 1) * gap) / rows * 2 / 3,
          ),
        );
      }

      final candidates = columns != null
          ? [columns!]
          : cards.length <= 6
          ? [2, 3, 6]
          : [3, 4, 6];
      var count = candidates.first;
      for (final candidate in candidates.skip(1)) {
        if (widthFor(candidate) > widthFor(count)) count = candidate;
      }
      final width = widthFor(count);
      final rows = (cards.length / count).ceil();
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: count * width + (count - 1) * gap,
          height: rows * width * 3 / 2 + (rows - 1) * gap,
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
                  key: ValueKey('$keyPrefix-$id'),
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
