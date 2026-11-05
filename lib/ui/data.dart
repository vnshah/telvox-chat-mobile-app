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
  });
  final String text, time, type, reaction;
  final String? reply, replyAuthor;

  /// Drawn in the reply quote in place of [reply]'s text, for a quote that
  /// is more than words: a voice note shows its length.
  final Widget? replyPreview;
  final bool out, read;
  final int? deliveryStatus;
}
