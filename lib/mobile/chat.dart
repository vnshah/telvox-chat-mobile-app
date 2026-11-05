import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import '../ui/data.dart' show Message;
import '../ui/conversation.dart' show ChatWallpaper;
import 'call_history.dart';
import 'camera.dart';
import 'calls.dart';
import 'conversation_search.dart';
import 'conversation_window.dart';
import 'api.dart';
import 'models.dart';
import 'screens.dart';
import 'media.dart';
import 'media_quality.dart';
import 'send_media.dart';
import 'composer.dart';
import 'local_cache.dart';
import 'contact_actions.dart';
import 'message_content.dart' show readableText;
import 'templates.dart';
import 'message_info.dart';
import 'message_view.dart';
import 'editors.dart' show EditField, showEditorSheet;
import 'location.dart';
import 'maps.dart';
import 'send_policy.dart';
import 'realtime.dart';

/// Photos, videos and the phone's position; tests replace them.
@visibleForTesting
MediaPicker mediaPicker = DeviceMediaPicker();
@visibleForTesting
LocationSource locationSource = DeviceLocationSource();

/// The app's camera; tests replace it.
@visibleForTesting
Future<CapturedMedia?> Function(BuildContext context) openCamera = (context) =>
    Navigator.of(context, rootNavigator: true).push<CapturedMedia>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraScreen(onGallery: mediaPicker.galleryItem),
      ),
    );

/// The preview of picked photos and videos, to [to]; tests replace it.
@visibleForTesting
Future<MediaBatch?> Function(
  BuildContext context,
  List<Attachment> items,
  String to,
)
openSendMedia = (context, items, to) =>
    Navigator.of(context, rootNavigator: true).push<MediaBatch>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SendMediaPage(items, recipient: to),
      ),
    );

class LiveChat extends StatefulWidget {
  const LiveChat(this.session, this.contact, {super.key, this.ticketId});
  final MobileSession session;
  final Json contact;
  final int? ticketId;
  @override
  State<LiveChat> createState() => _LiveChatState();
}

class _LiveChatState extends State<LiveChat> with WidgetsBindingObserver {
  final composer = TextEditingController(), scroll = ScrollController();
  // Drives only the scroll-to-latest button, so scrolling never rebuilds
  // the conversation itself.
  final scrolledUp = ValueNotifier(false);
  List<ApiMessage> messages = [];
  final pending = <PendingSend>[];
  ApiMessage? reply;

  /// The message long-pressed, as WhatsApp selects one: the top bar turns
  /// into its actions, its row turns green and its reactions float above it.
  ApiMessage? selected;

  /// Where the selected bubble is on screen, for the reactions above it.
  Rect? selectedAt;

  /// The reactions show until the chat scrolls.
  bool reacting = false;
  final bodyKey = GlobalKey();
  Attachment? attachment;
  bool picking = false;
  Json? detail, ticket;
  bool detailsBusy = false, showLoading = false;
  bool windowRejected = false, reopening = false;
  bool get closed =>
      widget.ticketId == null &&
      number(object(detail?['contact'])['conversation_status']) == 0;
  String get cacheKey =>
      "chat:${widget.session.api.wabaId}:$contactId:${widget.ticketId}";
  String get detailKey => 'detail:$cacheKey';
  SendPolicy get policy => windowRejected
      ? SendPolicy(
          "Messaging window closed. Send an approved template, or wait for a new customer message.",
          SendPolicy.evaluate(
            widget.session,
            detail,
            ticket: ticket,
          ).canTemplate,
          null,
        )
      : SendPolicy.evaluate(widget.session, detail, ticket: ticket);
  String? error, sync;
  // `busy` guards overlapping requests and is not display state; quiet
  // refreshes must not rebuild the screen just to toggle it. `again` records a
  // live event that arrived mid-request, so it is fetched right after.
  bool busy = false, more = false, loadedOnce = false, again = false;
  int? oldest;

  /// The kept copy was too old to catch up change by change: the next read
  /// starts over from the newest page instead, so history never has a gap.
  bool replaceNext = false;

  /// Opened from the phone's copy: the first read is the newest page in full,
  /// not only what changed since the copy's cursor. A change-only catch-up
  /// can never bring back a message the copy is missing (an older build left
  /// out a chat's bot and automation messages that way, and they stayed out),
  /// so the copy is checked against the server each time the chat opens.
  bool verifyNext = false;

  /// True while the list shows a page around a found or quoted message and
  /// newer messages lie beyond it, not yet loaded. Scrolling down pages them
  /// in until the list meets the live chat again.
  bool newerMore = false;

  /// The message just jumped to, lit up for a moment.
  int? highlightId;
  Timer? highlightTimer;
  final highlightKey = GlobalKey();

  /// Builds every row for a frame, so the jumped-to row can be scrolled to.
  bool reaching = false;

  /// Rows that arrived while the chat was on screen, by row key; each pops
  /// in once, the first time it is built.
  final popIn = <String>{};

  /// Beyond this, catching up change by change costs more than starting over.
  static const catchUpLimit = Duration(days: 3);

  /// Where this conversation's next sync starts, kept with its messages.
  Json get cursor => {
    'sync': sync,
    'oldest': oldest,
    'more': more,
    'synced_at': DateTime.now().toUtc().toIso8601String(),
  };

  /// Renders from this run's memory or the phone's copy at once, then asks
  /// the server only for what changed since the saved cursor.
  Future<void> openConversation() async {
    final memory = widget.session.viewCache[cacheKey] as List<ApiMessage>?;
    var saved = memory == null
        ? null
        : CachedConversation(
            const [],
            object(widget.session.viewCache['cursor:$cacheKey']),
          );
    if (memory != null) {
      messages = memory;
    } else {
      try {
        saved = await widget.session.cache.conversation(cacheKey);
      } catch (_) {}
      if (!mounted) return;
      if (saved != null && saved.messages.isNotEmpty) {
        setState(() => messages = saved!.messages.map(ApiMessage.new).toList());
      }
    }
    final c = saved?.cursor ?? const <String, dynamic>{};
    final syncedAt = DateTime.tryParse('${c['synced_at'] ?? ''}');
    if (messages.isNotEmpty && saved != null) {
      // However old the copy, it stays on screen and is checked against the
      // newest page (see [heal]); it is never swapped out wholesale.
      final stale =
          syncedAt == null ||
          DateTime.now().toUtc().difference(syncedAt) > catchUpLimit;
      sync = stale ? null : c['sync'] as String?;
      // Older history continues from the oldest message actually kept.
      oldest = number(messages.first.id);
      // The phone keeps only the newest messages; older ones page in.
      more =
          c['more'] == true || messages.length >= cacheMessagesPerConversation;
      loadedOnce = true;
      // Synced in the background a moment ago (see ConversationSync): the
      // copy is current, so only changes since then are asked for.
      final fresh =
          syncedAt != null &&
          DateTime.now().toUtc().difference(syncedAt) <
              const Duration(minutes: 1);
      verifyNext = widget.ticketId == null && !fresh;
    }
    load(quiet: messages.isNotEmpty);
  }

  /// Keeps what the server just returned, for this run and the next launch,
  /// and moves this conversation's inbox row to its latest message.
  void remember([List<ApiMessage> rows = const [], bool replace = false]) {
    // A page around an older message is not the conversation's newest: the
    // kept copy waits until the list meets the live chat again.
    if (newerMore) return;
    if (rows.isNotEmpty) announce();
    final c = cursor;
    widget.session.viewCache[cacheKey] = messages;
    widget.session.viewCache['cursor:$cacheKey'] = c;
    widget.session.cache
        .putMessages(
          cacheKey,
          [for (final m in rows) m.json],
          c,
          replace: replace,
        )
        .catchError((_) {});
  }

