import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart';
import 'detail_layout.dart';
import 'media.dart';
import 'message_content.dart' show readableText;
import 'models.dart' show MobileClock, formatPhone;
import 'screens.dart' show failure, mobileNotice, openPage;
import 'shared_media.dart';

class ContactActionsPage extends StatefulWidget {
  const ContactActionsPage(this.session, this.id, {super.key, this.initial});
  final MobileSession session;
  final int id;

  /// Details the caller already holds, shown while a fresh copy loads.
  final Json? initial;
  @override
  State<ContactActionsPage> createState() => _ContactActionsPageState();
}

class _ContactActionsPageState extends State<ContactActionsPage> {
  Json? data;
  String? error;
  bool busy = false;
  MobileApi get api => widget.session.api;
  @override
  void initState() {
    super.initState();
    data = widget.initial;
    load();
  }

  Future<void> load() async {
    try {
      final r = await api.post('inbox/getContactDetails', {
        'contact_id': widget.id,
      });
      if (mounted) {
        setState(() {
          data = object(r['data']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
      if (mounted) await load();
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(
    String title,
    List<EditField> fields,
    Future<void> Function(Json) save,
  ) async {
    await openPage(
      context,
      ActionEditor(title: title, fields: fields, save: save),
    );
  }

  Future<void> mutate(String path, {String method = 'POST', Json? body}) async {
    await api.request(path, method: method, data: body);
  }

  Json get contact => object(data?['contact']);
  bool get closed => number(contact['conversation_status']) == 0;

  void editName() => action(
    () => edit('Edit contact', [
      EditField(
        'profile_name',
        'Name',
        value: contact['profile_name'],
        required: true,
      ),
    ], (v) => mutate('inbox/contacts/${widget.id}/profile', body: v)),
  );

  void assign() => action(() async {
    final multi = data!['multiple_assignment_enabled'] == true;
    final users = rows(data!['users']);
    await edit(
      'Assign contact',
      [
        EditField(
          multi ? 'user_ids' : 'user_id',
          'Assignee',
          value: multi
              ? data!['assigned_user_ids']
              : number(contact['assigned_to']),
          multiple: multi,
          options: multi
              ? users
              : [
                  {'id': 0, 'name': 'Unassigned'},
                  ...users,
                ],
        ),
      ],
      (v) => mutate(
        'inbox/contacts/${widget.id}/assign',
        body: multi ? v : {'user_id': v['user_id'] == 0 ? null : v['user_id']},
      ),
    );
  });

  void favourite() =>
      action(() => mutate('inbox/contacts/${widget.id}/favorite'));

  void closeOrReopen() => action(
    () => mutate(
      'inbox/conversation/${closed ? 'reopen' : 'close'}',
      body: {'contact_id': widget.id},
    ),
  );

  bool can(String mode) =>
      data!['can_${mode == 'block' ? (data!['is_blocked'] == true ? 'unblock' : 'block') : (data!['is_dnd'] == true ? 'remove_dnd' : 'add_dnd')}'] ==
      true;

  void toggle(String mode) => action(() async {
    final remove = data![mode == 'block' ? 'is_blocked' : 'is_dnd'] == true;
    if (await confirmAction(
      context,
      'Update contact',
      '${remove ? 'Remove' : 'Apply'} ${mode == 'block' ? 'WhatsApp blocking' : 'marketing do-not-disturb'} for this contact?',
    )) {
      await mutate(
        'inbox/contacts/${widget.id}/$mode',
        method: remove ? 'DELETE' : 'POST',
      );
    }
  });

  void removeTag(Json tag) => action(
    () => mutate(
      'inbox/contacts/tag/remove',
      body: {'contact_id': widget.id, 'tag_id': tag['id']},
    ),
  );

  void addTag() => action(() async {
    final tags = rows(
      (await api.get('inbox/tags', query: {'contact_id': widget.id}))['data'],
    );
    if (!mounted) return;
    await edit(
      'Add tag',
      [EditField('tag_id', 'Tag', options: tags, required: true)],
      (v) => mutate(
        'inbox/contacts/tag/add',
        body: {'contact_id': widget.id, ...v},
      ),
    );
  });

  void note([Json? existing]) => action(
    () => edit(
      existing == null ? 'Add note' : 'Edit note',
      [
        EditField(
          'note',
          'Note',
          value: existing?['content'],
          required: true,
          lines: 4,
        ),
      ],
      (v) => mutate(
        'inbox/notes',
        body: {
          'contact_id': widget.id,
          if (existing != null) 'note_id': existing['id'],
          ...v,
        },
      ),
    ),
  );

  void deleteNote(Json existing) => action(() async {
    if (await confirmAction(
      context,
      'Delete note',
      'Delete this internal note?',
    )) {
      await mutate('inbox/notes/${existing['id']}', method: 'DELETE');
    }
  });

  /// Opened from a chat, Message simply returns to that conversation.
  void message() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = contact;
    if (data == null) {
      return DetailScaffold(
        title: 'Contact',
        children: [
          SizedBox(
            height: 400,
            child: error == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : failure(error!, load),
          ),
        ],
      );
    }
    final name = '${c['profile_name'] ?? c['waba_profile_name'] ?? ''}';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final assignee = '${object(data!['assignUser'])['name'] ?? 'Unassigned'}';
    final favourite = data!['is_favourite'] == true;
    final notes = rows(data!['notes']);
    final tags = rows(data!['tags']);
    final apple = isCupertino(context);
    return DetailScaffold(
      title: 'Contact',
      busy: busy,
      onRefresh: load,
      actions: [
        AppIconButton(
          tooltip: 'Edit name',
          onPressed: busy ? null : editName,
          icon: const AppIcon(Icons.edit_outlined),
        ),
      ],
      children: [
        DetailHero(
          avatar: initials.isEmpty ? '?' : initials,
          title: name.isEmpty ? formatPhone(c['wa_id']) : name,
          subtitle: formatPhone(c['display_wa_id'] ?? c['wa_id']),
          onTitleTap: busy ? null : editName,
          chips: [
            StatusChip(
              closed ? 'Closed' : 'Open',
              icon: closed ? Icons.lock_outline : Icons.schedule,
              positive: !closed,
            ),
            StatusChip(
              assignee == 'Unassigned' ? 'Unassigned' : 'Assigned to $assignee',
              icon: Icons.person_outline,
            ),
            if (favourite)
              const StatusChip('Favourite', icon: Icons.star_rounded),
          ],
          actions: [
            QuickAction(Icons.chat_outlined, 'Message', message, primary: true),
            QuickAction(
              favourite ? Icons.star_rounded : Icons.star_border_rounded,
              favourite ? 'Unfavourite' : 'Favourite',
              busy ? null : this.favourite,
            ),
            if (data!['can_assign_contact'] == true)
              QuickAction(
                Icons.person_add_alt_1_outlined,
                'Assign',
                busy ? null : assign,
              ),
            QuickAction(
              closed ? Icons.replay : Icons.task_alt,
              closed ? 'Reopen' : 'Close',
              busy ? null : closeOrReopen,
            ),
          ],
        ),
        DetailSection(
          title: 'Conversation',
          children: [
            DetailRow(
              icon: Icons.person_outline,
              label: 'Assigned to',
              value: assignee,
              onTap: data!['can_assign_contact'] == true && !busy
                  ? assign
                  : null,
            ),
            DetailRow(
              icon: closed ? Icons.lock_outline : Icons.schedule,
              tile: closed ? T.muted : T.green,
              label: 'Status',
              value: closed ? 'Closed' : 'Open',
            ),
          ],
        ),
        DetailSection(
          title: 'Tags',
          children: [
            TagWrap(
              tags: [for (final t in tags) '${t['name']}'],
              onRemove: busy ? null : (i) => removeTag(tags[i]),
              onAdd: busy ? null : addTag,
            ),
          ],
        ),
        DetailSection(
          title: 'Notes',
          action: 'Add',
          onAction: busy ? null : note,
          children: [
            if (notes.isEmpty)
              const DetailRow(
                icon: Icons.sticky_note_2_outlined,
                label: 'No notes yet',
              ),
            for (final n in notes)
              DetailRow(
                icon: Icons.sticky_note_2_outlined,
                label: '${n['content'] ?? ''}',
                subtitle: [
                  readableText(object(n['user'])['name']),
                  const MobileClock().listTime(n['created_at']),
                ].where((p) => p.isNotEmpty).join(' · '),
                onTap: busy ? null : () => note(n),
                trailing: AppIconButton(
                  tooltip: 'Delete note',
                  onPressed: busy ? null : () => deleteNote(n),
                  icon: AppIcon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: apple ? T.danger : T.muted,
                  ),
                ),
              ),
          ],
        ),
        DetailSection(
          title: 'More',
          children: [
            DetailRow(
              icon: Icons.tune_outlined,
              label: 'Details',
              subtitle: 'Custom fields',
              onTap: () => openPage(
                context,
                ContactFieldsPage(widget.session, widget.id),
              ),
            ),
            for (final (kind, icon) in [
              (SharedKind.media, Icons.photo_library_outlined),
              (SharedKind.documents, Icons.description_outlined),
              (SharedKind.links, Icons.link),
            ])
              DetailRow(
                icon: icon,
                label: kind.label,
                onTap: () => openPage(
                  context,
                  MediaGalleryPage(
                    widget.session,
                    contactId: widget.id,
                    initial: kind,
                  ),
                ),
              ),
          ],
        ),
        if (can('dnd') || can('block'))
          DetailSection(
            title: 'Privacy',
            children: [
              if (can('dnd'))
                DetailRow(
                  icon: Icons.do_not_disturb_on_outlined,
                  label: 'Marketing do not disturb',
                  trailing: Switch.adaptive(
                    value: data!['is_dnd'] == true,
                    onChanged: busy ? null : (_) => toggle('dnd'),
                  ),
                ),
              if (can('block'))
                DetailRow(
                  icon: Icons.block,
                  label: data!['is_blocked'] == true
                      ? 'Unblock contact'
                      : 'Block contact',
                  destructive: data!['is_blocked'] != true,
                  onTap: busy ? null : () => toggle('block'),
                ),
            ],
          ),
      ],
    );
  }
}

class ContactFieldsPage extends StatefulWidget {
  const ContactFieldsPage(this.session, this.id, {super.key});
  final MobileSession session;
  final int id;
  @override
  State<ContactFieldsPage> createState() => _ContactFieldsPageState();
}

class _ContactFieldsPageState extends State<ContactFieldsPage> {
  Json? data;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get(
        'inbox/custom-fields',
        query: {'contact_id': widget.id},
      );
      if (mounted) {
        setState(() {
          data = object(r['data']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> edit(Json field) async {
    final type = number(field['type']);
    final value = object(object(data!['customFieldValues'])['${field['id']}']);
    final kind = switch (type) {
      2 => 'textarea',
      3 || 12 || 13 => 'select',
      4 || 10 || 11 => 'multi_select',
      5 || 6 => 'date',
      7 => 'date_range',
      15 => 'image',
      16 => 'file',
      17 => 'video',
      _ => 'text',
    };
    final options = '${field['option_value'] ?? ''}'
        .split(',')
        .where((v) => v.isNotEmpty)
        .map((v) => <String, dynamic>{'id': v.trim(), 'name': v.trim()})
        .toList();
    final fields = <EditField>[
      if (['image', 'file', 'video'].contains(kind))
        EditField(
          'file',
          'File',
          kind: 'file:${kind == 'file' ? 'document' : kind}',
          required: true,
        )
      else if (kind == 'date' || kind == 'date_range') ...[
        EditField(
          'start_date',
          'Start date',
          value: value['start_date'],
          kind: 'date',
          required: number(field['required']) == 1,
        ),
        if (kind == 'date_range')
          EditField(
            'end_date',
            'End date',
            value: value['end_date'],
            kind: 'date',
          ),
      ] else
        EditField(
          'value',
          '${field['name']}',
          value: kind == 'multi_select'
              ? '${value['value'] ?? ''}'
                    .split(',')
                    .where((s) => s.isNotEmpty)
                    .toList()
              : value['value'],
          required: number(field['required']) == 1,
          options: options.isEmpty ? null : options,
          multiple: kind == 'multi_select',
          lines: kind == 'textarea' ? 4 : 1,
        ),
    ];
    await openPage(
      context,
      ActionEditor(
        title: '${field['name']}',
        fields: fields,
        save: (values) async {
          final body = <String, dynamic>{
            'contact_id': widget.id,
            'custom_field_id': field['id'],
            'field_type': kind,
            ...values,
          };
          if (body['value'] is List) {
            body['value'] = (body['value'] as List).join(',');
          }
          if (body['file'] is Attachment) {
            body['file'] = (body['file'] as Attachment).multipart();
            await widget.session.api.request(
              'inbox/custom-fields/update',
              method: 'POST',
              data: FormData.fromMap(body),
            );
          } else {
            await widget.session.api.post('inbox/custom-fields/update', body);
          }
        },
      ),
    );
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Custom fields')),
    body: data == null
        ? error == null
              ? const Center(child: CircularProgressIndicator())
              : failure(error!, load)
        : ListView(
            children: [
              if (rows(data!['customFields']).isEmpty)
                const ListTile(title: Text('No custom fields')),
              for (final f in rows(data!['customFields']))
                AppListTile(
                  title: Text('${f['name']}'),
                  subtitle: Text(
                    '${object(object(data!['customFieldValues'])['${f['id']}'])['value'] ?? object(object(data!['customFieldValues'])['${f['id']}'])['name'] ?? object(object(data!['customFieldValues'])['${f['id']}'])['start_date'] ?? 'Not set'}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => edit(f),
                ),
            ],
          ),
  );
}
