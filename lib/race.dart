import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'card_view.dart';
import 'data.dart';
import 'game.dart';

class RaceScreen extends StatefulWidget {
  const RaceScreen({super.key, required this.player, this.room});
  final PlayerData player;
  final String? room;
  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  String? room;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  Timer? countdown;
  Map<String, dynamic>? state;
  final selected = <int>{};
  bool connecting = false;
  bool connected = false;
  bool waiting = false;
  bool leaving = false;
  String feedback = '';
  int clockOffset = 0;
  String? recordedSeed;
  final code = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.room != null) {
      room = widget.room;
      connect();
    }
    countdown = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && state?['startAt'] != null && state?['ended'] != true) {
        setState(() {});
      }
    });
  }

  Future<void> create() async {
    if (connecting) return;
    setState(() {
      connecting = true;
      feedback = '';
    });
    try {
      final result = await OnlineApi().request('/rooms', body: {});
      if (!mounted) return;
      room = result['room'] as String;
      await connect();
    } catch (error) {
      if (mounted) {
        setState(() {
          feedback = 'Could not create room: $error';
          connecting = false;
        });
      }
    }
  }

  Future<void> connect() async {
    if (!mounted) return;
    setState(() {
      connecting = true;
      connected = false;
      feedback = '';
    });
    await subscription?.cancel();
    await channel?.sink.close();
    try {
      final apiUri = OnlineApi().uri('/rooms/$room', {
        'player': widget.player.player,
        'name': widget.player.nickname,
      });
      final next = WebSocketChannel.connect(
        apiUri.replace(scheme: apiUri.scheme == 'https' ? 'wss' : 'ws'),
      );
      channel = next;
      // Attach listeners immediately, including errors emitted before ready.
      subscription = next.stream.listen(
        (event) {
          if (!mounted) return;
          final message = jsonDecode(event as String) as Map<String, dynamic>;
          setState(() {
            if (message['type'] == 'state') {
              final seed = message['seed'] as String?;
              if (seed != null && seed != recordedSeed) {
                recordedSeed = seed;
                widget.player.claimSeed(seed).catchError((_) => false);
              }
              final oldProgress = ownProgress;
              state = message;
              clockOffset =
                  (message['now'] as int) -
                  DateTime.now().millisecondsSinceEpoch;
              if (oldProgress != ownProgress ||
                  waiting ||
                  message['ended'] == true) {
                selected.clear();
              }
              waiting = false;
            } else if (message['type'] == 'error') {
              feedback = message['message'] as String;
              selected.clear();
              waiting = false;
            }
          });
        },
        onError: (Object error) => disconnected(),
        onDone: disconnected,
      );
      await next.ready.timeout(const Duration(seconds: 12));
      if (!mounted) {
        await next.sink.close();
        return;
      }
      setState(() {
        connected = true;
        connecting = false;
      });
    } catch (_) {
      disconnected();
    }
  }

  void disconnected() {
    if (!mounted || leaving) return;
    setState(() {
      connected = false;
      connecting = false;
      waiting = false;
      feedback = 'Connection lost, or the room is full or expired. Reconnect to resume your place.';
    });
  }

  List<dynamic> get players => state?['players'] as List<dynamic>? ?? [];
  int get you => state?['you'] as int? ?? -1;
  int get ownProgress =>
      you >= 0 && you < players.length ? players[you]['progress'] as int : 0;
  void send(Map<String, dynamic> message) {
    if (connected) channel?.sink.add(jsonEncode(message));
  }

  void pick(int id) {
    if (!connected || waiting || state?['ended'] == true) return;
    setState(() {
      if (selected.remove(id)) return;
      selected.add(id);
      if (selected.length == 3) {
        waiting = true;
        feedback = '';
        send({
          'type': 'pick',
          'round': ownProgress,
          'cards': selected.toList(),
        });
      }
    });
  }

  Future<void> leave() async {
    leaving = true;
    send({'type': 'leave'});
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    leaving = true;
    countdown?.cancel();
    subscription?.cancel();
    channel?.sink.close();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startAt = state?['startAt'] as int?;
    final remaining = startAt == null
        ? 0
        : ((startAt - DateTime.now().millisecondsSinceEpoch - clockOffset) /
                  1000)
              .ceil();
    final board = state?['board'] as List<dynamic>? ?? [];
    final ended = state?['ended'] == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('1 vs 1'),
          leading: IconButton(
            onPressed: leave,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Leave race',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Same five boards. First to five wins. Leaving a started race forfeits it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (room == null) ...[
                  FilledButton(
                    onPressed: connecting ? null : create,
                    child: const Text('Create room'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Room code or shared link',
                    ),
                  ),
                  TextButton(
                    onPressed: connecting
                        ? null
                        : () {
                            final raw = code.text.trim();
                            final value =
                                (Uri.tryParse(raw)?.queryParameters['room'] ??
                                        raw)
                                    .toUpperCase();
                            if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(value)) {
                              setState(
                                () => feedback =
                                    'Enter a six-character room code.',
                              );
                              return;
                            }
                            room = value;
                            connect();
                          },
                    child: const Text('Join room'),
                  ),
                ] else ...[
                  Text(
                    'Room $room',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: shareLink('room', room!)),
                      );
                      if (mounted) {
                        setState(() => feedback = 'Invite link copied.');
                      }
                    },
                    child: const Text('Copy invite link'),
                  ),
                  for (var i = 0; i < players.length; i++)
                    ListTile(
                      title: Text(
                        '${players[i]['name']}${i == you ? ' (you)' : ''}',
                      ),
                      subtitle: Text(
                        players[i]['connected'] != true
                            ? 'Disconnected'
                            : players[i]['ready'] == true
                            ? 'Ready'
                            : 'Getting ready',
                      ),
                      trailing: Text('${players[i]['progress']} / 5'),
                    ),
                  if (connected && !ended && startAt == null)
                    FilledButton(
                      onPressed: you < 0 || players[you]['ready'] == true
                          ? null
                          : () => send({'type': 'ready'}),
                      child: Text(
                        players.length < 2
                            ? 'Ready — waiting for friend'
                            : 'Ready',
                      ),
                    ),
                  if (remaining > 0 && !ended)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '$remaining',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 80, color: accent),
                      ),
                    ),
                  if (ended) ...[
                    Semantics(
                      key: const ValueKey('race-result'),
                      container: true,
                      liveRegion: true,
                      label: state?['winner'] == you
                          ? 'You win!'
                          : 'Your friend wins!',
                      excludeSemantics: true,
                      child: Text(
                        state?['winner'] == you
                            ? 'You win!'
                            : 'Your friend wins!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Text(
                      'Race results are separate from solo high scores.',
                      textAlign: TextAlign.center,
                    ),
                    FilledButton(
                      onPressed: () async {
                        await subscription?.cancel();
                        await channel?.sink.close();
                        setState(() {
                          state = null;
                          room = null;
                          connected = false;
                        });
                      },
                      child: const Text('Another race'),
                    ),
                  ],
                  if (!connected && !connecting)
                    TextButton(
                      onPressed: connect,
                      child: const Text('Reconnect'),
                    ),
                  if (board.isNotEmpty && !ended && remaining <= 0)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 500 ? 4 : 3;
                        final rows = (board.length / columns).ceil();
                        final availableHeight =
                            (MediaQuery.sizeOf(context).height - 350).clamp(
                              260.0,
                              650.0,
                            );
                        final cardHeight =
                            (availableHeight - (rows - 1) * 10) / rows;
                        final width =
                            (columns * cardHeight * 2 / 3 + (columns - 1) * 10)
                                .clamp(0.0, constraints.maxWidth);
                        return Center(
                          child: SizedBox(
                            width: width,
                            child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: columns,
                              childAspectRatio: 2 / 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              children: [
                                for (final id in board)
                                  CardView(
                                    card: SetCard(id as int),
                                    selected: selected.contains(id),
                                    onTap: () => pick(id),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
                if (connecting)
                  const Center(child: CircularProgressIndicator()),
                if (feedback.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(feedback, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
