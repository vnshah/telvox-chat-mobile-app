import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'editors.dart' show confirmAction;
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

  Future<void> add() => open(null);

  /// Opens [note], or a blank page for a new one, in the editor.
  Future<void> open(Json? note) => openPage(
    context,
    NoteEditorPage(
      api,
      note: note,
      known: {for (final n in notes) n['id']},
      onSaved: (saved) {
        if (mounted) show(saved);
      },
      onDeleted: (gone) {
        if (mounted) show([...notes.where((n) => n['id'] != gone['id'])]);
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

/// A note on its own screen, as the phone's Notes app keeps one: the
/// keyboard is up at once, Undo and Redo sit at the top, and Done saves.
/// Going back with unsaved changes asks whether to save or discard them.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage(
    this.notes, {
    super.key,
    this.note,
    this.known = const {},
    required this.onSaved,
    this.onDeleted,
  });
  final ContactNotes notes;

  /// The note to edit; null starts a new one.
  final Json? note;

  /// Ids already listed, so a new note is told apart in the saved list.
  final Set<Object?> known;

  /// The contact's notes after each save.
  final ValueChanged<List<Json>> onSaved;
  final ValueChanged<Json>? onDeleted;
  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

enum _Saved { clean, saving, saved, failed }

class _NoteEditorPageState extends State<NoteEditorPage> {
  late Json? note = widget.note;
  late final text = TextEditingController(
    text: readableText(widget.note?['content']),
  );
  final undo = UndoHistoryController();
  final focus = FocusNode();
  late String stored = text.text.trim();
  var state = _Saved.clean;
  var leaving = false;

  /// Saves run one after another, so a new note is created only once.
  Future<bool> queue = Future.value(true);

  @override
  void initState() {
    super.initState();
    text.addListener(changed);
  }

  @override
  void dispose() {
    text.dispose();
    undo.dispose();
    focus.dispose();
    super.dispose();
  }

  bool get dirty => text.text.trim() != stored;

  /// Whether Done was last drawn as enabled.
  var shownDirty = false;

  void changed() {
    final stale = dirty && state != _Saved.clean && state != _Saved.saving;
    // Rebuild only when Done turns on or off, not on every keystroke.
    if (!stale && dirty == shownDirty) return;
    setState(() {
      shownDirty = dirty;
      if (stale) state = _Saved.clean;
    });
  }

  /// True once the page's text is on the server, or there is nothing to keep.
  Future<bool> save() => queue = queue.then((_) => write());

  Future<bool> write() async {
    final draft = text.text.trim();
    if (draft == stored) return true;
    // A cleared note is not saved over the old one: Delete removes a note.
    if (draft.isEmpty) {
      if (mounted) mobileNotice(context, 'A note cannot be empty.');
      return false;
    }
    if (mounted) setState(() => state = _Saved.saving);
    try {
      final saved = await widget.notes.save(draft, existing: note);
      final id = note?['id'];
      note = saved.firstWhere(
        (n) => id != null ? n['id'] == id : !widget.known.contains(n['id']),
        orElse: () => saved.isEmpty ? {'content': draft} : saved.first,
      );
      stored = draft;
      widget.onSaved(saved);
      if (mounted) {
        setState(() {
          shownDirty = dirty;
          state = dirty ? _Saved.clean : _Saved.saved;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => state = _Saved.failed);
        mobileNotice(context, e);
      }
      return false;
    }
  }

  Future<void> done() async {
    focus.unfocus();
    await save();
  }

  /// Back with unsaved changes asks first; nothing is saved unless chosen.
  Future<void> leave() async {
    if (leaving) return;
    leaving = true;
    try {
      await queue;
      if (!mounted) return;
      if (dirty) {
        focus.unfocus();
        final choice = await askToSave(context, isNew: note == null);
        if (!mounted || choice == null) return;
        if (choice == LeaveChoice.save && !await save()) return;
      }
      if (mounted) Navigator.pop(context);
    } finally {
      leaving = false;
    }
  }

  Future<void> delete() async {
    final existing = note;
    if (existing == null || existing['id'] == null) return;
    if (!await confirmAction(context, 'Delete note', 'Delete this note?')) {
      return;
    }
    try {
      await queue;
      await widget.notes.delete(existing);
      widget.onDeleted?.call(existing);
      stored = text.text.trim();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mobileNotice(context, e);
    }
  }

  String get status => switch (state) {
    _Saved.saving => 'Saving…',
    _Saved.saved => 'Saved',
    _Saved.failed => 'Not saved',
    _Saved.clean => note == null ? 'New note' : noteMeta(note!),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: platformAppBar(
        context,
        title: const Text(''),
        actions: [
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: undo,
            builder: (context, value, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  tooltip: 'Undo',
                  onPressed: value.canUndo ? undo.undo : null,
                  icon: const AppIcon(Icons.undo_rounded),
                ),
                AppIconButton(
                  tooltip: 'Redo',
                  onPressed: value.canRedo ? undo.redo : null,
                  icon: const AppIcon(Icons.redo_rounded),
                ),
              ],
            ),
          ),
          if (note?['id'] != null)
            AppIconButton(
              tooltip: 'Delete note',
              onPressed: delete,
              icon: const AppIcon(Icons.delete_outline_rounded),
            ),
          AppIconButton(
            tooltip: 'Done',
            // Only when there is something to save.
            onPressed: dirty && state != _Saved.saving ? done : null,
            icon: const AppIcon(Icons.check_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                status,
                key: const ValueKey('note-status'),
                style: TextStyle(
                  fontSize: 13,
                  color: state == _Saved.failed ? T.danger : T.brass,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('note-editor'),
                  controller: text,
                  undoController: undo,
                  focusNode: focus,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    color: T.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Write a note for your team. Customers never see it.',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
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

enum LeaveChoice { save, discard }

/// Asked when leaving unsaved changes: Save, Discard, or null to keep
/// editing. [body] says what changed; by default, a note.
Future<LeaveChoice?> askToSave(
  BuildContext context, {
  bool isNew = false,
  String? body,
}) {
  const title = 'Save changes?';
  body ??= isNew
      ? 'This note has not been saved yet.'
      : 'You changed this note. Save the changes before leaving?';
  if (isCupertino(context)) {
    return showCupertinoDialog<LeaveChoice>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text(title),
        content: Text(body!),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('leave-save'),
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialog, LeaveChoice.save),
            child: const Text('Save'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('leave-discard'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialog, LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('leave-keep'),
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
  }
  return showDialog<LeaveChoice>(
    context: context,
    builder: (dialog) => Dialog(
      backgroundColor: T.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.edit_note_rounded, color: T.brass, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(dialog).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: T.muted,
              ),
            ),
            const SizedBox(height: 22),
            AppButton.filled(
              key: const ValueKey('leave-save'),
              onPressed: () => Navigator.pop(dialog, LeaveChoice.save),
              child: const Text('Save'),
            ),
            const SizedBox(height: 8),
            AppButton.outlined(
              key: const ValueKey('leave-discard'),
              onPressed: () => Navigator.pop(dialog, LeaveChoice.discard),
              style: OutlinedButton.styleFrom(
                foregroundColor: T.danger,
                side: const BorderSide(color: T.danger),
              ),
              child: const Text('Discard'),
            ),
            const SizedBox(height: 4),
            AppButton.text(
              key: const ValueKey('leave-keep'),
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Keep editing'),
            ),
          ],
        ),
      ),
    ),
  );
}