  final live = <RealtimeSubscription>[];
  Timer? liveDebounce;
  late final repository = InboxRepository(widget.session.api);
  int get contactId => number(widget.contact['id'])!;

  /// When the conversation window closes, from the contact and its messages.
  DateTime? get windowExpires =>
      windowExpiresAt(callContact, [for (final m in messages) m.json]);

  /// The header's window, shared with the inbox row once drawn, so the
  /// list shows the same green dot.
  DateTime? get rememberedWindow {
    final expires = windowExpires;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => rememberWindow(contactId, expires),
    );
    return expires;
  }

  /// The contact as the call rules read it: the list row, updated by details.
  Json get callContact => {...widget.contact, ...object(detail?['contact'])};
  bool get callable =>
      widget.ticketId == null &&
      callEligibility(widget.session.config, callContact).blocked == null &&
      callEligibility(widget.session.config, callContact).shown;
  String get phone => '${widget.contact['wa_id'] ?? ''}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(() {
      // Scrolling away from a selected message puts its reactions away.
      if (reacting) setState(() => reacting = false);
      scrolledUp.value = newerMore || scroll.offset > 400;
      if (scroll.offset < 40 && !newerMore) unseen.value = 0;
      // Not while scrolling to a jumped-to message: only the reader's own
      // scroll down pages newer messages in.
      if (newerMore && !reaching && scroll.offset < 300) loadNewer();
    });
    final cached = widget.session.viewCache[detailKey] as List<Json?>?;
    if (cached != null) {
      detail = cached.first;
      ticket = cached.last;
    }
    openConversation();
    details();
    subscribeLive();
    focus(true);
    widget.session.visibleConversation = visibleKey;
    widget.session.visibleContacts.add('contact:$contactId');
  }

  String get visibleKey => widget.ticketId != null
      ? 'ticket:${widget.ticketId}'
      : 'contact:$contactId';

  /// The web inbox's channels for one conversation: sends and their status,
  /// incoming messages, reactions and activity (assign/close) — or the
  /// ticket's own channel. Events are signals; the incremental catch-up
  /// request then fetches exactly what changed, using the merge that already
  /// reconciles optimistic sends. Contact details refresh when [load] sees
  /// new incoming or activity rows, or when an activity event arrives.
  void subscribeLive() {
    final realtime = widget.session.realtime;
    final waba = widget.session.api.wabaId;
    final channels = widget.ticketId != null
        ? ['ticket.message.${widget.ticketId}']
        : phone.isEmpty || waba == null
        ? <String>[]
        : [
            'send.message.$waba.$phone',
            'receive.message.$waba.$phone',
            'receive.reaction.$waba.$phone',
            'change.log.$waba.$phone',
          ];
    for (final channel in channels) {
      // Kept joined after leaving, so coming straight back signs in nothing.
      realtime.keep(channel);
      live.add(
        realtime.listen(
          channel,
          (event, _) => liveRefresh(details: event == 'change.log.created'),
          onResync: () => liveRefresh(details: true),
        ),
      );
    }
  }

  bool _detailsWanted = false;

  void liveRefresh({bool details = false}) {
    _detailsWanted |= details;
    // A send fires sending/sent/status in quick succession, and coming back
    // to the app fires a resume and a channel resync: one request for each.
    liveDebounce?.cancel();
    liveDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (_detailsWanted) this.details();
      _detailsWanted = false;
      load(quiet: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Covers devices where live updates are unavailable; otherwise the
    // channel resync on reconnect does the same.
    if (state == AppLifecycleState.resumed) {
      // The same debounced refresh the channels' resync asks for, so coming
      // back fetches once, not once for the app and again for the socket.
      liveRefresh(details: true);
      focus(true);
    } else if (state == AppLifecycleState.paused) {
      focus(false);
    }
  }

  bool focused = false;
  DateTime? typedAt;

  /// Tells the server this chat is open on the phone (as the web inbox does),
  /// so messages arriving while it is on screen are not counted as unread and
  /// opening it marks it read; leaving or backgrounding the app releases it.
  void focus(bool open) {
    if (widget.ticketId != null || open == focused) return;
    focused = open;
    unawaited(widget.session.focusChat(contactId, open: open));
  }

  /// WhatsApp shows the customer "typing…" for up to 25 seconds per
  /// indicator, so it is re-sent at most every 20 seconds while typing.
  void typing() {
    if (!policy.canSend) return;
    final now = DateTime.now();
    if (typedAt != null &&
        now.difference(typedAt!) < const Duration(seconds: 20)) {
      return;
    }
    typedAt = now;
    widget.session.api
        .post('inbox/typing', {'contact_id': contactId})
        .catchError((_) => <String, dynamic>{});
  }

  @override
  void dispose() {
    focus(false);
    if (widget.session.visibleConversation == visibleKey) {
      widget.session.visibleConversation = null;
    }
    widget.session.visibleContacts.remove('contact:$contactId');
    liveDebounce?.cancel();
    highlightTimer?.cancel();
    for (final sub in live) {
      sub.cancel();
    }
    composer.dispose();
    scroll.dispose();
    scrolledUp.dispose();
    unseen.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> details() async {
    if (detailsBusy) return;
    detailsBusy = true;
    try {
      final Json nextDetail;
      final Json? nextTicket;
      if (widget.ticketId != null) {
        // A ticket conversation reads only the ticket: in ticketing mode the
        // shared inbox's contact details are not available to this account.
        final data = object(
          (await widget.session.api.post('inbox/ticket_details', {
            'ticket_id': widget.ticketId,
          }))['data'],
        );
        nextTicket = object(data['ticket']);
        nextDetail = ticketSendDetail(data);
      } else {
        nextDetail = object(
          (await widget.session.api.post('inbox/getContactDetails', {
            'contact_id': contactId,
          }))['data'],
        );
        nextTicket = null;
      }
      if (!mounted) return;
      widget.session.viewCache[detailKey] = [nextDetail, nextTicket];
      if (jsonEncode([nextDetail, nextTicket]) ==
          jsonEncode([detail, ticket])) {
        return;
      }
      setState(() {
        detail = nextDetail;
        ticket = nextTicket;
        if (SendPolicy.evaluate(
          widget.session,
          detail,
          ticket: ticket,
        ).canSend) {
          windowRejected = false;
        }
      });
    } catch (e) {
      if (mounted && detail == null) setState(() => error = '$e');
    } finally {
      detailsBusy = false;
    }
  }

  void markRead() {
    final path = widget.ticketId == null
        ? 'inbox/mark-read'
        : 'inbox/tickets/${widget.ticketId}/mark-seen';
    widget.session.api
        .post(path, widget.ticketId == null ? {'contact_id': contactId} : null)
        .catchError((_) => <String, dynamic>{});
  }

  void scrollToEnd({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      } else {
        scroll.jumpTo(0);
      }
    });
  }

  /// Shows a message: scrolls to it when it is loaded, otherwise loads the
  /// page around it (inbox/messages around_id or around_message_id), then
  /// lights it up — for a search result or a tapped reply quote.
  Future<void> jumpTo({int? id, String? wamid}) async {
    ApiMessage? shown;
    for (final m in messages) {
      if ((id != null && number(m.id) == id) ||
          (wamid != null && wamid.isNotEmpty && m.wamid == wamid)) {
        shown = m;
      }
    }
    if (shown != null) {
      reveal(number(shown.id)!);
      return;
    }
    if (busy) return;
    busy = true;
    setState(() => showLoading = true);
    try {
      final r = await widget.session.api.post('inbox/messages', {
        'contact_id': contactId,
        'limit': 40,
        if (id != null) 'around_id': id else 'around_message_id': wamid,
      });
      if (!mounted) return;
      final meta = object(r['meta']);
      final target = number(meta['target_id']);
      if (target == null) {
        // An older server answers with the newest page instead.
        mobileNotice(context, 'This server cannot open older messages yet.');
        return;
      }
      setState(() {
        messages = mergeMessages(
          [],
          rows(r['data']).map(ApiMessage.new).toList(),
        );
        more = meta['has_more_before'] == true;
        newerMore = meta['has_more_after'] == true;
        oldest = number(meta['oldest_id']);
      });
      scrolledUp.value = newerMore;
      reveal(target);
    } catch (e) {
      if (mounted) {
        mobileNotice(
          context,
          e is ApiFailure && e.httpStatus == 404
              ? 'That message is no longer in this chat.'
              : e,
        );
      }
    } finally {
      busy = false;
      if (mounted) setState(() => showLoading = false);
    }
  }

  /// Scrolls the loaded message into the middle and lights it up briefly.
  void reveal(int id) {
    highlightTimer?.cancel();
    setState(() {
      highlightId = id;
      reaching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final row = highlightKey.currentContext;
      if (row != null && row.mounted) {
        await Scrollable.ensureVisible(
          row,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        );
      }
      if (mounted) setState(() => reaching = false);
    });
    highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => highlightId = null);
    });
  }

  /// The next newer page after a jump; the last one rejoins the live chat.
  Future<void> loadNewer() async {
    if (!newerMore || busy || messages.isEmpty) return;
    busy = true;
    try {
      final r = await widget.session.api.post('inbox/messages', {
        'contact_id': contactId,
        'limit': 50,
        'after_id': number(messages.last.id),
      });
      if (!mounted) return;
      final meta = object(r['meta']);
      setState(() {
        messages = mergeMessages(
          messages,
          rows(r['data']).map(ApiMessage.new).toList(),
        );
        newerMore = meta['has_more'] == true;
      });
      scrolledUp.value = newerMore || scroll.offset > 400;
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    } finally {
      busy = false;
    }
    // Met the live chat: catch up on anything that changed meanwhile.
    if (mounted && !newerMore) load(quiet: true);
  }

  /// Back to the newest messages from anywhere in the history.
  void jumpToLatest() {
    if (!newerMore) {
      scrollToEnd(animate: true);
      return;
    }
    setState(() {
      newerMore = false;
      sync = null;
      replaceNext = true;
    });
    load();
    scrollToEnd();
  }

  Future<void> searchChat() async {
    final found = await openPage<Json>(
      context,
      ConversationSearchPage(
        widget.session,
        contactId: contactId,
        contactName:
            '${widget.contact['profile_name'] ?? widget.contact['display_wa_id'] ?? phone}',
      ),
    );
    if (found != null && mounted) jumpTo(id: number(found['id']));
  }

  /// New messages at the bottom: at the bottom already, ease down to them; read
  /// further up, keep the messages on screen where they are (the list grows
  /// below them) and count the new ones on the jump-to-latest button.
  void follow(int count, bool atBottom) {
    final above = scroll.hasClients ? scroll.position.extentAfter : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final position = scroll.position;
      if (atBottom) {
        if (MediaQuery.disableAnimationsOf(context)) {
          scroll.jumpTo(0);
        } else {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      // What lies above the screen did not change; hold it there.
      final target = position.maxScrollExtent - above;
      if (target > position.pixels) scroll.jumpTo(target);
      unseen.value += count;
    });
  }

  /// New messages that arrived below while reading further up.
  final unseen = ValueNotifier(0);

  /// The newest page in full, against the phone's copy: the page is what
  /// the server holds for its stretch of time, so what the copy lacked there
  /// appears and what the server no longer has goes. Older kept messages stay
  /// shown, and paging back fetches from the page's own oldest message, so
  /// gaps further back fill in as they are reached. The healed copy is saved.
  void heal(List<ApiMessage> page, Json meta) {
    if (page.isEmpty) {
      remember();
      return;
    }
    final start = page
        .map((m) => '${m.json['created_at']}')
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final ids = {for (final m in page) m.id};
    final older = [
      for (final m in messages)
        if ('${m.json['created_at']}'.compareTo(start) < 0 &&
            !ids.contains(m.id))
          m,
    ];
    final had = {for (final m in messages) m.id};
    final arrived = page.where((m) => !had.contains(m.id) && !m.outgoing);
    final added = page.where((m) => !had.contains(m.id)).length;
    final atBottom = !scroll.hasClients || scroll.offset < 100;
    setState(() {
      messages = mergeMessages(older, page);
      final temps = page.map((m) => m.tempId).where((t) => t.isNotEmpty);
      pending.removeWhere((p) => temps.contains(p.key));
      oldest = number(meta['oldest_id']) ?? oldest;
      more = meta['has_more'] == true || older.isNotEmpty;
      loadedOnce = true;
      error = null;
    });
    remember(messages, true);
    if (added > 0) follow(added, atBottom);
    if (arrived.isNotEmpty) {
      markRead();
      details();
    }
  }

  Future<void> load({bool older = false, bool quiet = false}) async {
    if (busy) {
      // Never drop a live update: fetch again once this request finishes.
      if (quiet && !older) again = true;
      return;
    }
    busy = true;
    if (!quiet) {
      setState(() {
        showLoading = true;
        error = null;
      });
    }
    final nearEnd = !scroll.hasClients || scroll.offset < 100;
    final verify = verifyNext && !older;
    verifyNext = verifyNext && older;
    try {
      Json result;
      if (widget.ticketId != null) {
        result = await widget.session.api.post('inbox/ticket_messages', {
          'ticket_id': widget.ticketId,
          'limit': 50,
          'offset': older ? messages.length : 0,
        });
      } else {
        result = await repository.messages(
          contactId,
          before: older ? oldest : null,
          since: !older && !verify ? sync : null,
        );
      }
      if (!mounted) return;
      var incoming = rows(result['data']).map(ApiMessage.new).toList();
      var meta = object(result['meta']);
      // Drain catch-up pages using the pair of cursor fields; never skip changes
      // sharing the same timestamp. Normal history keeps its own older cursor.
      if (widget.ticketId == null && !older && !verify && sync != null) {
        while (meta['has_more'] == true && meta['sync_after_id'] != null) {
          result = await repository.messages(
            contactId,
            since: '${meta['sync_from']}',
            after: number(meta['sync_after_id']),
          );
          if (!mounted) return;
          incoming.addAll(rows(result['data']).map(ApiMessage.new));
          meta = object(result['meta']);
        }
      }
      final known = {for (final m in messages) m.id: m};
      // Away from the newest, live changes update what is shown (ticks,
      // reactions); new messages arrive when the list pages down to them.
      if (newerMore && !older) {
        incoming = [
          for (final m in incoming)
            if (known.containsKey(m.id)) m,
        ];
      }
      final fresh = incoming.where((m) => !known.containsKey(m.id)).toList();
      final changed =
          fresh.isNotEmpty ||
          incoming.any(
            (m) => jsonEncode(m.json) != jsonEncode(known[m.id]!.json),
          );
      if (!older && meta['sync_from'] != null) sync = '${meta['sync_from']}';
      // Many refreshes change nothing (tickets re-send the latest page);
      // rebuilding and re-sorting every bubble then is pure jank.
      final replace = replaceNext && !older;
      if (verify) {
        heal(incoming, meta);
        return;
      }
      if (!changed && loadedOnce && error == null && !replace) {
        remember();
        return;
      }
      final wasLoaded = loadedOnce;
      // What is on screen now, so only rows the reader has not seen pop in.
      final shown = {
        for (final m in messages) rowKey(m),
        for (final p in pending) 'send:${p.key}',
      };
      final animate =
          !older && !replace && !newerMore && nearEnd && messages.isNotEmpty;
      setState(() {
        messages = mergeMessages(replace ? [] : messages, incoming);
        if (animate) {
          final added = [
            for (final m in fresh)
              if (!shown.contains(rowKey(m))) rowKey(m),
          ];
          // A long catch-up lands at once; a few new rows arrive one by one.
          if (added.length <= 6) popIn.addAll(added);
        }
        replaceNext = false;
        final ids = incoming
            .map((m) => m.tempId)
            .where((id) => id.isNotEmpty)
            .toSet();
        pending.removeWhere((p) => ids.contains(p.key));
        if (older || !loadedOnce) {
          more = widget.ticketId != null
              ? incoming.length == 50
              : meta['has_more'] == true;
          oldest = number(meta['oldest_id']);
        }
        loadedOnce = true;
        error = null;
      });
      remember(replace ? messages : incoming, replace);
      final arrived = fresh.where((m) => !m.outgoing);
      if (arrived.isNotEmpty) {
        markRead();
        // A customer message reopens the window; activity rows record
        // assignment/close changes. Either can change who may send.
        if (!older && wasLoaded) details();
      }
      // Back to the latest on purpose: the bottom. Otherwise new messages
      // either ease into view or wait below without moving the screen.
      if (!older && replace) {
        scrollToEnd();
      } else if (!older && fresh.isNotEmpty) {
        follow(fresh.length, nearEnd);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      busy = false;
      if (mounted && showLoading) setState(() => showLoading = false);
      if (again && mounted) {
        again = false;
        load(quiet: true);
      }
    }
  }

  /// Who wrote a message, as a reply quote names them on WhatsApp.
  String quoteAuthor(ApiMessage m) => m.outgoing
      ? (readableText(m.json['sender_name']).isEmpty
            ? 'You'
            : readableText(m.json['sender_name']))
      : '${widget.contact['profile_name'] ?? widget.contact['display_wa_id'] ?? phone}';

  Future<void> attachMenu(bool canTemplate) async {
    final choice = await showAttachSheet(context, templates: canTemplate);
    if (!mounted || choice == null) return;
    switch (choice) {
      case AttachChoice.document:
        pickAttachment(['document']);
      case AttachChoice.gallery:
        gallery();
      case AttachChoice.camera:
        camera();
      case AttachChoice.location:
        shareLocation();
      case AttachChoice.audio:
        pickAttachment(['audio']);
      case AttachChoice.quickReplies:
        quickReplies();
      case AttachChoice.templates:
        templates();
    }
  }

  /// A recorded voice note goes straight out, like WhatsApp's release-to-send.
  void sendVoiceNote(Attachment note) {
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    final item = PendingSend(
      {
        'waba_user_id': widget.session.api.wabaId,
        'contact_id': contactId,
        'wa_id': phone,
        'message_type': 'audio',
        'body': '',
        if (widget.ticketId != null) 'ticket_id': widget.ticketId,
      },
      attachment: note,
      voice: true,
    );
    setState(() => pending.add(item));
    scrollToEnd(animate: true);
    deliver(item);
  }

  /// Photos and videos from the gallery, up to 30 as WhatsApp allows, each
  /// checked as WhatsApp will take it, then previewed with their captions
  /// and the HD switch; they go one message each, at the quality chosen.
  Future<void> gallery() async {
    if (!policy.canSend || picking) return;
    setState(() => picking = true);
    final picked = <Attachment>[];
    try {
      final files = await mediaPicker.galleryItems(limit: 30);
      final refused = <String>[];
      for (final file in files) {
        try {
          picked.add(await pickedAttachment(file));
        } on ApiFailure catch (e) {
          refused.add(e.message);
        }
      }
      if (refused.isNotEmpty && mounted) {
        mobileNotice(
          context,
          picked.isEmpty
              ? refused.first
              : '${refused.length} of ${files.length} not added: '
                    '${refused.first}',
        );
      }
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
    if (picked.isEmpty || !mounted) return;
    final batch = await openSendMedia(context, picked, contactName);
    if (batch == null || !mounted) return;
    for (final (file, caption) in batch.items) {
      queue(
        {'message_type': 'text', 'body': caption},
        attachment: file,
        quality: batch.quality,
      );
    }
  }

  String get contactName =>
      '${widget.contact['profile_name'] ?? widget.contact['display_wa_id'] ?? phone}';

  /// WhatsApp's camera: a photo or video, reviewed and captioned, then sent.
  Future<void> camera() async {
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    final shot = await openCamera(context);
    if (shot == null || !mounted) return;
    try {
      final file = await pickedAttachment(shot.file);
      if (!mounted) return;
      queue(
        {'message_type': 'text', 'body': shot.caption},
        attachment: file,
        quality: shot.quality,
      );
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    }
  }

  /// Whether this number may ask the customer for permission to call.
  bool get canAskToCall =>
      widget.session.canSendType('call_permission_request') ??
      callEligibility(widget.session.config, widget.contact).shown;

  /// Share a place picked on the map, ask the customer for their location
  /// (WhatsApp gives them a "Send location" button), or ask permission to
  /// call them.
  Future<void> shareLocation() async {
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Share a location'),
              subtitle: const Text('Your position or a place you search for'),
              onTap: () => Navigator.pop(context, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.share_location_outlined),
              title: const Text('Ask for their location'),
              subtitle: const Text('They get a button to share it'),
              onTap: () => Navigator.pop(context, 'ask'),
            ),
            if (canAskToCall)
              ListTile(
                leading: const Icon(Icons.add_call),
                title: const Text('Ask permission to call'),
                subtitle: const Text('They choose whether you can call them'),
                onTap: () => Navigator.pop(context, 'call'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'ask':
        final body = await askText(
          'Ask for their location',
          'Please share your location.',
        );
        if (body != null) queue({'message_type': 'location', 'body': body});
      case 'call':
        final body = await askText(
          'Ask permission to call',
          'Can we call you on WhatsApp about your request?',
        );
        if (body != null) {
          queue({'message_type': 'call_permission_request', 'body': body});
        }
      default:
        final location = await openPage<Json>(
          context,
          LocationPickerPage(source: locationSource, lookup: placeLookup),
        );
        if (location != null && mounted) {
          queue({
            'message_type': 'send_location',
            'body': '',
            'location': location,
          });
        }
    }
  }

  /// The message a request goes with, written by the agent; WhatsApp needs
  /// one. Null when closed.
  Future<String?> askText(String title, String suggested) async {
    String? text;
    await showEditorSheet(
      context,
      title: title,
      submit: 'Send',
      fields: [
        EditField(
          'body',
          'Message',
          value: suggested,
          required: true,
          lines: 3,
          hint: 'Message',
        ),
      ],
      save: (v) async => text = '${v['body']}'.trim(),
    );
    return text == null || text!.isEmpty ? null : text;
  }

  /// Sends a message that is not typed text, through the same pending row.
  void queue(
    Json fields, {
    Attachment? attachment,
    MediaQuality quality = MediaQuality.standard,
  }) {
    final item = PendingSend(attachment: attachment, quality: quality, {
      'waba_user_id': widget.session.api.wabaId,
      'contact_id': contactId,
      'wa_id': phone,
      if (widget.ticketId != null) 'ticket_id': widget.ticketId,
      ...fields,
    });
    setState(() => pending.add(item));
    scrollToEnd(animate: true);
    deliver(item);
  }

  Future<void> pickAttachment([List<String>? kinds]) async {
    if (!policy.canSend) return;
    if (picking) return;
    setState(() => picking = true);
    try {
      final file = await chooseAttachment(kinds: kinds);
      if (mounted && file != null) {
        setState(() {
          attachment = file;
          reply = null;
        });
      }
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void send() {
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    // A sent message ends WhatsApp's indicator; typing again shows it again.
    typedAt = null;
    final text = composer.text.trim();
    if (text.isEmpty && attachment == null) return;
    // A message goes at the bottom of the live chat, so show it.
    if (newerMore) jumpToLatest();
    final item = PendingSend(
      {
        'waba_user_id': widget.session.api.wabaId,
        'contact_id': contactId,
        'wa_id': phone,
        'message_type': 'text',
        'body': text,
        if (attachment == null && reply != null && reply!.wamid.isNotEmpty)
          'contextual_reply_id': reply!.wamid,
        if (widget.ticketId != null) 'ticket_id': widget.ticketId,
      },
      attachment: attachment,
      quote: attachment == null ? quoteOf(reply) : null,
    );
    setState(() {
      attachment = null;
      pending.add(item);
      composer.clear();
      reply = null;
    });
    scrollToEnd(animate: true);
    deliver(item);
  }

  /// Tells the inbox list this chat's newest message, whoever sent it (the
  /// agent, the customer, the bot, an automation or a colleague on the web);
  /// it is read here, so nothing is unread.
  void announce() {
    if (widget.ticketId != null) return;
    ApiMessage? last;
    for (final m in messages.reversed) {
      if (!m.log) {
        last = m;
        break;
      }
    }
    if (last == null) return;
    widget.session.conversationActivity.value = {
      'id': contactId,
      'last_message': last.json,
      'last_message_date': last.json['created_at'],
      'unread_message_count': 0,
    };
  }

  /// The reply quote a sent message will carry, so its bubble does not change
  /// shape when the server's copy arrives.
  Json? quoteOf(ApiMessage? m) => m == null || m.wamid.isEmpty
      ? null
      : {
          'contextual_message': m.json['message_body'],
          'contextual_message_type': m.type,
          'contextual_message_json': m.json['message_body_json'],
        };

  Future<void> deliver(PendingSend item) async {
    if (item.sending || item.accepted) return;
    // The bubble keeps drawing this file once the server's row replaces it.
    if (item.attachment case final Attachment file) sentFiles[item.key] = file;
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    setState(() {
      item.sending = true;
      item.error = null;
    });
    try {
      // A video's encoding is the first half of its ring, the upload the
      // second; a photo compresses too quickly to show.
      final encoding = !item.prepared && item.attachment?.kind == 'video';
      final start = encoding ? .5 : 0.0;
      await item.prepare(
        progress: (done) {
          if (mounted) setState(() => item.progress = done * .5);
        },
      );
      if (!mounted) return;
      final result = await repository.send(
        item,
        progress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => item.progress = start + (1 - start) * sent / total);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        item.accepted = true;
        final saved = object(result['sent_message']);
        if (saved.isNotEmpty) {
          messages = mergeMessages(messages, [ApiMessage(saved)]);
          pending.remove(item);
        }
      });
      final saved = object(result['sent_message']);
      if (saved.isNotEmpty) remember([ApiMessage(saved)]);
      load(quiet: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          item.error = '$e';
          if ('$e'.contains('messaging window')) windowRejected = true;
        });
      }
    } finally {
      if (mounted) setState(() => item.sending = false);
    }
  }

  Message presentation(ApiMessage m) => messagePresentation(m);

  /// A long press selects the message, as WhatsApp does.
  void select(ApiMessage m, BuildContext bubbleContext) {
    final box = bubbleContext.findRenderObject() as RenderBox?;
    HapticFeedback.selectionClick();
    setState(() {
      selected = m;
      selectedAt = box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      reacting = true;
    });
  }

  void unselect() => setState(() {
    selected = null;
    reacting = false;
  });

  /// While a message is selected, a tap on another selects that one, and a
  /// tap on the same one lets it go.
  void tapWhileSelecting(ApiMessage m, BuildContext rowContext) {
    if (rowKey(m) == rowKey(selected!)) {
      unselect();
    } else {
      select(m, rowContext);
      setState(() => reacting = false);
    }
  }

  bool canReply(ApiMessage m) => policy.canSend && m.wamid.isNotEmpty;
  bool canReact(ApiMessage m) => m.wamid.isNotEmpty;
  bool hasInfo(ApiMessage m) => m.outgoing && m.wamid.isNotEmpty;

  Future<void> selectedAction(String action) async {
    final m = selected;
    if (m == null) return;
    unselect();
    switch (action) {
      case 'reply':
        setState(() => reply = m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
      case 'info':
        await showMessageInfo(context, m);
    }
  }

  Future<void> moreReactions(ApiMessage m) async {
    setState(() => reacting = false);
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final emoji in [
                '❤️',
                '🎉',
                '👏',
                '✅',
                '🙂',
                '😢',
                '🔥',
                '👌',
                '💯',
                '🤔',
                '🙌',
                '💚',
              ])
                AppButton.text(
                  onPressed: () => Navigator.pop(context, emoji),
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    unselect();
    if (emoji != null) await react(m, emoji);
  }

  /// Reacts to [m] with [emoji]; the same reaction again takes it away.
  Future<void> react(ApiMessage m, String emoji) async {
    if (!canReact(m)) return;
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    final same = m.reactions.any(
      (r) => r['emoji'] == emoji && r['can_remove'] == true,
    );
    try {
      await widget.session.api.request(
        'inbox/reactions',
        method: same ? 'DELETE' : 'POST',
        data: {'message_id': m.wamid, 'phone': phone, 'emoji': emoji},
      );
      await load(quiet: true);
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    }
  }

  /// WhatsApp's top bar while a message is selected: how many, then what
  /// can be done with it.
  AppBar selectionBar(ApiMessage m) => AppBar(
    key: const ValueKey('selection-bar'),
    shape: const Border(bottom: BorderSide(color: T.hairline)),
    leading: IconButton(
      key: const ValueKey('selection-close'),
      tooltip: 'Cancel',
      icon: const Icon(Icons.close),
      onPressed: unselect,
    ),
    title: const Text('1'),
    actions: [
      if (canReply(m))
        IconButton(
          key: const ValueKey('selection-reply'),
          tooltip: 'Reply',
          icon: const Icon(Icons.reply_rounded),
          onPressed: () => selectedAction('reply'),
        ),
      IconButton(
        key: const ValueKey('selection-copy'),
        tooltip: 'Copy',
        icon: const Icon(Icons.copy_rounded),
        onPressed: () => selectedAction('copy'),
      ),
      if (hasInfo(m))
        IconButton(
          key: const ValueKey('selection-info'),
          tooltip: 'Info',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => selectedAction('info'),
        ),
      const SizedBox(width: 4),
    ],
  );

  /// The reactions, floating just above the selected bubble.
  Widget reactionBar(BuildContext context) {
    final m = selected!, at = selectedAt;
    final body = bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (at == null || body == null || !body.hasSize) {
      return const SizedBox.shrink();
    }
    final top = body.globalToLocal(at.topLeft).dy - 64;
    final mine = {
      for (final r in m.reactions)
        if (r['can_remove'] == true) '${r['emoji']}',
    };
    return Positioned(
      left: 12,
      right: 12,
      top: top.clamp(8.0, body.size.height - 80),
      child: Align(
        alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Material(
          key: const ValueKey('message-reaction-picker'),
          color: Colors.white,
          elevation: 5,
          shadowColor: T.ink.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                  Tooltip(
                    message: 'React with $emoji',
                    child: InkResponse(
                      radius: 24,
                      onTap: () {
                        unselect();
                        react(m, emoji);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: mine.contains(emoji)
                              ? T.greenWash
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: 'More reactions',
                  child: InkResponse(
                    radius: 22,
                    onTap: () => moreReactions(m),
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: const BoxDecoration(
                        color: T.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: T.secondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> reopen() async {
    if (reopening) return;
    setState(() => reopening = true);
    try {
      await widget.session.api.post('inbox/conversation/reopen', {
        'contact_id': contactId,
      });
      await details();
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    } finally {
      if (mounted) setState(() => reopening = false);
    }
  }

  /// Customer details in the shared inbox; a ticket chat always sits on its
  /// ticket's details (as the web ticket inbox pairs them), so it returns.
  Future<void> openContact() async {
    if (widget.ticketId != null) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      return;
    }
    await openPage(
      context,
      ContactActionsPage(
        widget.session,
        contactId,
        initial: detail,
        windowExpires: windowExpires,
      ),
    );
    if (mounted) details();
  }

  Future<List<Json>> fetchQuickReplies(String key) async {
    final result = await widget.session.api.get('inbox/canned-responses');
    final data = object(result['data']);
    final list = [
      ...rows(data['uncategorised']),
      for (final c in rows(data['categories'])) ...rows(c['responses']),
    ];
    widget.session.viewCache[key] = list;
    return list;
  }

  Future<void> quickReplies() async {
    try {
      final key = 'quick:${widget.session.api.wabaId}';
      final cached = widget.session.viewCache[key] as List<Json>?;
      // Open instantly from the session cache and refresh it for next time.
      final refresh = fetchQuickReplies(key);
      if (cached != null) unawaited(refresh.then((_) {}, onError: (_) {}));
      final list = cached ?? await refresh;
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('Quick replies')),
              if (list.isEmpty)
                const ListTile(title: Text('No quick replies available')),
              for (final r in list)
                AppListTile(
                  title: Text('${r['title'] ?? ''}'),
                  subtitle: Text('${r['body'] ?? ''}'),
                  onTap: () => Navigator.pop(context, '${r['body'] ?? ''}'),
                ),
            ],
          ),
        ),
      );
      if (mounted && selected != null) {
        composer.text = selected.replaceAll(
          '{{name}}',
          '${widget.contact['profile_name'] ?? ''}',
        );
      }
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    }
  }

  Future<void> templates() async {
    if (!policy.canTemplate) return;
    await openPage(
      context,
      TemplatePicker(widget.session, widget.contact, ticketId: widget.ticketId),
    );
    if (mounted) {
      load(quiet: true);
      details();
    }
  }

  Widget historyItem(int index) {
    if (index == 0) {
      return more
          ? Center(
              child: AppButton.text(
                onPressed: showLoading ? null : () => load(older: true),
                child: const Text('Load older messages'),
              ),
            )
          : const SizedBox(height: 8);
    }
    final position = index - 1;
    if (position >= messages.length) {
      final at = position - messages.length;
      final p = pending[at];
      final previous = at > 0
          ? pendingMessage(pending[at - 1])
          : messages.lastOrNull;
      // Drawn by the same row as a delivered message, so the server's copy
      // replaces it in place: no slide-in, no extra status line.
      // The same shape as a saved row's, under the same key, so the server's
      // row takes this one's place without rebuilding the bubble.
      return KeyedSubtree(
        key: ValueKey('send:${p.key}'),
        // Never pops in: your own message appears at once, as you sent it.
        child: _PopIn(
          animate: false,
          from: Alignment.bottomRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Shaped exactly as a saved row is (see below), so it is
              // updated in place when the server's row replaces it.
              Builder(
                builder: (_) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: AbsorbPointer(
                    absorbing: false,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      color: Colors.transparent,
                      child: messageRow(
                        pendingMessage(p),
                        previous,
                        interactive: false,
                      ),
                    ),
                  ),
                ),
              ),
              // Photos, videos and documents show their own upload ring.
              if (p.sending && p.attachment?.kind == 'audio')
                SizedBox(
                  width: 150,
                  child: LinearProgressIndicator(value: p.progress),
                ),
              if (p.error != null)
                AppButton.text(
                  onPressed: policy.canSend ? () => deliver(p) : null,
                  child: const Text('Retry send'),
                ),
            ],
          ),
        ),
      );
    }
    final m = messages[position];
    final lit = highlightId != null && number(m.id) == highlightId;
    final key = rowKey(m);
    return KeyedSubtree(
      key: ValueKey(key),
      child: _PopIn(
        animate: popIn.remove(key),
        from: m.log
            ? Alignment.center
            : m.outgoing
            ? Alignment.bottomRight
            : Alignment.bottomLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // A jumped-to message glows for a moment, as on WhatsApp; a
            // selected one stays green across the row while selected.
            Builder(
              builder: (rowContext) {
                final chosen = selected != null && rowKey(selected!) == key;
                final row = AnimatedContainer(
                  key: lit ? highlightKey : null,
                  duration: const Duration(milliseconds: 150),
                  color: chosen
                      ? T.green.withValues(alpha: .16)
                      : lit
                      ? T.brass.withValues(alpha: .18)
                      : Colors.transparent,
                  child: messageRow(
                    m,
                    position == 0 ? null : messages[position - 1],
                  ),
                );
                // Always this shape, selecting or not, so selecting never
                // rebuilds a bubble (nor reloads its photo).
                final selecting = selected != null && !m.log;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selecting
                      ? () => tapWhileSelecting(m, rowContext)
                      : null,
                  child: AbsorbPointer(absorbing: selecting, child: row),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// One key per message across its life: the bubble shown while sending and
  /// the server's row share the send's temporary id, so the row is updated in
  /// place, never drawn twice or rebuilt from scratch.
  String rowKey(ApiMessage m) =>
      m.tempId.isNotEmpty && sharedTempIds[m.tempId] == 1
      ? 'send:${m.tempId}'
      : m.id;

  /// How many saved rows carry each temporary id; a copied request (a
  /// resend) can repeat one, and those rows then keep their own ids.
  Map<String, int> get sharedTempIds {
    if (!identical(_countedFor, messages)) {
      _countedFor = messages;
      _tempIds = {};
      for (final m in messages) {
        if (m.tempId.isNotEmpty) {
          _tempIds[m.tempId] = (_tempIds[m.tempId] ?? 0) + 1;
        }
      }
    }
    return _tempIds;
  }

  var _tempIds = <String, int>{};
  List<ApiMessage>? _countedFor;

  /// Where a row with this key is now, so a new message moves the others
  /// down instead of rebuilding every bubble below it.
  int? indexOfKey(Key key) {
    if (key is! ValueKey<String>) return null;
    final total = messages.length + pending.length;
    if (!identical(_indexedFor, messages) ||
        _indexedPending != pending.length) {
      _indexedFor = messages;
      _indexedPending = pending.length;
      _index = {
        for (final (at, m) in messages.indexed) rowKey(m): total - at - 1,
      };
    }
    final at = pending.indexWhere((p) => key.value == 'send:${p.key}');
    if (at >= 0) return pending.length - at - 1;
    return _index[key.value];
  }

  var _index = <String, int>{};
  List<ApiMessage>? _indexedFor;
  int _indexedPending = -1;

  /// A message waiting to be sent, shaped like the row the server returns,
  /// so the same bubble draws it before and after: a photo as the photo, a
  /// video by its first frame, a document as its card, a pin as its map.
  ApiMessage pendingMessage(PendingSend p) {
    final a = p.attachment;
    final caption = '${p.body['body'] ?? ''}';
    return ApiMessage({
      'id': 'pending:${p.key}',
      'temp_message_id': p.key,
      'type': 1,
      if (a != null) ...{
        'message_type': a.kind,
        'message_body': caption,
        'message_body_json': jsonEncode({
          a.kind: {
            'caption': caption,
            'filename': a.name,
            'media_mime_type': a.mime,
            if (p.voice) 'voice': true,
          },
        }),
      } else if (p.body['message_type'] == 'send_location') ...{
        'message_type': 'location',
        'message_body_json': jsonEncode({'location': p.body['location']}),
      } else ...{
        'message_type': 'text',
        'message_body': caption,
      },
      'created_at': p.createdAt,
      'message_status': p.error != null ? 4 : 0,
      'failed_reason': ?p.error,
      // Read by the media bubble's upload ring; gone once it is sent.
      if (a != null && p.error == null && !p.accepted)
        'upload_progress': p.progress,
      'sender_name': ?widget.session.user?['name'],
      ...?p.quote,
    });
  }

  Widget messageRow(
    ApiMessage m,
    ApiMessage? previous, {
    bool interactive = true,
  }) {
    final time = MobileClock.instant(m.json['created_at']),
        before = MobileClock.instant(previous?.json['created_at']);
    final day = const MobileClock().day(m.json['created_at']);
    final previousDay = const MobileClock().day(previous?.json['created_at']);
    final first =
        previous == null ||
        previous.outgoing != m.outgoing ||
        previous.log ||
        time == null ||
        before == null ||
        time.difference(before).abs().inMinutes >= 5;
    return Column(
      children: [
        if (day != previousDay && day.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: T.incoming,
                borderRadius: BorderRadius.circular(8),
                boxShadow: T.bubbleShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                child: Text(
                  const MobileClock().dayLabel(m.json['created_at']),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: T.secondary,
                  ),
                ),
              ),
            ),
          ),
        LiveMessageView(
          message: m,
          apiBase: widget.session.api.dio.options.baseUrl,
          first: first,
          onReply: interactive && policy.canSend && m.wamid.isNotEmpty
              ? () => setState(() => reply = m)
              : null,
          onActions: interactive ? (anchor) => select(m, anchor) : null,
          onCallBack: callable
              ? () => startCall(context, widget.session, callContact)
              : null,
          contactName:
              '${widget.contact['profile_name'] ?? widget.contact['display_wa_id'] ?? phone}',
          businessName: widget.session.wabaName,
          onQuoteTap:
              widget.ticketId == null &&
                  '${m.json['contextual_reply_id'] ?? ''}'.isNotEmpty
              ? () => jumpTo(wamid: '${m.json['contextual_reply_id']}')
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.contact['profile_name'] ?? phone}';
    final permission = policy;
    final swap = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final chosen = selected;
    // Back lets a selected message go before it leaves the chat.
    return PopScope(
      canPop: chosen == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selected != null) unselect();
      },
      child: Scaffold(
        appBar: chosen != null
            ? selectionBar(chosen)
            : AppBar(
                shape: const Border(bottom: BorderSide(color: T.hairline)),
                titleSpacing: 0,
                // Tapping the name opens contact details, as on WhatsApp and the web inbox.
                title: InkWell(
                  onTap: openContact,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          // The green dot: WhatsApp's conversation window is open.
                          child: ConversationWindow(
                            expiresAt: rememberedWindow,
                            builder: (context, open) => Row(
                              children: [
                                Avatar(
                                  name,
                                  size: 36,
                                  seed: widget.contact['id'],
                                  online: open,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      WindowStatus(
                                        permission.expiresAt,
                                        known: detail != null,
                                        prefix: widget.ticketId != null
                                            ? 'Ticket conversation'
                                            : formatPhone(
                                                widget.contact['display_wa_id'] ??
                                                    phone,
                                              ),
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
                ),
                // Updates are live, so no refresh button. iOS puts contact details
                // behind an info button; Android behind the overflow menu.
                actions: [
                  if (widget.ticketId == null)
                    AppIconButton(
                      tooltip: 'Search chat',
                      onPressed: searchChat,
                      icon: const AppIcon(Icons.search),
                    ),
                  if (widget.ticketId == null)
                    CallButton(session: widget.session, contact: callContact),
                  if (isCupertino(context))
                    AppIconButton(
                      tooltip: 'Contact details',
                      onPressed: openContact,
                      icon: const Icon(CupertinoIcons.info_circle),
                    )
                  else
                    OverflowMenu(
                      items: [
                        (label: 'Contact details', onPressed: openContact),
                        if (callEligibility(
                          widget.session.config,
                          callContact,
                        ).shown)
                          (
                            label: 'Call history',
                            onPressed: () => openPage(
                              context,
                              CallHistoryPage(widget.session, callContact),
                            ),
                          ),
                        if (permission.canTemplate)
                          (label: 'Send template', onPressed: templates),
                      ],
                    ),
                ],
              ),
        // The wallpaper runs behind the composer too, so the input floats on
        // the conversation the way WhatsApp's does.
        body: Stack(
          key: bodyKey,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const ChatWallpaper(),
                child: Column(
                  children: [
                    RealtimeNotice(widget.session.realtime),
                    LoadingBar(showLoading),
                    if (error != null && !isOffline(error))
                      MaterialBanner(
                        content: Text(error!),
                        actions: [
                          AppButton.text(
                            onPressed: () {
                              load();
                              details();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: messages.isEmpty && pending.isEmpty && !showLoading
                          ? const Center(child: Text('No messages yet.'))
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ListView.builder(
                                  controller: scroll,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    8,
                                  ),
                                  // Every row is built for the frame that scrolls to
                                  // a jumped-to message, so it can be found.
                                  scrollCacheExtent: reaching
                                      ? const ScrollCacheExtent.pixels(1e6)
                                      : null,
                                  itemCount:
                                      messages.length + pending.length + 1,
                                  itemBuilder: (_, index) => historyItem(
                                    messages.length + pending.length - index,
                                  ),
                                  findChildIndexCallback: indexOfKey,
                                ),
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: ValueListenableBuilder(
                                    valueListenable: scrolledUp,
                                    builder: (context, up, _) => AnimatedScale(
                                      scale: up ? 1 : 0,
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      child: ValueListenableBuilder(
                                        valueListenable: unseen,
                                        builder: (context, count, button) =>
                                            Badge(
                                              key: const ValueKey('unseen'),
                                              isLabelVisible: count > 0,
                                              label: Text('$count'),
                                              backgroundColor: T.green,
                                              child: button,
                                            ),
                                        child: AppIconButton.filledTonal(
                                          tooltip: 'Scroll to latest',
                                          onPressed: up ? jumpToLatest : null,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    // While permissions load, keep the composer's shape but disabled,
                    // so the bottom of the screen does not swap layouts a moment later.
                    // When it does change (the chat turns out closed, or the window
                    // shuts), the composer and the card cross-fade and the bar eases
                    // to its new height instead of jumping in one frame.
                    AnimatedSize(
                      duration: swap,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: AnimatedSwitcher(
                        duration: swap,
                        child: !permission.canSend && detail != null
                            ? SafeArea(
                                key: const ValueKey('composer-card'),
                                top: false,
                                child: _ComposerCard(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        permission.reason!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: T.secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (closed)
                                        AppButton.outlined(
                                          onPressed: reopening ? null : reopen,
                                          child: Text(
                                            reopening
                                                ? 'Reopening…'
                                                : 'Reopen conversation',
                                          ),
                                        ),
                                      if (permission.canTemplate)
                                        AppButton.filled(
                                          onPressed: templates,
                                          child: const Text('Send template'),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : Column(
                                key: const ValueKey('composer'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LoadingBar(picking),
                                  SafeArea(
                                    top: false,
                                    child: ChatComposer(
                                      controller: composer,
                                      enabled: permission.canSend,
                                      busy: picking,
                                      replyAuthor: reply == null
                                          ? null
                                          : quoteAuthor(reply!),
                                      replyText: reply?.text,
                                      onCancelReply: () =>
                                          setState(() => reply = null),
                                      attachment: attachment,
                                      onCancelAttachment: () =>
                                          setState(() => attachment = null),
                                      onSend: send,
                                      onAttach: () =>
                                          attachMenu(permission.canTemplate),
                                      onQuickReplies: quickReplies,
                                      onCamera: camera,
                                      onVoiceNote: sendVoiceNote,
                                      onTyping: typing,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (chosen != null && reacting) reactionBar(context),
          ],
        ),
      ),
    );
  }
}

/// A row that arrives while the chat is open grows into place: the bubbles
/// above glide up to make room, and it pops in from its own side (the
/// customer's left, yours right, activity in the middle) instead of the list
/// jumping in one frame. Rows already on screen are left exactly as they are.
class _PopIn extends StatefulWidget {
  const _PopIn({
    required this.animate,
    required this.from,
    required this.child,
  });

  /// Read once, when the row is first built.
  final bool animate;
  final Alignment from;
  final Widget child;
  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || !widget.animate) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Never animated: no extra layers for the many rows that stay still.
    if (controller == null) return widget.child;
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: controller,
        curve: const Interval(0, .7, curve: Curves.easeOutCubic),
      ),
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: controller,
          curve: const Interval(.15, .8, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          scale: Tween(begin: .85, end: 1.0).animate(
            CurvedAnimation(
              parent: controller,
              curve: const Interval(.15, 1, curve: Curves.easeOutBack),
            ),
          ),
          alignment: widget.from,
          child: widget.child,
        ),
      ),
    );
  }
}

class TemplatePicker extends StatefulWidget {
  const TemplatePicker(this.session, this.contact, {super.key, this.ticketId});
  final MobileSession session;
  final Json contact;
  final int? ticketId;
  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  List<Json>? templates;
  String? error;
  String query = '';

  /// A category to narrow to, or null for all of them.
  String? category;
  String get cacheKey =>
      'templates:${widget.session.api.wabaId}:${widget.contact['id']}';
  @override
  void initState() {
    super.initState();
    // Reopening shows the last list at once; the request still refreshes it.
    templates = widget.session.viewCache[cacheKey] as List<Json>?;
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get(
        'inbox/templates',
        query: {'contact_id': widget.contact['id']},
      );
      final next = rows(r['data']);
      widget.session.viewCache[cacheKey] = next;
      if (mounted) {
        setState(() {
          templates = next;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && templates == null) setState(() => error = '$e');
    }
  }

  Future<void> open(Json t) async {
    final sent = await openPage<bool>(
      context,
      TemplateSend(
        widget.session,
        widget.contact,
        t,
        ticketId: widget.ticketId,
      ),
    );
    // Close the picker too, landing back in the conversation.
    if (sent == true && mounted) Navigator.pop(context, true);
  }

  bool matches(Json t) {
    if (category != null && '${t['category']}'.toUpperCase() != category) {
      return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final body = templateComponents(t)
        .where((c) => '${c['type']}'.toUpperCase() == 'BODY')
        .map((c) => '${c['text'] ?? ''}')
        .join(' ');
    return '${t['name']} ${templateTitle(t['name'])} $body'
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final all = templates;
    final name = readableText(widget.contact['profile_name']);
    final categories = <String>{
      for (final t in all ?? const <Json>[]) '${t['category']}'.toUpperCase(),
    }.where((c) => c.isNotEmpty).toList()..sort();
    final shown = all?.where(matches).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send a template'),
            if (name.isNotEmpty)
              Text(
                'To $name',
                style: const TextStyle(fontSize: 13, color: T.muted),
              ),
          ],
        ),
      ),
      body: all == null
          ? error == null
                ? const Center(child: CircularProgressIndicator())
                : failure(error!, load)
          : all.isEmpty
          ? const _PickerEmpty(
              'No templates you can send to this contact yet. Approved templates appear here.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: SearchBox(
                    hint: 'Search templates',
                    dense: true,
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
                if (categories.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: PlatformFilters(
                      options: [
                        'All',
                        for (final c in categories) templateCategory(c),
                      ],
                      selected: category == null
                          ? 'All'
                          : templateCategory(category),
                      scrollable: true,
                      onSelected: (label) => setState(
                        () => category = label == 'All'
                            ? null
                            : categories.firstWhere(
                                (c) => templateCategory(c) == label,
                              ),
                      ),
                    ),
                  ),
                Expanded(
                  child: shown!.isEmpty
                      ? const _PickerEmpty('No templates match your search.')
                      : ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 16),
                          children: [
                            for (final t in shown)
                              TemplateCard(t, onTap: () => open(t)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: T.selected,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.article_outlined,
              color: T.bronze,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, color: T.secondary),
          ),
        ],
      ),
    ),
  );
}

/// Header subtitle with the customer-service window, like the web inbox's
/// timer pill. Ticks once a minute and rebuilds only itself.
class WindowStatus extends StatefulWidget {
  const WindowStatus(
    this.expiresAt, {
    super.key,
    required this.prefix,
    this.known = true,
  });
  final DateTime? expiresAt;

  /// False until contact details load; nothing is claimed before then.
  final bool known;
  final String prefix;
  @override
  State<WindowStatus> createState() => _WindowStatusState();
}

class _WindowStatusState extends State<WindowStatus> {
  Timer? tick;
  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = windowOpen(widget.expiresAt);
    final label = widget.known ? windowLabel(widget.expiresAt) : '';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.prefix),
          if (label.isNotEmpty) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: label,
              style: TextStyle(color: open ? T.green : T.danger),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: T.muted),
    );
  }
}

/// Warm grey card on the white chat, where the composer would be when
/// sending is not allowed (closed window, closed chat, not assigned).
class _ComposerCard extends StatelessWidget {
  const _ComposerCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: T.incoming,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}
