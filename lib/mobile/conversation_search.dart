import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'offline_bar.dart' show OfflineNote;
import 'message_content.dart' show readableText;
import 'models.dart';

/// The fewest letters a search sends (config('inbox.message_search.min_length')).
const searchMinLength = 2;

/// Searches the open conversation, as the web inbox's search panel does: the
/// messages whose shown text contains the words, newest first, with the words
/// marked. Choosing one returns it, and the chat jumps to it.
///
/// Typing waits 300 ms before asking, and an answer for older words is
/// dropped, so a fast typist sends one request per pause and never sees a
/// stale page land last.
class ConversationSearchPage extends StatefulWidget {
  const ConversationSearchPage(
    this.session, {
    super.key,
    required this.contactId,
    required this.contactName,
  });
  final MobileSession session;
  final int contactId;
  final String contactName;
  @override
  State<ConversationSearchPage> createState() => _ConversationSearchPageState();
}

class _ConversationSearchPageState extends State<ConversationSearchPage> {
  final query = TextEditingController();
  Timer? debounce;
  List<Json> results = [];
  int? nextBeforeId;
  bool loading = false, loadingMore = false;
  String? error;

  /// Bumped per request; an answer for an older one is ignored.
  int asked = 0;

  String get words => query.text.trim();
  bool get searchable => words.length >= searchMinLength;

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void changed(String _) {
    debounce?.cancel();
    asked++;
    setState(() {
      error = null;
      if (!searchable) {
        results = [];
        nextBeforeId = null;
        loading = false;
      } else {
        loading = true;
      }
    });
    if (searchable) {
      debounce = Timer(const Duration(milliseconds: 300), search);
    }
  }

  Future<Json> ask({int? beforeId}) => widget.session.api.post(
    'inbox/messages/search',
    {'contact_id': widget.contactId, 'q': words, 'before_id': ?beforeId},
  );

  /// The server's reason, or a plain one for a server without search.
  String reason(Object e) =>
      e is ApiFailure && e.httpStatus == 404 && e.message != 'Contact not found'
      ? 'Search is not available on this server yet.'
      : '$e';

  Future<void> search() async {
    final ticket = ++asked;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await ask();
      if (!mounted || ticket != asked) return;
      final meta = object(r['meta']);
      setState(() {
        results = rows(r['data']);
        nextBeforeId = meta['has_more'] == true
            ? number(meta['next_before_id'])
            : null;
      });
    } catch (e) {
      if (mounted && ticket == asked) setState(() => error = reason(e));
    } finally {
      if (mounted && ticket == asked) setState(() => loading = false);
    }
  }

  Future<void> more() async {
    if (nextBeforeId == null || loadingMore) return;
    final ticket = asked;
    setState(() => loadingMore = true);
    try {
      final r = await ask(beforeId: nextBeforeId);
      if (!mounted || ticket != asked) return;
      final meta = object(r['meta']);
      setState(() {
        results = [...results, ...rows(r['data'])];
        nextBeforeId = meta['has_more'] == true
            ? number(meta['next_before_id'])
            : null;
      });
    } catch (e) {
      if (mounted && ticket == asked) setState(() => error = reason(e));
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Widget body() {
    if (!searchable) {
      return const _Note(
        'Type at least $searchMinLength letters to search this chat.',
      );
    }
    if (isOffline(error)) return OfflineNote(search);
    if (error != null) {
      return EmptyView(
        title: 'Search did not finish',
        description: error!,
        icon: Icons.search_off,
        action: 'Try again',
        onAction: search,
      );
    }
    if (results.isEmpty) {
      return loading
          ? const SizedBox.shrink()
          : _Note('No messages in this chat match “$words”.');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length + (nextBeforeId == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1, color: T.hairline),
      itemBuilder: (context, i) {
        if (i == results.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: AppButton.text(
                onPressed: loadingMore ? null : more,
                child: Text(loadingMore ? 'Loading…' : 'Show older matches'),
              ),
            ),
          );
        }
        final r = results[i];
        final author = number(r['type']) == 2
            ? widget.contactName
            : (readableText(r['sender_name']).isEmpty
                  ? 'You'
                  : readableText(r['sender_name']));
        const clock = MobileClock();
        return InkWell(
          key: ValueKey('search-result-${r['id']}'),
          onTap: () => Navigator.pop(context, r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: T.secondary,
                        ),
                      ),
                    ),
                    Text(
                      '${clock.dayLabel(r['created_at'])}, '
                      '${clock.time(r['created_at'])}',
                      style: const TextStyle(fontSize: 12, color: T.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  marked(readableText(r['text']), words),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: T.ink,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: TextField(
        controller: query,
        autofocus: true,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onChanged: changed,
        onSubmitted: (_) {
          if (searchable) {
            debounce?.cancel();
            search();
          }
        },
        decoration: const InputDecoration(
          hintText: 'Search messages in this chat',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          counterText: '',
        ),
      ),
      actions: [
        if (query.text.isNotEmpty)
          AppIconButton(
            tooltip: 'Clear search',
            onPressed: () {
              query.clear();
              changed('');
            },
            icon: const Icon(Icons.close),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: loading
            ? const LinearProgressIndicator(minHeight: 2)
            : const SizedBox(height: 2),
      ),
    ),
    body: body(),
  );
}

/// [text] with each occurrence of [words] marked, ignoring case.
TextSpan marked(String text, String words) {
  if (words.isEmpty) return TextSpan(text: text);
  final lower = text.toLowerCase(), needle = words.toLowerCase();
  final spans = <TextSpan>[];
  var at = 0;
  while (true) {
    final found = lower.indexOf(needle, at);
    if (found < 0) break;
    if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
    spans.add(
      TextSpan(
        text: text.substring(found, found + needle.length),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          backgroundColor: T.outgoing,
        ),
      ),
    );
    at = found + needle.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, color: T.muted),
    ),
  );
}
