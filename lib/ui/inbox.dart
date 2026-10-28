import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    const destinations = [
      (path: '/inbox', title: 'Inbox', icon: Icons.chat_bubble_outline_rounded),
      (
        path: '/contacts',
        title: 'Contacts',
        icon: Icons.people_outline_rounded,
      ),
      (
        path: '/tickets',
        title: 'Tickets',
        icon: Icons.confirmation_number_outlined,
      ),
      (path: '/more', title: 'More', icon: Icons.grid_view_rounded),
    ];
    final selected = destinations.indexWhere((d) => location == d.path);
    final index = selected < 0 ? 0 : selected;
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      backgroundColor: T.paper,
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: 222,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      const Brand(),
                      const SizedBox(height: 36),
                      const Eyebrow('Your workspace'),
                      const SizedBox(height: 16),
                      for (var i = 0; i < destinations.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: ListTile(
                            shape: const StadiumBorder(
                              side: BorderSide(color: T.edge),
                            ),
                            tileColor: index == i
                                ? Colors.white
                                : Colors.transparent,
                            leading: Icon(destinations[i].icon, color: T.brass),
                            title: Text(destinations[i].title),
                            onTap: () => context.go(destinations[i].path),
                          ),
                        ),
                      const Spacer(),
                      const Pill(
                        'Preview workspace',
                        color: T.brass,
                        fill: T.wash,
                      ),
                      const SizedBox(height: 18),
                      MenuRow(
                        'Settings',
                        Icons.settings_outlined,
                        route: '/settings',
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Container(
                margin: wide
                    ? const EdgeInsets.fromLTRB(0, 8, 8, 8)
                    : EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(wide ? 18 : 0),
                  border: wide ? Border.all(color: T.edge) : null,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: !wide
                                  ? const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Brand(),
                                    )
                                  : Text(
                                      ref.watch(previewProvider).workspace,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Switch workspace',
                            onPressed: () => context.push('/workspaces'),
                            icon: const Icon(
                              Icons.unfold_more_rounded,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Notifications',
                            onPressed: () => context.push('/notifications'),
                            icon: Badge(
                              isLabelVisible: !ref
                                  .watch(previewProvider)
                                  .notificationsRead,
                              smallSize: 6,
                              backgroundColor: T.green,
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 23,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () => context.push('/profile'),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Avatar('Renav Shah', size: 32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: Material(color: Colors.white, child: child),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: T.paper,
                  border: Border(top: BorderSide(color: T.edge)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: index == i,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => context.go(destinations[i].path),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 60,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: index == i
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(30),
                                      border: index == i
                                          ? Border.all(color: T.control)
                                          : null,
                                    ),
                                    child: Icon(
                                      destinations[i].icon,
                                      color: index == i ? T.ink : T.brass,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    destinations[i].title,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: index == i ? T.ink : T.muted,
                                      fontWeight: index == i
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
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

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});
  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  String filter = 'My chats';
  String search = '';
  String tag = 'All tags';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(previewProvider);
    final people = state.people.where((p) {
      final matches = '${p.name} ${p.phone} ${p.preview}'
          .toLowerCase()
          .contains(search.toLowerCase());
      final tab = switch (filter) {
        'My chats' => p.assignee == 'You' && !p.closed,
        'Unread' => p.unread > 0 && !p.closed,
        'Unassigned' => p.assignee == 'Unassigned' && !p.closed,
        'Favourites' => p.favorite && !p.closed,
        'Closed' => p.closed,
        _ => !p.closed,
      };
      return matches && tab && (tag == 'All tags' || p.tags.contains(tag));
    }).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        tooltip: 'New conversation',
        backgroundColor: T.green,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        onPressed: () => context.push('/contacts?pick=true'),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Inbox',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 10),
                    Pill(
                      '${state.people.where((p) => p.unread > 0).length} unread',
                    ),
                    const Spacer(),
                    const Pill('Preview', color: T.brass, fill: T.wash),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Every conversation, in good hands.',
                  style: TextStyle(fontSize: 12, color: T.muted),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SearchBox(
                        hint: 'Search names, numbers, messages',
                        onChanged: (v) => setState(() => search = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Filter conversations',
                      style: IconButton.styleFrom(backgroundColor: T.wash),
                      onPressed: () => _filters(context),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final f in [
                  'My chats',
                  'All',
                  'Unread',
                  'Unassigned',
                  'Favourites',
                  'Closed',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: filter == f,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          Expanded(
            child: people.isEmpty
                ? EmptyView(
                    title: 'A little breathing room.',
                    description: search.isNotEmpty
                        ? 'No conversations match your search. Try another name or number.'
                        : 'No conversations in this view. You’re all caught up.',
                    action: 'View all chats',
                    onAction: () => setState(() {
                      filter = 'All';
                      search = '';
                      tag = 'All tags';
                    }),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: people.length,
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.only(left: 80),
                      child: Divider(),
                    ),
                    itemBuilder: (context, i) => ConversationRow(people[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _filters(BuildContext context) {
    var selected = tag;
    sheet(
      context,
      StatefulBuilder(
        builder: (context, update) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filter conversations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Find the conversations that need you.',
              style: TextStyle(color: T.muted),
            ),
            const Section('Contact tags'),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final value in [
                  'All tags',
                  'Customer',
                  'New lead',
                  'VIP',
                  'Support',
                  'Wholesale',
                ])
                  ChoiceChip(
                    label: Text(value),
                    selected: selected == value,
                    onSelected: (_) => update(() => selected = value),
                  ),
              ],
            ),
            const Section('Assigned to'),
            const Text(
              'Use My chats or Unassigned to narrow down your inbox.',
              style: TextStyle(color: T.muted, fontSize: 13),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () {
                setState(() => tag = selected);
                Navigator.pop(context);
              },
              child: const Text('Apply filters'),
            ),
            TextButton(
              onPressed: () {
                setState(() => tag = 'All tags');
                Navigator.pop(context);
              },
              child: const Text('Reset filters'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationRow extends ConsumerWidget {
  const ConversationRow(this.person, {super.key});
  final Person person;
  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    onTap: () {
      ref.read(previewProvider.notifier).read(person.id);
      context.push('/chat/${person.id}');
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            person.name,
            color: person.color,
            online: person.id == 'ananya',
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: person.unread > 0
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      person.time,
                      style: mono(
                        size: 10,
                        color: person.unread > 0 ? T.green : T.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (person.preview.startsWith('You:'))
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.done_all, color: T.blue, size: 14),
                      ),
                    Expanded(
                      child: Text(
                        person.preview.replaceFirst('You: ', ''),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: T.secondary,
                        ),
                      ),
                    ),
                    if (person.unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(5),
                        constraints: const BoxConstraints(minWidth: 20),
                        decoration: const BoxDecoration(
                          color: T.green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${person.unread}',
                          textAlign: TextAlign.center,
                          style: mono(
                            size: 9,
                            color: Colors.white,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    if (person.tags.isNotEmpty)
                      Pill(person.tags.first, color: T.brass, fill: T.wash),
                    const Spacer(),
                    if (person.bot)
                      const Icon(
                        Icons.auto_awesome_outlined,
                        color: T.brass,
                        size: 13,
                      )
                    else
                      const Icon(
                        Icons.person_outline,
                        color: T.muted,
                        size: 12,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      person.assignee,
                      style: const TextStyle(fontSize: 10, color: T.muted),
                    ),
                    if (person.favorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: T.brass,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({
    super.key,
    this.pick = false,
    this.call = false,
    this.template,
    this.product,
    this.draft,
  });
  final bool pick, call;
  final String? template, product, draft;
  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  String search = '';
  String destination(Person p) {
    if (widget.call) return '/call/${p.id}';
    if (widget.template != null) {
      return '/template/${widget.template}?contact=${p.id}';
    }
    if (widget.product != null) {
      return '/product/${widget.product}?contact=${p.id}';
    }
    if (widget.pick || widget.draft != null) {
      return Uri(
        path: '/chat/${p.id}',
        queryParameters: widget.draft == null ? null : {'draft': widget.draft!},
      ).toString();
    }
    return '/customer/${p.id}';
  }

  @override
  Widget build(BuildContext context) {
    final selecting =
        widget.pick ||
        widget.call ||
        widget.template != null ||
        widget.product != null ||
        widget.draft != null;
    final state = ref.watch(previewProvider);
    final people =
        state.people
            .where(
              (p) => '${p.name} ${p.phone}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add contact',
        backgroundColor: T.green,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => context.push('/contact/new'),
        child: const Icon(Icons.person_add_alt_outlined),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selecting)
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Text(
                      widget.call
                          ? 'New call'
                          : selecting
                          ? 'Choose contact'
                          : 'Contacts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 10),
                    Pill(
                      '${state.people.length}',
                      color: T.brass,
                      fill: T.wash,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Familiar faces. Meaningful connections.',
                  style: TextStyle(fontSize: 12, color: T.muted),
                ),
                const SizedBox(height: 20),
                SearchBox(
                  hint: 'Search contacts',
                  onChanged: (v) => setState(() => search = v),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: people.isEmpty
                ? const EmptyView(
                    title: 'No contacts found',
                    description: 'Try another name or add a new contact.',
                    icon: Icons.people_outline,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: people.length,
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.only(left: 80),
                      child: Divider(),
                    ),
                    itemBuilder: (context, i) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 9,
                      ),
                      leading: Avatar(people[i].name, color: people[i].color),
                      title: Text(
                        people[i].name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(people[i].phone, style: mono(size: 11)),
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: T.brass,
                      ),
                      onTap: () => context.push(destination(people[i])),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
