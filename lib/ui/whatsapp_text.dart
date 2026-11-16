import 'package:flutter/material.dart';

import 'theme.dart';

/// WhatsApp's text formatting, drawn as WhatsApp and the web inbox draw it:
/// *bold*, _italic_, ~strikethrough~, ```monospace```, `inline code`, lines
/// starting "* " or "- " as bullets, and "> " as a quote. The markers go;
/// what they wrap is styled. A marker counts only at a word's edge, so
/// snake_case, 2*3*4 and a lone * stay as typed.
List<InlineSpan> whatsappSpans(String text) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (i > 0) spans.add(const TextSpan(text: '\n'));
    final bullet = RegExp(r'^(\s*)[*-] (?=\S)').firstMatch(line);
    if (bullet != null) {
      spans.add(TextSpan(text: '${bullet.group(1)}•  '));
      line = line.substring(bullet.end);
    } else if (line.startsWith('> ')) {
      spans.add(
        TextSpan(
          children: _inline(line.substring(2), const TextStyle()),
          style: const TextStyle(color: T.secondary),
        ),
      );
      continue;
    }
    spans.addAll(_inline(line, const TextStyle()));
  }
  return spans;
}

/// [text] without its formatting markers, for a one-line preview.
String whatsappPlain(String text) =>
    TextSpan(children: whatsappSpans(text))
        .toPlainText(includeSemanticsLabels: false);

bool _edge(String text, int at) =>
    at < 0 ||
    at >= text.length ||
    !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text[at]);

const _styles = <String, TextStyle>{
  '*': TextStyle(fontWeight: FontWeight.w700),
  '_': TextStyle(fontStyle: FontStyle.italic),
  '~': TextStyle(decoration: TextDecoration.lineThrough),
};

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 14);

List<InlineSpan> _inline(String text, TextStyle style) {
  final out = <InlineSpan>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    out.add(TextSpan(text: plain.toString()));
    plain.clear();
  }

  var i = 0;
  while (i < text.length) {
    // ```monospace```: its content is never formatted further.
    if (text.startsWith('```', i)) {
      final end = text.indexOf('```', i + 3);
      if (end > i + 3) {
        flush();
        out.add(TextSpan(text: text.substring(i + 3, end), style: _mono));
        i = end + 3;
        continue;
      }
    }
    final c = text[i];
    if (c == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(
          TextSpan(
            text: text.substring(i + 1, end),
            style: _mono.copyWith(backgroundColor: const Color(0x14000000)),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    final marker = _styles[c];
    if (marker != null &&
        _edge(text, i - 1) &&
        i + 1 < text.length &&
        text[i + 1].trim().isNotEmpty &&
        text[i + 1] != c) {
      // The nearest closing marker that ends a word.
      var end = text.indexOf(c, i + 1);
      while (end != -1 &&
          (text[end - 1].trim().isEmpty || !_edge(text, end + 1))) {
        end = text.indexOf(c, end + 1);
      }
      if (end != -1) {
        flush();
        out.add(
          TextSpan(
            style: marker,
            children: _inline(text.substring(i + 1, end), style),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    plain.write(c);
    i++;
  }
  flush();
  return out;
}
