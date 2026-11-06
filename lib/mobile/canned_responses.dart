import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart' show SheetTitle;

/// A canned response's words for this chat, as the web ticket inbox fills
/// them in: the customer's name, the ticket's number, the agent's name and
/// the ticket's department. A token without a value is left empty; one the
/// web does not know is left as it is.
String fillCannedResponse(
  String body, {
  String customerName = '',
  String ticketNumber = '',
  String agentName = '',
  String department = '',
}) => body
    .replaceAll('{{customer_name}}', customerName)
    .replaceAll('{{ticket_number}}', ticketNumber)
    .replaceAll('{{agent_name}}', agentName)
    .replaceAll('{{department}}', department)
    // What the app filled before the web's tokens; kept for old replies.
    .replaceAll('{{name}}', customerName);

/// The number's canned responses, as the web ticket composer's picker shows
/// them: a General tab for those in no category, a tab per category with its
/// count, each reply's title, shortcut and first line. Typing searches every
/// reply (title, shortcut or text) through the server. Closes with the text.
class CannedResponseSheet extends StatefulWidget {
  const CannedResponseSheet({
    super.key,
    required this.session,
    required this.data,
    this.query = '',
  });
  final MobileSession session;

  /// `inbox/canned-responses`: `categories` with their `responses`, and
  /// `uncategorised`.
  final Json data;

  /// What was typed in the composer, such as "/", searched at once.
  final String query;
  @override
  State<CannedResponseSheet> createState() => _CannedResponseSheetState();
}

class _CannedResponseSheetState extends State<CannedResponseSheet> {
  late final search = TextEditingController(text: widget.query);
  late final tabs = <(String, List<Json>)>[
    if (rows(widget.data['uncategorised']).isNotEmpty)
      ('General', rows(widget.data['uncategorised'])),
    for (final c in rows(widget.data['categories']))
      ('${c['name'] ?? ''}', rows(c['responses'])),
  ];
  var tab = 0;
  Timer? debounce;
  List<Json>? results;
  var serial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.query.trim().isNotEmpty) searched(widget.query, now: true);
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void searched(String text, {bool now = false}) {
    debounce?.cancel();
    final request = ++serial;
    if (text.trim().isEmpty) {
      setState(() => results = null);
      return;
    }
    debounce = Timer(Duration(milliseconds: now ? 0 : 250), () async {
      try {
        final r = await widget.session.api.get(
          'inbox/canned-responses/search',
          query: {'q': text},
        );
        if (mounted && request == serial) {
          setState(() => results = rows(r['data']));
        }
      } catch (_) {
        if (mounted && request == serial) setState(() => results = []);
      }
    });
  }

  Widget reply(Json r) {
    final shortcut = '${r['shortcut'] ?? ''}';
    return ListTile(
      key: ValueKey('canned-${r['id']}'),
      title: Row(
        children: [
          Flexible(
            child: Text('${r['title'] ?? ''}', overflow: TextOverflow.ellipsis),
          ),
          if (shortcut.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: T.greenWash,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                shortcut,
                style: const TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 11.5,
                  color: T.green,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${r['body'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.pop(context, '${r['body'] ?? ''}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = search.text.trim().isNotEmpty;
    final found = results;
    final list = searching
        ? found ?? const <Json>[]
        : tabs.isEmpty
        ? const <Json>[]
        : tabs[tab].$2;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitle('Quick replies'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBox(
                  key: const ValueKey('canned-search'),
                  controller: search,
                  hint: 'Search or type a /shortcut',
                  dense: true,
                  onChanged: (v) {
                    setState(() {});
                    searched(v);
                  },
                ),
              ),
              if (!searching && tabs.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('canned-tab-$i'),
                            label: Text('${tabs[i].$1} (${tabs[i].$2.length})'),
                            selected: tab == i,
                            onSelected: (_) => setState(() => tab = i),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: searching && found == null
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                    ? Center(
                        child: Text(
                          searching
                              ? 'No results found'
                              : 'No quick replies available',
                          style: const TextStyle(color: T.muted),
                        ),
                      )
                    : ListView(children: [for (final r in list) reply(r)]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
