import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart';
import 'media.dart';
import 'screens.dart' show failure, mobileNotice, openPage;

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

  @override
  Widget build(BuildContext context) {
    final c = object(data?['contact']);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact details')),
      body: data == null
          ? error == null
                ? const Center(child: CircularProgressIndicator())
                : failure(error!, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Text(
                    '${c['profile_name'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${c['display_wa_id'] ?? c['wa_id'] ?? ''}'),
                  AppListTile(
                    title: const Text('Edit contact name'),
                    leading: const Icon(Icons.edit_outlined),
                    onTap: busy
                        ? null
                        : () => action(
                            () => edit(
                              'Edit contact',
                              [
                                EditField(
                                  'profile_name',
                                  'Name',
                                  value: c['profile_name'],
                                  required: true,
                                ),
                              ],
                              (v) => mutate(
                                'inbox/contacts/${widget.id}/profile',
                                body: v,
                              ),
                            ),
                          ),
                  ),
                  if (data!['can_assign_contact'] == true)
                    AppListTile(
                      title: const Text('Assignment'),
                      subtitle: Text(
                        '${object(data!['assignUser'])['name'] ?? 'Unassigned'}',
                      ),
                      onTap: busy
                          ? null
                          : () => action(() async {
                              final multi =
                                  data!['multiple_assignment_enabled'] == true;
                              final users = rows(data!['users']);
                              await edit(
                                'Assign contact',
                                [
                                  EditField(
                                    multi ? 'user_ids' : 'user_id',
                                    'Assignee',
                                    value: multi
                                        ? data!['assigned_user_ids']
                                        : number(c['assigned_to']),
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
                                  body: multi
                                      ? v
                                      : {
                                          'user_id': v['user_id'] == 0
                                              ? null
                                              : v['user_id'],
                                        },
                                ),
                              );
                            }),
                    ),
                  AppListTile(
                    title: Text(
                      data!['is_favourite'] == true
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                    ),
                    leading: const Icon(Icons.star_outline),
                    onTap: busy
                        ? null
                        : () => action(
                            () =>
                                mutate('inbox/contacts/${widget.id}/favorite'),
                          ),
                  ),
                  AppListTile(
                    title: Text(
                      number(c['conversation_status']) == 0
                          ? 'Reopen conversation'
                          : 'Close conversation',
                    ),
                    onTap: busy
                        ? null
                        : () => action(
                            () => mutate(
                              'inbox/conversation/${number(c['conversation_status']) == 0 ? 'reopen' : 'close'}',
                              body: {'contact_id': widget.id},
                            ),
                          ),
                  ),
                  for (final mode in ['block', 'dnd'])
                    if (data!['can_${mode == 'block' ? (data!['is_blocked'] == true ? 'unblock' : 'block') : (data!['is_dnd'] == true ? 'remove_dnd' : 'add_dnd')}'] ==
                        true)
                      AppListTile(
                        title: Text(
                          mode == 'block'
                              ? (data!['is_blocked'] == true
                                    ? 'Unblock contact'
                                    : 'Block contact')
                              : (data!['is_dnd'] == true
                                    ? 'Remove marketing DND'
                                    : 'Add marketing DND'),
                        ),
                        onTap: busy
                            ? null
                            : () => action(() async {
                                final remove =
                                    data![mode == 'block'
                                        ? 'is_blocked'
                                        : 'is_dnd'] ==
                                    true;
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
                              }),
                      ),
                  const Section('Tags'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in rows(data!['tags']))
                        InputChip(
                          label: Text('${tag['name']}'),
                          onDeleted: busy
                              ? null
                              : () => action(
                                  () => mutate(
                                    'inbox/contacts/tag/remove',
                                    body: {
                                      'contact_id': widget.id,
                                      'tag_id': tag['id'],
                                    },
                                  ),
                                ),
                        ),
                    ],
                  ),
                  AppButton.text(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            final tags = rows(
                              (await api.get(
                                'inbox/tags',
                                query: {'contact_id': widget.id},
                              ))['data'],
                            );
                            if (!mounted) return;
                            await edit(
                              'Add tag',
                              [
                                EditField(
                                  'tag_id',
                                  'Tag',
                                  options: tags,
                                  required: true,
                                ),
                              ],
                              (v) => mutate(
                                'inbox/contacts/tag/add',
                                body: {'contact_id': widget.id, ...v},
                              ),
                            );
                          }),
                    child: const Text('Add existing tag'),
                  ),
                  const Section('Internal notes'),
                  for (final note in rows(data!['notes']))
                    AppListTile(
                      title: Text('${note['content'] ?? ''}'),
                      subtitle: Text('${object(note['user'])['name'] ?? ''}'),
                      onTap: busy
                          ? null
                          : () => action(
                              () => edit(
                                'Edit note',
                                [
                                  EditField(
                                    'note',
                                    'Note',
                                    value: note['content'],
                                    required: true,
                                    lines: 4,
                                  ),
                                ],
                                (v) => mutate(
                                  'inbox/notes',
                                  body: {
                                    'contact_id': widget.id,
                                    'note_id': note['id'],
                                    ...v,
                                  },
                                ),
                              ),
                            ),
                      trailing: AppIconButton(
                        tooltip: 'Delete note',
                        onPressed: busy
                            ? null
                            : () => action(() async {
                                if (await confirmAction(
                                  context,
                                  'Delete note',
                                  'Delete this internal note?',
                                )) {
                                  await mutate(
                                    'inbox/notes/${note['id']}',
                                    method: 'DELETE',
                                  );
                                }
                              }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  AppButton.text(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => edit(
                              'Add note',
                              [
                                const EditField(
                                  'note',
                                  'Note',
                                  required: true,
                                  lines: 4,
                                ),
                              ],
                              (v) => mutate(
                                'inbox/notes',
                                body: {'contact_id': widget.id, ...v},
                              ),
                            ),
                          ),
                    child: const Text('Add note'),
                  ),
                  AppListTile(
                    title: const Text('Custom fields'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPage(
                      context,
                      ContactFieldsPage(widget.session, widget.id),
                    ),
                  ),
                  AppListTile(
                    title: const Text('Shared media and documents'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPage(
                      context,
                      MediaGalleryPage(widget.session, contactId: widget.id),
                    ),
                  ),
                ],
              ),
            ),
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

class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage(
    this.session, {
    super.key,
    this.contactId,
    this.ticketId,
  });
  final MobileSession session;
  final int? contactId, ticketId;
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  String type = 'media';
  int serial = 0;
  List<Json>? items;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final request = ++serial;
    setState(() {
      items = null;
      error = null;
    });
    try {
      final r = widget.ticketId == null
          ? await widget.session.api.post('inbox/getMediaData', {
              'contact_id': widget.contactId,
              'type': type,
            })
          : await widget.session.api.post(
              'inbox/tickets/${widget.ticketId}/media-data',
              {'type': type},
            );
      if (mounted && request == serial) setState(() => items = rows(r['data']));
    } catch (e) {
      if (mounted && request == serial) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shared media')),
    body: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final t in ['media', 'document', 'link'])
              ChoiceChip(
                label: Text(t),
                selected: type == t,
                onSelected: (_) {
                  type = t;
                  load();
                },
              ),
          ],
        ),
        Expanded(
          child: items == null
              ? error == null
                    ? const Center(child: CircularProgressIndicator())
                    : failure(error!, load)
              : ListView(
                  children: [
                    if (items!.isEmpty)
                      const ListTile(title: Text('No shared media')),
                    for (final i in items!)
                      if (mediaUri(
                            i['media_link'],
                            widget.session.api.dio.options.baseUrl,
                          )
                          case final Uri url)
                        MediaTile(
                          MessageMedia(
                            '${i['type']}',
                            url,
                            '${i['media_name'] ?? 'Media'}',
                          ),
                        ),
                  ],
                ),
        ),
      ],
    ),
  );
}
