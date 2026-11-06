import 'package:flutter/widgets.dart';

class Message {
  const Message(
    this.text, {
    this.out = false,
    this.time = '10:24',
    this.type = 'text',
    this.reply,
    this.replyAuthor,
    this.replyPreview,
    this.reaction = '',
    this.read = true,
    this.deliveryStatus,
    this.source = 0,
    this.failedReason,
  });
  final String text, time, type, reaction;
  final String? reply, replyAuthor;

  /// Drawn in the reply quote in place of [reply]'s text, for a quote that
  /// is more than words: a voice note shows its length.
  final Widget? replyPreview;
  final bool out, read;
  final int? deliveryStatus;

  /// What sent an outgoing message, as the inbox records it: 0 an agent,
  /// 1 a broadcast, 2 an automation, 3 a chatbot, 4 the API.
  final int source;

  /// Why WhatsApp did not deliver it, shown from the red mark as the web
  /// inbox's tooltip does.
  final String? failedReason;
}
