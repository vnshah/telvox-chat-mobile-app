import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'message_content.dart' show readableText;
import 'models.dart';

/// "Message info" as WhatsApp shows it for a message you sent: when it was
/// read, delivered and sent, from WhatsApp's own receipts. A step WhatsApp has
/// not reported reads as not yet, never as a guessed time; a customer who
/// turned read receipts off never shows Read.
Future<void> showMessageInfo(BuildContext context, ApiMessage m) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => MessageInfoSheet(m),
    );

class MessageInfoSheet extends StatelessWidget {
  const MessageInfoSheet(this.message, {super.key});
  final ApiMessage message;

  String? _when(Object? raw) {
    if (raw == null || '$raw'.isEmpty) return null;
    const clock = MobileClock();
    final day = clock.dayLabel(raw), time = clock.time(raw);
    if (time.isEmpty) return null;
    return day.isEmpty ? time : '$day, $time';
  }

  @override
  Widget build(BuildContext context) {
    final j = message.json;
    final failed = message.status == 4 || message.status == 5;
    final voice = message.type == 'audio';
    final reason = readableText(j['failed_reason']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message info', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              message.text.isEmpty ? 'Message' : message.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: T.secondary),
            ),
            const SizedBox(height: 16),
            if (failed)
              _Step(
                key: const ValueKey('info-failed'),
                icon: Icons.error_outline,
                colour: T.danger,
                label: 'Not delivered',
                value: reason.isEmpty
                    ? 'WhatsApp could not deliver it'
                    : reason,
              )
            else ...[
              if (voice)
                _Step(
                  key: const ValueKey('info-played'),
                  icon: Icons.mic,
                  colour: T.blue,
                  label: 'Played',
                  value: _when(j['played_at']),
                ),
              _Step(
                key: const ValueKey('info-read'),
                icon: Icons.done_all,
                colour: T.blue,
                label: 'Read',
                value: _when(j['read_at']),
              ),
              _Step(
                key: const ValueKey('info-delivered'),
                icon: Icons.done_all,
                colour: T.muted,
                label: 'Delivered',
                value: _when(j['delivered_at']),
              ),
            ],
            _Step(
              key: const ValueKey('info-sent'),
              icon: Icons.done,
              colour: T.muted,
              label: 'Sent',
              value: _when(j['sent_at']),
            ),
            const SizedBox(height: 12),
            const Text(
              'Times come from WhatsApp’s receipts. If the customer turned read receipts off, Read is never shown.',
              style: TextStyle(fontSize: 12, color: T.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.icon,
    required this.colour,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color colour;
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: T.hairline)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: colour),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value ?? '—',
          style: TextStyle(
            fontSize: 14,
            color: value == null ? T.muted : T.secondary,
          ),
        ),
      ],
    ),
  );
}
