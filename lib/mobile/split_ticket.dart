import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';

/// Copies chosen messages of a closed ticket to a new ticket, as the web's
/// Split Ticket does: a subject, and the department, status, priority and
/// assignee, each "Same as original" or another. They start on the ticket
/// settings' defaults (the agent as assignee), as on the web. Answers with
/// the new ticket.
class SplitTicketPage extends StatefulWidget {
  const SplitTicketPage(
    this.session,
    this.ticketId,
    this.messageIds, {
    super.key,
  });
  final MobileSession session;
  final int ticketId;
  final List<int> messageIds;
  @override
  State<SplitTicketPage> createState() => _SplitTicketPageState();
}

class _SplitTicketPageState extends State<SplitTicketPage> {
  Json? meta;
  final subject = TextEditingController();

  /// Picked ids by field; null is "Same as original".
  final picked = <String, int?>{};
  bool saving = false;
  String? error;

  static const fields = [
    ('department_id', 'Department', 'departments'),
    ('status_id', 'Status', 'statuses'),
    ('priority_id', 'Priority', 'priorities'),
    ('assign_user_id', 'Assign To', 'users'),
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    subject.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.session.api.get('inbox/ticket_create_metadata');
      final data = object(r['data']);
      final defaults = object(data['defaults']);
      if (!mounted) return;
      setState(() {
        meta = data;
        for (final (key, _, _) in fields) {
          picked[key] = number(defaults[key]);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Failed to load split ticket options');
      }
    }
  }

  Future<void> split() async {
    final text = subject.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Subject is required.');
      return;
    }
    if (widget.messageIds.isEmpty) {
      setState(() => error = 'No messages selected.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final r = await widget.session.api.post(
        'inbox/tickets/${widget.ticketId}/split',
        {
          'message_ids': widget.messageIds,
          'subject': text,
          for (final (key, _, _) in fields) key: picked[key],
        },
      );
      if (mounted) {
        Navigator.pop(context, object(object(r['data'])['new_ticket']));
      }
    } catch (e) {
      final said = '$e'.trim();
      if (mounted) {
        setState(() => error = said.isEmpty ? 'Failed to split ticket.' : said);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = meta;
    final defaults = object(data?['defaults']);
    final n = widget.messageIds.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Split ticket')),
      body: data == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!, style: const TextStyle(color: T.danger)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '$n message${n == 1 ? '' : 's'} will be copied to a new ticket',
                  style: const TextStyle(color: T.secondary),
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  key: const ValueKey('split-subject'),
                  controller: subject,
                  bordered: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Subject *',
                    hintText: 'New ticket subject',
                  ),
                ),
                for (final (key, label, list) in fields)
                  if (rows(data[list]).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey('split-$key'),
                        initialValue:
                            rows(data[list])
                                .any((o) => number(o['id']) == picked[key])
                            ? picked[key]
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              (key == 'status_id' || key == 'priority_id') &&
                                  defaults[key] != null
                              ? '$label (default from settings)'
                              : label,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Same as original'),
                          ),
                          for (final o in rows(data[list]))
                            if (number(o['id']) case final int id)
                              DropdownMenuItem<int?>(
                                value: id,
                                child: Text(
                                  '${o['name'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        ],
                        onChanged: (v) => setState(() => picked[key] = v),
                      ),
                    ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      error!,
                      style: const TextStyle(color: T.danger),
                    ),
                  ),
                const SizedBox(height: 20),
                AppButton.filled(
                  key: const ValueKey('split-submit'),
                  onPressed: saving || subject.text.trim().isEmpty
                      ? null
                      : split,
                  child: Text(saving ? 'Splitting…' : 'Split ticket'),
                ),
              ],
            ),
    );
  }
}
