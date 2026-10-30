import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/data.dart' show Message;
import '../ui/chat_message.dart';
import '../ui/conversation.dart' show SwipeReply;
import 'media.dart';
import 'models.dart';
import 'message_content.dart';

Message messagePresentation(ApiMessage m) => Message(
  m.content.text,
  out: m.outgoing,
  time: const MobileClock().time(m.json['created_at']),
  reply: m.json['contextual_message'] == null
      ? null
      : MessageContent({
          'message_type': m.json['contextual_message_type'] ?? 'text',
          'message_body': m.json['contextual_message'],
          'message_body_json': m.json['contextual_message_json'],
        }).summary,
  replyAuthor: 'Reply',
  read: m.status == 3,
  deliveryStatus: m.status,
);

class LiveMessageView extends StatelessWidget {
  const LiveMessageView({
    super.key,
    required this.message,
    required this.apiBase,
    required this.first,
    this.onReply,
    this.onActions,
  });
  final ApiMessage message;
  final String apiBase;
  final bool first;
  final VoidCallback? onReply;
  final void Function(BuildContext)? onActions;
  @override
  Widget build(BuildContext context) {
    final m = message, c = m.content;
    if (m.log) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 25),
        child: Text(
          c.summary,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: T.muted),
        ),
      );
    }
    Widget bubble = Builder(
      builder: (anchor) => GestureDetector(
        onLongPress: onActions == null ? null : () => onActions!(anchor),
        child: MessageBubble(
          message: messagePresentation(m),
          first: first,
          maxWidth: MediaQuery.sizeOf(context).width * .82,
          contentBefore: c.media.isEmpty
              ? null
              : SizedBox(
                  width: 250,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final media in c.media)
                        if (mediaUri(
                              media['media_path'] ??
                                  media['link'] ??
                                  media['url'],
                              apiBase,
                            )
                            case final Uri url)
                          Material(
                            color: Colors.transparent,
                            child: MediaTile(
                              MessageMedia(
                                '${media['type']}',
                                url,
                                '${media['filename'] ?? media['media_name'] ?? media['type']}',
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
          contentAfter: !c.structured
              ? null
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in c.fields.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '${f.key}: ${f.value}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      for (final b in c.buttons)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 9,
                            horizontal: 4,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: T.edge)),
                          ),
                          child: Text(
                            b,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: T.green,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
    if (onReply != null) bubble = SwipeReply(onReply: onReply!, child: bubble);
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 7 : 1,
        bottom: m.reactions.isEmpty ? 1 : 4,
      ),
      child: Align(
        alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: m.outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            bubble,
            if (m.status == 4 || m.status == 5)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .8,
                  ),
                  child: Text(
                    readableText(m.json['failed_reason']).isEmpty
                        ? 'Message failed to send'
                        : readableText(m.json['failed_reason']),
                    style: const TextStyle(fontSize: 11, color: T.danger),
                  ),
                ),
              ),
            if (m.reactions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: T.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: T.edge),
                ),
                child: Text(
                  m.reactions.map((r) => r['emoji'] ?? '').join(' '),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
