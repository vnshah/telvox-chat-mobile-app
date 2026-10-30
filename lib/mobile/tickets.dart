import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'chat.dart' show LiveChat;
import 'contact_actions.dart' show MediaGalleryPage;
import 'editors.dart';
import 'realtime.dart';
import 'screens.dart' show LoadingBar, failure, mobileNotice, openPage;

class TicketPage extends StatefulWidget {
  const TicketPage(this.session, this.id, {super.key});
  final MobileSession session;
  final int id;
  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  Json? data;
  String? error;
  bool busy = false;
  MobileApi get api => widget.session.api;
  String get cacheKey => 'ticket:${api.wabaId}:${widget.id}';
  RealtimeSubscription? live;
  Timer? liveDebounce;
  @override
  void initState() {
    super.initState();
    // Reopening a ticket shows the last details at once while they refresh.
    data = widget.session.viewCache[cacheKey] as Json?;
    load();
    // Status, SLA and last activity change as the conversation moves.
    live = widget.session.realtime.listen(
      'ticket.message.${widget.id}',
      (_, _) => liveRefresh(),
      onResync: liveRefresh,
    );
  }

  void liveRefresh() {
    liveDebounce?.cancel();
    liveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    liveDebounce?.cancel();
    live?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await api.post('inbox/ticket_details', {
        'ticket_id': widget.id,
      });
      final next = object(r['data']);
      widget.session.viewCache[cacheKey] = next;
      if (mounted) {
        setState(() {
          data = next;
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
    String path, {
    String method = 'POST',
  }) async {
    await openPage(
      context,
      ActionEditor(
        title: title,
        fields: fields,
        save: (v) async {
          await api.request(path, method: method, data: v);
        },
      ),
    );
  }

  Future<void> choose(String key, String label, String listKey) async {
    final r = await api.get(
      'inbox/ticket_metadata',
      query: {'ticket_id': widget.id},
    );
    if (!mounted) return;
    final ticket = object(data!['ticket']);
    await edit('Update $label', [
      EditField(
        '${key}_id',
        label,
        options: rows(object(r['data'])[listKey]),
        value: ticket['${key}_id'],
        required: true,
      ),
    ], 'inbox/tickets/${widget.id}/$key');
  }

  @override
  Widget build(BuildContext context) {
    final t = object(data?['ticket']);
    return Scaffold(
      appBar: AppBar(title: Text('${t['ticket_number'] ?? 'Ticket'}')),
      body: data == null
          ? error == null
                ? const Center(child: CircularProgressIndicator())
                : failure(error!, load)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LoadingBar(busy),
                  Text(
                    '${t['subject'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  AppButton.filled(
                    onPressed: () =>
                        openPage(
                          context,
                          LiveChat(
                            widget.session,
                            object(data!['contact']),
                            ticketId: widget.id,
                          ),
                        ).then((_) {
                          if (mounted) load();
                        }),
                    child: const Text('Open ticket messages'),
                  ),
                  AppListTile(
                    title: const Text('Subject'),
                    subtitle: Text('${t['subject'] ?? ''}'),
                    onTap: busy
                        ? null
                        : () => action(
                            () => edit('Ticket subject', [
                              EditField(
                                'subject',
                                'Subject',
                                value: t['subject'],
                                required: true,
                              ),
                            ], 'inbox/tickets/${widget.id}/subject'),
                          ),
                  ),
                  AppListTile(
                    title: const Text('Status'),
                    subtitle: Text(
                      '${object(t['status'])['name'] ?? t['status_name'] ?? ''}',
                    ),
                    onTap: busy
                        ? null
                        : () => action(
                            () => choose('status', 'Status', 'statuses'),
                          ),
                  ),
                  AppListTile(
                    title: const Text('Priority'),
                    subtitle: Text(
                      '${object(t['priority'])['name'] ?? t['priority_name'] ?? 'Not set'}',
                    ),
                    onTap: busy
                        ? null
                        : () => action(
                            () => choose('priority', 'Priority', 'priorities'),
                          ),
                  ),
                  AppListTile(
                    title: const Text('Assigned to'),
                    subtitle: Text(
                      '${object(t['assign_user'])['name'] ?? 'Unassigned'}',
                    ),
                    onTap: busy
                        ? null
                        : () => action(() async {
                            final users = rows(
                              await api.request('inbox/users'),
                            );
                            if (!mounted) return;
                            await edit('Assign ticket', [
                              EditField(
                                'user_id',
                                'Assignee',
                                options: users,
                                value: t['assign_user_id'],
                                required: true,
                              ),
                            ], 'inbox/tickets/${widget.id}/assign');
                          }),
                  ),
                  AppListTile(
                    title: const Text('Disposition'),
                    subtitle: Text(
                      '${object(t['disposition'])['name'] ?? 'Not set'}',
                    ),
                    onTap: busy
                        ? null
                        : () => action(() async {
                            final r = await api.get(
                              'inbox/tickets/${widget.id}/dispositions',
                            );
                            final choices = [
                              for (final c in rows(r['data']))
                                for (final d in rows(c['dispositions']))
                                  {...d, 'name': '${c['name']} · ${d['name']}'},
                            ];
                            if (!mounted) return;
                            await edit('Ticket disposition', [
                              EditField(
                                'disposition_id',
                                'Disposition',
                                value: t['disposition_id'],
                                required: true,
                                options: choices,
                              ),
                            ], 'inbox/tickets/${widget.id}/disposition');
                          }),
                  ),
                  for (final entry in object(data!['sla_badge']).entries)
                    if (entry.value is Map)
                      ListTile(
                        title: Text(
                          '${object(entry.value)['label'] ?? entry.key}',
                        ),
                        subtitle: Text(
                          '${object(entry.value)['due_at'] ?? ''}',
                        ),
                      ),
                  const Section('Tags'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in rows(data!['ticket_tags']))
                        InputChip(
                          label: Text('${tag['name']}'),
                          onDeleted: busy
                              ? null
                              : () => action(() async {
                                  await api.request(
                                    'inbox/tickets/${widget.id}/tags/${tag['id']}',
                                    method: 'DELETE',
                                  );
                                }),
                        ),
                    ],
                  ),
                  AppButton.text(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            final r = await api.get(
                              'inbox/tickets/${widget.id}/unattached-tags',
                            );
                            if (!context.mounted) return;
                            await openPage(
                              context,
                              ActionEditor(
                                title: 'Add tag',
                                fields: [
                                  EditField(
                                    'tag_id',
                                    'Tag',
                                    options: rows(r['data']),
                                    required: true,
                                  ),
                                ],
                                save: (v) async {
                                  await api.post(
                                    'inbox/tickets/${widget.id}/tags/${v['tag_id']}',
                                  );
                                },
                              ),
                            );
                          }),
                    child: const Text('Add existing tag'),
                  ),
                  const Section('Internal notes'),
                  for (final note in rows(data!['ticket_notes']))
                    AppListTile(
                      title: Text('${note['content'] ?? ''}'),
                      subtitle: Text('${object(note['author'])['name'] ?? ''}'),
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
                                'inbox/ticket/${widget.id}/notes/${note['id']}',
                                method: 'PUT',
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
                                  'Delete this internal ticket note?',
                                )) {
                                  await api.request(
                                    'inbox/ticket/${widget.id}/notes/${note['id']}',
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
                            () => edit('Add ticket note', [
                              const EditField(
                                'note',
                                'Note',
                                required: true,
                                lines: 4,
                              ),
                            ], 'inbox/ticket/${widget.id}/notes'),
                          ),
                    child: const Text('Add note'),
                  ),
                  AppListTile(
                    title: const Text('Ticket media'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPage(
                      context,
                      MediaGalleryPage(widget.session, ticketId: widget.id),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class CreateTicketPage extends StatefulWidget {
  const CreateTicketPage(this.session, {super.key});
  final MobileSession session;
  @override
  State<CreateTicketPage> createState() => _CreateTicketPageState();
}

class _CreateTicketPageState extends State<CreateTicketPage> {
  Json? metadata, contact;
  String? error;
  final search = TextEditingController();
  List<Json> contacts = [];
  Timer? debounce;
  int serial = 0;
  bool searching = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    serial++;
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get('inbox/ticket_create_metadata');
      if (mounted) {
        setState(() {
          metadata = object(r['data']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> searchContacts() async {
    final request = ++serial;
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final r = await widget.session.api.get(
        'inbox/ticket_search_contacts',
        query: {'search': search.text, 'limit': 20},
      );
      if (mounted && request == serial) {
        setState(() => contacts = rows(r['data']));
      }
    } catch (e) {
      if (mounted && request == serial) setState(() => error = '$e');
    } finally {
      if (mounted && request == serial) setState(() => searching = false);
    }
  }

  Future<void> form() async {
    final selected = contact!;
    final defaults = object(metadata!['defaults']);
    final created = await openPage<bool>(
      context,
      ActionEditor(
        title: 'New ticket for ${selected['profile_name']}',
        submit: 'Create ticket',
        fields: [
          const EditField('subject', 'Subject', required: true),
          for (final entry in {
            'department_id': ('Department', 'departments'),
            'status_id': ('Status', 'statuses'),
            'priority_id': ('Priority', 'priorities'),
            'assign_user_id': ('Assignee', 'users'),
          }.entries)
            EditField(
              entry.key,
              entry.value.$1,
              required: entry.key == 'assign_user_id',
              options: rows(metadata![entry.value.$2]),
              value: defaults[entry.key],
            ),
          EditField(
            'tags',
            'Tags',
            multiple: true,
            options: rows(metadata!['tags']),
            value: const <int>[],
          ),
          const EditField('notes', 'Internal note', lines: 4),
        ],
        save: (v) async {
          final body = <String, dynamic>{'contact_id': selected['id'], ...v}
            ..removeWhere((k, v) => v == null);
          await widget.session.api.post('inbox/ticket_create', body);
        },
      ),
    );
    if (mounted && created == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose ticket contact')),
    body: metadata == null
        ? error == null
              ? const Center(child: CircularProgressIndicator())
              : failure(error!, load)
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppTextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Search contact',
                  ),
                  onChanged: (_) {
                    debounce?.cancel();
                    serial++;
                    debounce = Timer(
                      const Duration(milliseconds: 350),
                      searchContacts,
                    );
                  },
                ),
              ),
              if (searching) const LinearProgressIndicator(),
              if (error != null)
                Text(error!, style: const TextStyle(color: T.danger)),
              Expanded(
                child: ListView(
                  children: [
                    for (final c in contacts)
                      AppListTile(
                        title: Text('${c['profile_name'] ?? ''}'),
                        subtitle: Text(
                          '${c['display_wa_id'] ?? c['wa_id'] ?? ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          contact = c;
                          form();
                        },
                      ),
                    if (contacts.isEmpty && !searching)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Search for the customer to open a ticket.',
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: AppButton.text(
                  onPressed: () async {
                    final created = await openPage<bool>(
                      context,
                      ActionEditor(
                        title: 'New ticket contact',
                        fields: const [
                          EditField('name', 'Name', required: true),
                          EditField(
                            'country',
                            'Country code',
                            value: '91',
                            required: true,
                          ),
                          EditField('phone', 'Phone', required: true),
                        ],
                        save: (v) async {
                          final r = await widget.session.api.post(
                            'inbox/ticket_create_contact',
                            v,
                          );
                          contact = object(r['data']);
                        },
                      ),
                    );
                    if (mounted && created == true && contact?['id'] != null) {
                      form();
                    }
                  },
                  child: const Text('Create a new contact'),
                ),
              ),
            ],
          ),
  );
}
