import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'devices.dart';
import 'game.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.player, this.seed});
  final PlayerData? player;
  final String? seed;
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late bool unique = widget.player?.unique ?? true;
  late String? seed = widget.seed;
  late Future<List<Score>> scores = load();
  Future<List<Score>> load() => OnlineApi().scores(unique: unique, seed: seed);
  void refresh() => setState(() => scores = load());

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
    refresh();
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
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(seed ?? 'Current seeds · fastest 100 runs'),
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
              child: FutureBuilder<List<Score>>(
                future: scores,
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
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No scores yet. Set the first time!'),
                    );
                  }
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        leading: Text('${index + 1}'),
                        title: Text(row.name),
                        subtitle: Text(
                          '${row.seed} · ${row.mistakes} mistakes',
                        ),
                        trailing: Text(
                          formatTime(Duration(milliseconds: row.milliseconds)),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: shareLink('seed', row.seed)),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Seed link copied. Replays are practice.',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
