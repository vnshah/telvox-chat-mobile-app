import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart';
import 'message_content.dart' show readableText;
import 'models.dart' show MobileClock;
import 'screens.dart' show mobileNotice, openPage;

/// A contact's internal notes, saved and listed by the inbox's notes API.
/// Saving answers with the contact's whole list, so the screens show exactly
/// what the server holds without a second request.
class ContactNotes {
  ContactNotes(this.session, this.contactId);
  final MobileSession session;
  final int contactId;

  Future<List<Json>> list() async => rows(
    (await session.api.get(
      'inbox/notes',
      query: {'contact_id': contactId},
    ))['data'],
  );

  /// Adds a note, or edits [existing]; the saved list, newest first.
  Future<List<Json>> save(String text, {Json? existing}) async => rows(
    (await session.api.post('inbox/notes', {
      'contact_id': contactId,
      'note': text,
      if (existing != null) 'note_id': existing['id'],
    }))['data'],
  );

  Future<void> delete(Json note) =>
      session.api.request('inbox/notes/${note['id']}', method: 'DELETE');
}

/// The note sheet: a tall box whose text and placeholder start at the top.
/// The saved list, or null when it was closed without saving.
Future<List<Json>?> editNote(
  BuildContext context,
  ContactNotes notes, {
  Json? existing,
}) async {
  List<Json>? saved;
  await showEditorSheet(
    context,
    title: existing == null ? 'Add note' : 'Edit note',
    fields: [
      EditField(
        'note',
        'Note',
        value: existing?['content'],
        required: true,
        lines: 6,
        hint: 'Write a note for your team. Customers never see it.',
      ),
    ],
    save: (v) async =>
        saved = await notes.save('${v['note']}'.trim(), existing: existing),
  );
  return saved;
}

String noteMeta(Json note) => [
  readableText(object(note['user'])['name']),
  const MobileClock().listTime(note['created_at']),
].where((p) => p.isNotEmpty).join(' · ');

/// Notes as Media, Documents and Links are: their own screen, a short preview
/// per note, and the whole note one tap away.
class NotesPage extends StatefulWidget {
  const NotesPage(
    this.session,
    this.contactId, {
    super.key,
    this.initial = const [],
    this.onChanged,
  });
  final MobileSession session;
  final int contactId;

  /// The notes the caller already shows, drawn while a fresh copy loads.
  final List<Json> initial;

  /// Each saved list, so the page behind updates its count in place.
  final ValueChanged<List<Json>>? onChanged;
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  late final api = ContactNotes(widget.session, widget.contactId);
  late List<Json> notes = widget.initial;
  bool loaded = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await api.list();
      if (mounted) {
        setState(() {
          notes = next;
          loaded = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void show(List<Json> next) {
    setState(() => notes = next);
    widget.onChanged?.call(next);
  }

  Future<void> add() async {
    final saved = await editNote(context, api);
    if (saved != null && mounted) show(saved);
  }

  Future<void> open(Json note) => openPage(
    context,
    NoteDetailPage(
      note,
      onEdit: () async {
        final saved = await editNote(context, api, existing: note);
        if (saved == null || !mounted) return null;
        show(saved);
        return saved.firstWhere(
          (n) => n['id'] == note['id'],
          orElse: () => note,
        );
      },
      onDelete: () async {
        await api.delete(note);
        if (mounted) show([...notes.where((n) => n['id'] != note['id'])]);
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: platformAppBar(
      context,
      title: const Text('Notes'),
      actions: [
        AppIconButton(
          tooltip: 'Add note',
          onPressed: add,
          icon: const AppIcon(Icons.add),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (notes.isEmpty && !loaded && error == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (notes.isEmpty && error != null)
            EmptyView(
              title: 'Notes did not load',
              description: error!,
              icon: Icons.cloud_off_outlined,
              action: 'Try again',
              onAction: load,
            )
          else if (notes.isEmpty)
            EmptyView(
              title: 'No notes yet',
              description: 'Notes are for your team; customers never see them.',
              icon: Icons.sticky_note_2_outlined,
              action: 'Add note',
              onAction: add,
            ),
          for (final n in notes)
            DecoratedBox(
              key: ValueKey('note-${n['id']}'),
              // Hairlines between notes, as between inbox rows.
              decoration: BoxDecoration(
                border: n == notes.first
                    ? null
                    : const Border(top: BorderSide(color: T.hairline)),
              ),
              child: InkWell(
                onTap: () => open(n),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              readableText(n['content']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                color: T.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              noteMeta(n),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: T.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 6, top: 2),
                        child: Icon(Icons.chevron_right, color: T.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One note in full, with Edit and Delete.
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage(
    this.note, {
    super.key,
    required this.onEdit,
    required this.onDelete,
  });
  final Json note;

  /// The note as saved, or null when the edit was dropped.
  final Future<Json?> Function() onEdit;
  final Future<void> Function() onDelete;
  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late Json note = widget.note;
  bool deleting = false;

  Future<void> edit() async {
    final saved = await widget.onEdit();
    if (saved != null && mounted) setState(() => note = saved);
  }

  Future<void> delete() async {
    if (!await confirmAction(context, 'Delete note', 'Delete this note?')) {
      return;
    }
    setState(() => deleting = true);
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => deleting = false);
        mobileNotice(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: platformAppBar(
      context,
      title: const Text('Note'),
      actions: [
        AppIconButton(
          tooltip: 'Edit note',
          onPressed: deleting ? null : edit,
          icon: const AppIcon(Icons.edit_outlined),
        ),
        AppIconButton(
          tooltip: 'Delete note',
          onPressed: deleting ? null : delete,
          icon: const AppIcon(Icons.delete_outline_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          noteMeta(note),
          style: const TextStyle(fontSize: 13, color: T.brass),
        ),
        const SizedBox(height: 12),
        SelectableText(
          readableText(note['content']),
          style: const TextStyle(fontSize: 16, height: 1.5, color: T.ink),
        ),
      ],
    ),
  );
}
