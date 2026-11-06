import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/chat_message.dart' show MessageBubble, sourceMarks;
import '../ui/delivery_tick.dart';
import '../ui/theme.dart';
import 'api.dart' show number;
import 'message_content.dart' show readableText;
import '../ui/conversation.dart' show ChatWallpaper;
import 'message_view.dart' show messagePresentation;
import 'models.dart';

/// "Message info" as WhatsApp shows it for a message you sent: the message
/// itself, then when it was read, delivered and sent (and played, for a
/// voice note), from WhatsApp's own receipts, with the web inbox's marks.
/// A step WhatsApp has not reported reads as not yet, never as a guessed
/// time; a customer who turned read receipts off never shows Read. Below
/// them, the message's own details: its status, who sent it, what sent it,
/// and its WhatsApp id.
Future<void> showMessageInfo(BuildContext context, ApiMessage m) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => MessageInfoPage(m)));

class MessageInfoPage extends StatelessWidget {
  const MessageInfoPage(this.message, {super.key});
  final ApiMessage message;

  static String? when(Object? raw) {
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
    final source = sourceMarks[number(j['message_source']) ?? 0];
    final sender = readableText(j['sender_name']);
    return Scaffold(
      backgroundColor: T.iosGrouped,
      appBar: AppBar(title: const Text('Message info')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // The message as it reads in the chat.
          CustomPaint(
            painter: const ChatWallpaper(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: MessageBubble(
                  message: messagePresentation(message),
                  first: true,
                  maxWidth: MediaQuery.sizeOf(context).width * .8,
                ),
              ),
            ),
          ),
          _Card(
            children: [
              if (failed)
                _Step(
                  key: const ValueKey('info-failed'),
                  mark: DeliveryTick(message.status, size: 20),
                  label: 'Not delivered',
                  value: reason.isEmpty
                      ? 'WhatsApp could not deliver it'
                      : reason,
                  danger: true,
                )
              else ...[
                if (voice)
                  _Step(
                    key: const ValueKey('info-played'),
                    mark: const Icon(
                      Icons.mic,
                      size: 20,
                      color: DeliveryTick.read,
                    ),
                    label: 'Played',
                    value: when(j['played_at']),
                  ),
                _Step(
                  key: const ValueKey('info-read'),
                  mark: const DeliveryTick(3, size: 20),
                  label: 'Read',
                  value: when(j['read_at']),
                ),
                _Step(
                  key: const ValueKey('info-delivered'),
                  mark: const DeliveryTick(2, size: 20),
                  label: 'Delivered',
                  value: when(j['delivered_at']),
                ),
              ],
              _Step(
                key: const ValueKey('info-sent'),
                mark: const DeliveryTick(1, size: 20),
                label: 'Sent',
                value: when(j['sent_at']),
                last: true,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Text(
              'Times come from WhatsApp’s receipts. If the customer turned '
              'read receipts off, Read is never shown.',
              style: TextStyle(fontSize: 12, color: T.muted),
            ),
          ),
          _Card(
            children: [
              _Detail(
                key: const ValueKey('info-status'),
                label: 'Status',
                trailing: DeliveryTick(message.status, size: 16),
                value: DeliveryTick.label(message.status),
              ),
              if (sender.isNotEmpty)
                _Detail(
                  key: const ValueKey('info-sender'),
                  label: 'Sent by',
                  value: sender,
                ),
              if (source != null)
                _Detail(
                  key: const ValueKey('info-source'),
                  label: 'Sent from',
                  trailing: Icon(source.$1, size: 16, color: T.muted),
                  value: source.$2.replaceFirst('Sent ', ''),
                ),
              if (when(j['created_at']) case final created?)
                _Detail(label: 'Created', value: created),
              if (message.wamid.isNotEmpty)
                _Detail(
                  key: const ValueKey('info-id'),
                  label: 'WhatsApp ID',
                  value: message.wamid,
                  small: true,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.wamid));
                    if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Message ID copied.')),
                      );
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: children),
  );
}

/// One receipt: its mark and name, with the time beneath, as WhatsApp lays
/// it out.
class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.mark,
    required this.label,
    required this.value,
    this.danger = false,
    this.last = false,
  });
  final Widget mark;
  final String label;
  final String? value;
  final bool danger, last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: T.hairline)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: mark),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: danger ? DeliveryTick.failed : T.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value ?? '—',
                style: TextStyle(
                  fontSize: 13.5,
                  color: danger
                      ? DeliveryTick.failed
                      : value == null
                      ? T.muted
                      : T.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.small = false,
    this.onTap,
  });
  final String label, value;
  final Widget? trailing;
  final bool small;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: T.muted),
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              value,
              maxLines: small ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: small ? 12 : 14, color: T.ink),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.copy_rounded, size: 16, color: T.muted),
        ],
      ),
    ),
  );
}
