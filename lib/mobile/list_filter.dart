import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart' show SheetTitle;

/// The shared inbox list's filter, as the web inbox's filter popover sets it:
/// chats with any of the picked tags, and chats assigned to one agent.
@immutable
class ListFilter {
  const ListFilter({
    this.tags = const [],
    this.assignedTo,
    this.status,
    this.priority,
    this.ticketType,
    this.cleared = false,
  });

  /// What Clear answers with: nothing picked, and the list starts over.
  static const none = ListFilter(cleared: true);

  /// Came from Clear rather than Apply.
  final bool cleared;
  final List<int> tags;
  final int? assignedTo;

  /// The ticket list's own filters: a status, a priority, and a kind of
  /// ticket (see [ticketTypes]).
  final int? status, priority;
  final String? ticketType;

  bool get active =>
      tags.isNotEmpty ||
      assignedTo != null ||
      status != null ||
      priority != null ||
      ticketType != null;

  /// Tells filters apart in cache keys and comparisons.
  String get key => active
      ? 't${([...tags]..sort()).join(',')}a${assignedTo ?? ''}'
            's${status ?? ''}p${priority ?? ''}k${ticketType ?? ''}'
      : '';

  /// What the list request adds for these filters.
  Json get body => {
    if (tags.isNotEmpty) 'tags': tags,
    'assignedTo': ?assignedTo,
    'status': ?status,
    'priority': ?priority,
    'ticketType': ?ticketType,
  };
}

/// The web ticket filter's kinds of ticket, as the server reads them.
const ticketTypes = {
  'reopened': 'Reopened',
  'overdue': 'Overdue',
  'waiting_customer': 'Waiting for Customer',
  'first_response_pending': 'First Response Pending',
};

/// Picks the tags (any of several) and the assignee (one, tapped again to
/// let go), then Apply; Clear empties both. The tags are the number's own,
/// from `inbox/tags`; the agents are those the inbox lists (`inbox/users`).
/// For tickets ([tickets]), as the web ticket filter: a status and priority
/// (`inbox/ticket_metadata`), a kind of ticket, the ticket tags
/// (`inbox/ticket_tags`) and the assignee, each one at a time.
class ListFilterSheet extends StatefulWidget {
  const ListFilterSheet({
    super.key,
    required this.session,
    required this.initial,
    this.people = const {},
    this.tickets = false,
  });
  final MobileSession session;
  final ListFilter initial;
  final bool tickets;

  /// Agents already loaded for the list's initials, by id.
  final Map<int, String> people;
  @override
  State<ListFilterSheet> createState() => _ListFilterSheetState();
}

class _ListFilterSheetState extends State<ListFilterSheet> {
  late final tags = {...widget.initial.tags};
  late int? assignedTo = widget.initial.assignedTo;
  late int? status = widget.initial.status;
  late int? priority = widget.initial.priority;
  late String? ticketType = widget.initial.ticketType;
  List<Json> statuses = [], priorities = [];
  List<Json>? tagOptions;
  late Map<int, String> people = widget.people;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final api = widget.session.api;
      final list = rows(
        (await api.get(
          widget.tickets ? 'inbox/ticket_tags' : 'inbox/tags',
        ))['data'],
      );
      if (widget.tickets) {
        final meta = object((await api.get('inbox/ticket_metadata'))['data']);
        statuses = rows(meta['statuses']);
        priorities = rows(meta['priorities']);
      }
      final agents = people.isNotEmpty
          ? people
          : {
              for (final u in rows(await api.request('inbox/users')))
                if (number(u['id']) case final int id) id: '${u['name'] ?? ''}',
            };
      if (!mounted) return;
      setState(() {
        tagOptions = list;
        people = agents;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  /// One at a time, as on the web: the picked one again lets it go.
  Widget choices<V>(
    String key,
    Map<V, String> options,
    V? current,
    void Function(V?) set, {
    String empty = 'None available',
  }) => options.isEmpty
      ? Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(empty, style: const TextStyle(color: T.muted)),
        )
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final MapEntry(key: value, value: label) in options.entries)
                ChoiceChip(
                  key: ValueKey('filter-$key-$value'),
                  label: Text(label),
                  selected: current == value,
                  onSelected: (_) =>
                      setState(() => set(current == value ? null : value)),
                ),
            ],
          ),
        );

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: T.secondary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final options = tagOptions;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle('Filter chats'),
            if (error != null && !isOffline(error))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(error!, style: const TextStyle(color: T.danger)),
              ),
            Flexible(
              child: options == null && error == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (widget.tickets) ...[
                          heading('Status'),
                          choices(
                            'status',
                            {
                              for (final o in statuses)
                                if (number(o['id']) case final int id)
                                  id: '${o['name'] ?? ''}',
                            },
                            status,
                            (v) => status = v,
                            empty: 'No statuses available',
                          ),
                          heading('Priority'),
                          choices(
                            'priority',
                            {
                              for (final o in priorities)
                                if (number(o['id']) case final int id)
                                  id: '${o['name'] ?? ''}',
                            },
                            priority,
                            (v) => priority = v,
                          ),
                          heading('Ticket Type'),
                          choices(
                            'type',
                            ticketTypes,
                            ticketType,
                            (v) => ticketType = v,
                          ),
                        ],
                        heading('Tags'),
                        if ((options ?? const []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text(
                              'No tags yet',
                              style: TextStyle(color: T.muted),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final t in options!)
                                  if (number(t['id']) case final int id)
                                    FilterChip(
                                      key: ValueKey('filter-tag-$id'),
                                      label: Text('${t['name'] ?? ''}'),
                                      selected: tags.contains(id),
                                      onSelected: (on) => setState(
                                        () =>
                                            on ? tags.add(id) : tags.remove(id),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        heading('Assigned to'),
                        for (final MapEntry(key: id, value: name)
                            in people.entries)
                          ListTile(
                            key: ValueKey('filter-agent-$id'),
                            dense: true,
                            title: Text(name),
                            trailing: assignedTo == id
                                ? const Icon(Icons.check, color: T.unread)
                                : null,
                            // The same agent again lets go, as on the web.
                            onTap: () => setState(
                              () => assignedTo = assignedTo == id ? null : id,
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton.outlined(
                      key: const ValueKey('filter-clear'),
                      onPressed: () => Navigator.pop(context, ListFilter.none),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.filled(
                      key: const ValueKey('filter-apply'),
                      onPressed: () => Navigator.pop(
                        context,
                        ListFilter(
                          tags: [...tags],
                          assignedTo: assignedTo,
                          status: status,
                          priority: priority,
                          ticketType: ticketType,
                        ),
                      ),
                      child: const Text('Apply'),
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
