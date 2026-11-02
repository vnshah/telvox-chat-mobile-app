import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'message_content.dart' show MessageContent, readableText;
import 'models.dart';

/// A customer's calls on this number, newest first and grouped by day, as the
/// call log of a phone lists them. Tapping a call shows every detail: when it
/// rang, was answered and ended, how long it rang and lasted, and who took or
/// placed it.
class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage(this.session, this.contact, {super.key});
  final MobileSession session;
  final Json contact;
  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  List<Json>? calls;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = object(
        await widget.session.api.post('inbox/call-history', {
          'contact_id': number(widget.contact['id']),
          'limit': 100,
        }),
      );
      if (!mounted) return;
      setState(() {
        calls = rows(result['data']);
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = readableText(widget.contact['profile_name']);
    final list = calls;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Call history'),
            if (name.isNotEmpty)
              Text(name, style: const TextStyle(fontSize: 13, color: T.muted)),
          ],
        ),
      ),
      body: list == null
          ? error == null
                ? const Center(child: CircularProgressIndicator())
                : _Message(
                    icon: Icons.error_outline,
                    text: error!,
                    action: AppButton.text(
                      onPressed: () {
                        setState(() => error = null);
                        load();
                      },
                      child: const Text('Try again'),
                    ),
                  )
          : RefreshIndicator(
              onRefresh: load,
              child: list.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        _Message(
                          icon: Icons.call_outlined,
                          text: 'No calls with this customer yet',
                        ),
                      ],
                    )
                  : ListView(children: _grouped(list)),
            ),
    );
  }

  List<Widget> _grouped(List<Json> list) {
    const clock = MobileClock();
    final out = <Widget>[];
    String? day;
    for (final call in list) {
      final label = clock.dayLabel(call['started_at']);
      if (label != day) {
        day = label;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: T.brass,
              ),
            ),
          ),
        );
      }
      out.add(CallLogTile(call, onTap: () => showCallDetails(context, call)));
    }
    return out;
  }
}

/// How a call went, worded for people.
String callStatusLabel(Json call) => switch ('${call['status']}') {
  'answered' => 'Answered',
  'missed' => 'Missed',
  'rejected' => 'Rejected',
  'no_answer' => 'No answer',
  'failed' => 'Failed',
  'in_progress' => 'In progress',
  final other => other,
};

bool _unanswered(Json call) => const {
  'missed',
  'rejected',
  'no_answer',
  'failed',
}.contains(call['status']);

String? _seconds(Object? raw) {
  final s = number(raw);
  return s == null ? null : MessageContent.callDuration(s);
}

String? _agent(Json call) {
  final name = readableText(object(call['agent'])['name']);
  return name.isEmpty ? null : name;
}

class CallLogTile extends StatelessWidget {
  const CallLogTile(this.call, {super.key, this.onTap});
  final Json call;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final incoming = call['direction'] == 'incoming';
    final red = _unanswered(call);
    final colour = red ? T.danger : T.secondary;
    final agent = _agent(call);
    final duration = number(call['duration_seconds']) ?? 0;
    final detail = [
      callStatusLabel(call),
      if (agent != null) incoming ? 'by $agent' : 'from $agent',
      if (duration > 0) MessageContent.callDuration(duration),
    ].join(' · ');
    return InkWell(
      key: ValueKey('call-log-${call['id']}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.hairline)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (red ? T.danger : T.green).withValues(alpha: .1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                incoming ? Icons.call_received : Icons.call_made,
                size: 20,
                color: colour,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incoming ? 'Incoming call' : 'Outgoing call',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: red ? T.danger : T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: T.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              const MobileClock().time(call['started_at']),
              style: const TextStyle(fontSize: 12.5, color: T.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every detail of one call.
Future<void> showCallDetails(BuildContext context, Json call) {
  const clock = MobileClock();
  String? when(Object? raw) {
    if (raw == null || '$raw'.isEmpty) return null;
    return '${clock.dayLabel(raw)}, ${clock.time(raw)}';
  }

  final incoming = call['direction'] == 'incoming';
  final reason = readableText(call['failure_reason']);
  final rows = <(String, String?)>[
    ('Type', incoming ? 'Incoming' : 'Outgoing'),
    ('Status', callStatusLabel(call)),
    (incoming ? 'Answered by' : 'Placed by', _agent(call)),
    ('Duration', _seconds(call['duration_seconds'])),
    ('Rang for', _seconds(call['ring_seconds'])),
    ('Started', when(call['started_at'])),
    ('Answered', when(call['answered_at'])),
    ('Ended', when(call['ended_at'])),
    if (reason.isNotEmpty) ('Reason', reason.replaceAll('_', ' ')),
    if (call['recorded'] == true) ('Recording', 'Recorded'),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incoming ? 'Incoming call' : 'Outgoing call',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (final (label, value) in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: T.hairline)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 14, color: T.muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value ?? '—',
                        style: TextStyle(
                          fontSize: 14,
                          color: value == null ? T.muted : T.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () =>
                  Clipboard.setData(ClipboardData(text: '${call['call_id']}')),
              child: Text(
                'Call ID: ${call['call_id']}  (tap to copy)',
                style: const TextStyle(fontSize: 11.5, color: T.muted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: T.muted),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: T.secondary),
        ),
        ?action,
      ],
    ),
  );
}
