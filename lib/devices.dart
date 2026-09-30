import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'data.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.player, this.initialCode});
  final PlayerData player;
  final String? initialCode;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final otherCode = TextEditingController(text: widget.initialCode);
  String ownCode = '';
  bool loading = true;
  bool merging = false;
  bool linked = false;
  int devices = 1;
  String message = '';
  Timer? refreshTimer;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refreshCount(),
    );
  }

  Future<void> refreshCount() async {
    if (loading || merging || refreshing || ownCode.isEmpty) return;
    refreshing = true;
    try {
      final result = await OnlineApi().request(
        '/players/code',
        body: {'player': widget.player.player},
      );
      final count = result['devices'] as int;
      if (mounted && count != devices) {
        setState(() {
          devices = count;
          message = 'Devices linked. Your scores now count as one player.';
        });
      }
    } catch (_) {
      // A brief loss of connectivity should not interrupt entering a code.
    } finally {
      refreshing = false;
    }
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await OnlineApi().request(
        '/players/pairing',
        body: {'player': widget.player.player},
      );
      if (!mounted) return;
      setState(() {
        ownCode = result['code'] as String;
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
        () => message = 'Enter the six-character code from your other device.',
      );
      return;
    }
    if (target == ownCode || target == widget.player.player) {
      setState(
        () => message = 'That is this device’s code. Enter the code from your other device.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
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
        linked = true;
        message = '';
      });
      otherCode.clear();
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

  Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        setState(() => message = 'Copied. Open it on your other device.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not copy. You can type the six-character code instead.',
        );
      }
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    otherCode.dispose();
    super.dispose();
  }

  Widget enterCode() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: otherCode,
        enabled: !merging,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (!loading && !merging) merge();
        },
        decoration: const InputDecoration(
          labelText: 'Code from your other device',
          hintText: 'ABC 234',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: loading || merging ? null : merge,
        child: Text(merging ? 'Linking…' : 'Link this device'),
      ),
    ],
  );

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
            Text(
              linked
                  ? 'Devices linked'
                  : widget.initialCode == null
                  ? 'One player, all your devices.'
                  : 'Link this device to your other one?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              linked
                  ? 'Your existing and future leaderboard scores now count as one player.'
                  : widget.initialCode == null
                  ? 'Scan the QR code with your other device, or enter this short code in Link devices there.'
                  : 'The code is filled in. Tap Link this device to combine your leaderboard scores.',
            ),
            if (devices > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '$devices devices linked',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 20),
            if (linked)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              )
            else if (widget.initialCode != null)
              enterCode(),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (ownCode.isNotEmpty) ...[
              if (widget.initialCode != null) const SizedBox(height: 20),
              const Text('This device’s code', textAlign: TextAlign.center),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText(
                    '${ownCode.substring(0, 3)} ${ownCode.substring(3)}',
                    key: const ValueKey('pairing-code'),
                    style: const TextStyle(
                      fontSize: 32,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => copy(ownCode),
                    tooltip: 'Copy device code',
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              Center(
                child: QrImageView(
                  key: const ValueKey('pairing-qr'),
                  data: shareLink('link', ownCode),
                  size: 200,
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.white,
                  semanticsLabel: 'Scan to link this device',
                ),
              ),
              TextButton.icon(
                onPressed: () => copy(shareLink('link', ownCode)),
                icon: const Icon(Icons.link),
                label: const Text('Copy pairing link'),
              ),
            ],
            if (widget.initialCode == null && !linked) ...[
              const SizedBox(height: 12),
              enterCode(),
            ],
            const SizedBox(height: 20),
            const Text(
              'Existing and future leaderboard scores count as one player. If both devices submitted the same seed, the first submission counts.',
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
