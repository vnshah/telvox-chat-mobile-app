import 'api.dart';
import 'message_content.dart' show readableText;
import 'models.dart' show ApiMessage;

/// The messages the web inbox lets an agent keep as a note: those with text
/// of their own (media, voice notes and stickers have none to keep).
const noteMessageTypes = {
  'text',
  'interactive',
  'interactiveGetAddress',
  'template',
  'interactiveFlow',
  'interactiveWithButton',
  'interactiveOrderDetails',
  'interactiveOrderStatus',
  'interactiveSingleProduct',
  'interactiveMultipleProduct',
  'interactiveCatalogue',
};

bool supportsNote(ApiMessage m) =>
    !m.log && m.wamid.isNotEmpty && noteMessageTypes.contains(m.type);

/// The note kept for [m], if one was made from it: notes remember the
/// WhatsApp id of the message they came from.
Json? noteFor(ApiMessage m, List<Json> notes) => m.wamid.isEmpty
    ? null
    : notes.where((n) => '${n['message_id'] ?? ''}' == m.wamid).firstOrNull;

/// A message's text as the web inbox copies it into a note: the text, an
/// interactive message's body, a template's body, or the stored text.
String noteText(ApiMessage m) {
  final body = object(decoded(m.json['message_body_json']));
  final type = m.type;
  final Object? text = switch (type) {
    'text' => object(body['text'])['body'] ?? m.json['message_body'],
    'template' => rows(
      body['preview'],
    ).where((p) => '${p['type']}' == 'BODY').firstOrNull?['text'],
    _ when type.startsWith('interactive') => object(
      object(body['component'])['body'],
    )['text'],
    _ =>
      m.json['message_body'] is Map
          ? object(m.json['message_body'])['text']
          : m.json['message_body'],
  };
  final kept = readableText(text).trim();
  if (kept.isNotEmpty) return kept;
  final shown = m.text.trim();
  return shown.isNotEmpty ? shown : '$type message';
}
