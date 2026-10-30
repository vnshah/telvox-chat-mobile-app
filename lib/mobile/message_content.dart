import 'package:html/parser.dart' show parseFragment;

import 'api.dart';

String readableText(Object? value) {
  if (value is! String) return '';
  final text = value.trim();
  if (text.startsWith('{') || text.startsWith('[')) return '';
  return parseFragment(
        text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
      ).text ??
      '';
}

class MessageContent {
  MessageContent(this.row) {
    _parse();
  }
  final Json row;
  String text = '';
  final buttons = <String>[];
  final media = <Json>[];
  final fields = <String, String>{};
  VoiceCall? voiceCall;
  bool get structured =>
      buttons.isNotEmpty || media.isNotEmpty || fields.isNotEmpty;
  String get summary => text.isNotEmpty
      ? text
      : fields.isNotEmpty
      ? 'Form response'
      : media.isNotEmpty
      ? '${media.first['type']} attachment'
      : 'Message';
  void line(Object? value) {
    final next = readableText(value);
    if (next.isNotEmpty) text = text.isEmpty ? next : '$text\n$next';
  }

  void attachment(String type, Object? value) {
    final m = object(value);
    if (m.isNotEmpty) media.add({'type': type, ...m});
  }

  void form(Object? value) {
    for (final entry in object(decoded(value)).entries) {
      if (RegExp(
        r'token|password|secret|^id$|^version$',
        caseSensitive: false,
      ).hasMatch(entry.key)) {
        continue;
      }
      if (entry.value is Map || entry.value is List || entry.value == null) {
        continue;
      }
      if (entry.key.isEmpty) continue;
      final label = entry.key.replaceAll('_', ' ');
      fields['${label[0].toUpperCase()}${label.substring(1)}'] =
          '${entry.value}';
    }
  }

  void component(Json c) {
    final type = '${c['type']}'.toLowerCase();
    if (type == 'buttons') {
      for (final b in rows(c['buttons'])) {
        final label = readableText(b['text']);
        if (label.isNotEmpty) buttons.add(label);
      }
    } else if (type == 'carousel') {
      for (final card in rows(c['cards'])) {
        for (final part in rows(card['components'])) {
          component(part);
        }
      }
    } else {
      line(c['text']);
      for (final kind in ['image', 'video', 'document', 'audio', 'sticker']) {
        attachment(kind, c[kind]);
      }
      if (c['location'] != null) location(object(c['location']));
    }
  }

  /// Voice call rows hold "Start calling..." until the call ends, then a JSON
  /// status. Worded as WhatsApp shows them: a missed incoming call, an
  /// unanswered outgoing one, or the call with its duration.
  void call(Object? body) {
    if (body is! Map) {
      voiceCall = VoiceCall(
        incoming: number(row['type']) == 2,
        missed: false,
        title: 'Voice call',
        subtitle: readableText(row['message_body']).isEmpty ? null : 'Calling…',
      );
    } else {
      final status = '${body['status'] ?? ''}'.toUpperCase();
      final incoming = body['direction'] == null
          ? number(row['type']) == 2
          : body['direction'] == 'USER_INITIATED';
      final seconds = int.tryParse('${body['duration']}') ?? 0;
      final answered = status == 'COMPLETED' && seconds > 0;
      voiceCall = answered
          ? VoiceCall(
              incoming: incoming,
              missed: false,
              title: 'Voice call',
              subtitle: callDuration(seconds),
            )
          : incoming
          ? VoiceCall(incoming: true, missed: true, title: 'Missed voice call')
          : VoiceCall(
              incoming: false,
              missed: false,
              title: 'Voice call',
              subtitle: status.isEmpty || status == 'COMPLETED'
                  ? 'No answer'
                  : '${status[0]}${status.substring(1).toLowerCase().replaceAll('_', ' ')}',
            );
    }
    final c = voiceCall!;
    text =
        '📞 ${c.title}${c.subtitle == null || c.subtitle == 'Calling…' ? '' : ' · ${c.subtitle}'}';
  }

  static String callDuration(Object? seconds) {
    final total = int.tryParse('$seconds') ?? 0;
    final secs = total % 60, mins = total ~/ 60;
    final secsLabel = '$secs ${secs == 1 ? 'sec' : 'secs'}';
    if (mins == 0) return secsLabel;
    final minsLabel = '$mins ${mins == 1 ? 'min' : 'mins'}';
    return secs > 0 ? '$minsLabel $secsLabel' : minsLabel;
  }

