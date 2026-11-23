import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// WhatsApp's text formatting, drawn as WhatsApp and the web inbox draw it:
/// *bold*, _italic_, ~strikethrough~, ```monospace```, `inline code`, lines
/// starting "* " or "- " as bullets, and "> " as a quote. The markers go;
/// what they wrap is styled. A marker counts only at a word's edge, so
/// snake_case, 2*3*4 and a lone * stay as typed. Links (see [findLinks]) are
/// drawn as links and open outside the app when tapped, unless [links] is
/// false, as for a one-line preview.
List<InlineSpan> whatsappSpans(String text, {bool links = true}) {
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
          children: _inline(line.substring(2), links),
          style: const TextStyle(color: T.secondary),
        ),
      );
      continue;
    }
    spans.addAll(_inline(line, links));
  }
  return spans;
}

/// [text] without its formatting markers, for a one-line preview.
String whatsappPlain(String text) =>
    TextSpan(children: whatsappSpans(text, links: false))
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

List<InlineSpan> _inline(String text, bool links) {
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
            children: _inline(text.substring(i + 1, end), links),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    if (links) {
      final url = _linkAt(text, i);
      if (url != null) {
        flush();
        out.add(
          TextSpan(
            text: url,
            style: _link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openMessageLink(linkUri(url)),
          ),
        );
        i += url.length;
        continue;
      }
    }
    plain.write(c);
    i++;
  }
  flush();
  return out;
}

const _link = TextStyle(
  color: T.blue,
  decoration: TextDecoration.underline,
  decorationColor: T.blue,
);

const _tlds =
    'com|in|org|net|io|co|app|dev|me|info|biz|ai|shop|store|xyz|online|site|'
    'tech|link|ly|gl|gov|edu|uk|us|ae';

final _linkPattern = RegExp(
  r'(?:(?:https?://|www\.)[^\s<>"]+'
  '|(?:[\\p{L}\\p{N}-]+\\.)+(?:$_tlds)'
  r'(?![\p{L}\p{N}-])(?:[/?#][^\s<>"]*)?)',
  caseSensitive: false,
  unicode: true,
);

/// What may come just before a link: not a letter or digit, nor the @ of an
/// email or the . / _ - inside a word or path.
final _inWord = RegExp(r'[\p{L}\p{N}@./_-]', unicode: true);

/// A link starting at [at] in [text], as the web inbox finds them: anything
/// starting http(s):// or www., or a bare domain with a common ending
/// (telvox.in, shop.example.com/offer); never an email address. Punctuation
/// that ends the sentence is left out, and a closing bracket kept only when
/// the link opened one.
String? _linkAt(String text, int at) {
  if (at > 0 && _inWord.hasMatch(text[at - 1])) return null;
  final match = _linkPattern.matchAsPrefix(text, at);
  if (match == null) return null;
  var url = match[0]!;
  while (url.isNotEmpty) {
    final c = url[url.length - 1];
    final open = {')': '(', ']': '['}[c];
    if ('.,;:!?\'"*_~'.contains(c) ||
        (open != null &&
            open.allMatches(url).length < c.allMatches(url).length)) {
      url = url.substring(0, url.length - 1);
      continue;
    }
    break;
  }
  // "https://" alone, or "www." with nothing after it, is no link.
  if (!RegExp(r'[\p{L}\p{N}]\.[\p{L}\p{N}]', unicode: true).hasMatch(url)) {
    return null;
  }
  return url;
}

/// The links in [text], as [whatsappSpans] draws them.
List<String> findLinks(String text) {
  final found = <String>[];
  var i = 0;
  while (i < text.length) {
    final url = _linkAt(text, i);
    if (url != null) {
      found.add(url);
      i += url.length;
    } else {
      i++;
    }
  }
  return found;
}

/// Where a link found in a message goes: https:// added when left off.
Uri linkUri(String url) => Uri.parse(
  RegExp(r'^https?://', caseSensitive: false).hasMatch(url)
      ? url
      : 'https://$url',
);

/// Opens a link from a message in the browser (or the app that owns it);
/// replaceable in tests.
Future<void> Function(Uri) openMessageLink = (uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
};
