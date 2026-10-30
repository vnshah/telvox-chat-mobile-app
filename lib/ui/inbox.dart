import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      (
        path: '/inbox',
        title: 'Inbox',
        icon: Icons.chat_bubble_outline_rounded,
        apple: CupertinoIcons.chat_bubble,
        active: CupertinoIcons.chat_bubble_fill,
      ),
      (
        path: '/contacts',
        title: 'Contacts',
        icon: Icons.people_outline_rounded,
        apple: CupertinoIcons.person_2,
        active: CupertinoIcons.person_2_fill,
      ),
      (
        path: '/tickets',
        title: 'Tickets',
        icon: Icons.confirmation_number_outlined,
        apple: CupertinoIcons.ticket,
        active: CupertinoIcons.ticket_fill,
      ),
      (
        path: '/settings',
        title: 'Settings',
        icon: Icons.settings_outlined,
        apple: CupertinoIcons.settings,
        active: CupertinoIcons.settings_solid,
      ),
    ];
    final index = destinations
        .indexWhere((d) => d.path == location)
        .clamp(0, 3);
    final apple = isCupertino(context);
    final wide = MediaQuery.sizeOf(context).width >= 850;
    void select(int value) => context.go(destinations[value].path);
    final add = switch (index) {
      0 => (
        label: 'New conversation',
        route: '/contacts?pick=true',
        icon: CupertinoIcons.square_pencil,
      ),
      1 => (
        label: 'Add contact',
        route: '/contact/new',
        icon: CupertinoIcons.person_add,
      ),
      _ => (
        label: 'Create ticket',
        route: '/ticket/new',
        icon: CupertinoIcons.plus,
      ),
    };
    final actions = <Widget>[
      if (!apple)
        AppIconButton(
          tooltip: 'Switch workspace',
          onPressed: () => context.push('/workspaces'),
          icon: const AppIcon(Icons.unfold_more_rounded, size: 20),
        ),
      AppIconButton(
        tooltip: 'Notifications',
        onPressed: () => context.push('/notifications'),
        icon: Badge(
          isLabelVisible: !ref.watch(previewProvider).notificationsRead,
          smallSize: 6,
          backgroundColor: T.green,
          child: const AppIcon(Icons.notifications_none_rounded, size: 23),
        ),
      ),
      if (apple && index != 3)
        AppIconButton(
          tooltip: add.label,
          onPressed: () => context.push(add.route),
          icon: Icon(add.icon, color: T.green, size: 23),
        ),
      AppIconButton(
        tooltip: 'Profile',
        onPressed: () => context.push('/profile'),
        padding: const EdgeInsets.all(4),
        icon: const Avatar('Renav Shah', size: 32),
      ),
    ];
    final brand = Tooltip(
      message: apple ? 'Switch workspace' : 'Telvox Chat',
      child: GestureDetector(
        onTap: apple ? () => context.push('/workspaces') : null,
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Brand(),
        ),
      ),
    );
    final PreferredSizeWidget bar = apple
        ? CupertinoNavigationBar(
            automaticallyImplyLeading: false,
            leading: SizedBox(
              width:
                  (MediaQuery.sizeOf(context).width - (index == 3 ? 124 : 168))
                      .clamp(100, 200)
                      .toDouble(),
              child: brand,
            ),
            backgroundColor: const Color(0xFAFCFCFC),
            border: const Border(
              bottom: BorderSide(color: Color(0xFFE5E6E8), width: .5),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
          )
        : AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: brand,
            actions: [...actions, const SizedBox(width: 8)],
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: apple ? Colors.white : T.paper,
      ),
      child: Scaffold(
        appBar: bar,
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              if (wide && !apple)
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: AppIcon(d.icon),
                        label: Text(d.title),
                      ),
                  ],
                ),
              if (wide && apple)
                SizedBox(
                  width: 220,
                  child: ColoredBox(
                    color: const Color(0xFFF2F2F7),
                    child: CupertinoListSection.insetGrouped(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          CupertinoListTile(
                            title: Text(
                              destinations[i].title,
                              style: TextStyle(
                                fontSize: 14,
                                color: index == i ? T.green : T.ink,
                              ),
                            ),
                            leading: Icon(
                              destinations[i].apple,
                              color: T.green,
                              size: 22,
                            ),
                            backgroundColor: index == i
                                ? T.selected.withValues(alpha: .5)
                                : Colors.white,
                            onTap: () => select(i),
                          ),
                      ],
                    ),
                  ),
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(
                child: Material(color: Colors.white, child: child),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : apple
            ? CupertinoTabBar(
                currentIndex: index,
                onTap: select,
                activeColor: T.green,
                inactiveColor: const Color(0xFF858C88),
                backgroundColor: const Color(0xFAFCFCFC),
                items: [
                  for (final d in destinations)
                    BottomNavigationBarItem(
                      icon: Icon(d.apple),
                      activeIcon: Icon(d.active),
                      label: d.title,
                    ),
                ],
              )
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: select,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(
                      icon: AppIcon(d.icon),
                      label: d.title,
                    ),
                ],
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
  String filter = 'All';
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
      floatingActionButton: AppFab(
        tooltip: 'New conversation',

        onPressed: () => context.push('/contacts?pick=true'),
        child: const AppIcon(Icons.edit_outlined),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SearchBox(
                        value: search,
                        hint: 'Search chats',
                        dense: true,
                        onChanged: (v) => setState(() => search = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppIconButton.filledTonal(
                      tooltip: 'Filter conversations',
                      style: IconButton.styleFrom(
                        backgroundColor: isCupertino(context)
                            ? Colors.transparent
                            : T.paper,
                      ),
                      onPressed: () => _filters(context),
                      icon: const AppIcon(Icons.tune_rounded, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: PlatformFilters(
              options: const [
                'My chats',
                'All',
                'Unread',
                'Unassigned',
                'Favourites',
                'Closed',
              ],
              selected: filter,
              onSelected: (value) => setState(() => filter = value),
              scrollable: true,
            ),
          ),
          const SizedBox(height: 6),
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
                  AppChoiceChip(
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
            AppButton.filled(
              onPressed: () {
                setState(() => tag = selected);
                Navigator.pop(context);
              },
              child: const Text('Apply filters'),
            ),
            AppButton.text(
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
    key: ValueKey('conversation-row-${person.id}'),
    onTap: () {
      ref.read(previewProvider.notifier).read(person.id);
      context.push('/chat/${person.id}');
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Avatar(person.name, size: 44, color: person.color),
          const SizedBox(width: 12),
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
                    const SizedBox(width: 10),
                    Text(
                      person.time,
                      style: mono(
                        size: 10,
                        color: person.unread > 0 ? T.green : T.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (person.preview.startsWith('You:'))
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: AppIcon(Icons.done_all, color: T.blue, size: 14),
                      ),
                    Expanded(
                      child: Text(
                        person.preview.replaceFirst('You: ', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: T.secondary,
                        ),
                      ),
                    ),
                    if (person.favorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: AppIcon(
                          Icons.star_rounded,
                          size: 12,
                          color: T.muted,
                        ),
                      ),
                    if (person.bot)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: AppIcon(
                          Icons.auto_awesome_outlined,
                          size: 12,
                          color: T.brass,
                        ),
                      ),
                    if (person.unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 7),
                        constraints: const BoxConstraints(
                          minWidth: 19,
                          minHeight: 19,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: T.green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${person.unread}',
                          textAlign: TextAlign.center,
                          style: mono(size: 9, color: Colors.white),
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
  const ContactsPage({super.key, this.pick = false, this.template, this.draft});
  final bool pick;
  final String? template, draft;
  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  String search = '';
  String destination(Person p) {
    if (widget.template != null) {
      return '/template/${widget.template}?contact=${p.id}';
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
        widget.pick || widget.template != null || widget.draft != null;
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
      floatingActionButton: AppFab(
        tooltip: 'Add contact',

        onPressed: () => context.push('/contact/new'),
        child: const AppIcon(Icons.person_add_alt_outlined),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selecting)
                      AppIconButton(
                        tooltip: 'Back',
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/inbox'),
                        icon: const AppIcon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: SearchBox(
                        value: search,
                        hint: selecting
                            ? 'Find a contact to message'
                            : 'Search contacts',
                        dense: true,
                        onChanged: (v) => setState(() => search = v),
                      ),
                    ),
                  ],
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
                    itemBuilder: (context, i) => AppListTile(
                      key: ValueKey('contact-row-${people[i].id}'),
                      dense: true,
                      minVerticalPadding: 9,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      leading: Avatar(
                        people[i].name,
                        size: 40,
                        color: people[i].color,
                      ),
                      title: Text(
                        people[i].name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(people[i].phone, style: mono(size: 11)),
                      trailing: const AppIcon(
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