  void location(Json l) {
    line(l['name']);
    line(l['address']);
    if (l['latitude'] != null && l['longitude'] != null) {
      line('${l['latitude']}, ${l['longitude']}');
    }
  }

  void _parse() {
    final type = '${row['message_type'] ?? 'text'}';
    if (type == 'text' &&
        row['message_body'] is String &&
        '${row['message_body']}'.isNotEmpty) {
      text = '${row['message_body']}';
      return;
    }
    var p = object(decoded(row['message_body_json']));
    final body = decoded(row['message_body']);
    if (p.isEmpty && body is Map) p = object(body);
    if (type == 'template') {
      for (final c in rows(p['preview'])) {
        component(c);
      }
      if (text.isEmpty) line(object(p['text'])['body']);
      if (text.isEmpty && media.isEmpty) {
        text = 'Template: ${readableText(row['message_body'])}';
      }
      return;
    }
    if (type.toLowerCase().startsWith('interactive')) {
      final incoming = object(p['interactive']);
      final reply = object(incoming['button_reply'] ?? incoming['list_reply']);
      line(reply['title']);
      line(reply['description']);
      final nfm = object(incoming['nfm_reply']);
      if (nfm.isNotEmpty) {
        text = 'Form response';
        form(nfm['response_json']);
      }
      final c = object(p['component'] ?? p['interactive']);
      line(object(c['header'])['text']);
      line(object(c['body'])['text']);
      line(object(c['footer'])['text']);
      for (final kind in ['image', 'video', 'document']) {
        attachment(kind, object(c['header'])[kind]);
      }
      final action = object(c['action']);
      for (final b in rows(action['buttons'])) {
        final label = readableText(object(b['reply'])['title'] ?? b['title']);
        if (label.isNotEmpty) buttons.add(label);
      }
      final params = object(action['parameters']);
      final cta = readableText(
        params['flow_cta'] ?? params['display_text'] ?? action['button'],
      );
      if (cta.isNotEmpty) buttons.add(cta);
      if (type.contains('Order')) {
        final order = object(params['order']);
        line(order['status'] == null ? null : 'Order ${order['status']}');
        for (final item in rows(order['items'])) {
          line('${item['name'] ?? 'Item'} × ${item['quantity'] ?? 1}');
        }
        final amount = object(params['total_amount']);
        final value = num.tryParse('${amount['value']}'),
            offset = num.tryParse('${amount['offset']}');
        if (value != null && offset != null && offset > 0) {
          line(
            '${params['currency'] ?? ''} ${(value / offset).toStringAsFixed(2)}',
          );
        }
      }
      if (text.isEmpty && body is Map && !body.containsKey('component')) {
        text = 'Form response';
        form(body);
      }
      if (text.isEmpty) text = readableText(row['message_body']);
      if (text.isEmpty) text = 'Interactive message';
      return;
    }
    if (type == 'voice_call') {
      call(body);
      return;
    }
    if (['image', 'video', 'document', 'audio', 'sticker'].contains(type)) {
      // Outgoing rows nest the file under its type; inbound rows store it flat.
      attachment(type, p[type] ?? (p['media_path'] != null ? p : null));
      line(object(p[type])['caption']);
      if (text.isEmpty &&
          !RegExp(
            r'attached|^image$|^video$|^document$|^audio$',
            caseSensitive: false,
          ).hasMatch('${row['message_body']}')) {
        line(row['message_body']);
      }
      return;
    }
    if (type == 'location') {
      location(object(p['location']));
      return;
    }
    if (type == 'contacts') {
      for (final c in rows(p['contacts'])) {
        line(object(c['name'])['formatted_name']);
        for (final phone in rows(c['phones'])) {
          line(phone['phone']);
        }
      }
      if (text.isEmpty) text = 'Contact card';
      return;
    }
    if (type == 'button') {
      line(object(p['button'])['text']);
    }
    if (text.isEmpty) line(row['message_body']);
    if (text.isEmpty) line(object(p['text'])['body'] ?? p['text']);
    if (text.isEmpty) {
      text = type.toLowerCase().contains('call')
          ? 'Call event'
          : 'Unsupported message';
    }
  }
}

class VoiceCall {
  const VoiceCall({
    required this.incoming,
    required this.missed,
    required this.title,
    this.subtitle,
  });
  final bool incoming, missed;
  final String title;
  final String? subtitle;
}
