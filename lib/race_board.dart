// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';

import 'card_board.dart';
import 'card_view.dart';

class RaceBoard extends StatelessWidget {
  const RaceBoard({
    super.key,
    required this.board,
    required this.players,
    required this.you,
    required this.selected,
    required this.onPick,
    required this.countdown,
    required this.feedback,
    this.onReconnect,
  });

  final List<int> board;
  final List<dynamic> players;
  final int you;
  final Set<int> selected;
  final ValueChanged<int> onPick;
  final int countdown;
  final String feedback;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < players.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${players[i]['name']}${i == you ? ' (you)' : ''}  ${players[i]['progress']} / 5',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: countdown > 0
                ? Center(
                    child: Text(
                      '$countdown',
                      style: const TextStyle(fontSize: 80, color: accent),
                    ),
                  )
                : CardBoard(
                    cards: board,
                    selected: selected,
                    onTap: (card) => onPick(card.id),
                  ),
          ),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                feedback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (onReconnect != null)
            TextButton(onPressed: onReconnect, child: const Text('Reconnect')),
        ],
      ),
    ),
  );
}
