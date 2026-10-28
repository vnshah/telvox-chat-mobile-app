import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class T {
  static const paper = Color(0xFFF0ECE5);
  static const wash = Color(0xFFF7F4EE);
  static const ink = Color(0xFF221C16);
  static const secondary = Color(0xFF4F4A44);
  static const muted = Color(0xFF7A7268);
  static const green = Color(0xFF1E7A4F);
  static const brass = Color(0xFF8A7355);
  static const edge = Color(0xFFE3DED4);
  static const control = Color(0xFFD5CFC4);
  static const selected = Color(0xFFE4EEE4);
  static const outgoing = Color(0xFFD5E8D6);
  static const firm = Color(0xFF1C1B1A);
  static const danger = Color(0xFFC2335E);
  static const blue = Color(0xFF1B9BD8);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Geist',
    fontFamilyFallback: const ['Noto Color Emoji'],
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: green).copyWith(
      primary: green,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      outline: control,
      error: danger,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.7,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -.5,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Geist',
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: const DividerThemeData(color: edge, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: control),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: control),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 46),
        side: const BorderSide(color: control),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: green),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: brass,
        minimumSize: const Size(44, 44),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: wash,
      selectedColor: selected,
      side: const BorderSide(color: edge),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        color: T.ink,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? green : paper,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ink,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

TextStyle mono({
  double size = 12,
  Color color = T.muted,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'GeistMono',
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: .1,
);

void notice(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/brand/mark.png',
        width: large ? 42 : 30,
        height: large ? 42 : 30,
      ),
      const SizedBox(width: 10),
      Text(
        'telvox',
        style: mono(
          size: large ? 24 : 19,
          color: T.ink,
          weight: FontWeight.w500,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text(
          '|',
          style: mono(size: large ? 23 : 18, color: T.control),
        ),
      ),
      Text(
        'chat',
        style: mono(size: large ? 24 : 19, color: T.green),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: mono(size: 10, color: T.brass).copyWith(letterSpacing: 1.5),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(
    this.name, {
    super.key,
    this.size = 46,
    this.color = T.selected,
    this.online = false,
  });
  final String name;
  final double size;
  final Color color;
  final bool online;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: T.edge),
          ),
          child: Text(
            name
                .trim()
                .split(' ')
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s[0])
                .join()
                .toUpperCase(),
            style: TextStyle(
              fontSize: size * .28,
              fontWeight: FontWeight.w600,
              color: T.secondary,
            ),
          ),
        ),
        if (online)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: T.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color = T.green,
    this.fill = T.selected,
    this.dot = false,
  });
  final String text;
  final Color color;
  final Color fill;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 5),
        ],
        Text(text, style: mono(size: 10, color: color)),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: T.edge),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(child: Eyebrow(title)),
        if (action != null)
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Text(
                action!,
                style: const TextStyle(
                  fontSize: 12,
                  color: T.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.bottom,
    this.scroll = true,
    this.fab,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? fab;
  final bool scroll;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    floatingActionButton: fab,
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: T.edge)),
              ),
              child: bottom,
            ),
          ),
    body: SafeArea(
      top: false,
      child: scroll
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (subtitle != null) ...[
                    Text(
                      subtitle!,
                      style: const TextStyle(color: T.muted, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                  ],
                  child,
                ],
              ),
            )
          : child,
    ),
  );
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    this.hint = 'Search',
    this.onChanged,
    this.controller,
  });
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, size: 21, color: T.muted),
      filled: true,
      fillColor: T.wash,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class MenuRow extends StatelessWidget {
  const MenuRow(
    this.title,
    this.icon, {
    super.key,
    this.subtitle,
    this.route,
    this.onTap,
    this.trailing,
    this.danger = false,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  final String? route;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    leading: Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFF6E0E7) : T.wash,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: danger ? T.danger : T.brass),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: danger ? T.danger : T.ink,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 12, color: T.muted)),
    trailing:
        trailing ??
        const Icon(Icons.chevron_right_rounded, size: 20, color: T.muted),
    onTap: onTap ?? (route == null ? null : () => context.push(route!)),
  );
}

class LabeledField extends StatelessWidget {
  const LabeledField(
    this.label, {
    super.key,
    this.value,
    this.hint,
    this.controller,
    this.obscure = false,
    this.lines = 1,
    this.keyboard,
    this.required = false,
    this.onChanged,
  });
  final String label;
  final String? value;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final int lines;
  final TextInputType? keyboard;
  final bool required;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? value : null,
          obscureText: obscure,
          maxLines: lines,
          keyboardType: keyboard,
          onChanged: onChanged,
          validator: required
              ? (v) => v == null || v.trim().isEmpty
                    ? 'Please enter ${label.toLowerCase()}'
                    : null
              : null,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.forum_outlined,
    this.action,
    this.onAction,
  });
  final String title;
  final String description;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: T.wash,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: T.brass, size: 32),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 9),
          Text(
            description,
            style: const TextStyle(color: T.muted, height: 1.6),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

Future<Result?> sheet<Result>(BuildContext context, Widget child) =>
    showModalBottomSheet<Result>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: T.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// Owns its field controllers for the full bottom-sheet route lifecycle.
class EditorSheet extends StatefulWidget {
  const EditorSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
  });
  final String title;
  final List<(String, String)> fields;
  final ValueChanged<List<String>> onSave;
  @override
  State<EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<EditorSheet> {
  final form = GlobalKey<FormState>();
  late final controllers = [
    for (final field in widget.fields) TextEditingController(text: field.$2),
  ];
  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 22),
        for (var i = 0; i < widget.fields.length; i++)
          LabeledField(
            widget.fields[i].$1,
            controller: controllers[i],
            required: true,
            lines: i == 0 ? 1 : 3,
          ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            widget.onSave([for (final c in controllers) c.text.trim()]);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
