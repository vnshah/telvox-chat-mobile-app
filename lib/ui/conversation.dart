import 'package:flutter/material.dart';
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
  String? reply;
  final reactions = <int, String>{};
  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(previewProvider);
    final p = person(state, widget.id);
    final messages =
        state.messages[p.id] ??
        [Message('Hello! How can we help you today?', out: true)];
    return Scaffold(
      backgroundColor: T.wash,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => context.push('/customer/${p.id}'),
          child: Row(
            children: [
              Avatar(p.name, size: 35, color: p.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(p.phone, style: mono(size: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            onPressed: () => context.push('/call/${p.id}'),
            icon: const Icon(Icons.call_outlined, size: 21),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            iconColor: T.brass,
            onSelected: (v) async {
              if (v == 'details') {
                context.push('/customer/${p.id}');
              }
              if (v == 'media') {
                context.push('/customer/${p.id}/media');
              }
              if (v == 'assign') {
                context.push('/customer/${p.id}/assign');
              }
              if (v == 'favourite') {
                ref.read(previewProvider.notifier).favorite(p.id);
              }
              if (v == 'close') {
                ref.read(previewProvider.notifier).close(p.id);
                notice(
                  context,
                  p.closed
                      ? 'Conversation reopened in preview.'
                      : 'Conversation closed in preview.',
                );
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
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: T.brass),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Assigned to ${p.assignee}',
                      style: const TextStyle(fontSize: 11, color: T.secondary),
                    ),
                  ),
                  const Pill('Preview', color: T.brass, fill: T.wash),
                  const SizedBox(width: 8),
                  Pill(p.closed ? 'Closed' : 'Open', dot: true),
                ],
              ),
            ),
            if (p.bot)
              Container(
                color: T.selected,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_outlined,
                      size: 17,
                      color: T.green,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Studio assistant is handling this chat.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(previewProvider.notifier).assign(p.id, 'You');
                        notice(context, 'Assigned to you in preview.');
                      },
                      child: const Text('Take over'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                itemCount: messages.length + 1,
                itemBuilder: (context, reversed) {
                  if (reversed == messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Center(
                        child: Pill(
                          'TODAY · 28 OCT',
                          color: T.muted,
                          fill: Colors.white.withValues(alpha: .8),
                        ),
                      ),
                    );
                  }
                  final i = messages.length - reversed - 1;
                  final m = messages[i];
                  return GestureDetector(
                    onLongPress: () => _messageActions(m, i),
                    child: Align(
                      alignment: m.out
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.sizeOf(context).width.clamp(320, 900) *
                              .76,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        decoration: BoxDecoration(
                          color: m.out ? T.outgoing : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(m.out ? 16 : 4),
                            bottomRight: Radius.circular(m.out ? 4 : 16),
                          ),
                          border: Border.all(
                            color: T.edge.withValues(alpha: .65),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.reply != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 9),
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .5),
                                  border: const Border(
                                    left: BorderSide(color: T.green, width: 3),
                                  ),
                                ),
                                child: Text(
                                  m.reply!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: T.secondary,
                                  ),
                                ),
                              ),
                            if (m.type == 'document')
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    color: T.brass,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.text,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          'PDF · 248 KB',
                                          style: mono(size: 9),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Preview document',
                                    onPressed: () =>
                                        context.push('/customer/${p.id}/media'),
                                    icon: const Icon(
                                      Icons.download_outlined,
                                      size: 19,
                                    ),
                                  ),
                                ],
                              )
                            else if (m.type == 'order')
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Eyebrow('Order confirmed'),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const ProductArt(
                                        icon: Icons.shopping_bag_outlined,
                                        small: true,
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Everyday canvas tote',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                            SizedBox(height: 5),
                                            Text(
                                              'Natural · 1 item',
                                              style: TextStyle(
                                                color: T.muted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '₹1,290',
                                    style: mono(size: 15, color: T.ink),
                                  ),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () => context.push('/order/2048'),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'View order',
                                            style: TextStyle(
                                              color: T.brass,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward,
                                            size: 14,
                                            color: T.brass,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else if (m.type == 'audio')
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Play voice preview',
                                    onPressed: () => notice(
                                      context,
                                      'Audio is a visual preview.',
                                    ),
                                    icon: const Icon(
                                      Icons.play_circle_outline,
                                      size: 30,
                                      color: T.green,
                                    ),
                                  ),
                                  const Expanded(child: VoiceWave()),
                                  Text('0:12', style: mono(size: 10)),
                                ],
                              )
                            else if (m.type == 'image')
                              Column(
                                children: [
                                  const ProductArt(
                                    icon: Icons.shopping_bag_outlined,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    m.text,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              )
                            else if (m.type == 'location')
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 100,
                                    width: 200,
                                    decoration: BoxDecoration(
                                      color: T.selected,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      size: 38,
                                      color: T.green,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    m.text,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              )
                            else
                              Text(
                                m.text,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.55,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if ((reactions[i] ?? m.reaction)
                                    .isNotEmpty) ...[
                                  Text(reactions[i] ?? m.reaction),
                                  const SizedBox(width: 10),
                                ],
                                const Spacer(),
                                Text(m.time, style: mono(size: 9)),
                                if (m.out) ...[
                                  const SizedBox(width: 5),
                                  Icon(
                                    m.time == 'Now'
                                        ? Icons.check
                                        : Icons.done_all,
                                    size: 14,
                                    color: m.time == 'Now' ? T.muted : T.blue,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (reply != null)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 16, color: T.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reply!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: T.muted),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: () => setState(() => reply = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: T.edge)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Attach',
                        onPressed: _attachments,
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 24,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: composer,
                          minLines: 1,
                          maxLines: 4,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Write a reply…',
                            filled: true,
                            fillColor: T.wash,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      IconButton.filled(
                        tooltip: composer.text.trim().isEmpty
                            ? 'Voice message'
                            : 'Send reply',
                        style: IconButton.styleFrom(
                          backgroundColor: T.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: composer.text.trim().isEmpty
                            ? _voice
                            : _send,
                        icon: Icon(
                          composer.text.trim().isEmpty
                              ? Icons.mic_none_rounded
                              : Icons.arrow_upward_rounded,
                          size: 23,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      _composerAction(
                        Icons.auto_awesome_outlined,
                        'AI assist',
                        () async {
                          final draft = await context.push<String>(
                            '/ai?contact=${p.id}',
                          );
                          if (draft != null && mounted) {
                            setState(() => composer.text = draft);
                          }
                        },
                      ),
                      const SizedBox(width: 18),
                      _composerAction(
                        Icons.bolt_outlined,
                        'Quick replies',
                        () async {
                          final draft = await context.push<String>(
                            '/quick-replies?pick=true',
                          );
                          if (draft != null && mounted) {
                            setState(() => composer.text = draft);
                          }
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            context.push('/templates?contact=${p.id}'),
                        child: const Text(
                          'Templates',
                          style: TextStyle(fontSize: 10, color: T.brass),
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

  Widget _composerAction(IconData icon, String label, VoidCallback tap) =>
      InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 13, color: T.brass),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10, color: T.brass)),
            ],
          ),
        ),
      );
  void _send() {
    ref
        .read(previewProvider.notifier)
        .send(widget.id, composer.text, reply: reply);
    setState(() {
      composer.clear();
      reply = null;
    });
  }

  void _messageActions(Message m, int i) => sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final emoji in ['🤍', '👍', '😊', '🙏', '✨'])
              TextButton(
                onPressed: () {
                  setState(() => reactions[i] = emoji);
                  Navigator.pop(context);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
          ],
        ),
        MenuRow(
          'Reply to message',
          Icons.reply_rounded,
          onTap: () {
            setState(() => reply = m.text);
            Navigator.pop(context);
          },
        ),
        MenuRow(
          'Remove reaction',
          Icons.emoji_emotions_outlined,
          onTap: () {
            setState(() => reactions[i] = '');
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
  void _attachments() => sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Share something', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Sample attachments for this preview.',
          style: TextStyle(color: T.muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final (icon, label, type, content) in [
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
                width: 92,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    ref
                        .read(previewProvider.notifier)
                        .send(widget.id, content, type: type);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: T.wash,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: T.brass),
                      ),
                      const SizedBox(height: 9),
                      Text(label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        MenuRow(
          'Share a product',
          Icons.shopping_bag_outlined,
          onTap: () {
            Navigator.pop(context);
            context.push('/catalogue?contact=${widget.id}');
          },
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
        const SizedBox(height: 30),
        const SizedBox(height: 50, child: VoiceWave()),
        const SizedBox(height: 12),
        Center(child: Text('0:12', style: mono(size: 16))),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            ref
                .read(previewProvider.notifier)
                .send(widget.id, 'Voice message', type: 'audio');
          },
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Add to conversation'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
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
    child: Icon(
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
        IconButton(
          tooltip: 'Edit contact',
          onPressed: () => context.push('/contact/$id/edit'),
          icon: const Icon(Icons.edit_outlined, size: 20),
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
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/chat/$id'),
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Message'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/call/$id'),
                  icon: const Icon(Icons.call_outlined, size: 17),
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
                  trailing: Switch(
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
                  trailing: Switch(
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
                  trailing: Switch(
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
    bottom: FilledButton(
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
              ListTile(
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
                trailing: Icon(
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
                  Icon(Icons.lock_outline, color: T.brass, size: 17),
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
            FilledButton(
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
                  FilterChip(
                    label: Text(tag),
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
            FilledButton(
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
            FilledButton(
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
                  ChoiceChip(
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
                      Icon(
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
