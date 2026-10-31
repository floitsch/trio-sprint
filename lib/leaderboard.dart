import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'devices.dart';
import 'game.dart';

/// Asks for a nickname and stores it. Returns false if cancelled.
Future<bool> editNickname(BuildContext context, PlayerData player) async {
  final controller = TextEditingController(text: player.nickname);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your nickname'),
      content: TextField(
        controller: controller,
        maxLength: 24,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'What should your friends see?',
          helperText: 'Shown on future scores and your total solved sets.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name == null) return false;
  await player.setNickname(name);
  return true;
}

/// The leaderboard pops with a seed when the player chooses to run it.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    required this.player,
    this.seed,
    this.mode = RunMode.sprint,
    this.api,
  });
  final PlayerData? player;
  final String? seed;
  final OnlineApi? api;

  /// The mode to show without a seed. A seed implies its own mode.
  final RunMode mode;
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late bool unique = widget.player?.unique ?? true;
  late String? seed = widget.seed;
  late RunMode mode = seed == null ? widget.mode : RunMode.of(seed!);
  late final OnlineApi api = widget.api ?? OnlineApi();
  bool showTotalSets = false;
  Future<List<SetTotalScore>>? totals;
  Future<List<Score>>? scores;
  Future<List<Score>> load() =>
      api.scores(unique: unique, mode: mode, seed: seed);
  void refresh() => setState(() {
    if (showTotalSets) {
      totals = null;
    } else {
      scores = null;
    }
  });

  Widget scoreList<T>(
    Future<List<T>> future,
    Widget Function(T row, int index) buildRow, {
    required String emptyText,
  }) => FutureBuilder<List<T>>(
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

  Future<void> chooseSeed() async {
    final controller = TextEditingController(text: seed ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scores for a seed'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 's2-1234abcd or a shared link',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Show'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final parsed = normalizeSeed(result);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a seed such as s2-1234abcd.')),
      );
      return;
    }
    seed = parsed;
    mode = RunMode.of(parsed);
    refresh();
  }

  Future<void> seedActions(String rowSeed) async {
    final played = await widget.player
        ?.hasAttempted(rowSeed)
        .catchError((Object _) => false);
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text('Play $rowSeed'),
              subtitle: Text(
                played == true
                    ? 'You already played this seed here. This run is practice.'
                    : 'Your first run of a seed can enter the high scores.',
              ),
              onTap: () => Navigator.pop(context, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy seed link'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'play') {
      Navigator.pop(context, rowSeed);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: shareLink('seed', rowSeed)));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Seed link copied.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('High scores'),
      actions: [
        if (widget.player != null)
          IconButton(
            tooltip: 'Link devices',
            icon: const Icon(Icons.devices),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevicesScreen(player: widget.player!),
                ),
              );
              if (mounted) refresh();
            },
          ),
        IconButton(
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh scores',
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            if (widget.player case final player?)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  player.nickname.isEmpty
                      ? 'No name yet'
                      : 'Playing as ${player.nickname}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    if (await editNickname(context, player) && mounted) {
                      refresh();
                    }
                  },
                  child: Text(player.nickname.isEmpty ? 'Set name' : 'Change'),
                ),
              ),
            if (!showTotalSets)
              SwitchListTile(
                title: const Text('Only each player’s best'),
                subtitle: const Text(
                  'Hide additional runs from the same player, including linked devices.',
                ),
                value: unique,
                onChanged: (value) {
                  unique = value;
                  widget.player?.setUnique(value);
                  refresh();
                },
              ),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final mode in RunMode.values)
                  ButtonSegment(
                    value: mode.prefix,
                    label: Text(mode.shortLabel),
                  ),
                const ButtonSegment(
                  value: 'total-sets',
                  label: Text('Total sets'),
                ),
              ],
              selected: {showTotalSets ? 'total-sets' : mode.prefix},
              onSelectionChanged: (selection) {
                showTotalSets = selection.single == 'total-sets';
                if (!showTotalSets) {
                  mode = RunMode.values.firstWhere(
                    (m) => m.prefix == selection.single,
                  );
                  if (seed != null && RunMode.of(seed!) != mode) seed = null;
                }
                refresh();
              },
            ),
            if (showTotalSets)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Total solved sets · top 100 players\n'
                  'Counts uploaded solves from all modes, including Training, hints and replays. '
                  'Solves in unfinished runs count. Linked devices share one total. '
                  'Set a nickname to appear.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    seed ??
                        (mode.timed
                            ? 'Current seeds · most sets, top 100 runs'
                            : 'Current seeds · fastest 100 runs'),
                  ),
                  TextButton(
                    onPressed: chooseSeed,
                    child: const Text('Choose seed'),
                  ),
                  if (seed != null)
                    TextButton(
                      onPressed: () {
                        seed = null;
                        refresh();
                      },
                      child: const Text('All seeds'),
                    ),
                ],
              ),
            Expanded(
              child: showTotalSets
                  ? scoreList<SetTotalScore>(
                      totals ??= api.totalSets(),
                      (row, index) => ListTile(
                        leading: Text('${index + 1}'),
                        title: Text(row.name),
                        trailing: Text(
                          '${row.sets} ${row.sets == 1 ? 'set' : 'sets'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      emptyText:
                          'No solved sets yet. Solve a set and sync to join!',
                    )
                  : scoreList<Score>(scores ??= load(), (row, index) {
                      final time = formatTime(
                        Duration(milliseconds: row.milliseconds),
                      );
                      final timed = RunMode.of(row.seed).timed;
                      return ListTile(
                        leading: Text('${index + 1}'),
                        title: Text(row.name),
                        subtitle: Text(
                          timed
                              ? '${row.seed} · last set at $time · ${row.mistakes} mistakes'
                              : '${row.seed} · ${row.mistakes} mistakes',
                        ),
                        trailing: Text(
                          timed
                              ? '${row.sets} ${row.sets == 1 ? 'set' : 'sets'}'
                              : time,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        onTap: () => seedActions(row.seed),
                      );
                    }, emptyText: 'No scores yet. Set the first time!'),
            ),
          ],
        ),
      ),
    ),
  );
}
