import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import '../ui/data.dart' show Message;
import '../ui/chat_message.dart';
import '../ui/conversation.dart' show ChatWallpaper;
import 'api.dart';
import 'models.dart';
import 'screens.dart';
import 'media.dart';
import 'contact_actions.dart';
import 'templates.dart';
import 'message_view.dart';
import 'send_policy.dart';

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
  // `busy` guards overlapping requests and is not display state; quiet polls
  // must not rebuild the screen just to toggle it.
  bool busy = false, more = false, loadedOnce = false;
  int? oldest;
  Timer? poll;
  int ticks = 0;
  late final repository = InboxRepository(widget.session.api);
  int get contactId => number(widget.contact['id'])!;
  String get phone => '${widget.contact['wa_id'] ?? ''}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(() => scrolledUp.value = scroll.offset > 400);
    messages = (widget.session.viewCache[cacheKey] as List<ApiMessage>?) ?? [];
    final cached = widget.session.viewCache[detailKey] as List<Json?>?;
    if (cached != null) {
      detail = cached.first;
      ticket = cached.last;
    }
    load(quiet: messages.isNotEmpty);
    details();
    startPoll();
  }

  /// Messages are polled every 5s. Contact details are an expensive request,
  /// so they refresh when new incoming/activity rows arrive (see [load]) and
  /// otherwise only every 30s as a fallback for silent changes.
  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if ((ModalRoute.of(context)?.isCurrent ?? false) && !busy) {
        load(quiet: true);
        if (++ticks % 6 == 0) details();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPoll();
      load(quiet: true);
      details();
    } else {
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    composer.dispose();
    scroll.dispose();
    scrolledUp.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> details() async {
    if (detailsBusy) return;
    detailsBusy = true;
    try {
      final results = await Future.wait([
        widget.session.api.post('inbox/getContactDetails', {
          'contact_id': contactId,
        }),
        if (widget.ticketId != null)
          widget.session.api.post('inbox/ticket_details', {
            'ticket_id': widget.ticketId,
          }),
      ]);
      if (!mounted) return;
      final nextDetail = object(results.first['data']);
      final nextTicket = widget.ticketId == null
          ? null
          : object(object(results.last['data'])['ticket']);
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

  Future<void> load({bool older = false, bool quiet = false}) async {
    if (busy) return;
    busy = true;
    if (!quiet) {
      setState(() {
        showLoading = true;
        error = null;
      });
    }
    final nearEnd = !scroll.hasClients || scroll.offset < 100;
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
          since: !older ? sync : null,
        );
      }
      if (!mounted) return;
      var incoming = rows(result['data']).map(ApiMessage.new).toList();
      var meta = object(result['meta']);
      // Drain catch-up pages using the pair of cursor fields; never skip changes
      // sharing the same timestamp. Normal history keeps its own older cursor.
      if (widget.ticketId == null && !older && sync != null) {
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
      final fresh = incoming.where((m) => !known.containsKey(m.id)).toList();
      final changed =
          fresh.isNotEmpty ||
          incoming.any(
            (m) => jsonEncode(m.json) != jsonEncode(known[m.id]!.json),
          );
      if (!older && meta['sync_from'] != null) sync = '${meta['sync_from']}';
      // Most polls change nothing (ticket polls re-send the latest page);
      // rebuilding and re-sorting every bubble then is pure jank.
      if (!changed && loadedOnce && error == null) return;
      final wasLoaded = loadedOnce;
      setState(() {
        messages = mergeMessages(messages, incoming);
        widget.session.viewCache[cacheKey] = messages;
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
      final arrived = fresh.where((m) => !m.outgoing);
      if (arrived.isNotEmpty) {
        markRead();
        // A customer message reopens the window; activity rows record
        // assignment/close changes. Either can change who may send.
        if (!older && wasLoaded) details();
      }
      if (!older && fresh.isNotEmpty && nearEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) scroll.jumpTo(0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      busy = false;
      if (mounted && showLoading) setState(() => showLoading = false);
    }
  }

  Future<void> pickAttachment() async {
    if (!policy.canSend) return;
    if (picking) return;
    setState(() => picking = true);
    try {
      final file = await chooseAttachment();
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
    final text = composer.text.trim();
    if (text.isEmpty && attachment == null) return;
    final item = PendingSend({
      'waba_user_id': widget.session.api.wabaId,
      'contact_id': contactId,
      'wa_id': phone,
      'message_type': 'text',
      'body': text,
      if (attachment == null && reply != null && reply!.wamid.isNotEmpty)
        'contextual_reply_id': reply!.wamid,
      if (widget.ticketId != null) 'ticket_id': widget.ticketId,
    }, attachment: attachment);
    setState(() {
      attachment = null;
      pending.add(item);
      composer.clear();
      reply = null;
    });
    scrollToEnd(animate: true);
    deliver(item);
  }

  Future<void> deliver(PendingSend item) async {
    if (item.sending || item.accepted) return;
    if (!policy.canSend) {
      mobileNotice(context, policy.reason!);
      return;
    }
    setState(() {
      item.sending = true;
      item.error = null;
    });
    try {
      final result = await repository.send(
        item,
        progress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => item.progress = sent / total);
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
  Future<void> actions(ApiMessage m, BuildContext bubbleContext) async {
    final box = bubbleContext.findRenderObject() as RenderBox?;
    var choice = await showMessageActions(
      context: context,
      message: presentation(m),
      anchor: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      first: true,
      starred: false,
      reaction: '',
      actions: [
        if (policy.canSend && m.wamid.isNotEmpty)
          ('reply', 'Reply', Icons.reply),
        ('copy', 'Copy', Icons.copy),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'more-reactions') {
      choice = await showModalBottomSheet<String>(
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
                    onPressed: () => Navigator.pop(context, 'emoji:$emoji'),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || choice == null) return;
    }
    if (!mounted) return;
    if (choice == 'reply') setState(() => reply = m);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
    }
    if (!mounted) return;
    if (choice.startsWith('emoji:') && m.wamid.isNotEmpty) {
      if (!policy.canSend) {
        mobileNotice(context, policy.reason!);
        return;
      }
      final emoji = choice.substring(6);
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

  Future<void> openContact() async {
    await openPage(
      context,
      ContactActionsPage(widget.session, contactId, initial: detail),
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
      final p = pending[position - messages.length];
      return TweenAnimationBuilder<double>(
        key: ValueKey(p.key),
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 100),
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MessageBubble(
                  message: Message(
                    '${p.attachment == null ? '' : '${p.attachment!.name}\n'}${p.body['body']}',
                    out: true,
                    time: const MobileClock().time(
                      DateTime.now().toUtc().toIso8601String(),
                    ),
                    read: false,
                    deliveryStatus: p.error != null ? 4 : 0,
                  ),
                  maxWidth: MediaQuery.sizeOf(context).width * .82,
                ),
                if (p.sending && p.attachment != null)
                  SizedBox(
                    width: 150,
                    child: LinearProgressIndicator(value: p.progress),
                  ),
                if (p.error != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .82,
                    ),
                    child: Text(
                      p.error!,
                      style: const TextStyle(fontSize: 11, color: T.danger),
                    ),
                  ),
                if (p.error != null)
                  AppButton.text(
                    onPressed: policy.canSend ? () => deliver(p) : null,
                    child: const Text('Retry send'),
                  ),
                if (p.accepted)
                  const Text(
                    'Accepted · syncing',
                    style: TextStyle(fontSize: 10, color: T.muted),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final m = messages[position],
        previous = position == 0 ? null : messages[position - 1];
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
      key: ValueKey(m.id),
      children: [
        if (day != previousDay && day.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: T.ink.withValues(alpha: .1),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
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
          onReply: policy.canSend && m.wamid.isNotEmpty
              ? () => setState(() => reply = m)
              : null,
          onActions: (anchor) => actions(m, anchor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.contact['profile_name'] ?? phone}';
    final permission = policy;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // Tapping the name opens contact details, as on WhatsApp and the web inbox.
        title: InkWell(
          onTap: openContact,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Avatar(name, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      WindowStatus(
                        permission.expiresAt,
                        known: detail != null,
                        prefix: widget.ticketId == null
                            ? '${widget.contact['display_wa_id'] ?? phone}'
                            : 'Ticket conversation',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          AppIconButton(
            tooltip: 'Refresh',
            onPressed: showLoading
                ? null
                : () {
                    load(quiet: messages.isNotEmpty);
                    details();
                  },
            icon: const Icon(Icons.refresh),
          ),
          AppIconButton(
            tooltip: 'Contact details',
            onPressed: openContact,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      // The wallpaper runs behind the composer too, so the input floats on
      // the conversation the way WhatsApp's does.
      body: CustomPaint(
        painter: const ChatWallpaper(),
        child: Column(
          children: [
            LoadingBar(showLoading),
            if (error != null)
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
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: messages.length + pending.length + 1,
                          itemBuilder: (_, index) => historyItem(
                            messages.length + pending.length - index,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: ValueListenableBuilder(
                            valueListenable: scrolledUp,
                            builder: (context, up, _) => AnimatedScale(
                              scale: up ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: AppIconButton.filledTonal(
                                tooltip: 'Scroll to latest',
                                onPressed: up
                                    ? () => scrollToEnd(animate: true)
                                    : null,
                                icon: const Icon(Icons.keyboard_arrow_down),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            // While permissions load, keep the composer's shape but disabled,
            // so the bottom of the screen does not swap layouts a moment later.
            if (!permission.canSend && detail != null)
              SafeArea(
                top: false,
                child: _ComposerCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            reopening ? 'Reopening…' : 'Reopen conversation',
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
            else ...[
              LoadingBar(picking),
              if (attachment != null)
                _ComposerCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.attach_file),
                    title: Text(
                      attachment!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: AppIconButton(
                      tooltip: 'Remove attachment',
                      onPressed: () => setState(() => attachment = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (reply != null)
                _ComposerCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.reply, color: T.green),
                    title: Text(
                      reply!.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: AppIconButton(
                      tooltip: 'Cancel reply',
                      onPressed: () => setState(() => reply = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: IgnorePointer(
                  ignoring: !permission.canSend,
                  child: AnimatedOpacity(
                    opacity: permission.canSend ? 1 : .45,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _ComposerCard(
                              margin: EdgeInsets.zero,
                              padding: const EdgeInsets.only(right: 12),
                              radius: 24,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  AppMenuButton<String>(
                                    tooltip: 'Message tools',
                                    onSelected: (v) {
                                      if (v == 'attach') {
                                        pickAttachment();
                                      } else if (v == 'quick') {
                                        quickReplies();
                                      } else {
                                        templates();
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'attach',
                                        child: Text('Image, video or document'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'quick',
                                        child: Text('Quick replies'),
                                      ),
                                      if (permission.canTemplate)
                                        const PopupMenuItem(
                                          value: 'templates',
                                          child: Text('Templates'),
                                        ),
                                    ],
                                    icon: const Icon(Icons.add, color: T.brass),
                                  ),
                                  Expanded(
                                    child: AppTextField(
                                      controller: composer,
                                      minLines: 1,
                                      maxLines: 5,
                                      // "/" opens quick replies, as in the
                                      // web ticket inbox.
                                      onChanged: (v) {
                                        if (v == '/') {
                                          composer.clear();
                                          quickReplies();
                                        }
                                      },
                                      decoration: const InputDecoration(
                                        hintText: 'Message  ·  / quick replies',
                                        isDense: true,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        filled: false,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Send message',
                            child: Semantics(
                              button: true,
                              label: 'Send message',
                              child: Material(
                                color: T.green,
                                shape: const CircleBorder(),
                                elevation: 1,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: picking ? null : send,
                                  child: const SizedBox(
                                    width: 46,
                                    height: 46,
                                    child: Icon(
                                      Icons.send,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Templates')),
    body: templates == null
        ? error == null
              ? const Center(child: CircularProgressIndicator())
              : failure(error!, load)
        : ListView(
            children: [
              if (templates!.isEmpty)
                const ListTile(title: Text('No sendable templates')),
              for (final t in templates!)
                AppListTile(
                  title: Text('${t['name']}'),
                  subtitle: Text('${t['category']} · ${t['language']}'),
                  onTap: () async {
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
                    if (sent == true && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                ),
            ],
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
    final expires = widget.expiresAt;
    final left = expires?.difference(DateTime.now());
    final open = left != null && !left.isNegative;
    final label = !widget.known
        ? ''
        : open
        ? left.inHours > 0
              ? '${left.inHours}h ${left.inMinutes % 60}m left'
              : '${left.inMinutes.clamp(1, 59)}m left'
        : 'Window closed';
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

/// White raised surface floating on the chat wallpaper (composer, banners).
class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(8, 4, 8, 4),
    this.padding = const EdgeInsets.all(12),
    this.radius = 14,
  });
  final Widget child;
  final EdgeInsets margin, padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: T.ink.withValues(alpha: .12),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ],
    ),
    child: child,
  );
}
