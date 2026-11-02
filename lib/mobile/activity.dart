import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';

/// When the customer was last verifiably active, from WhatsApp's own records:
/// a message they sent, or a read receipt for one we sent them. WhatsApp's
/// Business API reports no presence, so the app never claims "online" — only
/// activity it saw, and how long ago.
DateTime? customerActiveAt(Iterable<Json> messages) {
  DateTime? latest;
  void see(Object? raw) {
    final at = MobileClock.instant(raw);
    if (at != null && (latest == null || at.isAfter(latest!))) latest = at;
  }

  for (final m in messages) {
    if (m.isEmpty) continue;
    // type 2: the customer's message; type 1: ours, active when they read it.
    if (number(m['type']) == 2) {
      see(m['created_at']);
    } else if (number(m['type']) == 1) {
      see(m['read_at']);
      see(m['played_at']);
    }
  }
  return latest;
}

/// How recent counts as "active now" (the green dot).
const activeWindow = Duration(minutes: 5);

/// "Active now", "Active 12 min ago", or nothing past an hour.
String? activityLabel(Duration? ago) {
  if (ago == null || ago > const Duration(hours: 1)) return null;
  if (ago < const Duration(minutes: 1)) return 'Active now';
  return 'Active ${ago.inMinutes} min ago';
}

bool activeNow(Duration? ago) => ago != null && ago <= activeWindow;

/// Rebuilds [builder] with how long ago [at] was, and keeps it current: the
/// dot goes out and the label ages on their own, with no list reload.
class RecentActivity extends StatefulWidget {
  const RecentActivity({super.key, required this.at, required this.builder});
  final DateTime? at;
  final Widget Function(BuildContext context, Duration? ago) builder;
  @override
  State<RecentActivity> createState() => _RecentActivityState();
}

class _RecentActivityState extends State<RecentActivity> {
  Timer? _tick;

  Duration? get _ago {
    final at = widget.at;
    if (at == null) return null;
    final ago = DateTime.now().toUtc().difference(at.toUtc());
    // A clock slightly ahead of the server still reads as just now.
    return ago.isNegative ? Duration.zero : ago;
  }

  void _schedule() {
    _tick?.cancel();
    final ago = _ago;
    if (ago == null || ago > const Duration(hours: 1)) return;
    _tick = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(_schedule);
    });
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(RecentActivity old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _schedule();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ago);
}
