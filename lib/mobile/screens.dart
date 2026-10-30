import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'chat.dart';
import 'models.dart';
import 'message_content.dart';
import 'send_policy.dart' show flag;
import 'tickets.dart';

void mobileNotice(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$message')));
}

Future<R?> openPage<R>(BuildContext context, Widget page) =>
    Navigator.of(context).push<R>(MaterialPageRoute(builder: (_) => page));

/// Thin progress strip that always reserves its height, so content below it
/// never shifts when loading starts or stops.
class LoadingBar extends StatelessWidget {
  const LoadingBar(this.active, {super.key});
  final bool active;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 2,
    child: active ? const LinearProgressIndicator(minHeight: 2) : null,
  );
}

Widget failure(String message, VoidCallback retry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        AppButton.outlined(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  ),
);

class LoginScreen extends StatefulWidget {
  const LoginScreen(this.session, {super.key});
  final MobileSession session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  bool busy = false, hidden = true, recovery = false;
  String? error, method;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.session.challenge != null) {
        await widget.session.verify(
          code.text,
          method ?? '${widget.session.challenge!['default_method']}',
          recovery: recovery,
        );
      } else {
        if (email.text.trim().isEmpty || password.text.isEmpty) {
          throw const ApiFailure('Enter your email and password.');
        }
        await widget.session.login(email.text, password.text);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.session.challenge;
    final methods = rows(challenge?['methods']);
    final selected = method ?? '${challenge?['default_method'] ?? 'totp'}';
    return Scaffold(
      backgroundColor: T.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: Brand()),
                  const SizedBox(height: 32),
                  Text(
                    challenge == null ? 'Welcome back.' : 'Verify your sign-in',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    challenge == null
                        ? 'Sign in with your existing work account.'
                        : 'Use your account’s verification method.',
                  ),
                  const SizedBox(height: 24),
                  if (challenge == null) ...[
                    AppTextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Work email',
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: password,
                      obscureText: hidden,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: AppIconButton(
                          tooltip: 'Show password',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                      ),
                    ),
                  ] else ...[
                    if (!recovery && methods.length > 1)
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        items: [
                          for (final m in methods)
                            DropdownMenuItem(
                              value: '${m['key']}',
                              child: Text(
                                '${m['key']} ${m['destination_hint'] ?? ''}',
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() => method = v),
                      ),
                    const SizedBox(height: 12),
                    AppTextFormField(
                      controller: code,
                      decoration: InputDecoration(
                        labelText: recovery
                            ? 'Recovery code'
                            : 'Verification code',
                      ),
                    ),
                    if (challenge['recovery_codes_available'] == true)
                      AppSwitchTile(
                        title: const Text('Use a recovery code'),
                        value: recovery,
                        onChanged: (v) => setState(() => recovery = v),
                      ),
                    if (!recovery &&
                        methods.any(
                          (m) =>
                              m['key'] == selected && m['sends_code'] == true,
                        ))
                      AppButton.text(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() => busy = true);
                                try {
                                  await widget.session.resend(selected);
                                  if (context.mounted) {
                                    mobileNotice(context, 'Code sent.');
                                  }
                                } catch (e) {
                                  if (mounted) setState(() => error = '$e');
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              },
                        child: const Text('Send verification code'),
                      ),
                  ],
                  if (error != null || widget.session.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error ?? widget.session.error!,
                        style: const TextStyle(color: T.danger),
                      ),
                    ),
                  const SizedBox(height: 24),
                  AppButton.filled(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : challenge == null
                          ? 'Sign in'
                          : 'Verify',
                    ),
                  ),
                  if (challenge != null)
                    AppButton.text(
                      onPressed: busy ? null : widget.session.cancelChallenge,
                      child: const Text('Back to login'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NumberPicker extends StatefulWidget {
  const NumberPicker(this.session, {super.key});
  final MobileSession session;
  @override
  State<NumberPicker> createState() => _NumberPickerState();
}

class _NumberPickerState extends State<NumberPicker> {
  List<Json> items = [];
  bool busy = true;
  String? error;
  Json? business;
  int page = 1;
  bool more = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bound = number(widget.session.user?['bound_waba_user_id']);
      if (bound != null) {
        await widget.session.selectNumber(bound);
        return;
      }
      final result = await widget.session.api.get(
        business == null ? 'businesses' : 'numbers',
        query: business == null
            ? {'page': page}
            : {'business_user_id': business!['id']},
      );
      if (!mounted) return;
      setState(() {
        items = [if (append) ...items, ...rows(result['data'])];
        more = result['next_page_url'] != null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        business == null ? 'Choose business' : 'Choose WhatsApp number',
      ),
      leading: business == null
          ? null
          : BackButton(
              onPressed: () {
                setState(() {
                  business = null;
                  page = 1;
                });
                load();
              },
            ),
      actions: [
        AppIconButton(
          tooltip: 'Sign out',
          onPressed: () async {
            try {
              await widget.session.logout();
            } catch (e) {
              if (context.mounted) mobileNotice(context, e);
            }
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? failure(error!, load)
        : ListView(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No available businesses or numbers for this account.',
                  ),
                ),
              for (final item in items)
                AppListTile(
                  leading: Avatar('${item['name'] ?? ''}', size: 40),
                  title: Text(
                    '${item['name'] ?? item['company_name'] ?? 'Business'}',
                  ),
                  subtitle: business == null
                      ? null
                      : Text('${item['phone'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (business == null) {
                      setState(() {
                        business = item;
                        page = 1;
                      });
                      await load();
                    } else {
                      setState(() => busy = true);
                      try {
                        await widget.session.selectNumber(number(item['id'])!);
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            error = '$e';
                            busy = false;
                          });
                        }
                      }
                    }
                  },
                ),
              if (more)
                AppButton.text(
                  onPressed: () {
                    page++;
                    load(append: true);
                  },
                  child: const Text('Load more'),
                ),
            ],
          ),
  );
}

