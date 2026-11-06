import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_slide.dart';
import 'platform.dart';
export 'platform.dart';

/// The telvox family palette, as TheMessenger web uses it, on white screens:
///
///  - White and warm neutrals carry the surface: screens are white, fills a
///    light warm grey ([incoming]), lines [hairline], [edge] and [control].
///  - Bronze marks structure and selection, and keeps the brand: section
///    labels, list icons, avatars, tags, the selected chip and tab ([brass],
///    [bronze], [selected], [onSelected]).
///  - Green is reserved for what can be acted on, or went well: send, the
///    primary button, links, unread counts, "Open", your own messages.
abstract final class T {
  static const paper = Color(0xFFF0ECE5);
  static const wash = Color(0xFFF7F4EE);
  static const ink = Color(0xFF221C16);
  static const secondary = Color(0xFF4F4A44);
  static const muted = Color(0xFF7A7268);
  static const green = Color(0xFF1E7A4F);
  static const forest = Color(0xFF14432C);
  static const mint = Color(0xFFB8DCC7);
  static const brass = Color(0xFF8A7355);
  static const edge = Color(0xFFE3DED4);
  static const control = Color(0xFFCFC6B8);

  /// Deep bronze: text and icons on [selected], and bronze emphasis on white.
  static const bronze = Color(0xFF6B5640);

  /// Bronze wash: avatars, tags, selected chips and the active tab. Lighter
  /// than the warm paper look's taupe, so it reads as an accent on white.
  static const selected = Color(0xFFF1EADF);
  static const onSelected = bronze;
  static const greenWash = Color(0xFFDCEBDD);

  /// Screens are white; the warm tones stay in controls, tags and bubbles.
  static const surface = Colors.white;
  static const surfaceHigh = Color(0xFFEFEAE2);

  /// iOS grouped background and bar tint in the same warm family.
  static const iosGrouped = Color(0xFFF2EFEA);
  static const iosBar = Color(0xF2FAF8F4);
  static const iosSeparator = Color(0x293C3228);

  /// WhatsApp's own sent-message green, so your messages look as they do on
  /// WhatsApp.
  static const outgoing = Color(0xFFD9FDD3);

  /// A customer's message, the day and activity pills and the composer:
  /// white on the chat's beige, as on WhatsApp.
  static const incoming = Colors.white;

  /// WhatsApp's warm beige behind a conversation.
  static const chatWallpaper = Color(0xFFEFEAE2);

  /// The chat list's times as WhatsApp shows them: grey, or WhatsApp's green
  /// (with the unread count in the same green) while a chat has unread
  /// messages.
  static const listTime = Color(0xFF636466);
  static const unread = Color(0xFF1DAA61);

  /// WhatsApp's faint lift under bubbles, pills and the composer on the
  /// beige: one pixel down, barely blurred.
  static const bubbleShadow = [
    BoxShadow(color: Color(0x210B141A), offset: Offset(0, 1), blurRadius: .5),
  ];

  /// Hairlines between inbox rows and around the chat's bars.
  static const hairline = Color(0xFFEFECE7);
  static const firm = Color(0xFF1C1B1A);
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
    scaffoldBackgroundColor: iosGrouped,
    barBackgroundColor: iosBar,
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
      // Android pages slide in from the right, as WhatsApp's do; iOS keeps
      // its own slide.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SlidePageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: apple ? NoSplash.splashFactory : InkSparkle.splashFactory,
      highlightColor: apple ? Colors.transparent : null,
      scaffoldBackgroundColor: apple ? iosGrouped : surface,
      // Material 3 roles: primary is the action green, secondary the taupe.
      colorScheme: ColorScheme.fromSeed(seedColor: green).copyWith(
        primary: green,
        onPrimary: Colors.white,
        primaryContainer: greenWash,
        onPrimaryContainer: forest,
        secondary: brass,
        onSecondary: Colors.white,
        secondaryContainer: selected,
        onSecondaryContainer: onSelected,
        tertiary: brass,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: secondary,
        // Sheets, dialogs and menus are white like the screens; fills that
        // need to stand apart use the light warm grey of customer messages.
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: incoming,
        surfaceContainerHigh: Colors.white,
        surfaceContainerHighest: hairline,
        outline: control,
        outlineVariant: edge,
        inverseSurface: ink,
        onInverseSurface: const Color(0xFFF2EEE6),
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
        toolbarHeight: 60,
        backgroundColor: apple ? iosBar : surface,
        foregroundColor: ink,
        iconTheme: IconThemeData(color: apple ? green : secondary),
        actionsIconTheme: IconThemeData(color: apple ? green : secondary),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: apple,
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Geist'],
          fontSize: apple ? 17 : 20,
          fontWeight: apple ? FontWeight.w600 : FontWeight.w400,
          color: ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: selected,
        surfaceTintColor: Colors.transparent,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? onSelected
                : secondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: family,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? ink : secondary,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: selected,
        selectedIconTheme: IconThemeData(color: onSelected),
        unselectedIconTheme: IconThemeData(color: secondary),
      ),
      // The one main action on a screen: green, like the web's primary button.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
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
      // Compact Material 3 outlined fields: 48 dp, 1 px outline (2 px when
      // focused), 14 sp text and a small floating label.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        labelStyle: const TextStyle(color: secondary, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: green, fontSize: 13),
        prefixIconColor: muted,
        suffixIconColor: muted,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
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
          borderSide: const BorderSide(color: green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
      ),
      // White with a thin outline, as the white design draws search.
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused) ? brass : control,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        constraints: const BoxConstraints(minHeight: 46),
        hintStyle: const WidgetStatePropertyAll(
          TextStyle(color: muted, fontSize: 14),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: brass,
        textColor: ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 8,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
          foregroundColor: apple ? green : secondary,
          minimumSize: const Size(44, 44),
        ),
      ),
      // Material 3 filter chips: outlined, taupe container when selected.
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: selected,
        secondarySelectedColor: selected,
        checkmarkColor: onSelected,
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
          color: onSelected,
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
        backgroundColor: ink,
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

