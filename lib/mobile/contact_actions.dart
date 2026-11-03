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

/// A contact's custom fields as one form: change any number of them, then
/// Save sends every change together, or Cancel puts the saved values back.
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

  /// Unsaved edits: field id → input key → value.
  final draft = <String, Map<String, Object?>>{};

  /// Why a field's last save was refused, by field id.
  final refused = <String, String>{};

  /// Replaced on Cancel, so text boxes start again from the saved values.
  var form = GlobalKey<FormState>();
  var saving = false;

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

  List<Json> get fields => data == null ? [] : rows(data!['customFields']);

  Json valueOf(Json field) =>
      object(object(data!['customFieldValues'])['${field['id']}']);

  List<Json> optionsOf(Json field) => [
    for (final v in '${field['option_value'] ?? ''}'.split(','))
      if (v.trim().isNotEmpty) {'id': v.trim(), 'name': v.trim()},
  ];

  /// The inputs a field is edited with, holding its saved values.
  List<EditField> inputsOf(Json field) {
    final spec = FieldSpec.of(field);
    final value = valueOf(field);
    final required = number(field['required']) == 1;
    final name = '${field['name']}';
    final options = optionsOf(field);
    if (spec.input.startsWith('file:')) {
      final saved = readableText(value['name']).isNotEmpty
          ? readableText(value['name'])
          : ('${value['url'] ?? ''}'.isEmpty ? null : 'File attached');
      return [EditField('file', name, value: saved, kind: spec.input)];
    }
    if (spec.input == 'range') {
      return [
        EditField(
          'start_date',
          'From',
          value: value['start_date'],
          kind: 'date',
          required: required,
          hint: 'From',
        ),
        EditField(
          'end_date',
          'To',
          value: value['end_date'],
          kind: 'date',
          hint: 'To',
        ),
      ];
    }
    if (spec.input == 'date' || spec.input == 'datetime') {
      return [
        EditField(
          'start_date',
          name,
          value: value['start_date'],
          kind: spec.input,
          required: required,
        ),
      ];
    }
    return [
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
        lines: spec.input == 'textarea' ? 3 : 1,
        kind: switch (spec.input) {
          'switch' || 'email' || 'number' || 'password' => spec.input,
          _ => 'text',
        },
        hint: switch (spec.input) {
          'list' => 'Separate values with commas',
          'email' => 'name@example.com',
          'number' => '0',
          _ => 'Not set',
        },
      ),
    ];
  }

  Object? current(Json field, EditField input) {
    final edits = draft['${field['id']}'];
    return edits != null && edits.containsKey(input.key)
        ? edits[input.key]
        : input.value;
  }

  /// Values as compared: list order, spacing and null against empty do not
  /// count as changes; a newly chosen file always does.
  static Object same(Object? v) => switch (v) {
    Attachment() => v,
    List() => (v.map((e) => '$e'.trim()).toList()..sort()).join(','),
    _ => '${v ?? ''}'.trim(),
  };

  bool isChanged(Json field) {
    final edits = draft['${field['id']}'];
    if (edits == null) return false;
    return inputsOf(field).any(
      (i) => edits.containsKey(i.key) && same(edits[i.key]) != same(i.value),
    );
  }

  List<Json> get changed => [
    for (final f in fields)
      if (isChanged(f)) f,
  ];

  void edit(Json field, String key, Object? value) => setState(() {
    (draft['${field['id']}'] ??= {})[key] = value;
    refused.remove('${field['id']}');
  });

  void cancel() => setState(() {
    draft.clear();
    refused.clear();
    form = GlobalKey<FormState>();
  });

  /// Sends one field's change; the saved value, or throws.
  Future<Json> send(Json field) async {
    final spec = FieldSpec.of(field);
    final body = <String, dynamic>{
      'contact_id': widget.id,
      'custom_field_id': field['id'],
      'field_type': spec.saveAs,
      for (final i in inputsOf(field)) i.key: current(field, i),
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
    return {
      ...valueOf(field),
      for (final k in ['value', 'start_date', 'end_date'])
        if (body.containsKey(k)) k: body[k],
    };
  }

  /// Saves every changed field at once. Fields the server refuses stay
  /// changed and marked, so they can be fixed and saved again.
  Future<bool> save() async {
    final pending = changed;
    if (pending.isEmpty) return true;
    var valid = form.currentState?.validate() ?? true;
    for (final f in pending) {
      final input = inputsOf(f).first;
      final v = current(f, input);
      if (input.required && input.multiple && (v is! List || v.isEmpty)) {
        refused['${f['id']}'] = 'Choose at least one';
        valid = false;
      }
    }
    if (!valid) {
      setState(() {});
      return false;
    }
    setState(() => saving = true);
    final results = await Future.wait([
      for (final f in pending)
        send(f).then<Object>((v) => v, onError: (Object e) => '$e'),
    ]);
    if (!mounted) return false;
    var files = false;
    setState(() {
      saving = false;
      final values = {...object(data!['customFieldValues'])};
      for (var i = 0; i < pending.length; i++) {
        final id = '${pending[i]['id']}';
        final result = results[i];
        if (result is Json) {
          values[id] = result;
          draft.remove(id);
          files |= FieldSpec.of(pending[i]).input.startsWith('file:');
        } else {
          refused[id] = '$result';
        }
      }
      data = {...data!, 'customFieldValues': values};
    });
    // A stored file's name and link are the server's; fetch them once.
    if (files) await load();
    if (!mounted) return false;
    final failures = results.whereType<String>().length;
    mobileNotice(
      context,
      failures == 0
          ? (pending.length == 1 ? 'Saved' : 'Saved ${pending.length} fields')
          : '${pending.length - failures} of ${pending.length} saved. '
                'Check the marked fields.',
    );
    return failures == 0;
  }

  Future<void> leave() async {
    if (saving) return;
    final n = changed.length;
    final choice = await askToSave(
      context,
      body: n == 1
          ? 'You changed a custom field. Save it before leaving?'
          : 'You changed $n custom fields. Save them before leaving?',
    );
    if (!mounted || choice == null) return;
    if (choice == LeaveChoice.save && !await save()) return;
    if (mounted) Navigator.pop(context);
  }

  Widget label(Json field, {required bool edited}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '${field['name']}',
              children: [
                if (number(field['required']) == 1)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: T.danger),
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
        if (edited)
          const Text(
            'Edited',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: T.brass,
            ),
          ),
      ],
    ),
  );

  Widget input(Json field, EditField i) => FieldInput(
    i,
    value: current(field, i),
    enabled: !saving,
    onChanged: (v) => edit(field, i.key, v),
    onError: (e) => mobileNotice(context, e),
  );

  Widget fieldRow(Json f) {
    final inputs = inputsOf(f);
    final problem = refused['${f['id']}'];
    return Padding(
      key: ValueKey('field-${f['id']}'),
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(f, edited: isChanged(f)),
          for (final (n, i) in inputs.indexed) ...[
            if (n > 0) const SizedBox(height: 8),
            input(f, i),
          ],
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 3),
              child: Text(
                problem,
                style: const TextStyle(fontSize: 12, color: T.danger),
              ),
            ),
        ],
      ),
    );
  }

  Widget? actions(int n) => n == 0 && !saving
      ? null
      : DecoratedBox(
          decoration: const BoxDecoration(
            color: T.surface,
            border: Border(top: BorderSide(color: T.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton.outlined(
                      key: const ValueKey('fields-cancel'),
                      onPressed: saving ? null : cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.filled(
                      key: const ValueKey('fields-save'),
                      onPressed: saving ? null : save,
                      child: saving
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Saving…'),
                              ],
                            )
                          : Text(n > 1 ? 'Save $n changes' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final n = changed.length;
    return PopScope(
      canPop: n == 0 && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: platformAppBar(context, title: const Text('Custom fields')),
        bottomNavigationBar: actions(n),
        body: data == null
            ? error == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : failure(error!, load)
            : RefreshIndicator(
                // A refresh would lose unsaved edits.
                onRefresh: n == 0 ? load : () async {},
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
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Form(
                            key: form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [for (final f in fields) fieldRow(f)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
