import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'connection.dart';

/// Covers the whole app while the server cannot be reached, and lifts by
/// itself once it can. What lies beneath (an open chat, a half-typed
/// message) is kept exactly as it was.
class OfflineScreen extends StatefulWidget {
  const OfflineScreen(this.connection, {super.key});
  final ConnectionMonitor connection;

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool checking = false;

  Future<void> retry() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      await widget.connection.check();
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apple = isCupertino(context);
    return Material(
      key: const ValueKey('offline-screen'),
      color: Colors.white,
      child: SafeArea(
        child: Semantics(
          liveRegion: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: T.greenWash,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      apple
                          ? CupertinoIcons.wifi_slash
                          : Icons.wifi_off_rounded,
                      size: 40,
                      color: T.green,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'You’re offline',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Check your Wi-Fi or mobile data. Telvox Chat '
                    'reconnects by itself, and nothing you were doing is lost.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4, color: T.muted),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 44,
                    child: apple
                        ? CupertinoButton.filled(
                            key: const ValueKey('offline-retry'),
                            onPressed: checking ? null : retry,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(checking ? 'Checking…' : 'Try again'),
                          )
                        : FilledButton(
                            key: const ValueKey('offline-retry'),
                            onPressed: checking ? null : retry,
                            child: Text(checking ? 'Checking…' : 'Try again'),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: T.muted,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Waiting for network…',
                        style: TextStyle(fontSize: 13, color: T.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
