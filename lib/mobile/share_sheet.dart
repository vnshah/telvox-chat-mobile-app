import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../ui/theme.dart';
import 'api.dart';
import 'offline_bar.dart' show OfflineNote;
import 'chat.dart' show LiveChat;
import 'conversation_window.dart';
import 'media.dart';
import 'message_content.dart' show readableText;
import 'message_view.dart' show VideoFirstFrame;
import 'models.dart';
import 'screens.dart' show openPage;

/// At most this many chats per share, as WhatsApp limits forwarding.
const shareChatLimit = 10;

/// Opens the share flow for files another app shared: choose chats, check
/// the preview, send. Returns once it is closed.
Future<void> openShare(
  NavigatorState navigator,
  MobileSession session,
  List<XFile> files,
) => navigator.push(
  MaterialPageRoute(builder: (_) => ShareTargetsPage(session, files)),
);

/// Whether this account may send from the shared inbox on this number; the
/// reason when it may not.
String? shareBlocked(MobileSession session) {
  if (session.inboxMode != InboxMode.shared) {
    return 'Sharing to chats works in the shared inbox. This number uses '
        'tickets, so open a ticket and attach the file there.';
  }
  if (session.canRoute('inbox.send.message') == false) {
    return 'Your account cannot send messages from this number.';
  }
  return null;
}

/// WhatsApp's "Send to…": the chats this account may see on this number,
/// searchable, one or more picked, then Next for the preview.
class ShareTargetsPage extends StatefulWidget {
  const ShareTargetsPage(this.session, this.files, {super.key});
  final MobileSession session;
  final List<XFile> files;
  @override
  State<ShareTargetsPage> createState() => _ShareTargetsPageState();
}

class _ShareTargetsPageState extends State<ShareTargetsPage> {
  final search = TextEditingController();
  Timer? debounce;
  List<Json> chats = [];
  final picked = <int, Json>{};
  bool loading = true;
  String? error;
  int asked = 0;

  @override
  void initState() {
    super.initState();
    if (shareBlocked(widget.session) == null) load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  /// The same list the inbox shows (the server scopes it to this account and
  /// number), newest first; search narrows it on the server.
  Future<void> load() async {
    final ticket = ++asked;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await InboxRepository(widget.session.api)
          .contacts(search: search.text.trim(), limit: 50);
      if (mounted && ticket == asked) setState(() => chats = rows);
    } catch (e) {
      if (mounted && ticket == asked) setState(() => error = '$e');
    } finally {
      if (mounted && ticket == asked) setState(() => loading = false);
    }
  }

