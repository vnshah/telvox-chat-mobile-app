class Message {
  const Message(
    this.text, {
    this.out = false,
    this.time = '10:24',
    this.type = 'text',
    this.reply,
    this.replyAuthor,
    this.reaction = '',
    this.read = true,
    this.deliveryStatus,
  });
  final String text, time, type, reaction;
  final String? reply, replyAuthor;
  final bool out, read;
  final int? deliveryStatus;
}