/// The telvox family wordmark, as on the web: "telvox" in the mono face, a
/// thin drawn hairline, then the product name at 0.78x in the product green.
class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false, this.onDark = false});
  final bool large, onDark;
  @override
  Widget build(BuildContext context) {
    final size = large ? 24.0 : 19.0;
    return Semantics(
      label: 'telvox chat',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'telvox',
            style: mono(
              size: size,
              color: onDark ? Colors.white : T.ink,
              weight: FontWeight.w500,
            ).copyWith(letterSpacing: -.025 * size),
          ),
          Container(
            width: 1,
            height: size * .62,
            margin: EdgeInsets.symmetric(horizontal: size * .31),
            color: onDark ? T.mint.withValues(alpha: .5) : T.control,
          ),
          Text(
            'chat',
            style: mono(
              size: size * .78,
              color: onDark ? T.mint : T.green,
            ).copyWith(letterSpacing: -.02 * size),
          ),
        ],
      ),
    );
  }
}

/// Soft tints with a deep letter of the same hue, so each person is told
/// apart at a glance and the letters stay readable on white screens. Hues
/// that look alike are kept apart in the list.
const avatarPalette = <(Color, Color)>[
  (Color(0xFFF6DED3), Color(0xFF9A3F1F)), // terracotta
  (Color(0xFFD6E4F5), Color(0xFF1F4F8A)), // blue
  (Color(0xFFE6EBCB), Color(0xFF515D12)), // olive
  (Color(0xFFEBDCEF), Color(0xFF74357F)), // plum
  (Color(0xFFCFE8E6), Color(0xFF145F5A)), // teal
  (Color(0xFFF7E7C4), Color(0xFF7F5300)), // amber
  (Color(0xFFDEDDF5), Color(0xFF46409A)), // indigo
  (Color(0xFFD5EBDD), Color(0xFF1F6B45)), // green
  (Color(0xFFF5D9E0), Color(0xFF9B2C4B)), // rose
  (Color(0xFFDDE3E8), Color(0xFF3B5062)), // slate
];

/// A person's tint and letter colour, picked by [key] (their contact id, or
/// else their name): the same person has the same colour in the list, the
/// chat, their details and on a call, and two people sharing a name differ.
(Color, Color) avatarColors(String key) {
  // FNV-1a, not String.hashCode (which Dart does not promise across runs).
  var hash = 0x811c9dc5;
  for (final unit in key.trim().toLowerCase().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  // Then a final mix: contacts made one after another have ids one apart,
  // which alone would land on neighbouring colours.
  hash ^= hash >> 16;
  hash = (hash * 0x85ebca6b) & 0xffffffff;
  hash ^= hash >> 13;
  hash = (hash * 0xc2b2ae35) & 0xffffffff;
  hash ^= hash >> 16;
  return avatarPalette[hash % avatarPalette.length];
}

/// Up to two initials: "Urmi Shah" → "US", "Rahil" → "R".
String avatarInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .take(2)
    .map((s) => s.characters.first)
    .join()
    .toUpperCase();

/// A profile picture's address, or null when there is none to show. The web
/// inbox loads it straight from WhatsApp's servers, so no headers go with it.
String? profilePicture(Object? url) {
  final text = '${url ?? ''}'.trim();
  return text.startsWith('http://') || text.startsWith('https://')
      ? text
      : null;
}

/// Large initials read best: one letter fills more of the circle than two.
double avatarLetterSize(double size, String initials) =>
    size * (initials.characters.length > 1 ? .38 : .46);

class Avatar extends StatelessWidget {
  const Avatar(
    this.name, {
    super.key,
    this.size = 46,
    this.color,
    this.seed,
    this.online = false,
    this.image,
  });
  final String name;
  final double size;

  /// The customer's WhatsApp profile picture, as the web inbox shows it; the
  /// initials stay underneath while it loads and when it cannot be loaded.
  final String? image;

  /// What picks the colour, such as the contact's id; the name by default.
  final Object? seed;

  /// A fixed fill; by default each name gets its own colour.
  final Color? color;
  final bool online;
  @override
  Widget build(BuildContext context) {
    final initials = avatarInitials(name);
    final (fill, ink) = color == null
        ? avatarColors(seed == null ? name : '$seed')
        : (color!, T.onSelected);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: avatarLetterSize(size, initials),
                fontWeight: FontWeight.w600,
                height: 1,
                color: ink,
              ),
            ),
          ),
          if (profilePicture(image) case final url?)
            ClipOval(
              key: const ValueKey('avatar-picture'),
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (online)
            Positioned(
              key: const ValueKey('online-dot'),
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
      leading: const AppIcon(Icons.search_rounded, size: 22, color: T.brass),
      constraints: BoxConstraints(minHeight: widget.dense ? 44 : 48),
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
