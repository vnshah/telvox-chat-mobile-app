import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'media.dart';
import 'template_plan.dart';
import 'send_policy.dart';
import 'detail_layout.dart' show DetailSection;
import 'message_content.dart' show readableText;
import 'screens.dart' show failure, mobileNotice;

class TemplateSend extends StatefulWidget {
  const TemplateSend(
    this.session,
    this.contact,
    this.template, {
    super.key,
    this.ticketId,
  });
  final MobileSession session;
  final Json contact, template;
  final int? ticketId;
  @override
  State<TemplateSend> createState() => _TemplateSendState();
}

class _TemplateSendState extends State<TemplateSend> {
  TemplatePlan? plan;
  Json values = {};
  Json? retryBody;
  String? retryKey, error;
  bool busy = false;
  double? progress;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get(
        'inbox/templates/${widget.template['id']}',
      );
      final next = TemplatePlan(object(r['data']));
      if (mounted) {
        setState(() {
          plan = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> upload(TemplateInput field) async {
    if (busy || retryBody != null) return;
    setState(() => busy = true);
    try {
      final attachment = await chooseAttachment(kind: field.kind);
      if (attachment == null) return;
      final data = await uploadAttachment(
        widget.session.api,
        attachment,
        progress: (sent, total) {
          if (mounted && total > 0) setState(() => progress = sent / total);
        },
      );
      if (data['file_url'] == null) {
        throw const ApiFailure('The upload did not return a media URL.');
      }
      if (mounted) {
        setState(
          () => values[field.key] = {
            'file_url': data['file_url'],
            'new_file_name': data['file_name'] ?? attachment.name,
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> send() async {
    if (busy) return;
    setState(() => error = null);
    try {
      setState(() => busy = true);
      // Ticket conversations re-check through the ticket alone: in ticketing
      // mode the shared inbox's contact details are not available. The
      // server still enforces DND for marketing templates either way.
      final Json details;
      Json? ticket;
      if (widget.ticketId != null) {
        final data = object(
          (await widget.session.api.post('inbox/ticket_details', {
            'ticket_id': widget.ticketId,
          }))['data'],
        );
        ticket = object(data['ticket']);
        details = ticketSendDetail(data);
      } else {
        details = object(
          (await widget.session.api.post('inbox/getContactDetails', {
            'contact_id': widget.contact['id'],
          }))['data'],
        );
      }
      if (flag(details['is_dnd']) &&
          plan!.template['category'] == 'MARKETING') {
        throw const ApiFailure(
          'This contact has opted out of marketing. Choose a utility or authentication template.',
        );
      }
      final permission = SendPolicy.evaluate(
        widget.session,
        details,
        ticket: ticket,
      );
      if (!permission.canTemplate) {
        throw ApiFailure(
          permission.reason ?? 'You do not have permission to send templates.',
        );
      }
      retryBody ??= {
        'waba_user_id': widget.session.api.wabaId,
        'contact_id': widget.contact['id'],
        'phone_number': widget.contact['wa_id'],
        'template_id': widget.template['id'],
        'variables': plan!.variables(values),
        'error_variable': plan!.requirements,
        if (widget.ticketId != null) 'ticket_id': widget.ticketId,
      };
      retryKey ??= newRequestId();
      setState(() => busy = true);
      await widget.session.api.request(
        'inbox/send-template-by-contact',
        method: 'POST',
        idempotencyKey: retryKey,
        data: {...retryBody!, 'temp_message_id': retryKey},
      );
      if (mounted) {
        mobileNotice(context, 'Template accepted.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      if (e is ApiFailure && !e.uncertain) {
        retryBody = null;
        retryKey = null;
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void changed(String key, String value) => setState(() => values[key] = value);

  /// The fields under the part of the message each one fills.
  List<(String, List<TemplateInput>)> get groups {
    final out = <String, List<TemplateInput>>{};
    for (final f in plan!.inputs) {
      final group = f.key == 'card.button'
          ? 'Button'
          : switch (f.key.split('.').first) {
              'header' || 'location' => 'Header',
              'body' || 'otp' => 'Message',
              'button' => 'Button',
              'card' => 'Cards',
              'lto' => 'Offer',
              _ => 'Details',
            };
      out.putIfAbsent(group, () => []).add(f);
    }
    return [for (final e in out.entries) (e.key, e.value)];
  }

  Widget field(TemplateInput f) {
    if (['image', 'video', 'document'].contains(f.kind)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: MediaSlot(
          label: f.label,
          kind: f.kind,
          fileName: object(values[f.key])['new_file_name']?.toString(),
          progress: progress,
          onPick: () => upload(f),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AppTextFormField(
        key: ValueKey('template-field-${f.key}'),
        initialValue: values[f.key] is String ? values[f.key] as String : null,
        keyboardType: f.kind == 'coordinate'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : f.kind == 'datetime'
            ? TextInputType.datetime
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.kind == 'datetime' ? '2026-12-31T18:00' : null,
        ),
        onChanged: (v) => changed(f.key, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final name = readableText(widget.contact['profile_name']);
    final ready = plan;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(templateTitle(t['name'])),
            Text(
              [
                templateCategory(t['category']),
                '${t['language'] ?? ''}'.toUpperCase(),
              ].where((p) => p.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13, color: T.muted),
            ),
          ],
        ),
      ),
      body: ready == null
          ? error == null
                ? const Center(child: CircularProgressIndicator())
                : failure(error!, load)
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                DetailSection(
                  title: 'Preview',
                  children: [
                    Container(
                      color: T.wash,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      alignment: Alignment.centerRight,
                      child: TemplateBubble(
                        ready.template,
                        values: values,
                        key: const ValueKey('template-preview'),
                      ),
                    ),
                  ],
                ),
                if (ready.inputs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Nothing to fill in: this template sends as it is.',
                      style: TextStyle(fontSize: 13.5, color: T.muted),
                    ),
                  ),
                if (retryBody != null)
                  const Notice(
                    'The previous send is not confirmed. Retry sends the original values safely.',
                  ),
                AbsorbPointer(
                  absorbing: busy || retryBody != null,
                  child: Column(
                    children: [
                      for (final (title, fields) in groups)
                        DetailSection(
                          title: title,
                          children: [for (final f in fields) field(f)],
                        ),
                    ],
                  ),
                ),
                if (error != null) Notice(error!, danger: true),
              ],
            ),
      bottomNavigationBar: ready == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: T.hairline)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'To $name',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: T.muted,
                          ),
                        ),
                      ),
                    AppButton.filled(
                      onPressed: busy ? null : send,
                      child: Text(
                        busy
                            ? 'Please wait…'
                            : retryBody == null
                            ? 'Send template'
                            : 'Retry original send',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// "order_update" as people read it: "Order update".
String templateTitle(Object? name) {
  final words = '${name ?? ''}'.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (words.isEmpty) return 'Template';
  return words[0].toUpperCase() + words.substring(1);
}

String templateCategory(Object? category) =>
    switch ('${category ?? ''}'.toUpperCase()) {
      'MARKETING' => 'Marketing',
      'UTILITY' => 'Utility',
      'AUTHENTICATION' => 'Authentication',
      final other =>
        other.isEmpty ? '' : other[0] + other.substring(1).toLowerCase(),
    };

List<Json> templateComponents(Json template) =>
    rows(decoded(template['rowdata']));

/// The message text with its {{n}} placeholders: a filled one in bold, an
/// empty one as a bronze tag, so it is plain which values are still missing.
class TemplateText extends StatelessWidget {
  const TemplateText(
    this.text, {
    super.key,
    this.values = const {},
    this.style,
    this.maxLines,
  });
  final String text;

  /// Placeholder number (1-based) to the value typed for it.
  final Map<int, String> values;
  final TextStyle? style;
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    final base =
        style ?? const TextStyle(fontSize: 14.5, height: 1.35, color: T.ink);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in RegExp(r'\{\{(\d+)\}\}').allMatches(text)) {
      spans.add(TextSpan(text: text.substring(at, m.start)));
      final n = int.parse(m[1]!);
      final value = values[n]?.trim() ?? '';
      spans.add(
        value.isNotEmpty
            ? TextSpan(
                text: value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : TextSpan(
                text: ' {{$n}} ',
                style: TextStyle(
                  color: T.bronze,
                  fontWeight: FontWeight.w600,
                  background: Paint()..color = T.selected,
                ),
              ),
      );
      at = m.end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// The template as the customer will see it: header, message, footer and
/// buttons in a sent-message bubble, with the values typed so far.
class TemplateBubble extends StatelessWidget {
  const TemplateBubble(this.template, {super.key, this.values = const {}});
  final Json template;
  final Json values;

  Map<int, String> _values(String prefix) => {
    for (final e in values.entries)
      if (e.key.startsWith(prefix) && e.value is String)
        (int.tryParse(e.key.substring(prefix.length)) ?? -1) + 1:
            e.value as String,
  };

  @override
  Widget build(BuildContext context) {
    final parts = templateComponents(template);
    final body = _values('body.');
    final header = {1: '${values['header.text'] ?? ''}'};
    final children = <Widget>[];
    final buttons = <Json>[];
    for (final c in parts) {
      final type = '${c['type']}'.toUpperCase();
      if (type == 'HEADER') {
        final format = '${c['format'] ?? 'TEXT'}'.toUpperCase();
        if (format == 'TEXT') {
          children.add(
            TemplateText(
              '${c['text'] ?? ''}',
              values: header,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: T.ink,
              ),
            ),
          );
        } else {
          final file = object(values['header.media'])['new_file_name'];
          children.add(
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mediaIcon(format.toLowerCase()),
                    color: T.brass,
                    size: 30,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    file == null ? 'Header ${format.toLowerCase()}' : '$file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: T.secondary),
                  ),
                ],
              ),
            ),
          );
        }
      } else if (type == 'BODY') {
        children.add(TemplateText('${c['text'] ?? ''}', values: body));
      } else if (type == 'FOOTER') {
        children.add(
          Text(
            '${c['text'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, color: T.muted),
          ),
        );
      } else if (type == 'BUTTONS') {
        buttons.addAll(rows(c['buttons']));
      } else if (type == 'CAROUSEL') {
        children.add(
          Text(
            '${rows(c['cards']).length} cards',
            style: const TextStyle(fontSize: 12.5, color: T.muted),
          ),
        );
      }
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: T.outgoing,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    children[i],
                  ],
                ],
              ),
            ),
            for (final b in buttons)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: T.green.withValues(alpha: .15)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      switch ('${b['type']}') {
                        'URL' => Icons.open_in_new,
                        'PHONE_NUMBER' => Icons.call,
                        'COPY_CODE' => Icons.copy,
                        _ => Icons.reply,
                      },
                      size: 16,
                      color: T.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${b['text'] ?? b['type']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: T.green,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _mediaIcon(String kind) => switch (kind) {
  'image' => Icons.image_outlined,
  'video' => Icons.videocam_outlined,
  _ => Icons.description_outlined,
};

/// A media header to upload: what it takes, the chosen file, and the button.
class MediaSlot extends StatelessWidget {
  const MediaSlot({
    super.key,
    required this.label,
    required this.kind,
    required this.onPick,
    this.fileName,
    this.progress,
  });
  final String label, kind;
  final String? fileName;
  final double? progress;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: T.control),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: T.selected,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_mediaIcon(kind), color: T.bronze),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileName ??
                        switch (kind) {
                          'image' => 'JPEG or PNG, up to 5 MB',
                          'video' => 'MP4, up to 16 MB',
                          _ => 'PDF or Office file, up to 100 MB',
                        },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: fileName == null ? T.muted : T.green,
                    ),
                  ),
                ],
              ),
            ),
            AppButton.text(
              onPressed: onPick,
              child: Text(fileName == null ? 'Upload' : 'Replace'),
            ),
          ],
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(value: progress),
          ),
      ],
    ),
  );
}

