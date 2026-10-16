// Copyright (C) 2026 Toit contributors.
import 'package:flutter/material.dart';

import 'leaderboard.dart';
import 'sync.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.sync});
  final SyncService sync;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offline & sync')),
    body: ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final player = sync.player;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: Icon(
                sync.offlineReady ? Icons.offline_pin : Icons.downloading,
              ),
              title: Text(
                sync.offlineReady
                    ? 'Ready for offline play'
                    : 'Offline download not ready yet',
              ),
              subtitle: Text(
                sync.offlineReady
                    ? 'Solo runs, training and statistics work in airplane mode.'
                    : 'Keep the app open online until it has downloaded. Then check again before travelling.',
              ),
            ),
            const Text(
              'Every board attempt and eligible score is saved on this device first. Uploads retry when you return to the app and every 30 seconds while it is open. Multiplayer and live leaderboards need a connection.',
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Scores waiting to upload'),
              trailing: Text('${player.pendingScores}'),
            ),
            ListTile(
              title: const Text('Board attempts waiting to upload'),
              trailing: Text('${player.pendingAttempts}'),
            ),
            if (player.nickname.isEmpty) ...[
              const Text(
                'Add a nickname to publish saved first-attempt scores. Your board history can sync without one.',
              ),
              TextButton(
                onPressed: () async {
                  if (await editNickname(context, player)) await sync.sync();
                },
                child: const Text('Set nickname'),
              ),
            ],
            if (!sync.api.configured)
              const Text(
                'This build has no sync server configured. Everything stays saved locally.',
              ),
            if (sync.probablyOffline)
              const Text(
                'You may be offline. Everything is saved on this device and will sync automatically when you reconnect.',
              )
            else if (sync.error != null)
              const Text('Uploads are waiting. Retrying automatically.'),
            if (player.pendingScores == 0 && player.pendingAttempts == 0)
              const Text('Nothing waiting to upload.'),
            if (sync.busy) const Text('Syncing…'),
            for (final score in player.savedScores.where(
              (s) => s['status'] == 'rejected',
            ))
              ListTile(
                title: Text('Score not accepted: ${score['seed']}'),
                subtitle: Text(
                  '${score['error']}\nThe original score is still saved on this device.',
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Board history is uploaded separately from public high scores. Device linking still combines leaderboard identity; this screen does not download another device’s statistics.',
            ),
          ],
        );
      },
    ),
  );
}
