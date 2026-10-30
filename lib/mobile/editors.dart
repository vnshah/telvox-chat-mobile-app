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
  });
  final String title, submit;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
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
                                  f.options!.any(
                                    (o) => o['id'] == values[f.key],
                                  )
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
                      if (context.mounted) Navigator.pop(context, true);
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
