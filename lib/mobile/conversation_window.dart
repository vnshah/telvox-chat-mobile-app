import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';

/// When this chat's WhatsApp conversation window closes, or null if unknown.
/// The contact's service (24 h) and ad-referral (72 h) expiries are WhatsApp's
/// own. A customer message newer than they reflect — a live list event carries
/// the message, not the new expiry — opens the window 24 hours from it.
DateTime? windowExpiresAt(Json contact, [Iterable<Json> messages = const []]) {
  final dates = <DateTime>[
    ?MobileClock.instant(contact['service_expiration_timestamp']),
    ?MobileClock.instant(contact['referral_conversion_expiration_timestamp']),
    for (final m in messages)
      if (number(m['type']) == 2)
        if (MobileClock.instant(m['created_at']) case final DateTime at)
          at.add(const Duration(hours: 24)),
  ]..sort();
  return dates.lastOrNull;
}

/// Windows learned from opened chats, which load the contact in full, by
/// contact id. The inbox list may lack the expiry (an older server sends
/// none); with this its dot still agrees with the chat header.
final knownWindows = ValueNotifier<Map<String, DateTime>>({});

/// Notes a chat's window; only a later expiry changes anything.
void rememberWindow(Object? contactId, DateTime? expires) {
  if (contactId == null || expires == null) return;
  final known = knownWindows.value['$contactId'];
  if (known != null && !expires.isAfter(known)) return;
  knownWindows.value = {...knownWindows.value, '$contactId': expires};
}

/// The later of the row's own expiry and what an opened chat learned.
DateTime? rowWindowExpires(Json contact, [Iterable<Json> messages = const []]) {
  final own = windowExpiresAt(contact, messages);
  final known = knownWindows.value['${contact['id']}'];
  if (own == null) return known;
  if (known == null) return own;
  return known.isAfter(own) ? known : own;
}

bool windowOpen(DateTime? expires, [DateTime? now]) =>
    expires != null && expires.isAfter(now ?? DateTime.now());

/// "5h 12m left", "40m left", "Open" past three days (a later expiry is bad
/// data, not a 632635-hour window), or "Window closed".
String windowLabel(DateTime? expires, [DateTime? now]) {
  final left = expires?.difference(now ?? DateTime.now());
  if (left == null || left.isNegative) return 'Window closed';
  if (left.inHours >= 72) return 'Open';
  if (left.inHours > 0) return '${left.inHours}h ${left.inMinutes % 60}m left';
  return '${left.inMinutes.clamp(1, 59)}m left';
}

/// The web ticket inbox's session timer: the time left in the window as
/// HH:MM:SS (hours past 24 as they are, "71:59:58"), or "Session Closed".
String sessionTimerLabel(DateTime? expires, [DateTime? now]) {
  final left = expires?.difference(now ?? DateTime.now());
  if (left == null || left.isNegative || left == Duration.zero) {
    return 'Session Closed';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
}

/// Rebuilds [builder] with whether the window is open, and once more when it
/// closes, so the green dot goes out on time with no reload.
class ConversationWindow extends StatefulWidget {
  const ConversationWindow({
    super.key,
    required this.expiresAt,
    required this.builder,
  });
  final DateTime? expiresAt;
  final Widget Function(BuildContext context, bool open) builder;
  @override
  State<ConversationWindow> createState() => _ConversationWindowState();
}

class _ConversationWindowState extends State<ConversationWindow> {
  Timer? _close;

  void _schedule() {
    _close?.cancel();
    final left = widget.expiresAt?.difference(DateTime.now());
    // Only a real window is timed; one past three days is bad data.
    if (left == null || left.isNegative || left.inHours >= 72) return;
    _close = Timer(left + const Duration(seconds: 1), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ConversationWindow old) {
    super.didUpdateWidget(old);
    if (old.expiresAt != widget.expiresAt) _schedule();
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, windowOpen(widget.expiresAt));
}