/// A short tinted note above or below a form.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: danger ? T.danger.withValues(alpha: .08) : T.selected,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          danger ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: danger ? T.danger : T.bronze,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              color: danger ? T.danger : T.bronze,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One template in the picker: its name, category and language, and the
/// start of its message, so the right one is found by reading, not guessing.
class TemplateCard extends StatelessWidget {
  const TemplateCard(this.template, {super.key, this.onTap});
  final Json template;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final parts = templateComponents(template);
    final body = parts
        .where((c) => '${c['type']}'.toUpperCase() == 'BODY')
        .firstOrNull;
    final header = parts
        .where((c) => '${c['type']}'.toUpperCase() == 'HEADER')
        .firstOrNull;
    final media = '${header?['format'] ?? 'TEXT'}'.toUpperCase();
    final text = '${body?['text'] ?? template['body'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: T.edge),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('template-${template['id']}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        templateTitle(template['name']),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: T.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Pill(
                            templateCategory(template['category']),
                            color: T.bronze,
                          ),
                          Text(
                            '${template['language'] ?? ''}'.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: T.muted,
                            ),
                          ),
                          if (['IMAGE', 'VIDEO', 'DOCUMENT'].contains(media))
                            Icon(
                              _mediaIcon(media.toLowerCase()),
                              size: 16,
                              color: T.brass,
                            ),
                        ],
                      ),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TemplateText(
                          text,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: T.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: T.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
