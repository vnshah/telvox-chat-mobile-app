import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'theme.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage(this.id, {super.key, this.initialDraft});
  final String? initialDraft;
  final String id;
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  late final composer = TextEditingController(text: widget.initialDraft);
  final focus = FocusNode();
  final scroll = ScrollController();
  final bubbleKeys = <int, GlobalKey>{};
  final reactions = <int, String>{};
  final starred = <int>{};
  final deleted = <int>{};
  final entering = <int>{};
  String? reply;

  @override
  void dispose() {
    composer.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  Rect? _rect(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(previewProvider);
    final p = person(state, widget.id);
    final messages = state.messages[p.id] ?? <Message>[];
    final indices = [
      for (var i = 0; i < messages.length; i++)
        if (!deleted.contains(i)) i,
    ];
    final hasText = composer.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: T.paper,
      appBar: platformAppBar(
        context,
        leadingWidth: 42,
        leading: AppIconButton(
          tooltip: 'Back to inbox',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/inbox'),
          icon: const AppIcon(Icons.arrow_back_rounded, size: 22),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: () => context.push('/customer/${p.id}'),
          child: Row(
            children: [
              Avatar(p.name, size: 35, color: p.color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.closed
                          ? 'Closed · ${p.phone}'
                          : 'Assigned to ${p.assignee}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: T.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppIconButton(
            tooltip: 'Voice call',
            onPressed: () => context.push('/call/${p.id}'),
            icon: const AppIcon(
              Icons.call_outlined,
              size: 21,
              color: Colors.white,
            ),
          ),
          AppMenuButton<String>(
            tooltip: 'Conversation options',
            icon: const AppIcon(Icons.more_vert, size: 22, color: T.green),
            onSelected: (v) {
              switch (v) {
                case 'details':
                  context.push('/customer/${p.id}');
                case 'media':
                  context.push('/customer/${p.id}/media');
                case 'assign':
                  context.push('/customer/${p.id}/assign');
                case 'favourite':
                  ref.read(previewProvider.notifier).favorite(p.id);
                case 'close':
                  ref.read(previewProvider.notifier).close(p.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'details',
                child: Text('Contact details'),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Text('Media & documents'),
              ),
              const PopupMenuItem(
                value: 'assign',
                child: Text('Assign conversation'),
              ),
              PopupMenuItem(
                value: 'favourite',
                child: Text(
                  p.favorite ? 'Remove favourite' : 'Add to favourites',
                ),
              ),
              PopupMenuItem(
                value: 'close',
                child: Text(
                  p.closed ? 'Reopen conversation' : 'Close conversation',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomPaint(
          painter: const ChatWallpaper(),
          child: Column(
            children: [
              if (p.bot)
                Container(
                  color: T.selected,
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  child: Row(
                    children: [
                      const AppIcon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                        color: T.green,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Studio assistant is handling this chat.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      AppButton.text(
                        onPressed: () => ref
                            .read(previewProvider.notifier)
                            .assign(p.id, 'You'),
                        child: const Text('Take over'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                  itemCount: indices.length + 1,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String> ||
                        !key.value.startsWith('message-')) {
                      return null;
                    }
                    final index = int.tryParse(key.value.substring(8));
                    final position = indices.indexOf(index ?? -1);
                    return position < 0 ? null : indices.length - position - 1;
                  },
                  itemBuilder: (context, reversed) {
                    if (reversed == indices.length) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 12, bottom: 18),
                        child: Center(child: _DayLabel()),
                      );
                    }
                    final visible = indices.length - reversed - 1;
                    final i = indices[visible];
                    final m = messages[i];
                    final first =
                        visible == 0 ||
                        messages[indices[visible - 1]].out != m.out;
                    final reaction = reactions[i] ?? m.reaction;
                    return MessageEntry(
                      key: ValueKey('message-$i'),
                      animate: entering.contains(i),
                      onEnd: () => entering.remove(i),
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: first ? 10 : 5,
                          bottom: 1,
                        ),
                        child: SwipeReply(
                          onReply: () => _reply(m),
                          child: Align(
                            alignment: m.out
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: m.out
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onLongPress: () => _messageActions(m, i),
                                  child: MessageBubble(
                                    key: bubbleKeys.putIfAbsent(
                                      i,
                                      () => GlobalKey(),
                                    ),
                                    message: m,
                                    first: first,
                                    starred: starred.contains(i),
                                    maxWidth: math.min(
                                      MediaQuery.sizeOf(context).width * .84,
                                      520,
                                    ),
                                    onMenu: () => _messageActions(m, i),
                                  ),
                                ),
                                if (reaction.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 3,
                                      left: 8,
                                      right: 8,
                                      bottom: 1,
                                    ),
                                    child: InkWell(
                                      key: ValueKey('message-reaction-$i'),
                                      onTap: () => _messageActions(m, i),
                                      borderRadius: BorderRadius.circular(20),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        child: Container(
                                          key: ValueKey(reaction),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: T.wash,
                                            border: Border.all(color: T.edge),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Text(
                                            reaction,
                                            style: const TextStyle(
                                              fontSize: 13,
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
                    );
                  },
                ),
              ),
              if (reply != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 4, 58, 0),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: T.wash,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const AppIcon(Icons.reply, size: 18, color: T.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Replying to message',
                              style: TextStyle(
                                fontSize: 10,
                                color: T.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              reply!,
                              key: const ValueKey('reply-preview'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: T.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppIconButton(
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() => reply = null),
                        icon: const AppIcon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Padding(
                key: const ValueKey('chat-composer'),
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: T.edge.withValues(alpha: .65),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _smallAction(
                              Icons.emoji_emotions_outlined,
                              'Emoji',
                              _emoji,
                            ),
                            Expanded(
                              child: AppTextField(
                                controller: composer,
                                focusNode: focus,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  isDense: true,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 2,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            _smallAction(
                              Icons.attach_file_rounded,
                              'Attach',
                              _attachments,
                            ),
                            if (!hasText &&
                                MediaQuery.sizeOf(context).width >= 360)
                              _smallAction(
                                Icons.camera_alt_outlined,
                                'Camera',
                                () => _sendText(
                                  'Everyday canvas tote · Natural',
                                  type: 'image',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: AppIconButton.filled(
                        tooltip: hasText ? 'Send reply' : 'Voice message',
                        style: IconButton.styleFrom(
                          backgroundColor: T.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: hasText ? _send : _voice,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (child, a) =>
                              ScaleTransition(scale: a, child: child),
                          child: AppIcon(
                            hasText
                                ? Icons.send_rounded
                                : Icons.mic_none_rounded,
                            key: ValueKey(hasText),
                            size: 22,
                          ),
                        ),
                      ),
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

  Widget _smallAction(IconData icon, String label, VoidCallback action) =>
      SizedBox(
        width: 40,
        height: 44,
        child: AppIconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          onPressed: action,
          icon: AppIcon(icon, size: 22, color: T.muted),
        ),
      );

  void _reply(Message m) {
    HapticFeedback.selectionClick();
    setState(() => reply = m.text);
    focus.requestFocus();
  }

  void _send() {
    final text = composer.text.trim();
    if (text.isEmpty) return;
    _sendText(text, quoted: reply);
    setState(() {
      composer.clear();
      reply = null;
    });
  }

  void _sendText(String text, {String type = 'text', String? quoted}) {
    final index = (ref.read(previewProvider).messages[widget.id] ?? []).length;
    if (!MediaQuery.disableAnimationsOf(context)) entering.add(index);
    ref
        .read(previewProvider.notifier)
        .send(widget.id, text, type: type, reply: quoted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  Future<void> _messageActions(Message m, int i) async {
    focus.unfocus();
    final anchor = _rect(bubbleKeys[i]);
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss message actions',
      barrierColor: Colors.black.withValues(alpha: .12),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
      pageBuilder: (dialogContext, _, _) => SafeArea(
        child: LayoutBuilder(
          builder: (context, size) {
            final top =
                ((anchor?.top ?? size.maxHeight / 3) -
                        MediaQuery.paddingOf(context).top -
                        52)
                    .clamp(12.0, math.max(12.0, size.maxHeight - 410))
                    .toDouble();
            return Stack(
              children: [
                Positioned(
                  top: top,
                  right: m.out ? 12 : null,
                  left: m.out ? null : 12,
                  width: math.min(270, size.maxWidth - 24),
                  child: Material(
                    color: T.wash,
                    elevation: 3,
                    shadowColor: T.ink.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(100, size.maxHeight - top - 12),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (final emoji in [
                                    '👍',
                                    '🤍',
                                    '😊',
                                    '🙏',
                                    '✨',
                                  ])
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => Navigator.pop(
                                          dialogContext,
                                          'emoji:$emoji',
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Center(
                                            child: Text(
                                              emoji,
                                              style: const TextStyle(
                                                fontSize: 23,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            for (final (value, label, icon) in [
                              ('reply', 'Reply', Icons.reply_rounded),
                              ('copy', 'Copy', Icons.content_copy_rounded),
                              ('forward', 'Forward', Icons.forward_rounded),
                              (
                                'star',
                                starred.contains(i) ? 'Unstar' : 'Star',
                                Icons.star_border_rounded,
                              ),
                              if ((reactions[i] ?? m.reaction).isNotEmpty)
                                (
                                  'remove-reaction',
                                  'Remove reaction',
                                  Icons.emoji_emotions_outlined,
                                ),
                              (
                                'info',
                                'Message info',
                                Icons.info_outline_rounded,
                              ),
                              (
                                'delete',
                                'Delete for me',
                                Icons.delete_outline_rounded,
                              ),
                            ])
                              InkWell(
                                onTap: () =>
                                    Navigator.pop(dialogContext, value),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: value == 'delete'
                                                ? T.danger
                                                : T.ink,
                                          ),
                                        ),
                                      ),
                                      AppIcon(
                                        icon,
                                        size: 19,
                                        color: value == 'delete'
                                            ? T.danger
                                            : T.secondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.startsWith('emoji:')) {
      HapticFeedback.selectionClick();
      setState(() => reactions[i] = selected.substring(6));
      return;
    }
    switch (selected) {
      case 'reply':
        _reply(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) notice(context, 'Message copied');
      case 'forward':
        _forward(m);
      case 'star':
        setState(
          () => starred.contains(i) ? starred.remove(i) : starred.add(i),
        );
      case 'remove-reaction':
        setState(() => reactions[i] = '');
      case 'info':
        sheet(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Message info',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Text(m.text),
              const SizedBox(height: 20),
              InfoLine(m.out ? 'Sent' : 'Received', m.time),
              if (m.out)
                const InfoLine('Delivery', 'Delivered · sample status'),
            ],
          ),
        );
      case 'delete':
        if (await confirm(
              context,
              'Delete this message?',
              'Remove it from this preview conversation.',
              action: 'Delete for me',
            ) &&
            mounted) {
          setState(() => deleted.add(i));
        }
    }
  }

  void _forward(Message m) => sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forward to', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final p
            in ref.read(previewProvider).people.where((p) => p.id != widget.id))
          AppListTile(
            leading: Avatar(p.name, size: 36, color: p.color),
            title: Text(p.name),
            subtitle: Text(p.phone, style: mono(size: 10)),
            onTap: () {
              ref
                  .read(previewProvider.notifier)
                  .send(p.id, m.text, type: m.type);
              Navigator.pop(context);
              notice(context, 'Forwarded to ${p.name} in preview.');
            },
          ),
      ],
    ),
  );

  void _emoji() => sheet(
    context,
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final emoji in [
          '😊',
          '🤍',
          '👍',
          '🙏',
          '✨',
          '🎉',
          '👋',
          '❤️',
          '🙌',
          '🙂',
          '✅',
          '📦',
        ])
          AppIconButton(
            tooltip: 'Insert $emoji',
            onPressed: () {
              final selection = composer.selection;
              final start = selection.isValid
                  ? selection.start
                  : composer.text.length;
              final end = selection.isValid ? selection.end : start;
              composer.value = TextEditingValue(
                text: composer.text.replaceRange(start, end, emoji),
                selection: TextSelection.collapsed(
                  offset: start + emoji.length,
                ),
              );
              setState(() {});
              Navigator.pop(context);
              focus.requestFocus();
            },
            icon: Text(emoji, style: const TextStyle(fontSize: 25)),
          ),
      ],
    ),
  );

  Future<void> _draftTool(String route) async {
    Navigator.pop(context);
    final draft = await context.push<String>(route);
    if (draft != null && mounted) {
      setState(() => composer.text = draft);
      focus.requestFocus();
    }
  }

  void _attachments() => sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Share & compose', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final (icon, label, type, text) in [
              (
                Icons.image_outlined,
                'Photo',
                'image',
                'Everyday canvas tote · Natural',
              ),
              (
                Icons.description_outlined,
                'Document',
                'document',
                'Product_catalogue.pdf',
              ),
              (
                Icons.location_on_outlined,
                'Location',
                'location',
                'Studio North · Ahmedabad',
              ),
              (
                Icons.person_outline,
                'Contact',
                'text',
                'Studio North\n+91 98765 00001',
              ),
            ])
              SizedBox(
                width: 86,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _sendText(text, type: type);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: T.selected,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(icon, color: T.green),
                      ),
                      const SizedBox(height: 7),
                      Text(label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        MenuRow(
          'Quick replies',
          Icons.bolt_outlined,
          onTap: () => _draftTool('/quick-replies?pick=true'),
        ),
        MenuRow(
          'AI assist',
          Icons.auto_awesome_outlined,
          onTap: () => _draftTool('/ai?contact=${widget.id}'),
        ),
        MenuRow(
          'Templates',
          Icons.article_outlined,
          onTap: () {
            Navigator.pop(context);
            context.push('/templates?contact=${widget.id}');
          },
        ),
        MenuRow(
          'Share a product',
          Icons.shopping_bag_outlined,
          onTap: () {
            Navigator.pop(context);
            context.push('/catalogue?contact=${widget.id}');
          },
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Attachments use sample content in this preview.',
            style: TextStyle(fontSize: 11, color: T.muted),
          ),
        ),
      ],
    ),
  );

  void _voice() => sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Voice message', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'Preview a sample voice message.',
          style: TextStyle(color: T.muted),
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 45, child: VoiceWave()),
        const SizedBox(height: 12),
        Center(child: Text('0:12', style: mono(size: 16))),
        const SizedBox(height: 20),
        AppButton.filledIcon(
          onPressed: () {
            Navigator.pop(context);
            _sendText('Voice message', type: 'audio');
          },
          icon: const AppIcon(Icons.send_outlined, size: 18),
          label: const Text('Add to conversation'),
        ),
        AppButton.text(
          onPressed: () => Navigator.pop(context),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
}

class _DayLabel extends StatelessWidget {
  const _DayLabel();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: T.wash.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(7),
    ),
    child: const Text(
      'Today',
      style: TextStyle(fontSize: 10, color: T.secondary),
    ),
  );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.first = false,
    this.starred = false,
    this.maxWidth = 320,
    this.onMenu,
  });
  final Message message;
  final bool first, starred;
  final double maxWidth;
  final VoidCallback? onMenu;
  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = m.out ? T.outgoing : Colors.white;
    return CustomPaint(
      painter: first ? _BubbleTail(m.out, color) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: EdgeInsets.fromLTRB(
          m.type == 'image' || m.type == 'order' ? 5 : 11,
          9,
          9,
          7,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(first && !m.out ? 3 : 10),
            topRight: Radius.circular(first && m.out ? 3 : 10),
            bottomLeft: const Radius.circular(10),
            bottomRight: const Radius.circular(10),
          ),
          border: Border.all(
            color: m.out
                ? T.green.withValues(alpha: .18)
                : T.control.withValues(alpha: .65),
          ),
          boxShadow: [
            BoxShadow(
              color: T.ink.withValues(alpha: .08),
              offset: const Offset(0, 2),
              blurRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.reply != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: T.green.withValues(alpha: .07),
                  border: const Border(
                    left: BorderSide(color: T.green, width: 3),
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reply',
                      style: TextStyle(
                        color: T.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.reply!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: T.secondary),
                    ),
                  ],
                ),
              ),
            if (m.type == 'image' || m.type == 'order') ...[
              SizedBox(
                width: maxWidth - 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: const SizedBox(
                    height: 122,
                    child: ProductArt(icon: Icons.shopping_bag_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (m.type == 'document')
              Container(
                padding: const EdgeInsets.all(9),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: T.green.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon(
                      Icons.description_outlined,
                      color: T.brass,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.text,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'PDF · 248 KB',
                            style: TextStyle(fontSize: 9, color: T.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const AppIcon(
                      Icons.download_rounded,
                      size: 20,
                      color: T.brass,
                    ),
                  ],
                ),
              ),
            if (m.type == 'audio')
              SizedBox(
                width: maxWidth - 18,
                child: Row(
                  children: [
                    const AppIcon(
                      Icons.play_arrow_rounded,
                      color: T.green,
                      size: 30,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: SizedBox(height: 32, child: VoiceWave()),
                    ),
                    const SizedBox(width: 8),
                    Text('0:12', style: mono(size: 9)),
                  ],
                ),
              ),
            if (m.type == 'location')
              Container(
                height: 88,
                width: maxWidth - 18,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: T.selected,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: AppIcon(Icons.location_on, color: T.green, size: 32),
                ),
              ),
            Stack(
              children: [
                if (m.type != 'document' && m.type != 'audio')
                  Padding(
                    padding: const EdgeInsets.only(right: 1),
                    child: Text.rich(
                      TextSpan(
                        text: m.text,
                        children: [
                          WidgetSpan(
                            child: SizedBox(
                              width: starred ? 97 : 83,
                              height: 13,
                            ),
                          ),
                        ],
                      ),
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: T.ink,
                      ),
                    ),
                  )
                else
                  SizedBox(width: maxWidth - 18, height: 17),
                Positioned(
                  right: 0,
                  bottom: -2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (starred)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: AppIcon(
                            Icons.star_rounded,
                            size: 10,
                            color: T.brass,
                          ),
                        ),
                      Text(
                        m.time == 'Now' ? 'now' : m.time,
                        style: mono(size: 8, color: T.muted),
                      ),
                      if (m.out)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: AppIcon(
                            m.time == 'Now' ? Icons.check : Icons.done_all,
                            size: 13,
                            color: m.time == 'Now' ? T.muted : T.blue,
                          ),
                        ),
                      if (onMenu != null)
                        SizedBox(
                          width: 25,
                          height: 23,
                          child: AppIconButton(
                            tooltip: 'Message options',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onMenu,
                            icon: const AppIcon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: T.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  _BubbleTail(this.out, this.color);
  final bool out;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final x = out ? size.width - 2 : 2.0;
    final direction = out ? 1.0 : -1.0;
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x + 7 * direction, 0)
        ..quadraticBezierTo(x + 8 * direction, 0, x + 5 * direction, 4)
        ..lineTo(x, 10)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTail old) =>
      old.out != out || old.color != color;
}

class SwipeReply extends StatefulWidget {
  const SwipeReply({super.key, required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double distance = 0;
  bool dragging = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: (_) => setState(() => dragging = true),
    onHorizontalDragUpdate: (d) =>
        setState(() => distance = (distance + d.delta.dx).clamp(0, 64)),
    onHorizontalDragEnd: (_) {
      if (distance >= 38) widget.onReply();
      setState(() {
        dragging = false;
        distance = 0;
      });
    },
    onHorizontalDragCancel: () => setState(() {
      dragging = false;
      distance = 0;
    }),
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (distance > 8)
          Opacity(
            opacity: (distance / 48).clamp(0, 1),
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: AppIcon(Icons.reply_rounded, color: T.green, size: 22),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: dragging ? 0 : 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(distance, 0, 0),
          child: widget.child,
        ),
      ],
    ),
  );
}

class MessageEntry extends StatefulWidget {
  const MessageEntry({
    super.key,
    required this.child,
    required this.animate,
    required this.onEnd,
  });
  final Widget child;
  final bool animate;
  final VoidCallback onEnd;
  @override
  State<MessageEntry> createState() => _MessageEntryState();
}

class _MessageEntryState extends State<MessageEntry>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: widget.animate ? 0 : 1,
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) controller.forward().whenComplete(widget.onEnd);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = controller.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: progress,
      child: ScaleTransition(
        scale: Tween<double>(begin: .99, end: 1).animate(progress),
        alignment: Alignment.bottomRight,
        child: widget.child,
      ),
    );
  }
}

class ChatWallpaper extends CustomPainter {
  const ChatWallpaper();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [T.paper, Color(0xFFE5EDE4)],
        ).createShader(Offset.zero & size),
    );
    final line = Paint()
      ..color = T.brass.withValues(alpha: .085)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var y = -24.0; y < size.height + 80; y += 108) {
      for (var x = -10.0; x < size.width + 80; x += 116) {
        canvas.save();
        canvas.translate(x + ((y ~/ 108).isEven ? 0 : 50), y);
        canvas.rotate(-.20);
        // Small chat, leaf and spark motifs echo the Telvox mark and earthy palette.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 8, 27, 19),
            const Radius.circular(6),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15, 27)
            ..lineTo(13, 32)
            ..lineTo(22, 27),
          line,
        );
        canvas.drawLine(const Offset(15, 16), const Offset(28, 16), line);
        canvas.drawLine(const Offset(15, 21), const Offset(23, 21), line);
        canvas.drawPath(
          Path()
            ..moveTo(66, 69)
            ..quadraticBezierTo(43, 46, 72, 42)
            ..quadraticBezierTo(84, 61, 66, 69)
            ..moveTo(63, 76)
            ..lineTo(72, 49),
          line,
        );
        canvas.drawLine(const Offset(82, 15), const Offset(82, 25), line);
        canvas.drawLine(const Offset(77, 20), const Offset(87, 20), line);
        canvas.drawCircle(const Offset(25, 76), 2.5, line);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChatWallpaper oldDelegate) => false;
}

class VoiceWave extends StatelessWidget {
  const VoiceWave({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < (size.maxWidth / 7).floor().clamp(5, 45); i++)
          Container(
            width: 3,
            height: (8 + (i * 17 % 27)).toDouble(),
            decoration: BoxDecoration(
              color: i < 7 ? T.green : T.brass.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
      ],
    ),
  );
}

class ProductArt extends StatelessWidget {
  const ProductArt({
    super.key,
    required this.icon,
    this.color = T.paper,
    this.small = false,
  });
  final IconData icon;
  final Color color;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
    height: small ? 52 : 160,
    width: small ? 52 : double.infinity,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(small ? 9 : 14),
    ),
    alignment: Alignment.center,
    child: AppIcon(
      icon,
      size: small ? 30 : 76,
      color: T.brass.withValues(alpha: .8),
    ),
  );
}

class CustomerPage extends ConsumerWidget {
  const CustomerPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewProvider);
    final p = person(state, id);
    return PageFrame(
      title: 'Contact details',
      actions: [
        AppIconButton(
          tooltip: 'Edit contact',
          onPressed: () => context.push('/contact/$id/edit'),
          icon: const AppIcon(Icons.edit_outlined, size: 20),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(child: Avatar(p.name, size: 80, color: p.color)),
          const SizedBox(height: 16),
          Center(
            child: Text(p.name, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 6),
          Center(child: Text(p.phone, style: mono(size: 13))),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: AppButton.outlinedIcon(
                  onPressed: () => context.push('/chat/$id'),
                  icon: const AppIcon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Message'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton.outlinedIcon(
                  onPressed: () => context.push('/call/$id'),
                  icon: const AppIcon(Icons.call_outlined, size: 17),
                  label: const Text('Call'),
                ),
              ),
            ],
          ),
          Section(
            'Labels',
            action: 'Edit',
            onTap: () => context.push('/customer/$id/tags'),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in p.tags) Pill(tag, color: T.brass, fill: T.wash),
            ],
          ),
          const Section('Conversation'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                MenuRow(
                  'Assigned to',
                  Icons.person_outline,
                  subtitle: p.assignee,
                  route: '/customer/$id/assign',
                ),
                const Divider(),
                MenuRow(
                  'Favourite',
                  Icons.star_border_rounded,
                  trailing: Switch.adaptive(
                    value: p.favorite,
                    onChanged: (_) =>
                        ref.read(previewProvider.notifier).favorite(id),
                  ),
                  onTap: () => ref.read(previewProvider.notifier).favorite(id),
                ),
                const Divider(),
                MenuRow(
                  'Status',
                  Icons.check_circle_outline,
                  subtitle: p.closed ? 'Closed' : 'Open',
                  trailing: Pill(p.closed ? 'Closed' : 'Open'),
                  onTap: () => ref.read(previewProvider.notifier).close(id),
                ),
              ],
            ),
          ),
          const Section('Customer information'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                MenuRow(
                  'Notes',
                  Icons.notes_rounded,
                  subtitle: '${p.notes.length} notes',
                  route: '/customer/$id/notes',
                ),
                const Divider(),
                MenuRow(
                  'Custom fields',
                  Icons.list_alt_outlined,
                  route: '/customer/$id/fields',
                ),
                const Divider(),
                MenuRow(
                  'Media & documents',
                  Icons.photo_library_outlined,
                  route: '/customer/$id/media',
                ),
                const Divider(),
                MenuRow(
                  'Order history',
                  Icons.shopping_bag_outlined,
                  route: '/orders',
                ),
              ],
            ),
          ),
          const Section('Preferences'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                MenuRow(
                  'Do not disturb',
                  Icons.notifications_off_outlined,
                  subtitle: 'Pause outbound marketing',
                  trailing: Switch.adaptive(
                    value: state.preferences['dnd$id'] ?? false,
                    onChanged: (v) => ref
                        .read(previewProvider.notifier)
                        .preference('dnd$id', v),
                  ),
                ),
                const Divider(),
                MenuRow(
                  'Block contact',
                  Icons.block_outlined,
                  danger: true,
                  trailing: Switch.adaptive(
                    value: state.preferences['block$id'] ?? false,
                    onChanged: (v) async {
                      if (await confirm(
                        context,
                        v ? 'Block this contact?' : 'Unblock this contact?',
                        'This changes the contact in this preview only.',
                      )) {
                        ref
                            .read(previewProvider.notifier)
                            .preference('block$id', v);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ContactFormPage extends ConsumerStatefulWidget {
  const ContactFormPage({super.key, this.id});
  final String? id;
  @override
  ConsumerState<ContactFormPage> createState() => _ContactFormPageState();
}

class _ContactFormPageState extends ConsumerState<ContactFormPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.id == null
        ? ''
        : person(ref.read(previewProvider), widget.id!).name,
  );
  late final phone = TextEditingController(
    text: widget.id == null
        ? ''
        : person(ref.read(previewProvider), widget.id!).phone,
  );
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.id == null ? 'New contact' : 'Edit contact',
    subtitle: 'A few details to make every conversation personal.',
    bottom: AppButton.filled(
      onPressed: () {
        if (!form.currentState!.validate()) return;
        ref
            .read(previewProvider.notifier)
            .contact(name.text, phone.text, id: widget.id);
        context.pop();
        notice(context, 'Contact saved in preview.');
      },
      child: const Text('Save contact'),
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Center(child: Avatar('New contact', size: 76)),
          const SizedBox(height: 28),
          LabeledField(
            'Full name',
            controller: name,
            hint: 'e.g. Ananya Shah',
            required: true,
          ),
          LabeledField(
            'Phone number',
            controller: phone,
            hint: '+91 98765 43210',
            keyboard: TextInputType.phone,
            required: true,
          ),
          const LabeledField(
            'Email address',
            hint: 'name@example.com',
            keyboard: TextInputType.emailAddress,
          ),
          const LabeledField('Company', hint: 'Business or company name'),
          const LabeledField(
            'Notes',
            hint: 'Anything your team should know',
            lines: 3,
          ),
        ],
      ),
    ),
  );
}

class ContactToolPage extends ConsumerStatefulWidget {
  const ContactToolPage(this.id, this.tool, {super.key});
  final String id, tool;
  @override
  ConsumerState<ContactToolPage> createState() => _ContactToolPageState();
}

class _ContactToolPageState extends ConsumerState<ContactToolPage> {
  final note = TextEditingController();
  String tab = 'Photos';
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = person(ref.watch(previewProvider), widget.id);
    final control = ref.read(previewProvider.notifier);
    final tool = widget.tool;
    final title = switch (tool) {
      'assign' => 'Assign conversation',
      'notes' => 'Internal notes',
      'tags' => 'Contact labels',
      'fields' => 'Custom fields',
      _ => 'Media & documents',
    };
    return PageFrame(
      title: title,
      subtitle: p.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tool == 'assign') ...[
            const Panel(
              color: T.wash,
              child: Text(
                'Keep ownership clear so every customer gets a thoughtful reply.',
                style: TextStyle(color: T.secondary, fontSize: 13),
              ),
            ),
            const Section('Team members'),
            for (final member in [
              'You',
              'Meera',
              'Aditya',
              'Studio assistant',
              'Unassigned',
            ])
              AppListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(member, size: 40),
                title: Text(member, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  member == 'Studio assistant'
                      ? 'AI chatbot'
                      : member == 'Unassigned'
                      ? 'Available to the team'
                      : 'Customer experience',
                  style: const TextStyle(fontSize: 11, color: T.muted),
                ),
                selected: p.assignee == member,
                trailing: AppIcon(
                  p.assignee == member
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: p.assignee == member ? T.green : T.control,
                ),
                onTap: () {
                  control.assign(p.id, member);
                  context.pop();
                },
              ),
          ],
          if (tool == 'notes') ...[
            const Panel(
              color: T.wash,
              child: Row(
                children: [
                  AppIcon(Icons.lock_outline, color: T.brass, size: 17),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only your team can see these notes.',
                      style: TextStyle(fontSize: 12, color: T.secondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              'Add a note',
              controller: note,
              hint: 'Leave useful context for your team…',
              lines: 4,
            ),
            AppButton.filled(
              onPressed: () {
                if (note.text.trim().isEmpty) return;
                control.note(p.id, note.text.trim());
                note.clear();
              },
              child: const Text('Add note'),
            ),
            const Section('Conversation notes'),
            if (p.notes.isEmpty)
              const EmptyView(
                title: 'A place for the little details.',
                description:
                    'Preferences, follow-ups, or context worth keeping.',
                icon: Icons.notes_outlined,
              ),
            for (final n in p.notes.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Avatar('Renav Shah', size: 25),
                          SizedBox(width: 8),
                          Text(
                            'You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Spacer(),
                          Pill('Just now', color: T.muted, fill: T.wash),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(n),
                    ],
                  ),
                ),
              ),
          ],
          if (tool == 'tags') ...[
            const Eyebrow('Choose labels'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 9,
              runSpacing: 10,
              children: [
                for (final tag in [
                  'Customer',
                  'VIP',
                  'New lead',
                  'Order enquiry',
                  'Support',
                  'Repeat customer',
                  'Wholesale',
                  'Resolved',
                ])
                  AppFilterChip(
                    label: Text(tag),
                    labelStyle: const TextStyle(fontSize: 12, color: T.ink),
                    selected: p.tags.contains(tag),
                    onSelected: (value) => control.tags(
                      p.id,
                      value
                          ? [...p.tags, tag]
                          : p.tags.where((t) => t != tag).toList(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            AppButton.filled(
              onPressed: () => context.pop(),
              child: const Text('Done'),
            ),
          ],
          if (tool == 'fields') ...[
            const Section('Customer profile'),
            const LabeledField('Customer type', value: 'Retail'),
            const LabeledField('Preferred language', value: 'English'),
            const LabeledField('City', value: 'Ahmedabad'),
            const LabeledField('Order reference', value: 'ST-2048'),
            const LabeledField(
              'Birthday',
              hint: 'DD / MM / YYYY',
              keyboard: TextInputType.datetime,
            ),
            AppButton.filled(
              onPressed: () {
                notice(context, 'Fields saved in preview.');
                context.pop();
              },
              child: const Text('Save fields'),
            ),
          ],
          if (tool == 'media') ...[
            Wrap(
              spacing: 8,
              children: [
                for (final value in ['Photos', 'Documents', 'Links'])
                  AppChoiceChip(
                    label: Text(value),
                    selected: value == tab,
                    onSelected: (_) => setState(() => tab = value),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (tab == 'Photos')
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final product in products)
                    InkWell(
                      onTap: () => context.push('/product/${product.id}'),
                      child: ProductArt(
                        icon: product.icon,
                        color: product.color,
                      ),
                    ),
                ],
              )
            else if (tab == 'Documents') ...[
              MenuRow(
                'Invoice_ST2048.pdf',
                Icons.description_outlined,
                subtitle: 'PDF · 248 KB · Today',
                onTap: () => sheet(
                  context,
                  const Column(
                    children: [
                      AppIcon(
                        Icons.description_outlined,
                        size: 60,
                        color: T.brass,
                      ),
                      SizedBox(height: 20),
                      Text('Invoice #ST-2048'),
                      InfoLine('Customer', 'Ananya Shah'),
                      InfoLine('Item', 'Everyday canvas tote'),
                      InfoLine('Total', '₹1,290'),
                    ],
                  ),
                ),
              ),
              MenuRow(
                'Product_catalogue.pdf',
                Icons.description_outlined,
                subtitle: 'PDF · 1.2 MB · Yesterday',
                route: '/catalogue',
              ),
            ] else
              MenuRow(
                'Studio North catalogue',
                Icons.link_rounded,
                subtitle: 'Shared today',
                route: '/catalogue',
              ),
          ],
        ],
      ),
    );
  }
}
