import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'chat.dart' show LiveChat;
import 'contact_actions.dart' show ContactFieldsPage;
import 'shared_media.dart' show MediaGalleryPage;
import 'detail_layout.dart';
import 'editors.dart';
import 'models.dart' show MobileClock, formatPhone;
import 'send_policy.dart' show flag, ticketSendDetail;
import 'realtime.dart';
import 'screens.dart' show failure, mobileNotice, openPage;

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
    // A closed ticket left without a disposition asks for one on opening.
    load().then((_) => askDisposition()).catchError((_) {});
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
    // Small changes open over the ticket and save in place. The sheet shows
    // its own progress; the page is idle while it is open.
    setState(() => busy = false);
    await showEditorSheet(
      context,
      title: title,
      fields: fields,
      save: (v) async {
        await api.request(path, method: method, data: v);
      },
    );
    if (mounted) setState(() => busy = true);
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

  void editSubject(Json t) => action(
    () => edit('Ticket subject', [
      EditField('subject', 'Subject', value: t['subject'], required: true),
    ], 'inbox/tickets/${widget.id}/subject'),
  );

  void assign(Json t) => action(() async {
    final users = rows(await api.request('inbox/users'));
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
  });

  /// May this agent change the ticket: theirs, or one of their team's, as
  /// the web ticket inbox allows it.
  bool get canEditTicket {
    final assignee = number(object(data?['ticket'])['assign_user_id']);
    if (assignee == null || data == null) return false;
    final team = ticketSendDetail(data!)['child_user_ids'] as List;
    return assignee == number(widget.session.user?['id']) ||
        team.contains(assignee);
  }

  bool get ticketClosed {
    final t = object(data?['ticket']);
    return '${t['closed_at'] ?? ''}'.isNotEmpty && flag(t['status_is_closed']);
  }

  /// The statuses the web offers from here: all when the current one is a
  /// reopen status; closed and reopen statuses on a closed ticket; on an
  /// open one, all but the reopen statuses.
  List<Json> statusChoices(List<Json> statuses) {
    final current = statuses
        .where((s) => '${s['id']}' == '${object(data!['ticket'])['status_id']}')
        .firstOrNull;
    if (current != null && flag(current['is_reopen'])) return statuses;
    return [
      for (final s in statuses)
        if (ticketClosed
            ? flag(s['is_closed']) || flag(s['is_reopen'])
            : !flag(s['is_reopen']))
          s,
    ];
  }

  /// A new status; closing one asks what came of it, as the web does.
  void changeStatus() => action(() async {
    final r = await api.get('inbox/ticket_metadata');
    if (!mounted) return;
    final statuses = rows(object(r['data'])['statuses']);
    Json? picked;
    setState(() => busy = false);
    await showEditorSheet(
      context,
      title: 'Update Status',
      fields: [
        EditField(
          'status_id',
          'Status',
          options: statusChoices(statuses),
          value: object(data!['ticket'])['status_id'],
          required: true,
        ),
      ],
      save: (v) async {
        await api.request(
          'inbox/tickets/${widget.id}/status',
          method: 'POST',
          data: v,
        );
        picked = statuses.where((s) => s['id'] == v['status_id']).firstOrNull;
      },
    );
    if (picked != null && flag(picked!['is_closed']) && mounted) {
      await load();
      // The page waits idle under the question, as under any sheet.
      if (mounted) await askDisposition(force: true);
    }
    if (mounted) setState(() => busy = true);
  });

  var askedDisposition = false;

  /// What came of a closed ticket: asked when it closes, and when a closed
  /// ticket without one is opened, of an agent who may change it. Back puts
  /// it off until the ticket is opened again, as switching tickets does on
  /// the web; with no dispositions set up there is nothing to ask.
  Future<void> askDisposition({bool force = false}) async {
    final t = object(data?['ticket']);
    if (!mounted || data == null) return;
    if (!force && (askedDisposition || t['disposition_id'] != null)) return;
    if (!ticketClosed || !canEditTicket) return;
    askedDisposition = true;
    final r = await api.get('inbox/tickets/${widget.id}/dispositions');
    final categories = [
      for (final c in rows(r['data']))
        if (rows(c['dispositions']).isNotEmpty) c,
    ];
    if (categories.isEmpty || !mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => DispositionSheet(
        categories: categories,
        initial: number(t['disposition_id']),
        save: (id) => api.request(
          'inbox/tickets/${widget.id}/disposition',
          method: 'POST',
          data: {'disposition_id': id},
        ),
      ),
    );
    if (saved == true && mounted) await load();
  }

  void disposition(Json t) => action(() async {
    setState(() => busy = false);
    await askDisposition(force: true);
    // A closed or someone else's ticket: the plain list, as before.
    if (!ticketClosed || !canEditTicket) {
      final r = await api.get('inbox/tickets/${widget.id}/dispositions');
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
    }
    if (mounted) setState(() => busy = true);
  });

  void addTag() => action(() async {
    final r = await api.get('inbox/tickets/${widget.id}/unattached-tags');
    if (!mounted) return;
    setState(() => busy = false);
    await showEditorSheet(
      context,
      title: 'Add tag',
      fields: [
        EditField('tag_id', 'Tag', options: rows(r['data']), required: true),
      ],
      save: (v) async {
        await api.post('inbox/tickets/${widget.id}/tags/${v['tag_id']}');
      },
    );
    if (mounted) setState(() => busy = true);
  });

  void note([Json? existing]) => action(
    () => edit(
      existing == null ? 'Add ticket note' : 'Edit note',
      [
        EditField(
          'note',
          'Note',
          value: existing?['content'],
          required: true,
          lines: 4,
        ),
      ],
      existing == null
          ? 'inbox/ticket/${widget.id}/notes'
          : 'inbox/ticket/${widget.id}/notes/${existing['id']}',
      method: existing == null ? 'POST' : 'PUT',
    ),
  );

  void deleteNote(Json existing) => action(() async {
    if (await confirmAction(
      context,
      'Delete note',
      'Delete this internal ticket note?',
    )) {
      await api.request(
        'inbox/ticket/${widget.id}/notes/${existing['id']}',
        method: 'DELETE',
      );
    }
  });

  void messages() =>
      openPage(
        context,
        LiveChat(widget.session, object(data!['contact']), ticketId: widget.id),
      ).then((_) {
        if (mounted) load();
      });

  @override
  Widget build(BuildContext context) {
    final t = object(data?['ticket']);
    final number = '${t['ticket_number'] ?? 'Ticket'}';
    if (data == null) {
      return DetailScaffold(
        title: number,
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
    final contact = object(data!['contact']);
    final status = '${object(t['status'])['name'] ?? t['status_name'] ?? ''}';
    final closed =
        flag(t['status_is_closed']) || flag(object(t['status'])['is_closed']);
    final priority =
        '${object(t['priority'])['name'] ?? t['priority_name'] ?? 'Not set'}';
    final assignee = '${object(t['assign_user'])['name'] ?? 'Unassigned'}';
    final notes = rows(data!['ticket_notes']);
    final tags = rows(data!['ticket_tags']);
    final sla = [
      for (final entry in object(data!['sla_badge']).entries)
        if (entry.value is Map) object(entry.value)..['key'] = entry.key,
    ];
    final apple = isCupertino(context);
    final who = '${contact['profile_name'] ?? ''}';
    return DetailScaffold(
      title: number,
      busy: busy,
      onRefresh: load,
      children: [
        DetailHero(
          centered: false,
          title: '${t['subject'] ?? number}',
          subtitle: [
            who,
            formatPhone(contact['display_wa_id'] ?? contact['wa_id']),
          ].where((p) => p.isNotEmpty).join(' · '),
          onTitleTap: busy ? null : () => editSubject(t),
          chips: [
            if (status.isNotEmpty)
              StatusChip(
                status,
                icon: closed ? Icons.lock_outline : Icons.schedule,
                positive: !closed,
              ),
            StatusChip(priority, icon: Icons.flag_outlined),
          ],
          actions: [
            QuickAction(
              Icons.chat_outlined,
              'Messages',
              messages,
              primary: true,
            ),
            QuickAction(Icons.timelapse, 'Status', busy ? null : changeStatus),
            QuickAction(
              Icons.person_add_alt_1_outlined,
              'Assign',
              busy ? null : () => assign(t),
            ),
            QuickAction(
              Icons.flag_outlined,
              'Priority',
              busy
                  ? null
                  : () => action(
                      () => choose('priority', 'Priority', 'priorities'),
                    ),
            ),
          ],
        ),
        DetailSection(
          title: 'Details',
          children: [
            if ('${t['ticket_number'] ?? ''}'.isNotEmpty)
              DetailRow(
                key: const ValueKey('ticket-number'),
                icon: Icons.confirmation_number_outlined,
                label: 'Ticket ID',
                value: '#${t['ticket_number']}',
                // As the web's copy icon: the number itself, without "#".
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${t['ticket_number']}'),
                  );
                  if (context.mounted) {
                    mobileNotice(context, 'Ticket number copied.');
                  }
                },
                trailing: const AppIcon(Icons.copy_rounded, size: 18),
              ),
            DetailRow(
              icon: Icons.timelapse,
              tile: closed ? T.muted : T.green,
              label: 'Status',
              value: status.isEmpty ? 'Not set' : status,
              onTap: busy ? null : changeStatus,
            ),
            DetailRow(
              icon: Icons.flag_outlined,
              label: 'Priority',
              value: priority,
              onTap: busy
                  ? null
                  : () => action(
                      () => choose('priority', 'Priority', 'priorities'),
                    ),
            ),
            DetailRow(
              icon: Icons.person_outline,
              label: 'Assigned to',
              value: assignee,
              onTap: busy ? null : () => assign(t),
            ),
            DetailRow(
              icon: Icons.check_circle_outline,
              label: 'Disposition',
              value: '${object(t['disposition'])['name'] ?? 'Not set'}',
              onTap: busy ? null : () => disposition(t),
            ),
          ],
        ),
        if (sla.isNotEmpty)
          DetailSection(
            title: 'SLA',
            children: [
              for (final s in sla)
                DetailRow(
                  icon: Icons.schedule,
                  tile: T.green,
                  label: '${s['label'] ?? s['key']}',
                  value: '${s['due_at'] ?? ''}',
                ),
            ],
          ),
        DetailSection(
          title: 'Tags',
          children: [
            TagWrap(
              tags: [for (final tag in tags) '${tag['name']}'],
              onRemove: busy
                  ? null
                  : (i) => action(() async {
                      await api.request(
                        'inbox/tickets/${widget.id}/tags/${tags[i]['id']}',
                        method: 'DELETE',
                      );
                    }),
              onAdd: busy ? null : addTag,
            ),
          ],
        ),
        DetailSection(
          title: 'Internal notes',
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
                  '${object(n['author'])['name'] ?? ''}',
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
          children: [
            // The web ticket inbox's Custom Field tab.
            DetailRow(
              key: const ValueKey('ticket-custom-fields'),
              icon: Icons.tune,
              label: 'Custom fields',
              onTap: () => openPage(
                context,
                ContactFieldsPage(
                  widget.session,
                  int.tryParse('${contact['id']}') ?? 0,
                  ticketId: widget.id,
                ),
              ),
            ),
            DetailRow(
              icon: Icons.perm_media_outlined,
              label: 'Media, documents and links',
              onTap: () => openPage(
                context,
                MediaGalleryPage(widget.session, ticketId: widget.id),
              ),
            ),
          ],
        ),
      ],
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
              if (error != null && !isOffline(error))
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

/// What came of a closed ticket, as the web's disposition panel asks it: a
/// tab per category, its dispositions as cards, and Save once one is picked.
class DispositionSheet extends StatefulWidget {
  const DispositionSheet({
    super.key,
    required this.categories,
    required this.save,
    this.initial,
  });
  final List<Json> categories;
  final Future<Object?> Function(int id) save;
  final int? initial;
  @override
  State<DispositionSheet> createState() => _DispositionSheetState();
}

class _DispositionSheetState extends State<DispositionSheet> {
  late int tab = () {
    final at = widget.categories.indexWhere(
      (c) =>
          rows(c['dispositions']).any((d) => number(d['id']) == widget.initial),
    );
    return at < 0 ? 0 : at;
  }();
  late int? picked = widget.initial;
  bool saving = false;
  String? error;

  Future<void> save() async {
    final id = picked;
    if (id == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = rows(widget.categories[tab]['dispositions']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select disposition',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'This ticket is closed. Choose how it ended.',
              style: TextStyle(fontSize: 13, color: T.secondary),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < widget.categories.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('disposition-tab-$i'),
                        label: Text('${widget.categories[i]['name'] ?? ''}'),
                        selected: tab == i,
                        // Another category starts with nothing picked.
                        onSelected: (_) => setState(() {
                          tab = i;
                          picked = null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.8,
                children: [
                  for (final d in options)
                    if (number(d['id']) case final int id)
                      OutlinedButton(
                        key: ValueKey('disposition-$id'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: picked == id
                              ? T.greenWash
                              : Colors.white,
                          side: BorderSide(
                            color: picked == id ? T.green : T.hairline,
                          ),
                          foregroundColor: T.ink,
                        ),
                        // The picked one again lets it go.
                        onPressed: saving
                            ? null
                            : () => setState(
                                () => picked = picked == id ? null : id,
                              ),
                        child: Text(
                          '${d['name'] ?? ''}',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: T.danger)),
              ),
            const SizedBox(height: 12),
            AppButton.filled(
              key: const ValueKey('disposition-save'),
              onPressed: picked == null || saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
