import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'media.dart';
import 'template_plan.dart';
import 'send_policy.dart';
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
      final permissionData = await Future.wait([
        widget.session.api.post('inbox/getContactDetails', {
          'contact_id': widget.contact['id'],
        }),
        if (widget.ticketId != null)
          widget.session.api.post('inbox/ticket_details', {
            'ticket_id': widget.ticketId,
          }),
      ]);
      if (flag(object(permissionData.first['data'])['is_dnd']) &&
          plan!.template['category'] == 'MARKETING') {
        throw const ApiFailure(
          'This contact has opted out of marketing. Choose a utility or authentication template.',
        );
      }
      final permission = SendPolicy.evaluate(
        widget.session,
        object(permissionData.first['data']),
        ticket: widget.ticketId == null
            ? null
            : object(object(permissionData.last['data'])['ticket']),
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.template['name']}')),
    body: plan == null
        ? error == null
              ? const Center(child: CircularProgressIndicator())
              : failure(error!, load)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final text in plan!.previews)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(text),
                ),
              const Divider(),
              if (retryBody != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'The previous send is not confirmed. Retry sends the original values safely.',
                  ),
                ),
              AbsorbPointer(
                absorbing: busy || retryBody != null,
                child: Column(
                  children: [
                    for (final f in plan!.inputs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ['image', 'video', 'document'].contains(f.kind)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(f.label),
                                  AppButton.outlined(
                                    onPressed: () => upload(f),
                                    child: Text(
                                      object(
                                            values[f.key],
                                          )['new_file_name']?.toString() ??
                                          'Choose and upload ${f.kind}',
                                    ),
                                  ),
                                ],
                              )
                            : AppTextFormField(
                                decoration: InputDecoration(labelText: f.label),
                                onChanged: (v) => values[f.key] = v,
                              ),
                      ),
                  ],
                ),
              ),
              if (progress != null) LinearProgressIndicator(value: progress),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(error!, style: const TextStyle(color: T.danger)),
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
  );
}
