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
    this.hint,
    this.maxLength,
    this.help,
  });
  final String key, label;

  /// The most characters a text input takes.
  final int? maxLength;

  /// A line under the input, such as what the value does.
  final String? help;

  /// text, email, number, password, date, datetime, switch, or `file:kind`.
  final String kind;
  final Object? value;
  final bool required, multiple;
  final int lines;
  final List<Json>? options;

  /// The placeholder inside the input.
  final String? hint;
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

  /// A lone field with a placeholder needs no label: the sheet's title and
  /// the placeholder already say what goes in it.
  bool _labelled(EditField f) => widget.fields.length > 1 || f.hint == null;

  Widget _label(EditField f) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text.rich(
      TextSpan(
        text: f.label,
        children: [
          if (f.required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: T.danger),
            ),
        ],
      ),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: T.secondary,
      ),
    ),
  );

  Widget _input(EditField f) => FieldInput(
    f,
    value: values[f.key],
    enabled: !busy,
    onChanged: (v) => setState(() => values[f.key] = v),
    onError: (e) => setState(() => error = e),
  );

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [if (_labelled(f)) _label(f), _input(f)],
              ),
            ),
          ),
        if (error != null && !isOffline(error))
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

/// One field's input, by its kind: a text box, switch, date picker, choice
/// list, dropdown, or file chooser. The caller keeps the value.
class FieldInput extends StatelessWidget {
  const FieldInput(
    this.field, {
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.onError,
  });
  final EditField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool enabled;
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) {
    final f = field;
    final busy = !enabled;
    if (f.kind.startsWith('file:')) {
      final picked = value;
      return FieldBox(
        text: picked is Attachment
            ? picked.name
            : (picked is String && picked.isNotEmpty ? picked : null),
        hint: f.hint ?? 'Choose a file',
        icon: Icons.attach_file,
        onTap: busy
            ? null
            : () async {
                try {
                  final file = await chooseAttachment(
                    kind: f.kind.substring(5),
                  );
                  if (file != null) onChanged(file);
                } catch (e) {
                  onError?.call('$e');
                }
              },
      );
    }
    if (f.kind == 'switch') {
      final on = '$value' == '1' || value == true;
      return Row(
        children: [
          Expanded(child: Text(on ? 'On' : 'Off')),
          Switch.adaptive(
            value: on,
            onChanged: busy ? null : (v) => onChanged(v ? '1' : '0'),
          ),
        ],
      );
    }
    if (f.kind == 'date' || f.kind == 'datetime') {
      return FormField<Object?>(
        initialValue: value,
        validator: (_) => f.required && '${value ?? ''}'.isEmpty
            ? 'Choose ${f.label.toLowerCase()}'
            : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldBox(
              text: '${value ?? ''}'.isEmpty
                  ? null
                  : shownDate('$value', time: f.kind == 'datetime'),
              hint: f.hint ?? 'Choose a date',
              icon: Icons.calendar_today_outlined,
              error: field.hasError,
              onClear: f.required || '${value ?? ''}'.isEmpty || busy
                  ? null
                  : () {
                      onChanged(null);
                      field.didChange(null);
                    },
              onTap: busy
                  ? null
                  : () async {
                      final picked = await pickDate(
                        context,
                        '${value ?? ''}',
                        time: f.kind == 'datetime',
                      );
                      if (picked != null) {
                        onChanged(picked);
                        field.didChange(picked);
                      }
                    },
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 3),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(fontSize: 12, color: T.danger),
                ),
              ),
          ],
        ),
      );
    }
    if (f.options != null && f.multiple) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in f.options!)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${option['name']}'),
              subtitle: optionDetail(option),
              value: (value is List ? value as List : []).contains(
                option['id'],
              ),
              onChanged: busy
                  ? null
                  : (checked) {
                      final selected = List<dynamic>.from(
                        value is List ? value as List : [],
                      );
                      checked == true
                          ? selected.add(option['id'])
                          : selected.remove(option['id']);
                      onChanged(selected);
                    },
            ),
        ],
      );
    }
    if (f.options != null) {
      return DropdownButtonFormField<Object>(
        initialValue: f.options!.any((o) => o['id'] == value) ? value : null,
        isExpanded: true,
        // The same face and size as the text boxes beside it.
        style: Theme.of(context).textTheme.bodyLarge,
        hint: Text(f.hint ?? 'Choose…'),
        // The closed box shows the name; the open list adds the detail line.
        selectedItemBuilder: (_) => [
          for (final option in f.options!)
            Text('${option['name']}', overflow: TextOverflow.ellipsis),
        ],
        items: [
          for (final option in f.options!)
            DropdownMenuItem(
              value: option['id'],
              child: optionDetail(option) == null
                  ? Text('${option['name']}', overflow: TextOverflow.ellipsis)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${option['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        optionDetail(option)!,
                      ],
                    ),
            ),
        ],
        onChanged: busy ? null : onChanged,
        validator: (v) =>
            f.required && v == null ? 'Choose ${f.label.toLowerCase()}' : null,
      );
    }
    final multiline = f.lines > 1;
    return AppTextFormField(
      initialValue: '${f.value ?? ''}',
      minLines: multiline ? f.lines : null,
      maxLines: multiline ? f.lines + 6 : 1,
      textAlignVertical: multiline ? TextAlignVertical.top : null,
      bordered: true,
      obscureText: f.kind == 'password',
      keyboardType: switch (f.kind) {
        'email' => TextInputType.emailAddress,
        'number' => const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        _ => multiline ? TextInputType.multiline : null,
      },
      maxLength: f.maxLength,
      decoration: InputDecoration(
        hintText: f.hint,
        helperText: f.help,
        helperMaxLines: 3,
        contentPadding: multiline ? const EdgeInsets.all(14) : null,
      ),
      enabled: enabled,
      onChanged: onChanged,
      validator: (v) {
        final text = v?.trim() ?? '';
        if (f.required && text.isEmpty) {
          return 'Enter ${f.label.toLowerCase()}';
        }
        if (text.isEmpty) return null;
        if (f.kind == 'email' &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
          return 'Enter a valid email address';
        }
        if (f.kind == 'number' && num.tryParse(text) == null) {
          return 'Enter a valid number';
        }
        return null;
      },
    );
  }
}

