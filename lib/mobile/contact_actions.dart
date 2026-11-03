import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart';
import 'detail_layout.dart';
import 'media.dart';
import 'notes.dart';
import 'message_content.dart' show readableText;
import 'models.dart' show formatPhone;
import 'screens.dart' show failure, mobileNotice, openPage;
import 'shared_media.dart';
import 'call_history.dart';
import 'calls.dart' show callEligibility;
import 'conversation_window.dart';

class ContactActionsPage extends StatefulWidget {
  const ContactActionsPage(
    this.session,
    this.id, {
    super.key,
    this.initial,
    this.windowExpires,
  });
  final MobileSession session;
  final int id;

  /// When the chat's conversation window closes, as the open chat knows it.
  final DateTime? windowExpires;

  /// Details the caller already holds, shown while a fresh copy loads.
  final Json? initial;
  @override
  State<ContactActionsPage> createState() => _ContactActionsPageState();
}

class _ContactActionsPageState extends State<ContactActionsPage> {
  Json? data;
  String? error;
  MobileApi get api => widget.session.api;

  /// Sections with a change in flight. Only that section waits; the rest of
  /// the page stays as it is, so nothing flickers.
  final saving = <String>{};

  /// Bumped by every local change, so a reload that started before it cannot
  /// put the older server copy back over it.
  int version = 0;

  @override
  void initState() {
    super.initState();
    data = widget.initial;
    load();
  }

