import 'dart:async';

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
  List<ApiMessage> messages = [];
  final pending = <PendingSend>[];
  ApiMessage? reply;
  Attachment? attachment;
  bool picking = false;
  Json? detail, ticket;
  bool detailsBusy = false, showLoading = false;
  bool windowRejected = false;
  String get cacheKey =>
      "chat:${widget.session.api.wabaId}:$contactId:${widget.ticketId}";
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
  bool busy = false, more = false;
  int? oldest;
  Timer? poll;
  late final repository = InboxRepository(widget.session.api);
  int get contactId => number(widget.contact['id'])!;
  String get phone => '${widget.contact['wa_id'] ?? ''}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messages = (widget.session.viewCache[cacheKey] as List<ApiMessage>?) ?? [];
    load(quiet: messages.isNotEmpty);
    details();
    startPoll();
  }

  void startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if ((ModalRoute.of(context)?.isCurrent ?? false) && !busy) {
        load(quiet: true);
        details();
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
    poll?.cancel();
    composer.dispose();
    scroll.dispose();
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
      setState(() {
        detail = object(results.first['data']);
        if (widget.ticketId != null) {
          ticket = object(object(results.last['data'])['ticket']);
        }
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
    setState(() {
      busy = true;
      showLoading = !quiet;
      if (!quiet) error = null;
    });
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
      setState(() {
        final initial = messages.isEmpty;
        messages = mergeMessages(messages, incoming);
        widget.session.viewCache[cacheKey] = messages;
        final ids = incoming
            .map((m) => m.tempId)
            .where((id) => id.isNotEmpty)
            .toSet();
        pending.removeWhere((p) => ids.contains(p.key));
        if (older || initial) {
          more = widget.ticketId != null
              ? incoming.length == 50
              : meta['has_more'] == true;
          oldest = number(meta['oldest_id']);
        }
        if (!older && meta['sync_from'] != null) sync = '${meta['sync_from']}';
        error = null;
      });
      if (incoming.any((m) => !m.outgoing)) markRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        if (!older && nearEnd) scroll.jumpTo(0);
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          showLoading = false;
        });
      }
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

  Future<void> quickReplies() async {
    try {
      final result = await widget.session.api.get('inbox/canned-responses');
      final data = object(result['data']);
      final list = [
        ...rows(data['uncategorised']),
        for (final c in rows(data['categories'])) ...rows(c['responses']),
      ];
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
                onPressed: busy ? null : () => load(older: true),
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
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: T.paper,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 11, color: T.muted),
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
        title: Row(
          children: [
            Avatar(name, size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    widget.ticketId == null
                        ? '${widget.contact['display_wa_id'] ?? phone}'
                        : 'Ticket conversation',
                    style: const TextStyle(fontSize: 11, color: T.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          AppIconButton(
            tooltip: 'Refresh',
            onPressed: busy
                ? null
                : () {
                    load(quiet: messages.isNotEmpty);
                    details();
                  },
            icon: const Icon(Icons.refresh),
          ),
          AppIconButton(
            tooltip: 'Contact details',
            onPressed: () async {
              await openPage(
                context,
                ContactActionsPage(widget.session, contactId),
              );
              if (mounted) details();
            },
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (showLoading) const LinearProgressIndicator(minHeight: 2),
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
            child: CustomPaint(
              painter: ChatWallpaper(),
              child: messages.isEmpty && pending.isEmpty && !busy
                  ? const Center(child: Text('No messages yet.'))
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: messages.length + pending.length + 1,
                      itemBuilder: (_, index) =>
                          historyItem(messages.length + pending.length - index),
                    ),
            ),
          ),
          if (!permission.canSend)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: T.paper,
                  border: Border(top: BorderSide(color: T.edge)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      permission.reason!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: T.secondary),
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
            if (picking) const LinearProgressIndicator(minHeight: 2),
            if (attachment != null)
              ListTile(
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
            if (reply != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.reply),
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
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
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
                      icon: const Icon(Icons.add),
                    ),
                    Expanded(
                      child: AppTextField(
                        controller: composer,
                        minLines: 1,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          isDense: true,
                        ),
                      ),
                    ),
                    AppIconButton(
                      tooltip: 'Send message',
                      onPressed: picking ? null : send,
                      icon: const Icon(Icons.send, color: T.green),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
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
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get(
        'inbox/templates',
        query: {'contact_id': widget.contact['id']},
      );
      if (mounted) {
        setState(() {
          templates = rows(r['data']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
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
                  onTap: () => openPage(
                    context,
                    TemplateSend(
                      widget.session,
                      widget.contact,
                      t,
                      ticketId: widget.ticketId,
                    ),
                  ),
                ),
            ],
          ),
  );
}
