import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'media.dart';

class EditField {
  const EditField(
    this.key,
    this.label, {
    this.value,
    this.required = false,
    this.options,
    this.multiple = false,
    this.lines = 1,
    this.kind = 'text',
  });
  final String key, label, kind;
  final Object? value;
  final bool required, multiple;
  final int lines;
  final List<Json>? options;
}

/// Values remain editable after a rejected mutation. Closing never commits changes.
class ActionEditor extends StatefulWidget {
  const ActionEditor({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.submit = 'Save',
    this.sheet = false,
  });
  final String title, submit;

  /// Drawn in a bottom sheet over the screen rather than as its own page.
  final bool sheet;
  final List<EditField> fields;
  final Future<void> Function(Json) save;
  @override
  State<ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<ActionEditor> {
  final form = GlobalKey<FormState>();
  late final values = <String, dynamic>{
    for (final f in widget.fields) f.key: f.value,
  };
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    if (!widget.sheet) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: _form(),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(widget.title),
          Flexible(child: _form(shrink: true)),
        ],
      ),
    );
  }

  Widget _form({bool shrink = false}) => Form(
    key: form,
    child: ListView(
      shrinkWrap: shrink,
      padding: EdgeInsets.fromLTRB(20, shrink ? 4 : 20, 20, 20),
      children: [
        for (final f in widget.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: AbsorbPointer(
              absorbing: busy,
              child: f.kind.startsWith('file:')
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label),
                        AppButton.outlined(
                          onPressed: busy
                              ? null
                              : () async {
                                  try {
                                    final picked = await chooseAttachment(
                                      kind: f.kind.substring(5),
                                    );
                                    if (mounted && picked != null) {
                                      setState(() => values[f.key] = picked);
                                    }
                                  } catch (e) {
                                    if (mounted) setState(() => error = '$e');
                                  }
                                },
                          child: Text(
                            values[f.key] is Attachment
                                ? (values[f.key] as Attachment).name
                                : 'Choose file',
                          ),
                        ),
                      ],
                    )
                  : f.options != null
                  ? f.multiple
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.label),
                              for (final option in f.options!)
                                CheckboxListTile(
                                  title: Text('${option['name']}'),
                                  value:
                                      (values[f.key] is List
                                              ? values[f.key] as List
                                              : [])
                                          .contains(option['id']),
                                  onChanged: busy
                                      ? null
                                      : (checked) {
                                          final selected = List<dynamic>.from(
                                            values[f.key] is List
                                                ? values[f.key] as List
                                                : [],
                                          );
                                          checked == true
                                              ? selected.add(option['id'])
                                              : selected.remove(option['id']);
                                          setState(
                                            () => values[f.key] = selected,
                                          );
                                        },
                                ),
                            ],
                          )
                        : DropdownButtonFormField<Object>(
                            initialValue:
                                f.options!.any((o) => o['id'] == values[f.key])
                                ? values[f.key]
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: [
                              for (final option in f.options!)
                                DropdownMenuItem(
                                  value: option['id'],
                                  child: Text(
                                    '${option['name']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: busy ? null : (v) => values[f.key] = v,
                            validator: (v) => f.required && v == null
                                ? 'Choose ${f.label.toLowerCase()}'
                                : null,
                          )
                  : AppTextFormField(
                      initialValue: '${f.value ?? ''}',
                      maxLines: f.lines,
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText: f.kind == 'date' ? 'YYYY-MM-DD' : null,
                      ),
                      onChanged: (v) => values[f.key] = v,
                      validator: (v) {
                        if (f.required && (v == null || v.trim().isEmpty)) {
                          return 'Enter ${f.label.toLowerCase()}';
                        }
                        if (f.kind == 'date' &&
                            v != null &&
                            v.isNotEmpty &&
                            DateTime.tryParse(v) == null) {
                          return 'Enter a valid date';
                        }
                        return null;
                      },
                    ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: const TextStyle(color: T.danger)),
          ),
        AppButton.filled(
          onPressed: busy
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  for (final f in widget.fields) {
                    if (f.required &&
                        (values[f.key] == null ||
                            (values[f.key] is List &&
                                (values[f.key] as List).isEmpty))) {
                      setState(() => error = 'Complete ${f.label}.');
                      return;
                    }
                  }
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.save(values);
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Saving…' : widget.submit),
        ),
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

/// The title row of an editing sheet.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null)
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: T.muted)),
      ],
    ),
  );
}

/// Edits shown over the screen instead of on a page of their own. A single
/// choice (assignee, status, priority, tag) saves on tap, as a dropdown does;
/// several choices save with a button; text opens the form in the sheet.
/// True when the change was saved.
Future<bool> showEditorSheet(
  BuildContext context, {
  required String title,
  required List<EditField> fields,
  required Future<void> Function(Json values) save,
  String submit = 'Save',
}) async {
  final only = fields.length == 1 ? fields.single : null;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => only?.options != null
        ? ChoiceSheet(title: title, field: only!, save: save)
        : ActionEditor(
            title: title,
            fields: fields,
            save: save,
            submit: submit,
            sheet: true,
          ),
  );
  return saved == true;
}

/// One field's options as a list: tap to choose (and save), or tick several
/// and save. Long lists can be searched.
class ChoiceSheet extends StatefulWidget {
  const ChoiceSheet({
    super.key,
    required this.title,
    required this.field,
    required this.save,
  });
  final String title;
  final EditField field;
  final Future<void> Function(Json values) save;
  @override
  State<ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<ChoiceSheet> {
  late final picked = <Object?>{
    if (widget.field.multiple && widget.field.value is List)
      ...widget.field.value as List,
  };
  Object? saving;
  String query = '';
  String? error;

  Future<void> commit(Object? value) async {
    if (saving != null) return;
    setState(() {
      saving = value ?? 'all';
      error = null;
    });
    try {
      await widget.save({widget.field.key: value});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = null;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final options = f.options!;
    final q = query.trim().toLowerCase();
    final shown = [
      for (final o in options)
        if (q.isEmpty || '${o['name']}'.toLowerCase().contains(q)) o,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle(widget.title),
              if (options.length > 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBox(
                    hint: 'Search',
                    dense: true,
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(error!, style: const TextStyle(color: T.danger)),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in shown)
                      ListTile(
                        key: ValueKey('choice-${o['id']}'),
                        title: Text('${o['name']}'),
                        enabled: saving == null,
                        trailing: saving == o['id']
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : f.multiple
                            ? Checkbox(
                                value: picked.contains(o['id']),
                                onChanged: saving == null
                                    ? (_) => setState(
                                        () => picked.contains(o['id'])
                                            ? picked.remove(o['id'])
                                            : picked.add(o['id']),
                                      )
                                    : null,
                              )
                            : f.value == o['id']
                            ? const Icon(Icons.check, color: T.bronze)
                            : null,
                        onTap: saving != null
                            ? null
                            : f.multiple
                            ? () => setState(
                                () => picked.contains(o['id'])
                                    ? picked.remove(o['id'])
                                    : picked.add(o['id']),
                              )
                            // Choosing the current value changes nothing.
                            : f.value == o['id']
                            ? () => Navigator.pop(context, false)
                            : () => commit(o['id']),
                      ),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nothing matches.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: T.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (f.multiple)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: AppButton.filled(
                    onPressed: saving != null || (f.required && picked.isEmpty)
                        ? null
                        : () => commit(picked.toList()),
                    child: Text(saving != null ? 'Saving…' : 'Save'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
