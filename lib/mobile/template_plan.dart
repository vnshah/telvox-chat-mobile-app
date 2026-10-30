import 'api.dart';

class TemplateInput {
  const TemplateInput(this.key, this.label, {this.kind = 'text'});
  final String key, label, kind;
}

int variableCount(Object? text) =>
    RegExp(r'\{\{(\d+)\}\}')
        .allMatches('$text')
        .map((m) => int.parse(m[1]!))
        .fold(0, (a, b) => a > b ? a : b);

/// Maps editable fields to the existing template-send contract, including its
/// shared URL suffix and shared carousel-button value (not one per button).
class TemplatePlan {
  TemplatePlan(this.template) {
    _build();
  }
  final Json template;
  final inputs = <TemplateInput>[];
  final previews = <String>[];
  final requirements = <String>[];
  final cards = <Json>[];
  int bodyCount = 0;
  bool auth = false;
  void add(String key, String label, {String kind = 'text'}) {
    if (!inputs.any((i) => i.key == key)) {
      inputs.add(TemplateInput(key, label, kind: kind));
    }
  }

  void require(String key) {
    if (!requirements.contains(key)) requirements.add(key);
  }

  void _build() {
    auth = template['category'] == 'AUTHENTICATION';
    final components = rows(decoded(template['rowdata']));
    if (components.isEmpty) {
      throw const ApiFailure(
        'This template has no usable components. Refresh the template list.',
      );
    }
    if (auth) add('otp', 'Authentication code');
    for (final c in components) {
      final type = '${c['type']}'.toUpperCase();
      if (type == 'BODY') {
        previews.add('${c['text'] ?? template['body'] ?? ''}');
        bodyCount = variableCount(c['text']);
        if (!auth) {
          for (var i = 0; i < bodyCount; i++) {
            add('body.$i', 'Body value ${i + 1}');
          }
          if (bodyCount > 0) require('body_text');
        }
      } else if (type == 'HEADER') {
        final format = '${c['format'] ?? 'TEXT'}'.toUpperCase();
        if (format == 'TEXT') {
          previews.insert(0, '${c['text'] ?? ''}');
          if (variableCount(c['text']) > 0) {
            add('header.text', 'Header value');
            require('header_text');
          }
        } else if (['IMAGE', 'VIDEO', 'DOCUMENT'].contains(format)) {
          add(
            'header.media',
            'Header ${format.toLowerCase()}',
            kind: format.toLowerCase(),
          );
          require('header_media');
        } else if (format == 'LOCATION') {
          for (final field in ['latitude', 'longitude', 'name', 'address']) {
            add(
              'location.$field',
              'Location $field',
              kind: field == 'latitude' || field == 'longitude'
                  ? 'coordinate'
                  : 'text',
            );
          }
          require('header_location');
        } else {
          throw ApiFailure('Unsupported template header: $format.');
        }
      } else if (type == 'FOOTER') {
        previews.add('${c['text'] ?? ''}');
      } else if (type == 'BUTTONS') {
        for (final button in rows(c['buttons'])) {
          previews.add('${button['text'] ?? button['type']}');
          if (button['type'] == 'URL' &&
              variableCount(button['url']) > 0 &&
              !auth) {
            add('button.url', 'Dynamic button URL value');
            require('button_url_text');
          }
          if (button['type'] == 'COPY_CODE' && !auth) {
            add('button.url', 'Coupon code');
            require('button_url_text');
          }
        }
      } else if (type == 'LIMITED_TIME_OFFER') {
        add('lto', 'Offer expiry (ISO date and time)', kind: 'datetime');
        require('limited_time_offer');
      } else if (type == 'CAROUSEL') {
        cards.addAll(rows(c['cards']));
        for (var i = 0; i < cards.length; i++) {
          for (final part in rows(cards[i]['components'])) {
            if (part['type'] == 'HEADER') {
              final format = '${part['format']}'.toLowerCase();
              if (!['image', 'video'].contains(format)) {
                throw const ApiFailure('Unsupported carousel media format.');
              }
              add('card.$i.media', 'Card ${i + 1} $format', kind: format);
              require('card_header_media');
            }
            if (part['type'] == 'BODY') {
              previews.add('Card ${i + 1}: ${part['text'] ?? ''}');
              for (var n = 0; n < variableCount(part['text']); n++) {
                add('card.$i.body.$n', 'Card ${i + 1}, value ${n + 1}');
                require('card_body_text');
              }
            }
            if (part['type'] == 'BUTTONS') {
              for (final button in rows(part['buttons'])) {
                if (button['type'] == 'URL' &&
                    variableCount(button['url']) > 0) {
                  add('card.button', 'Carousel button URL value');
                }
              }
            }
          }
        }
      } else {
        throw ApiFailure('Unsupported template component: $type.');
      }
    }
  }

  Json variables(Json values) {
    for (final f in inputs) {
      final value = values[f.key];
      if (value == null || (value is String && value.trim().isEmpty)) {
        throw ApiFailure('Complete ${f.label.toLowerCase()}.');
      }
      if (['image', 'video', 'document'].contains(f.kind) &&
          object(value)['file_url'] == null) {
        throw ApiFailure('Upload ${f.label.toLowerCase()}.');
      }
      if (f.kind == 'coordinate') {
        final n = double.tryParse('$value');
        final max = f.key.endsWith('latitude') ? 90 : 180;
        if (n == null || !n.isFinite || n.abs() > max) {
          throw ApiFailure('Enter a valid ${f.label.toLowerCase()}.');
        }
      }
      if (f.kind == 'datetime' && DateTime.tryParse('$value') == null) {
        throw const ApiFailure('Enter a valid offer expiry date and time.');
      }
    }
    final result = <String, dynamic>{};
    if (auth) result['otp'] = values['otp'];
    if (!auth && bodyCount > 0) {
      result['bodyText'] = [
        for (var i = 0; i < bodyCount; i++) values['body.$i'],
      ];
    }
    if (values.containsKey('header.text')) {
      result['header_text'] = values['header.text'];
    }
    if (values.containsKey('button.url')) {
      result['button_url_text'] = values['button.url'];
    }
    if (values.containsKey('lto')) result['limited_time_offer'] = values['lto'];
    if (values.containsKey('location.latitude')) {
      result['headerLocation'] = {
        'latitude': double.parse('${values['location.latitude']}'),
        'longitude': double.parse('${values['location.longitude']}'),
        'name': values['location.name'],
        'address': values['location.address'],
      };
    }
    final media = <String, dynamic>{};
    if (values.containsKey('header.media')) {
      media['header_media'] = values['header.media'];
    }
    final carousel = <String, dynamic>{};
    final cardBodies = <List<dynamic>>[];
    for (var i = 0; i < cards.length; i++) {
      if (values.containsKey('card.$i.media')) {
        carousel['${i + 1}'] = values['card.$i.media'];
      }
      final body = rows(cards[i]['components'])
          .where((c) => c['type'] == 'BODY')
          .firstOrNull;
      cardBodies.add([
        for (var n = 0; n < variableCount(body?['text']); n++)
          values['card.$i.body.$n'],
      ]);
    }
    if (carousel.isNotEmpty) media['carousel'] = carousel;
    if (media.isNotEmpty) result['mediaTemplate'] = media;
    if (cards.isNotEmpty) result['carousel_body_text'] = cardBodies;
    if (values.containsKey('card.button')) {
      result['card_button'] = values['card.button'];
    }
    return result;
  }
}