  Future<void> load() async {
    final started = version;
    try {
      final r = await api.post('inbox/getContactDetails', {
        'contact_id': widget.id,
      });
      if (mounted && started == version) {
        setState(() {
          data = object(r['data']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted && data == null) setState(() => error = '$e');
    }
  }

  /// Applies [changes] to the details shown, at once.
  void patch(Json changes) {
    if (!mounted) return;
    version++;
    setState(() => data = {...?data, ...changes});
  }

  void patchContact(Json changes) => patch({
    'contact': {...contact, ...changes},
  });

  /// Runs one section's change. [optimistic] shows the result before the
  /// server answers; a failure puts back what was there and says why.
  Future<void> change(
    String section,
    Future<void> Function() work, {
    VoidCallback? optimistic,
    bool reload = false,
  }) async {
    if (saving.contains(section)) return;
    final before = data;
    setState(() => saving.add(section));
    optimistic?.call();
    try {
      await work();
      // Only where the server works out more than the one value changed.
      if (reload && mounted) await load();
    } catch (e) {
      if (mounted) {
        version++;
        setState(() => data = before);
        mobileNotice(context, e);
      }
    } finally {
      if (mounted) setState(() => saving.remove(section));
    }
  }

  Json get contact => object(data?['contact']);
  bool get closed => number(contact['conversation_status']) == 0;

  /// The later of what the details say and what the open chat saw.
  DateTime? get windowExpires {
    final dates = [?windowExpiresAt(contact), ?widget.windowExpires]..sort();
    return dates.lastOrNull;
  }

  Widget? spinner(String section) => saving.contains(section)
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : null;

  Future<void> editName() => showEditorSheet(
    context,
    title: 'Contact name',
    fields: [
      EditField(
        'profile_name',
        'Name',
        value: '${contact['profile_name'] ?? ''}',
        required: true,
        hint: 'Contact name',
      ),
    ],
    save: (v) async {
      final name = '${v['profile_name']}'.trim();
      if (name == '${contact['profile_name'] ?? ''}') return;
      await api.request(
        'inbox/contacts/${widget.id}/profile',
        method: 'POST',
        data: {'profile_name': name},
      );
      patchContact({'profile_name': name});
    },
  );

  Future<void> setStatus(bool open) => change(
    'status',
    () => api.request(
      'inbox/conversation/${open ? 'reopen' : 'close'}',
      method: 'POST',
      data: {'contact_id': widget.id},
    ),
    optimistic: () => patchContact({'conversation_status': open ? 1 : 0}),
  );

  Future<void> status() => showEditorSheet(
    context,
    title: 'Conversation status',
    fields: [
      EditField(
        'status',
        'Status',
        value: closed ? 0 : 1,
        required: true,
        options: const [
          {'id': 1, 'name': 'Open'},
          {'id': 0, 'name': 'Closed'},
        ],
      ),
    ],
    // The sheet waits for the save; the page shows it the moment it lands.
    save: (v) async {
      await api.request(
        'inbox/conversation/${v['status'] == 0 ? 'close' : 'reopen'}',
        method: 'POST',
        data: {'contact_id': widget.id},
      );
      patchContact({'conversation_status': v['status'] == 0 ? 0 : 1});
    },
  );

  Future<void> assign() async {
    final multi = data!['multiple_assignment_enabled'] == true;
    final users = rows(data!['users']);
    await showEditorSheet(
      context,
      title: 'Assign contact',
      fields: [
        EditField(
          multi ? 'user_ids' : 'user_id',
          'Assignee',
          value: multi
              ? data!['assigned_user_ids']
              : number(contact['assigned_to']) ?? 0,
          multiple: multi,
          options: multi
              ? users
              : [
                  {'id': 0, 'name': 'Unassigned'},
                  ...users,
                ],
        ),
      ],
      save: (v) async {
        final r = object(
          await api.request(
            'inbox/contacts/${widget.id}/assign',
            method: 'POST',
            data: multi
                ? v
                : {'user_id': v['user_id'] == 0 ? null : v['user_id']},
          ),
        );
        // The server answers with what it saved: the contact and assignee.
        final saved = object(r['data']);
        final ids = multi ? List.of(v['user_ids'] as List) : null;
        patch({
          if (saved['contact'] is Map)
            'contact': {...contact, ...object(saved['contact'])},
          if (!multi) 'assignUser': saved['assignUser'],
          if (multi) 'assigned_user_ids': ids,
          if (multi)
            'assignUser': users
                .where((u) => ids!.contains(u['id']))
                .firstOrNull,
        });
      },
    );
  }

  Future<void> favourite() {
    final now = data!['is_favourite'] == true;
    return change(
      'favourite',
      () => api.request('inbox/contacts/${widget.id}/favorite', method: 'POST'),
      optimistic: () => patch({'is_favourite': !now}),
    );
  }

  bool can(String mode) =>
      data!['can_${mode == 'block' ? (data!['is_blocked'] == true ? 'unblock' : 'block') : (data!['is_dnd'] == true ? 'remove_dnd' : 'add_dnd')}'] ==
      true;

  Future<void> toggle(String mode) async {
    final remove = data![mode == 'block' ? 'is_blocked' : 'is_dnd'] == true;
    if (!await confirmAction(
      context,
      'Update contact',
      '${remove ? 'Remove' : 'Apply'} ${mode == 'block' ? 'WhatsApp blocking' : 'marketing do-not-disturb'} for this contact?',
    )) {
      return;
    }
    // Which of block/unblock the user may do next is the server's call.
    await change(
      mode,
      () => api.request(
        'inbox/contacts/${widget.id}/$mode',
        method: remove ? 'DELETE' : 'POST',
      ),
      reload: true,
    );
  }

  List<Json> get tags => rows(data!['tags']);

  Future<void> removeTag(Json tag) => change(
    'tags',
    () => api.request(
      'inbox/contacts/tag/remove',
      method: 'POST',
      data: {'contact_id': widget.id, 'tag_id': tag['id']},
    ),
    optimistic: () =>
        patch({'tags': tags.where((t) => t['id'] != tag['id']).toList()}),
  );

  Future<void> addTag() async {
    late final List<Json> options;
    try {
      setState(() => saving.add('tags'));
      options = rows(
        (await api.get('inbox/tags', query: {'contact_id': widget.id}))['data'],
      );
    } catch (e) {
      if (mounted) mobileNotice(context, e);
      return;
    } finally {
      if (mounted) setState(() => saving.remove('tags'));
    }
    if (!mounted) return;
    final have = {for (final t in tags) t['id']};
    await showEditorSheet(
      context,
      title: 'Add tag',
      fields: [
        EditField(
          'tag_id',
          'Tag',
          options: [...options.where((o) => !have.contains(o['id']))],
          required: true,
        ),
      ],
      save: (v) async {
        await api.request(
          'inbox/contacts/tag/add',
          method: 'POST',
          data: {'contact_id': widget.id, ...v},
        );
        patch({
          'tags': [...tags, options.firstWhere((o) => o['id'] == v['tag_id'])],
        });
      },
    );
  }

  List<Json> get notes => rows(data!['notes']);

  Future<void> openNotes() => openPage(
    context,
    NotesPage(
      widget.session,
      widget.id,
      initial: notes,
      onChanged: (next) => patch({'notes': next}),
    ),
  );

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
    final canAssign = data!['can_assign_contact'] == true;
    final notes = this.notes;
    final latest = notes.isEmpty ? null : readableText(notes.first['content']);
    return DetailScaffold(
      title: 'Contact',
      onRefresh: load,
      actions: [
        AppIconButton(
          tooltip: 'Edit name',
          onPressed: editName,
          icon: const AppIcon(Icons.edit_outlined),
        ),
      ],
      children: [
        ConversationWindow(
          expiresAt: windowExpires,
          builder: (context, open) => DetailHero(
            avatar: initials.isEmpty ? '?' : initials,
            title: name.isEmpty ? formatPhone(c['wa_id']) : name,
            subtitle: formatPhone(c['display_wa_id'] ?? c['wa_id']),
            onTitleTap: editName,
            online: open,
            status: open
                ? switch (windowLabel(windowExpires)) {
                    'Open' => 'Window open',
                    final left => 'Window open · $left',
                  }
                : null,
            chips: [
              StatusChip(
                closed ? 'Closed' : 'Open',
                icon: closed ? Icons.lock_outline : Icons.schedule,
                positive: !closed,
                onTap: saving.contains('status') ? null : status,
              ),
              StatusChip(
                assignee == 'Unassigned'
                    ? 'Unassigned'
                    : 'Assigned to $assignee',
                icon: Icons.person_outline,
                onTap: canAssign ? assign : null,
              ),
              if (favourite)
                const StatusChip('Favourite', icon: Icons.star_rounded),
            ],
            actions: [
              QuickAction(
                Icons.chat_outlined,
                'Message',
                message,
                primary: true,
              ),
              QuickAction(
                favourite ? Icons.star_rounded : Icons.star_border_rounded,
                favourite ? 'Unfavourite' : 'Favourite',
                saving.contains('favourite') ? null : this.favourite,
              ),
              if (canAssign)
                QuickAction(Icons.person_add_alt_1_outlined, 'Assign', assign),
              QuickAction(
                closed ? Icons.replay : Icons.task_alt,
                closed ? 'Reopen' : 'Close',
                saving.contains('status') ? null : () => setStatus(closed),
              ),
            ],
          ),
        ),
        DetailSection(
          title: 'Conversation',
          children: [
            DetailRow(
              icon: Icons.person_outline,
              label: 'Assigned to',
              value: assignee,
              onTap: canAssign ? assign : null,
            ),
            DetailRow(
              icon: closed ? Icons.lock_outline : Icons.schedule,
              tile: closed ? T.muted : T.green,
              label: 'Status',
              value: saving.contains('status')
                  ? null
                  : closed
                  ? 'Closed'
                  : 'Open',
              trailing: spinner('status'),
              onTap: saving.contains('status') ? null : status,
            ),
          ],
        ),
        DetailSection(
          title: 'Tags',
          children: [
            TagWrap(
              tags: [for (final t in tags) '${t['name']}'],
              onRemove: saving.contains('tags')
                  ? null
                  : (i) => removeTag(tags[i]),
              onAdd: saving.contains('tags') ? null : addTag,
            ),
          ],
        ),
        DetailSection(
          title: 'More',
          children: [
            DetailRow(
              key: const ValueKey('notes-row'),
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              subtitle: latest == null
                  ? 'No notes yet'
                  : '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} · ${latest.replaceAll('\n', ' ')}',
              subtitleLines: 1,
              onTap: openNotes,
            ),
            DetailRow(
              icon: Icons.tune_outlined,
              label: 'Custom fields',
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
            if (callEligibility(widget.session.config, contact).shown)
              DetailRow(
                icon: Icons.history,
                label: 'Call history',
                onTap: () => openPage(
                  context,
                  CallHistoryPage(widget.session, {
                    ...contact,
                    'id': widget.id,
                  }),
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
                  trailing:
                      spinner('dnd') ??
                      Switch.adaptive(
                        value: data!['is_dnd'] == true,
                        onChanged: (_) => toggle('dnd'),
                      ),
                ),
              if (can('block'))
                DetailRow(
                  icon: Icons.block,
                  label: data!['is_blocked'] == true
                      ? 'Unblock contact'
                      : 'Block contact',
                  destructive: data!['is_blocked'] != true,
                  trailing: spinner('block'),
                  onTap: saving.contains('block')
                      ? null
                      : () => toggle('block'),
                ),
            ],
          ),
      ],
    );
  }
}

/// How one custom field type (config/customfield.php) is edited and saved:
/// the update endpoint's field_type, the editor input, and its icon.
class FieldSpec {
  const FieldSpec(this.saveAs, this.input, this.icon, {this.choice = false});
  final String saveAs, input;
  final IconData icon;

  /// Picked from the field's own options.
  final bool choice;

  static FieldSpec of(Json field) => switch (number(field['type'])) {
    2 => const FieldSpec('textarea', 'textarea', Icons.notes),
    3 ||
    12 => const FieldSpec('select', 'select', Icons.expand_more, choice: true),
    13 => const FieldSpec('select', 'switch', Icons.toggle_on_outlined),
    4 || 10 => const FieldSpec(
      'multi_select',
      'multi',
      Icons.checklist,
      choice: true,
    ),
    11 => const FieldSpec('multi_select', 'list', Icons.list),
    5 => const FieldSpec('date', 'datetime', Icons.event_outlined),
    6 => const FieldSpec('date', 'date', Icons.calendar_today_outlined),
    7 => const FieldSpec('date_range', 'range', Icons.date_range_outlined),
    8 => const FieldSpec('text', 'password', Icons.lock_outline),
    9 => const FieldSpec('text', 'email', Icons.alternate_email),
    14 => const FieldSpec('text', 'number', Icons.pin_outlined),
    15 => const FieldSpec('image', 'file:image', Icons.image_outlined),
    16 => const FieldSpec('file', 'file:document', Icons.attach_file),
    17 => const FieldSpec('video', 'file:video', Icons.videocam_outlined),
    _ => const FieldSpec('text', 'text', Icons.short_text),
  };
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
      if (mounted && data == null) setState(() => error = '$e');
    }
  }

  Json valueOf(Json field) =>
      object(object(data!['customFieldValues'])['${field['id']}']);

  List<Json> optionsOf(Json field) => [
    for (final v in '${field['option_value'] ?? ''}'.split(','))
      if (v.trim().isNotEmpty) {'id': v.trim(), 'name': v.trim()},
  ];

  /// The saved value as it reads in the list, or null when there is none.
  String? shown(Json field) {
    final spec = FieldSpec.of(field);
    final v = valueOf(field);
    final text = readableText(v['value']);
    return switch (spec.input) {
      'switch' => text == '1' ? 'On' : (v.isEmpty ? null : 'Off'),
      'password' => text.isEmpty ? null : '••••••••',
      'multi' || 'list' =>
        text.isEmpty ? null : text.split(',').map((s) => s.trim()).join(', '),
      'date' || 'datetime' =>
        '${v['start_date'] ?? ''}'.isEmpty
            ? null
            : shownDate('${v['start_date']}', time: spec.input == 'datetime'),
      'range' =>
        '${v['start_date'] ?? ''}'.isEmpty
            ? null
            : [
                shownDate('${v['start_date']}'),
                if ('${v['end_date'] ?? ''}'.isNotEmpty)
                  shownDate('${v['end_date']}'),
              ].join(' – '),
      _ when spec.input.startsWith('file:') =>
        readableText(v['name']).isNotEmpty
            ? readableText(v['name'])
            : ('${v['url'] ?? ''}'.isEmpty ? null : 'File attached'),
      _ => text.isEmpty ? null : text,
    };
  }

  Future<void> edit(Json field) async {
    final spec = FieldSpec.of(field);
    final value = valueOf(field);
    final required = number(field['required']) == 1;
    final name = '${field['name']}';
    final options = optionsOf(field);
    final fields = <EditField>[
      if (spec.input.startsWith('file:'))
        EditField('file', name, kind: spec.input, required: true)
      else if (spec.input == 'range') ...[
        EditField(
          'start_date',
          'From',
          value: value['start_date'],
          kind: 'date',
          required: required,
        ),
        EditField('end_date', 'To', value: value['end_date'], kind: 'date'),
      ] else if (spec.input == 'date' || spec.input == 'datetime')
        EditField(
          'start_date',
          name,
          value: value['start_date'],
          kind: spec.input,
          required: required,
        )
      else
        EditField(
          'value',
          name,
          value: switch (spec.input) {
            'multi' =>
              '${value['value'] ?? ''}'
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            'switch' => '${value['value'] ?? '0'}',
            _ => value['value'],
          },
          required: required,
          options: spec.choice && options.isNotEmpty ? options : null,
          multiple: spec.input == 'multi',
          lines: spec.input == 'textarea' ? 4 : 1,
          kind: switch (spec.input) {
            'switch' || 'email' || 'number' || 'password' => spec.input,
            _ => 'text',
          },
          hint: switch (spec.input) {
            'list' => 'Separate values with commas',
            'email' => 'name@example.com',
            'textarea' => 'Write $name',
            _ => null,
          },
        ),
    ];
    Json? saved;
    await showEditorSheet(
      context,
      title: name,
      fields: fields,
      save: (values) async {
        final body = <String, dynamic>{
          'contact_id': widget.id,
          'custom_field_id': field['id'],
          'field_type': spec.saveAs,
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
        saved = {
          ...value,
          for (final k in ['value', 'start_date', 'end_date'])
            if (body.containsKey(k)) k: body[k],
        };
      },
    );
    if (saved == null || !mounted) return;
    if (spec.input.startsWith('file:')) {
      // The stored name and link are the server's; fetch them.
      await load();
      return;
    }
    // Only this field's value changes; the rest of the form stays put.
    setState(() {
      data = {
        ...data!,
        'customFieldValues': {
          ...object(data!['customFieldValues']),
          '${field['id']}': saved,
        },
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = data == null ? <Json>[] : rows(data!['customFields']);
    return Scaffold(
      appBar: platformAppBar(context, title: const Text('Custom fields')),
      body: data == null
          ? error == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : failure(error!, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  if (fields.isEmpty)
                    const EmptyView(
                      title: 'No custom fields',
                      description: 'Custom fields are set up on the web, under Settings.',
                      icon: Icons.tune_outlined,
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final f in fields)
                              Padding(
                                key: ValueKey('field-${f['id']}'),
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Text.rich(
                                        TextSpan(
                                          text: '${f['name']}',
                                          children: [
                                            if (number(f['required']) == 1)
                                              const TextSpan(
                                                text: ' *',
                                                style: TextStyle(
                                                  color: T.danger,
                                                ),
                                              ),
                                          ],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: T.secondary,
                                        ),
                                      ),
                                    ),
                                    FieldBox(
                                      text: shown(f),
                                      hint: 'Not set',
                                      icon: FieldSpec.of(f).icon,
                                      lines: FieldSpec.of(f).input == 'textarea'
                                          ? 3
                                          : 1,
                                      onTap: () => edit(f),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
