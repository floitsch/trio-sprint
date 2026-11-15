// Copyright (C) 2026 Florian Loitsch.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';

enum AbandonReason { interrupted, tooSlow }

Future<AbandonReason?> confirmAbandonRun(
  BuildContext context, {
  bool keepSlowBoards = false,
}) => showDialog<AbandonReason>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(keepSlowBoards ? 'Why stop this run?' : 'Abandon this run?'),
    content: Text(
      keepSlowBoards
          ? 'Interrupted boards are excluded from difficult-card training. Too slow keeps this board for training, as Restart does.'
          : 'This incomplete run will not count towards your high scores.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep playing'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, AbandonReason.interrupted),
        child: Text(keepSlowBoards ? 'Interrupted' : 'Abandon'),
      ),
      if (keepSlowBoards)
        TextButton(
          onPressed: () => Navigator.pop(context, AbandonReason.tooSlow),
          child: const Text('Too slow'),
        ),
    ],
  ),
);

Future<String?> enterRunSeed(
  BuildContext context, {
  String initial = '',
  String hint = 's2-1234abcd or a shared link',
  String title = 'Run a seed',
  String action = 'Run seed',
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _SeedDialog(initial: initial, hint: hint, title: title, action: action),
);

class _SeedDialog extends StatefulWidget {
  const _SeedDialog({
    required this.initial,
    required this.hint,
    required this.title,
    required this.action,
  });
  final String initial;
  final String hint;
  final String title;
  final String action;

  @override
  State<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends State<_SeedDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

Future<void> copyRunSeedLink(
  BuildContext context,
  String seed, {
  String parameter = 'seed',
}) async {
  await Clipboard.setData(ClipboardData(text: shareLink(parameter, seed)));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Seed link copied.')));
  }
}

class RunScoreList<T> extends StatelessWidget {
  const RunScoreList({
    super.key,
    required this.future,
    required this.buildRow,
    this.emptyText = 'No scores yet. Be the first!',
  });
  final Future<List<T>> future;
  final Widget Function(T row, int index) buildRow;
  final String emptyText;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load scores. ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data!;
      if (rows.isEmpty) return Center(child: Text(emptyText));
      return ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) => buildRow(rows[index], index),
      );
    },
  );
}
