import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.player});
  final PlayerData player;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final ownCode = TextEditingController();
  final otherCode = TextEditingController();
  bool loading = true;
  bool merging = false;
  int devices = 1;
  String message = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await OnlineApi().request(
        '/players/code',
        body: {'player': widget.player.player},
      );
      if (!mounted) return;
      final code = result['code'] as String;
      ownCode.text = List.generate(
        6,
        (i) => code.substring(i * 8, (i + 1) * 8),
      ).join('-');
      setState(() {
        devices = result['devices'] as int;
        message = '';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not connect. Go online and tap Refresh to load your device code.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> merge() async {
    final target = normalizeDeviceCode(otherCode.text);
    if (target == null) {
      setState(
        () =>
            message = 'Paste the complete device code from your other device.',
      );
      return;
    }
    setState(() {
      merging = true;
      message = '';
    });
    try {
      final result = await OnlineApi().request(
        '/players/merge',
        body: {'player': widget.player.player, 'target': target},
      );
      if (!mounted) return;
      setState(() {
        devices = result['devices'] as int;
        message = target == widget.player.player
            ? 'That is this device’s code. Paste the code from your other device.'
            : 'Devices linked. Your existing and future scores now count as one player.';
      });
      if (target != widget.player.player) otherCode.clear();
    } catch (error) {
      if (mounted) {
        setState(
          () => message =
              'Could not link devices. ${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => merging = false);
    }
  }

  Future<void> copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: ownCode.text));
      if (mounted) {
        setState(
          () => message = 'Device code copied. Paste it on your other device.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not copy. Select and copy the code above.',
        );
      }
    }
  }

  @override
  void dispose() {
    ownCode.dispose();
    otherCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Link devices'),
      actions: [
        IconButton(
          onPressed: loading || merging ? null : load,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'Use one leaderboard identity on all your devices.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'On one device, copy its code. On the other, open Link devices and paste that code below. No login needed.',
            ),
            if (devices > 1)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '$devices devices linked',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 24),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (ownCode.text.isNotEmpty) ...[
              TextField(
                controller: ownCode,
                readOnly: true,
                minLines: 2,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'This device’s code',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy device code'),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: otherCode,
              enabled: !merging,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Code from your other device',
                hintText: 'Paste device code',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: loading || merging ? null : merge,
              child: Text(
                merging ? 'Linking…' : 'Merge leaderboard identities',
              ),
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty)
              Semantics(liveRegion: true, child: Text(message)),
            const SizedBox(height: 20),
            const Text(
              'Existing scores are combined. “Only each player’s best” treats linked devices as one person. If both devices submitted the same seed, the first submission counts.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Personal bests, seed-attempt history and training history stay on each device. Only submit a seed the first time you ever play it, across all devices.',
            ),
          ],
        ),
      ),
    ),
  );
}