class LiveHome extends StatefulWidget {
  const LiveHome(this.session, {super.key});
  final MobileSession session;
  @override
  State<LiveHome> createState() => _LiveHomeState();
}

class _LiveHomeState extends State<LiveHome> with WidgetsBindingObserver {
  int tab = 0;
  Timer? heartbeat;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    startHeartbeat();
  }

  void startHeartbeat() {
    heartbeat?.cancel();
    heartbeat = Timer.periodic(
      Duration(
        seconds:
            (number(widget.session.config?['heartbeat_interval_seconds']) ?? 30)
                .clamp(15, 300),
      ),
      (_) async {
        try {
          await widget.session.api.post('presence/heartbeat');
        } catch (_) {
          /* Next foreground heartbeat retries presence only. */
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The visible list refreshes itself quietly on resume; rebuilding it here
    // would discard its rows and scroll position and reload from scratch.
    if (state == AppLifecycleState.resumed) {
      startHeartbeat();
    } else {
      heartbeat?.cancel();
    }
  }

  @override
  void dispose() {
    heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Brand(),
      actions: [
        AppIconButton(
          tooltip: 'Switch number',
          onPressed: widget.session.switchNumber,
          icon: const Icon(Icons.swap_horiz),
        ),
        AppIconButton(
          tooltip: 'Sign out',
          onPressed: () async {
            try {
              await widget.session.logout();
            } catch (e) {
              if (context.mounted) mobileNotice(context, e);
            }
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: LiveList(widget.session, kind: tab, key: ValueKey(tab)),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          label: 'Inbox',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          label: 'Contacts',
        ),
        NavigationDestination(
          icon: Icon(Icons.confirmation_number_outlined),
          label: 'Tickets',
        ),
      ],
    ),
  );
}

class LiveList extends StatefulWidget {
  const LiveList(this.session, {required this.kind, super.key});
  final MobileSession session;
  final int kind;
  @override
  State<LiveList> createState() => _LiveListState();
}

class _LiveListState extends State<LiveList> with WidgetsBindingObserver {
  final search = TextEditingController();
  List<Json> items = [];
  String filter = 'all';
  String? error;
  bool busy = false, more = true;
  Timer? debounce, poll;
  int serial = 0;
  // Same tabs and order as the web inbox; tickets have no favourites.
  Map<String, String> get filters => {
    'mychats': 'My chats',
    'all': 'All',
    'unread': 'Unread',
    'unassigned': 'Unassigned',
    if (widget.kind != 2) 'favourite': 'Favourites',
    'closed': 'Closed',
  };
  // Inbox and Contacts request the same contact list, so they share a cache.
  String get cacheKey =>
      "list:${widget.session.api.wabaId}:${widget.kind == 2 ? 'tickets' : 'contacts'}:$filter:${search.text}";

  /// Shows any cached rows for the current filter/search at once, then
  /// refreshes quietly; only an uncached view shows the loading strip.
  void reload() {
    final cached = widget.session.viewCache[cacheKey] as List<Json>?;
    setState(() => items = cached ?? []);
    load(quiet: cached != null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    items = (widget.session.viewCache[cacheKey] as List<Json>?) ?? [];
    load(quiet: items.isNotEmpty);
    startPoll();
  }

  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if ((ModalRoute.of(context)?.isCurrent ?? false) && !busy) {
        load(quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPoll();
      load(quiet: true);
    } else {
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    serial++;
    debounce?.cancel();
    poll?.cancel();
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load({bool append = false, bool quiet = false}) async {
    final request = ++serial;
    if (!quiet) setState(() => busy = true);
    try {
      final List<Json> next;
      if (widget.kind == 2) {
        final result = await widget.session.api.post('inbox/tickets', {
          'listType': filter,
          'search': search.text,
          'limit': 30,
          'offset': append ? items.length : 0,
        });
        next = rows(result['data']);
      } else {
        next = await InboxRepository(widget.session.api).contacts(
          filter: filter,
          search: search.text,
          offset: append ? items.length : 0,
        );
      }
      if (!mounted || request != serial) return;
      final merged = [if (append) ...items, ...next];
      widget.session.viewCache[cacheKey] = merged;
      // Background polls usually return identical rows; skip the rebuild.
      if (!append && error == null && jsonEncode(merged) == jsonEncode(items)) {
        return;
      }
      setState(() {
        items = merged;
        more = next.length == 30;
        error = null;
      });
    } catch (e) {
      if (mounted && request == serial) setState(() => error = '$e');
    } finally {
      if (mounted && request == serial && busy) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: AppTextField(
          controller: search,
          onChanged: (_) {
            debounce?.cancel();
            serial++;
            debounce = Timer(const Duration(milliseconds: 350), reload);
          },
          decoration: InputDecoration(
            hintText: widget.kind == 2
                ? 'Search tickets'
                : 'Search name or number',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: PlatformFilters(
          options: filters.values.toList(),
          selected: filters[filter] ?? 'All',
          scrollable: true,
          onSelected: (label) {
            filter = filters.entries.firstWhere((e) => e.value == label).key;
            reload();
          },
        ),
      ),
      if (widget.kind == 2)
        Align(
          alignment: Alignment.centerRight,
          child: AppButton.textIcon(
            onPressed: () async {
              await openPage(context, CreateTicketPage(widget.session));
              if (mounted) load();
            },
            icon: const Icon(Icons.add),
            label: const Text('New ticket'),
          ),
        ),
      if (widget.kind == 1)
        Align(
          alignment: Alignment.centerRight,
          child: AppButton.textIcon(
            onPressed: () async {
              await openPage(context, ContactEditor(widget.session));
              load();
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add contact'),
          ),
        ),
      LoadingBar(busy),
      if (error != null && items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error!, style: const TextStyle(color: T.danger)),
        ),
      Expanded(
        child: error != null && items.isEmpty
            ? failure(error!, load)
            : RefreshIndicator(
                // The pull indicator is the feedback; avoid a second strip.
                onRefresh: () => load(quiet: true),
                child: ListView.builder(
                  key: PageStorageKey('list:${widget.kind}'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return items.isEmpty && !busy
                          ? const Padding(
                              padding: EdgeInsets.all(30),
                              child: Text(
                                'No results in this view.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : more && items.isNotEmpty
                          ? AppButton.text(
                              onPressed: busy ? null : () => load(append: true),
                              child: const Text('Load more'),
                            )
                          : const SizedBox(height: 24);
                    }
                    final item = items[index];
                    final ticket = widget.kind == 2;
                    final contact = ticket ? object(item['contact']) : item;
                    return LiveConversationRow(
                      session: widget.session,
                      item: item,
                      ticket: ticket,
                      onTap: () async {
                        if (ticket) {
                          await openPage(
                            context,
                            TicketPage(widget.session, number(item['id'])!),
                          );
                        } else {
                          await openPage(
                            context,
                            LiveChat(widget.session, contact),
                          );
                        }
                        if (mounted) load(quiet: true);
                      },
                    );
                  },
                ),
              ),
      ),
    ],
  );
}

class ContactEditor extends StatefulWidget {
  const ContactEditor(this.session, {super.key});
  final MobileSession session;
  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      country = TextEditingController(text: '91');
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New contact')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final field in [
          (name, 'Name'),
          (country, 'Country code'),
          (phone, 'Phone number'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppTextField(
              controller: field.$1,
              decoration: InputDecoration(labelText: field.$2),
            ),
          ),
        if (error != null)
          Text(error!, style: const TextStyle(color: T.danger)),
        AppButton.filled(
          onPressed: busy
              ? null
              : () async {
                  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                    setState(() => error = 'Enter a name and phone number.');
                    return;
                  }
                  setState(() => busy = true);
                  try {
                    await widget.session.api.post('inbox/contact/new', {
                      'name': name.text.trim(),
                      'phone': phone.text.trim(),
                      'country': country.text.trim(),
                    });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Saving…' : 'Create contact'),
        ),
      ],
    ),
  );
}

/// Conversation row matching the approved inbox design, driven by API data:
/// name/time emphasised when unread, last-message ticks, state markers.
class LiveConversationRow extends StatelessWidget {
  const LiveConversationRow({
    super.key,
    required this.session,
    required this.item,
    required this.onTap,
    this.ticket = false,
  });
  final MobileSession session;
  final Json item;
  final bool ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contact = ticket ? object(item['contact']) : item;
    final name =
        '${contact['profile_name'] ?? contact['waba_profile_name'] ?? contact['display_wa_id'] ?? 'Contact'}';
    final last = object(item[ticket ? 'last_thread' : 'last_message']);
    final unread =
        number(item[ticket ? 'unread_message' : 'unread_message_count']) ?? 0;
    final outgoing = last.isNotEmpty && number(last['type']) == 1;
    final status = number(last['message_status']) ?? 0;
    final me = number(session.user?['id']);
    final favourites = decoded(contact['favourite']);
    final favourite =
        !ticket &&
        me != null &&
        favourites is List &&
        favourites.map(number).contains(me);
    final preview = ticket
        ? '$name · ${object(item['status'])['name'] ?? ''}'
        : last.isNotEmpty
        ? MessageContent(last).summary.replaceAll('\n', ' ')
        : 'No messages yet';
    final time = const MobileClock().listTime(
      last['created_at'] ?? item['last_message_date'],
    );
    final strong = unread > 0;
    Widget marker(IconData icon, String label, Color color) => Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Tooltip(
        message: label,
        child: AppIcon(icon, size: 13, color: color),
      ),
    );
    return Semantics(
      button: true,
      label: '$name${strong ? ', $unread unread' : ''}',
      child: InkWell(
        key: ValueKey('live-row-${item['id']}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Avatar(name, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket
                                ? '${item['subject'] ?? item['ticket_number'] ?? 'Ticket'}'
                                : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: strong
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          time,
                          style: mono(
                            size: 11,
                            color: strong ? T.green : T.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (outgoing && !ticket)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: AppIcon(
                              switch (status) {
                                0 => Icons.schedule,
                                1 => Icons.check,
                                4 || 5 => Icons.error_outline,
                                _ => Icons.done_all,
                              },
                              size: 15,
                              color: switch (status) {
                                3 => T.blue,
                                4 || 5 => T.danger,
                                _ => T.muted,
                              },
                            ),
                          ),
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: strong ? T.ink : T.secondary,
                            ),
                          ),
                        ),
                        if (!ticket && number(contact['conversation_status']) == 0)
                          marker(Icons.lock_outline, 'Closed', T.muted),
                        if (!ticket &&
                            number(contact['conversation_owner_type']) == 1)
                          marker(Icons.smart_toy_outlined, 'Bot', T.brass),
                        if (!ticket && flag(contact['is_blocked']))
                          marker(Icons.block, 'Blocked', T.danger),
                        if (!ticket && flag(contact['is_dnd']))
                          marker(
                            Icons.do_not_disturb_on_outlined,
                            'Do not disturb',
                            T.muted,
                          ),
                        if (favourite)
                          marker(Icons.star_rounded, 'Favourite', T.muted),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 7),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: T.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unread >= 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: mono(size: 10, color: Colors.white),
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
      ),
    );
  }
}
