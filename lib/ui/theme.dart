import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'platform.dart';
export 'platform.dart';

abstract final class T {
  static const paper = Color(0xFFEAF2EB);
  static const wash = Color(0xFFF4F7F3);
  static const ink = Color(0xFF1B2922);
  static const secondary = Color(0xFF405047);
  static const muted = Color(0xFF566258);
  static const green = Color(0xFF176B46);
  static const forest = Color(0xFF173D2E);
  static const mint = Color(0xFFB8DCC7);
  static const brass = Color(0xFF5F7365);
  static const edge = Color(0xFFDCE5DC);
  static const control = Color(0xFFB6C7BA);
  static const selected = Color(0xFFC8E4D1);
  // Brighter than the chat wallpaper so outgoing bubbles lift off it.
  static const outgoing = Color(0xFFD5F1DD);
  static const firm = Color(0xFF173D2E);
  static const danger = Color(0xFFC2335E);
  static const blue = Color(0xFF137BA4);

  // iOS uses its system face. Previewing that UI elsewhere uses our bundled face.
  static String get cupertinoFamily =>
      defaultTargetPlatform == TargetPlatform.iOS ? '.SF Pro Text' : 'Geist';
  static String get cupertinoDisplayFamily =>
      defaultTargetPlatform == TargetPlatform.iOS ? '.SF Pro Display' : 'Geist';

