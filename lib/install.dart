import 'package:flutter/material.dart';

import 'install_stub.dart'
    if (dart.library.js_interop) 'install_web.dart'
    as platform;

Future<void> showInstall(BuildContext context) async {
  if (await platform.promptInstall()) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Install Trio Sprint'),
      content: const Text(
        'iPhone / iPad\nOpen this site in Safari, tap Share → Add to Home Screen. Enable “Open as Web App” if shown.\n\nAndroid\nOpen this site in Chrome, then choose ⋮ → Install app or Add to Home screen.\n\nSolo runs and training work offline after the app has finished downloading. High scores and 1 vs 1 need an internet connection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
