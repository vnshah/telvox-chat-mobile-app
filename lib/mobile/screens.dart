import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'chat.dart';
import 'models.dart';
import 'realtime.dart';
import 'list_sync.dart';
import 'message_content.dart';
import 'send_policy.dart' show flag;
import 'tickets.dart';

void mobileNotice(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$message')));
}

Future<R?> openPage<R>(BuildContext context, Widget page) =>
    Navigator.of(context).push<R>(MaterialPageRoute(builder: (_) => page));

/// Shows a quiet strip only when live updates stay down for a while. Brief
/// blips (network handover, server restart) reconnect unseen, as on the web.
class RealtimeNotice extends StatefulWidget {
  const RealtimeNotice(this.realtime, {super.key});
  final Realtime realtime;
  @override
  State<RealtimeNotice> createState() => _RealtimeNoticeState();
}

class _RealtimeNoticeState extends State<RealtimeNotice> {
  Timer? grace;
  bool shown = false;
  @override
  void initState() {
    super.initState();
    widget.realtime.addListener(changed);
    changed();
  }

  void changed() {
    final down = widget.realtime.state == RealtimeState.reconnecting;
    if (!down) {
      grace?.cancel();
      grace = null;
      if (shown && mounted) setState(() => shown = false);
      return;
    }
    grace ??= Timer(const Duration(seconds: 8), () {
      if (mounted && widget.realtime.state == RealtimeState.reconnecting) {
        setState(() => shown = true);
      }
    });
  }