  void searched(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), load);
  }

  void toggle(Json chat) {
    final id = number(chat['id']);
    if (id == null) return;
    setState(() {
      if (picked.remove(id) == null) {
        if (picked.length >= shareChatLimit) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can share with up to $shareChatLimit chats'),
            ),
          );
          return;
        }
        picked[id] = chat;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocked = shareBlocked(widget.session);
    final count = widget.files.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send to…'),
            Text(
              picked.isEmpty
                  ? '$count file${count == 1 ? '' : 's'}'
                  : '${picked.length} selected',
              style: const TextStyle(fontSize: 13, color: T.muted),
            ),
          ],
        ),
      ),
      body: blocked != null
          ? EmptyView(
              title: 'Cannot share here',
              description: blocked,
              icon: Icons.block,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    controller: search,
                    onChanged: searched,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search name or number',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: T.incoming,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (picked.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final chat in picked.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(_name(chat)),
                              onDeleted: () => toggle(chat),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: isOffline(error)
                      ? OfflineNote(load)
                      : error != null
                      ? EmptyView(
                          title: 'Chats did not load',
                          description: error!,
                          icon: Icons.cloud_off_outlined,
                          action: 'Try again',
                          onAction: load,
                        )
                      : chats.isEmpty && !loading
                      ? const EmptyView(
                          title: 'No chats found',
                          description: 'Try another name or number.',
                          icon: Icons.search_off,
                        )
                      : ListView.builder(
                          itemCount: chats.length,
                          itemBuilder: (context, i) => _row(chats[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: picked.isEmpty
          ? null
          : FloatingActionButton(
              key: const ValueKey('share-next'),
              tooltip: 'Next',
              backgroundColor: T.green,
              foregroundColor: Colors.white,
              onPressed: () => openPage(
                context,
                SharePreviewPage(
                  widget.session,
                  widget.files,
                  picked.values.toList(),
                ),
              ),
              child: const Icon(Icons.arrow_forward),
            ),
    );
  }

  Widget _row(Json chat) {
    final id = number(chat['id']);
    final selected = picked.containsKey(id);
    final window = shareWindow(chat);
    return ListTile(
      key: ValueKey('share-chat-$id'),
      onTap: () => toggle(chat),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(_name(chat), size: 44),
          if (selected)
            const Positioned(
              right: -2,
              bottom: -2,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: T.green,
                child: Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(_name(chat), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        window == false
            ? 'Window closed: only a template can be sent'
            : formatPhone('${chat['wa_id'] ?? ''}'),
        style: TextStyle(
          fontSize: 12.5,
          color: window == false ? T.danger : T.muted,
        ),
      ),
    );
  }
}

String _name(Json chat) {
  final name = readableText(chat['profile_name']);
  return name.isNotEmpty
      ? name
      : formatPhone('${chat['display_wa_id'] ?? chat['wa_id'] ?? ''}');
}

/// Whether the chat's WhatsApp window is open: true or false when the list
/// says, null when it cannot tell (an older server sends no expiry; then the
/// send itself is the check).
bool? shareWindow(Json chat) {
  final known =
      chat.containsKey('service_expiration_timestamp') ||
      chat.containsKey('referral_conversion_expiration_timestamp');
  final last = object(chat['last_message']);
  final expires = windowExpiresAt(chat, [if (last.isNotEmpty) last]);
  if (windowOpen(expires)) return true;
  return known ? false : null;
}

/// One shared file, checked as WhatsApp will take it: a supported type
/// within its size limit, or the reason it cannot go.
class SharedItem {
  SharedItem(this.file, {this.attachment, this.problem});
  final XFile file;
  final Attachment? attachment;
  final String? problem;
  final caption = TextEditingController();
}

Future<SharedItem> checkShared(XFile file) async {
  try {
    final mime = file.mimeType ?? '';
    final attachment = mime.startsWith('image/') || mime.startsWith('video/')
        ? await pickedAttachment(file)
        : await Attachment.fromFile(file);
    return SharedItem(file, attachment: attachment);
  } on ApiFailure catch (e) {
    return SharedItem(file, problem: e.message);
  } catch (_) {
    return SharedItem(file, problem: 'This file could not be read.');
  }
}

/// The preview before sending, as WhatsApp shows it: each file with a
/// caption, the chats it goes to, and Send. Files that cannot go say why
/// and are left out. Back cancels.
class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage(this.session, this.files, this.chats, {super.key});
  final MobileSession session;
  final List<XFile> files;
  final List<Json> chats;
  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  List<SharedItem>? items;
  bool sending = false;
  int sent = 0, total = 0;

  @override
  void initState() {
    super.initState();
    Future.wait(widget.files.map(checkShared)).then((checked) {
      if (mounted) setState(() => items = checked);
    });
  }

  @override
  void dispose() {
    for (final item in items ?? const <SharedItem>[]) {
      item.caption.dispose();
    }
    super.dispose();
  }

  List<SharedItem> get sendable => [
    for (final item in items ?? const <SharedItem>[])
      if (item.attachment != null) item,
  ];

  /// Every file to every chat, one after another, each as its own message
  /// in its own format; failures are collected, not fatal.
  Future<void> send() async {
    final files = sendable;
    if (files.isEmpty) return;
    final repository = InboxRepository(widget.session.api);
    final failed = <String>[];
    setState(() {
      sending = true;
      sent = 0;
      total = files.length * widget.chats.length;
    });
    for (final chat in widget.chats) {
      for (final item in files) {
        try {
          await repository.send(
            PendingSend({
              'waba_user_id': widget.session.api.wabaId,
              'contact_id': chat['id'],
              'wa_id': chat['wa_id'],
              'message_type': 'text',
              'body': item.caption.text.trim(),
            }, attachment: item.attachment),
          );
        } catch (e) {
          failed.add('${_name(chat)}: $e');
        }
        if (mounted) setState(() => sent++);
      }
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (failed.isEmpty) {
      // Done: back to where the user was, in the chat if it was one.
      navigator.popUntil((route) => route.isFirst);
      if (widget.chats.length == 1) {
        unawaited(
          openPage(
            navigator.context,
            LiveChat(widget.session, widget.chats.single),
          ),
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Sent to ${widget.chats.length} '
            'chat${widget.chats.length == 1 ? '' : 's'}',
          ),
        ),
      );
      return;
    }
    setState(() => sending = false);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          failed.length == total ? 'Not sent' : '${failed.length} not sent',
        ),
        content: SingleChildScrollView(child: Text(failed.join('\n\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checked = items;
    final names = widget.chats.map(_name).join(', ');
    return PopScope(
      canPop: !sending,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preview'),
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: sending ? null : () => Navigator.pop(context),
          ),
        ),
        body: checked == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [for (final item in checked) _item(item)],
              ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: T.surface,
            border: Border(top: BorderSide(color: T.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sending ? 'Sending $sent of $total…' : 'To: $names',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: T.secondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    key: const ValueKey('share-send'),
                    tooltip: 'Send',
                    backgroundColor: T.green,
                    foregroundColor: Colors.white,
                    onPressed: sending || sendable.isEmpty ? null : send,
                    child: sending
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(SharedItem item) {
    final a = item.attachment;
    final name = item.file.name;
    final Widget preview = a == null
        ? ListTile(
            leading: const Icon(Icons.error_outline, color: T.danger),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${item.problem} This file will not be sent.',
              style: const TextStyle(color: T.danger),
            ),
          )
        : switch (a.kind) {
            'image' => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(a.file.path),
                height: 260,
                width: double.infinity,
                fit: BoxFit.cover,
                // A photo the phone cannot draw still goes; it shows a stand-in.
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 260,
                  child: ColoredBox(
                    color: T.incoming,
                    child: Icon(Icons.image_outlined, size: 48, color: T.muted),
                  ),
                ),
              ),
            ),
            'video' => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoFirstFrame(Uri.file(a.file.path)),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 56,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _ => ListTile(
              tileColor: T.incoming,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(
                a.kind == 'audio' ? Icons.audiotrack : Icons.description,
                color: T.brass,
                size: 32,
              ),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${name.split('.').last.toUpperCase()} · ${fileSize(a.size)}',
              ),
            ),
          };
    return Padding(
      key: ValueKey('share-item-$name'),
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          preview,
          if (a != null && a.kind != 'audio')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: item.caption,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add a caption…',
                  isDense: true,
                  filled: true,
                  fillColor: T.incoming,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