  static CupertinoThemeData get cupertino => CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: green,
    scaffoldBackgroundColor: Color(0xFFF2F2F7),
    barBackgroundColor: Color(0xFAFCFCFC),
    textTheme: CupertinoTextThemeData(
      primaryColor: green,
      textStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist', 'Noto Color Emoji'],
        fontSize: 15,
        color: ink,
      ),
      actionTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 16,
        color: green,
      ),
      navActionTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 16,
        color: green,
      ),
      navTitleTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      navLargeTitleTextStyle: TextStyle(
        fontFamily: cupertinoDisplayFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      tabLabelTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 10,
        color: muted,
      ),
      pickerTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 20,
        color: ink,
      ),
      dateTimePickerTextStyle: TextStyle(
        fontFamily: cupertinoFamily,
        fontFamilyFallback: ['Geist'],
        fontSize: 20,
        color: ink,
      ),
    ),
  );

  static ThemeData themeFor(TargetPlatform platform) {
    final apple = platform == TargetPlatform.iOS;
    final family = apple ? cupertinoFamily : 'Roboto';
    return ThemeData(
      useMaterial3: true,
      platform: platform,
      brightness: Brightness.light,
      fontFamily: family,
      fontFamilyFallback: const ['Geist', 'Noto Color Emoji'],
      cupertinoOverrideTheme: cupertino,
      splashFactory: apple ? NoSplash.splashFactory : InkSparkle.splashFactory,
      highlightColor: apple ? Colors.transparent : null,
      scaffoldBackgroundColor: apple ? const Color(0xFFF2F2F7) : wash,
      colorScheme: ColorScheme.fromSeed(seedColor: green).copyWith(
        primary: green,
        onPrimary: Colors.white,
        primaryContainer: selected,
        onPrimaryContainer: forest,
        secondary: green,
        secondaryContainer: selected,
        onSecondaryContainer: forest,
        surface: Colors.white,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainer: paper,
        surfaceContainerLow: wash,
        surfaceContainerHighest: paper,
        outline: control,
        outlineVariant: edge,
        error: danger,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          height: 1.12,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
          color: ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -.4,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          letterSpacing: -.3,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: 64,
        backgroundColor: apple ? Colors.white : paper,
        foregroundColor: forest,
        iconTheme: const IconThemeData(color: green),
        actionsIconTheme: const IconThemeData(color: green),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: apple,
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Geist'],
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: selected,
        surfaceTintColor: Colors.transparent,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: family,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? forest : muted,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: paper,
        indicatorColor: selected,
        selectedIconTheme: IconThemeData(color: forest),
        unselectedIconTheme: IconThemeData(color: muted),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: selected,
        foregroundColor: forest,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(
        color: edge,
        thickness: .7,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: wash,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: control),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: control),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: green, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: control),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: green),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(44, 44),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: selected,
        secondarySelectedColor: selected,
        checkmarkColor: forest,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected) ? selected : control,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Geist'],
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Geist'],
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: forest,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: forest,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
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
  const Brand({super.key, this.large = false, this.onDark = false});
  final bool large, onDark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'telvox',
        style: mono(
          size: large ? 24 : 19,
          color: onDark ? Colors.white : T.ink,
          weight: FontWeight.w500,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text(
          '|',
          style: mono(
            size: large ? 23 : 18,
            color: onDark ? T.mint.withValues(alpha: .5) : T.control,
          ),
        ),
      ),
      Text(
        'chat',
        style: mono(size: large ? 24 : 19, color: onDark ? T.mint : T.green),
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
          AppIcon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mono(size: 10, color: color),
          ),
        ),
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
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(isCupertino(context) ? 12 : 16),
      side: BorderSide(
        color: color == Colors.white
            ? T.edge
            : Colors.white.withValues(alpha: .12),
        width: .7,
      ),
    );
    if (!isCupertino(context)) {
      return Card.filled(
        margin: EdgeInsets.zero,
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
    }
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
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
    appBar: platformAppBar(
      context,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
    ),
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

class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    this.hint = 'Search',
    this.onChanged,
    this.controller,
    this.dense = false,
    this.value,
  });
  final String hint;
  final String? value;
  final bool dense;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final owned = TextEditingController(text: widget.value);
  TextEditingController get controller => widget.controller ?? owned;
  @override
  void didUpdateWidget(covariant SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != controller.text) {
      controller.value = TextEditingValue(
        text: widget.value!,
        selection: TextSelection.collapsed(offset: widget.value!.length),
      );
    }
  }

  @override
  void dispose() {
    owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      return CupertinoSearchTextField(
        controller: controller,
        onChanged: widget.onChanged,
        placeholder: widget.hint,
        style: Theme.of(context).textTheme.bodyMedium,
        backgroundColor: const Color(0xFFEFEFF1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        borderRadius: BorderRadius.circular(10),
      );
    }
    return SearchBar(
      controller: controller,
      onChanged: widget.onChanged,
      hintText: widget.hint,
      leading: const AppIcon(Icons.search_rounded, size: 22, color: T.muted),
      constraints: BoxConstraints(minHeight: widget.dense ? 44 : 48),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: const WidgetStatePropertyAll(T.paper),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.bodyMedium),
      hintStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.bodyMedium?.copyWith(color: T.muted),
      ),
    );
  }
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
  Widget build(BuildContext context) => AppListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    leading: Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFF6E0E7) : T.wash,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AppIcon(icon, size: 19, color: danger ? T.danger : T.brass),
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
        const AppIcon(Icons.chevron_right_rounded, size: 20, color: T.muted),
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
        AppTextFormField(
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
            child: AppIcon(icon, color: T.brass, size: 32),
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
            AppButton.filled(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

Future<Result?> sheet<Result>(BuildContext context, Widget child) {
  if (isCupertino(context)) {
    return showCupertinoModalPopup<Result>(
      context: context,
      builder: (popup) {
        final inset = MediaQuery.viewInsetsOf(popup).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: CupertinoPopupSurface(
            child: Material(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(popup).height - inset - 70)
                        .clamp(160, 1000),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 34,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1D1D6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<Result>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (popup) => Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        0,
        22,
        24 + MediaQuery.viewInsetsOf(popup).bottom,
      ),
      child: SingleChildScrollView(child: child),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
}) async {
  final destructive =
      action.toLowerCase().contains('delete') ||
      action.toLowerCase().contains('remove');
  if (isCupertino(context)) {
    return await showCupertinoDialog<bool>(
          context: context,
          builder: (dialog) => CupertinoAlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: destructive,
                isDefaultAction: !destructive,
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }
  return await showDialog<bool>(
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
              style: TextButton.styleFrom(
                foregroundColor: destructive ? T.danger : T.green,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

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
        AppButton.filled(
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