/// A read-only input that opens a picker: same height, outline and
/// placeholder as a text field, so a form reads as one.
class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.text,
    required this.hint,
    required this.icon,
    this.onTap,
    this.onClear,
    this.error = false,
    this.lines = 1,
  });
  final String? text;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap, onClear;
  final bool error;
  final int lines;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: error ? T.danger : T.control),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text ?? hint,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: text == null ? T.muted : T.ink,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.close, size: 18, color: T.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(icon, size: 19, color: T.brass),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "3 Nov 2026", or "3 Nov 2026, 14:30" — from the API's Y-m-d (H:i:s).
String shownDate(String raw, {bool time = false}) {
  final at = DateTime.tryParse(raw);
  if (at == null) return raw;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final day = '${at.day} ${months[at.month - 1]} ${at.year}';
  if (!time) return day;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$day, ${two(at.hour)}:${two(at.minute)}';
}

/// The platform date (and time) picker; the value as the API stores it.
Future<String?> pickDate(
  BuildContext context,
  String current, {
  bool time = false,
}) async {
  final now = DateTime.now();
  final initial = DateTime.tryParse(current) ?? now;
  final day = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(2100),
  );
  if (day == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${day.year}-${two(day.month)}-${two(day.day)}';
  if (!time || !context.mounted) return date;
  final clock = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (clock == null) return null;
  return '$date ${two(clock.hour)}:${two(clock.minute)}:00';
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
              if (error != null && !isOffline(error))
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
                        subtitle: optionDetail(o),
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

/// An option's second line, such as an agent's "Manager - Sales"; null when
/// the option has none.
Widget? optionDetail(Map option) {
  final detail = '${option['detail'] ?? ''}';
  if (detail.isEmpty) return null;
  return Text(
    detail,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 12.5, color: T.muted),
  );
}