  @override
  void dispose() {
    grace?.cancel();
    widget.realtime.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 150),
    child: !shown
        ? const SizedBox(width: double.infinity)
        : Container(
            width: double.infinity,
            color: const Color(0xFFFFF4D6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Text(
              'Reconnecting to live updates…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: T.secondary),
            ),
          ),
  );
}

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
    final apple = isCupertino(context);
    return Scaffold(
      backgroundColor: apple ? T.iosGrouped : T.surface,
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
                    challenge == null ? 'Welcome back' : 'Verify your sign-in',
                    style: apple
                        ? CupertinoTheme.of(context)
                              .textTheme
                              .navLargeTitleTextStyle
                        : const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -.3,
                            color: T.ink,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    challenge == null
                        ? 'Sign in with your work account.'
                        : 'Use your account’s verification method.',
                    style: const TextStyle(fontSize: 15, color: T.secondary),
                  ),
                  const SizedBox(height: 24),
                  if (challenge == null && apple)
                    // iOS: both fields in one grouped card, as in Settings.
                    Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Column(
                        children: [
                          CupertinoTextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            placeholder: 'Work email',
                            decoration: null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                          ),
                          Container(
                            height: .5,
                            margin: const EdgeInsets.only(left: 16),
                            color: T.iosSeparator,
                          ),
                          CupertinoTextField(
                            controller: password,
                            obscureText: hidden,
                            placeholder: 'Password',
                            decoration: null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            suffix: CupertinoButton(
                              padding: const EdgeInsets.only(right: 12),
                              onPressed: () => setState(() => hidden = !hidden),
                              child: Icon(
                                hidden
                                    ? CupertinoIcons.eye
                                    : CupertinoIcons.eye_slash,
                                size: 20,
                                color: T.muted,
                                semanticLabel: 'Show password',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (challenge == null) ...[
                    // Android: compact Material 3 outlined fields.
                    AppTextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Work email',
                        prefixIcon: Icon(Icons.mail_outline, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppTextFormField(
                      controller: password,
                      obscureText: hidden,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: AppIconButton(
                          tooltip: 'Show password',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
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
  Timer? heartbeat;
  RealtimeSubscription? device;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    startHeartbeat();
    final channel = widget.session.deviceChannel;
    if (channel != null) {
      device = widget.session.realtime.listen(channel, (event, _) {
        if (event == 'device.revoked') widget.session.deviceRevoked();
      });
    }
    widget.session.realtime.start();
    widget.session.push.enable();
    widget.session.addListener(openPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => openPending());
  }

  bool opening = false;

  /// Opens the chat or ticket from a tapped notification. A push for another
  /// number switches to it first; the new home screen then finishes the job.
  Future<void> openPending() async {
    final session = widget.session;
    final data = session.pendingOpen;
    if (data == null || opening || !mounted) return;
    opening = true;
    try {
      final waba = number(data['waba_user_id']);
      if (waba != null && waba != session.api.wabaId) {
        await session.selectNumber(waba);
        return;
      }
      session.pendingOpen = null;
      final ticketId = number(data['ticket_id']);
      final contactId = number(data['contact_id']);
      // In ticketing mode a conversation only opens through its ticket.
      if (ticketId == null && session.inboxMode != InboxMode.shared) return;
      if (ticketId != null) {
        await openPage(context, TicketPage(session, ticketId));
      } else if (contactId != null) {
        final details = await session.api.post('inbox/getContactDetails', {
          'contact_id': contactId,
        });
        final contact = object(object(details['data'])['contact']);
        if (mounted && contact.isNotEmpty) {
          await openPage(context, LiveChat(session, contact));
        }
      }
    } catch (e) {
      session.pendingOpen = null;
      if (mounted) mobileNotice(context, e);
    } finally {
      opening = false;
    }
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
    // Live updates stop in background (Android would cut the socket anyway)
    // and resume on return; every open screen then catches up once.
    if (state == AppLifecycleState.resumed) {
      startHeartbeat();
      widget.session.realtime.start();
    } else {
      heartbeat?.cancel();
      if (state == AppLifecycleState.paused) widget.session.realtime.stop();
    }
  }

  @override
  void dispose() {
    heartbeat?.cancel();
    device?.cancel();
    refresh.dispose();
    widget.session.removeListener(openPending);
    widget.session.realtime.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lists reload after the home screen creates a contact or ticket.
  final refresh = ValueNotifier(0);

  InboxMode get mode => widget.session.inboxMode;

  /// The one main action: Add contact in the shared inbox, New ticket in the
  /// ticket inbox (where the ticket form can also create the contact).
  Future<void> create() async {
    if (mode == InboxMode.tickets) {
      final created = await openPage<Object?>(
        context,
        CreateTicketPage(widget.session),
      );
      if (mounted && created != false) refresh.value++;
      return;
    }
    // Shared inbox: a quick sheet, then straight into the new conversation.
    // A new contact has no customer message yet, so the chat offers templates
    // only until the customer writes.
    final contact = await showQuickAddContact(context, widget.session);
    if (!mounted || contact == null) return;
    refresh.value++;
    await openPage(context, LiveChat(widget.session, contact));
  }

  Future<void> signOut() async {
    try {
      await widget.session.logout();
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    }
  }

  /// The account menu: a Material menu on Android, an action sheet on iOS.
  Future<void> account() async {
    final name = '${widget.session.user?['name'] ?? 'Account'}';
    if (isCupertino(context)) {
      final out = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (popup) => CupertinoActionSheet(
          title: Text(name),
          message: Text('${widget.session.user?['email'] ?? ''}'),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(popup, true),
              child: const Text('Sign Out'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popup),
            child: const Text('Cancel'),
          ),
        ),
      );
      if (out == true) await signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final mode = this.mode;
    final tickets = mode == InboxMode.tickets;
    final title = tickets ? 'Tickets' : 'Inbox';
    final initials = '${session.user?['name'] ?? '?'}'
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final body = mode == InboxMode.none
        ? const _NoInbox()
        : Column(
            children: [
              RealtimeNotice(session.realtime),
              Expanded(
                child: LiveList(
                  session,
                  kind: tickets ? 2 : 0,
                  key: ValueKey(mode),
                  refresh: refresh,
                ),
              ),
            ],
          );
    final createLabel = tickets ? 'New ticket' : 'Add contact';
    if (isCupertino(context)) {
      // iOS: number picker and actions in the navigation bar, then a large
      // title. One inbox, so no tab bar.
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: session.switchNumber,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.wabaName,
                            style: const TextStyle(
                              fontSize: 16,
                              color: T.green,
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: T.green,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (mode != InboxMode.none)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: create,
                        child: Icon(
                          tickets
                              ? CupertinoIcons.plus
                              : CupertinoIcons.person_badge_plus,
                          semanticLabel: createLabel,
                        ),
                      ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 6, right: 14),
                      onPressed: account,
                      child: const Icon(
                        CupertinoIcons.person_crop_circle,
                        size: 26,
                        semanticLabel: 'Account',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle,
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    // Android: Material 3 top app bar and one floating action button.
    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ActionChip(
              avatar: const Icon(Icons.swap_horiz, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(session.wabaName, overflow: TextOverflow.ellipsis),
              ),
              tooltip: 'Switch number',
              onPressed: session.switchNumber,
              side: const BorderSide(color: T.control),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            position: PopupMenuPosition.under,
            onSelected: (v) {
              if (v == 'signout') signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  '${session.user?['name'] ?? 'Account'}',
                  style: const TextStyle(
                    color: T.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: T.selected,
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: T.onSelected,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: body,
      floatingActionButton: mode == InboxMode.none
          ? null
          : tickets
          ? FloatingActionButton.extended(
              onPressed: create,
              icon: const Icon(Icons.add),
              label: Text(createLabel),
            )
          : FloatingActionButton(
              tooltip: createLabel,
              onPressed: create,
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
    );
  }
}

/// Shown when the selected number allows neither inbox for this account.
class _NoInbox extends StatelessWidget {
  const _NoInbox();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(Icons.lock_outline, size: 40, color: T.brass),
          SizedBox(height: 12),
          Text(
            'No inbox access for this number',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Your account cannot open the shared inbox or tickets here. '
            'Switch number, or ask an admin for access.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: T.secondary),
          ),
        ],
      ),
    ),
  );
}

class LiveList extends StatefulWidget {
  const LiveList(this.session, {required this.kind, super.key, this.refresh});
  final MobileSession session;
  final int kind;

  /// Fired by the home screen after it creates a contact or ticket.
  final Listenable? refresh;
  @override
  State<LiveList> createState() => _LiveListState();
}

class _LiveListState extends State<LiveList> with WidgetsBindingObserver {
  final search = TextEditingController();
  List<Json> items = [];
  String filter = 'all';
  String? error;
  bool busy = false, more = true;
  Timer? debounce, liveDebounce;
  RealtimeSubscription? live;
  int serial = 0;
  // Agent names by id, for the assignee initials on each row.
  Map<int, String> people = {};
  // Same tabs and order as the web inbox; tickets have no favourites.
  Map<String, String> get filters => {
    'all': 'All',
    'mychats': widget.kind == 2 ? 'Mine' : 'My chats',
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
    if (cached != null) {
      load(quiet: true);
    } else {
      openFromDevice();
    }
  }

  ListSync get sync => widget.kind == 2 ? ListSync.tickets : ListSync.contacts;

  /// Searches are not kept on the phone; each tab's own list is.
  bool get persisted => search.text.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    items = (widget.session.viewCache[cacheKey] as List<Json>?) ?? [];
    if (items.isNotEmpty) {
      load(quiet: true);
    } else {
      openFromDevice();
    }
    loadPeople();
    subscribeLive();
    widget.refresh?.addListener(load);
    widget.session.conversationActivity.addListener(followChat);
  }

  /// An open chat synced a newer message: its row moves now, without a
  /// request. Conversations this list does not show are left to the server.
  void followChat() {
    final activity = widget.session.conversationActivity.value;
    if (activity == null || widget.kind == 2) return;
    final next = sync.follow(items, activity, filter: filter);
    if (next == null || !mounted) return;
    keep(next);
    setState(() => items = next);
  }

  /// Shows the list kept on the phone from the last visit at once, then
  /// refreshes quietly in the background.
  Future<void> openFromDevice() async {
    final key = cacheKey, request = serial;
    List<Json>? saved;
    if (persisted) {
      try {
        saved = await widget.session.cache.list(key);
      } catch (_) {}
    }
    if (!mounted || key != cacheKey || request != serial) return;
    if (saved != null && items.isEmpty) {
      widget.session.viewCache[key] = saved;
      setState(() => items = saved!);
    }
    load(quiet: items.isNotEmpty);
  }

  /// Remembers the list for the next visit, on the phone and for this run.
  void keep(List<Json> rows) {
    widget.session.viewCache[cacheKey] = rows;
    if (persisted) {
      widget.session.cache.putList(cacheKey, rows).catchError((_) {});
    }
  }

  /// Same channels as the web inbox and ticket inbox. Each event means "the
  /// list changed"; one quiet refresh then fetches the rows with the server's
  /// own filtering, so the app never guesses where a conversation belongs.
  void subscribeLive() {
    final session = widget.session;
    final channel = widget.kind == 2
        ? session.authUserId == null
              ? null
              : 'ticket.agent.${session.authUserId}'
        : session.wabaPhone == null
        ? null
        : 'inbox.user.list.update.${session.api.wabaId}.${session.wabaPhone}';
    if (channel == null) return;
    live = session.realtime.listen(
      channel,
      (_, data) => liveEvent(data),
      onResync: liveRefresh,
    );
  }

  /// A conversation the list already shows moves to its new place at once,
  /// from the event; the server's first page then confirms it. Anything the
  /// list does not show yet comes only from the server, which applies this
  /// account's permissions and the tab's filter.
  void liveEvent(Object? data) {
    final row = object(object(data)['contact']);
    final patched = row.isEmpty || widget.kind == 2
        ? null
        : sync.patch(items, row, filter: filter);
    if (patched != null) {
      keep(patched);
      setState(() => items = patched);
    }
    liveRefresh();
  }

  /// Bursts (a message plus its status updates) collapse into one request.
  void liveRefresh() {
    liveDebounce?.cancel();
    liveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) load(quiet: true, firstPage: true);
    });
  }

  /// One request per session and number; rows show initials without names
  /// until it answers, and simply omit them if it fails.
  Future<void> loadPeople() async {
    final key = 'users:${widget.session.api.wabaId}';
    final cached = widget.session.viewCache[key] as Map<int, String>?;
    if (cached != null) {
      people = cached;
      return;
    }
    try {
      final list = rows(await widget.session.api.request('inbox/users'));
      final next = {
        for (final u in list)
          if (number(u['id']) case final int id) id: '${u['name'] ?? ''}',
      };
      widget.session.viewCache[key] = next;
      if (mounted) setState(() => people = next);
    } catch (_) {
      /* Assignee initials are optional decoration. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Covers the case where live updates are unavailable; with them, the
    // channel's resync on reconnect does the same.
    if (state == AppLifecycleState.resumed) load(quiet: true, firstPage: true);
  }

  @override
  void dispose() {
    serial++;
    debounce?.cancel();
    liveDebounce?.cancel();
    live?.cancel();
    widget.refresh?.removeListener(load);
    widget.session.conversationActivity.removeListener(followChat);
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// [firstPage]: a background check after a live event or resume. Only the
  /// first page is read and reconciled; rows further down stay as loaded.
  Future<void> load({
    bool append = false,
    bool quiet = false,
    bool firstPage = false,
  }) async {
    final request = ++serial;
    if (!quiet) setState(() => busy = true);
    // A plain quiet refresh (pull, the + action) re-reads the pages already
    // scrolled through, so it never drops rows loaded with "Load more".
    final limit = append || !quiet || firstPage
        ? 30
        : items.length.clamp(30, 100);
    try {
      final List<Json> next;
      if (widget.kind == 2) {
        final result = await widget.session.api.post('inbox/tickets', {
          'listType': filter,
          'search': search.text,
          'limit': limit,
          'offset': append ? items.length : 0,
        });
        next = rows(result['data']);
      } else {
        next = await InboxRepository(widget.session.api).contacts(
          filter: filter,
          search: search.text,
          offset: append ? items.length : 0,
          limit: limit,
        );
      }
      if (!mounted || request != serial) return;
      final merged = append
          ? sync.append(items, next)
          : firstPage
          ? sync.reconcile(items, next, complete: next.length < limit)
          : next;
      // Live refreshes often return identical rows; skip the rebuild.
      if (!append && error == null && jsonEncode(merged) == jsonEncode(items)) {
        return;
      }
      keep(merged);
      setState(() {
        items = merged;
        if (!firstPage) more = next.length == limit;
        error = null;
      });
    } catch (e) {
      if (mounted && request == serial) setState(() => error = '$e');
    } finally {
      if (mounted && request == serial && busy) setState(() => busy = false);
    }
  }

  void searched(String _) {
    debounce?.cancel();
    serial++;
    debounce = Timer(const Duration(milliseconds: 350), reload);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      // Native search: Material 3 search bar, or the iOS search field.
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: isCupertino(context)
            ? CupertinoSearchTextField(
                controller: search,
                onChanged: searched,
                placeholder: widget.kind == 2 ? 'Search tickets' : 'Search',
              )
            : SearchBar(
                controller: search,
                onChanged: searched,
                hintText: widget.kind == 2
                    ? 'Search tickets'
                    : 'Search name or number',
                leading: const Icon(Icons.search, color: T.secondary),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
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
                      people: people,
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

/// Opens the quick-add sheet and returns the saved contact, or null.
Future<Json?> showQuickAddContact(
  BuildContext context,
  MobileSession session,
) => showModalBottomSheet<Json>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => QuickAddContact(session),
);

/// A compact add-contact panel, like the quick replies sheet: name and number,
/// then Save. The server refuses a number already saved on this WhatsApp number.
class QuickAddContact extends StatefulWidget {
  const QuickAddContact(this.session, {super.key});
  final MobileSession session;
  @override
  State<QuickAddContact> createState() => _QuickAddContactState();
}

class _QuickAddContactState extends State<QuickAddContact> {
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

  String digits(TextEditingController c) =>
      c.text.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> save() async {
    final code = digits(country), number = digits(phone);
    if (name.text.trim().isEmpty || number.isEmpty || code.isEmpty) {
      setState(() => error = 'Enter a name, country code and phone number.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.api.post('inbox/contact/new', {
        'name': name.text.trim(),
        'phone': number,
        'country': code,
      });
      final contact = object(result['data']);
      if (mounted) Navigator.pop(context, contact.isEmpty ? null : contact);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    // Rides above the keyboard.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add contact',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            AppTextFormField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Name',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: AppTextFormField(
                    controller: country,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      hintText: 'Code',
                      prefixText: '+',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: 'Phone number',
                    ),
                  ),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  error!,
                  style: const TextStyle(color: T.danger, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            AppButton.filled(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
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
    this.people = const {},
  });
  final MobileSession session;
  final Json item;
  final bool ticket;
  final Map<int, String> people;
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
    final receipt = number(last['message_status']) ?? 0;
    final me = number(session.user?['id']);
    final favourites = decoded(contact['favourite']);
    final favourite =
        !ticket &&
        me != null &&
        favourites is List &&
        favourites.map(number).contains(me);
    final content = last.isEmpty || ticket ? null : MessageContent(last);
    final preview = ticket
        ? name
        : content != null
        ? content.summary.replaceAll('\n', ' ')
        : 'No messages yet';
    // A proper icon for the message kind, never an emoji.
    final kindIcon = switch (content?.kind) {
      'missed_call' => Icons.call_missed,
      'call' => Icons.call_outlined,
      'image' => Icons.image_outlined,
      'video' => Icons.videocam_outlined,
      'audio' => Icons.mic_none_rounded,
      'document' => Icons.description_outlined,
      'sticker' => Icons.emoji_emotions_outlined,
      'location' => Icons.location_on_outlined,
      'contact' => Icons.person_outline,
      _ => null,
    };
    final time = const MobileClock().listTime(
      last['created_at'] ?? item['last_message_date'],
    );
    final strong = unread > 0;
    final assignedIds = (contact['assigned_user_ids'] as List?) ?? const [];
    final assigneeId = ticket
        ? number(item['assign_user_id'])
        : assignedIds.isNotEmpty
        ? number(assignedIds.first)
        : number(contact['assigned_to']);
    final assignee = assigneeId == null
        ? null
        : assigneeId == me
        ? 'You'
        : '${object(item['assign_user'])['name'] ?? people[assigneeId] ?? ''}';
    final status = ticket
        ? '${object(item['status'])['name'] ?? item['status_name'] ?? ''}'
        : '';
    final priority = ticket ? '${object(item['priority'])['name'] ?? ''}' : '';
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
                              switch (receipt) {
                                0 => Icons.schedule,
                                1 => Icons.check,
                                4 || 5 => Icons.error_outline,
                                _ => Icons.done_all,
                              },
                              size: 15,
                              color: switch (receipt) {
                                3 => T.blue,
                                4 || 5 => T.danger,
                                _ => T.muted,
                              },
                            ),
                          ),
                        if (kindIcon != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: AppIcon(
                              kindIcon,
                              size: 16,
                              color: kindIcon == Icons.call_missed
                                  ? T.danger
                                  : T.muted,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: strong ? T.ink : T.secondary,
                            ),
                          ),
                        ),
                        if (!ticket &&
                            number(contact['conversation_status']) == 0)
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
                        if (status.isNotEmpty)
                          _RowChip(
                            status,
                            flag(item['status_is_closed']) ? T.muted : T.green,
                          ),
                        if (priority.isNotEmpty) _RowChip(priority, T.brass),
                        if (assignee != null && assignee.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Tooltip(
                              message: 'Assigned to $assignee',
                              child: _Initials(assignee),
                            ),
                          )
                        else if (ticket && assigneeId == null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              'UNASSIGNED',
                              style: mono(size: 9, color: T.muted),
                            ),
                          ),
                        // WhatsApp's count of new messages: a green pill
                        // under the time, which turns green with it.
                        if (unread > 0)
                          Container(
                            key: ValueKey('unread-${item['id']}'),
                            margin: const EdgeInsets.only(left: 8),
                            constraints: const BoxConstraints(
                              minWidth: 21,
                              minHeight: 21,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: T.green,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              unread >= 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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

class _Initials extends StatelessWidget {
  const _Initials(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: T.selected, shape: BoxShape.circle),
    child: Text(
      name == 'You'
          ? 'Y'
          : name
                .trim()
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s[0])
                .join()
                .toUpperCase(),
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: T.forest,
      ),
    ),
  );
}

class _RowChip extends StatelessWidget {
  const _RowChip(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    constraints: const BoxConstraints(maxWidth: 90),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}
