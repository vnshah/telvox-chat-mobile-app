import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Building blocks shared by the customer and ticket detail screens, laid out
/// as WhatsApp's contact info is on each platform. On Android: white blocks on
/// a light grey page, a large avatar, round action buttons and plain Material
/// rows. On iOS: Apple's own grouped list, in iOS's system colours (grey page,
/// white inset sections, plain line icons, grey values and chevrons), with
/// white action buttons under the avatar. Both identical in structure.

/// WhatsApp's light-theme colours for these screens on Android.
/// iOS's system colours for a grouped list, resolved for light or dark.
abstract final class IosDetailColors {
  static Color page(BuildContext context) =>
      CupertinoColors.systemGroupedBackground.resolveFrom(context);
  static Color cell(BuildContext context) =>
      CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
  static Color label(BuildContext context) =>
      CupertinoColors.label.resolveFrom(context);
  static Color secondary(BuildContext context) =>
      CupertinoColors.secondaryLabel.resolveFrom(context);
  static Color separator(BuildContext context) =>
      CupertinoColors.separator.resolveFrom(context);
  static Color danger(BuildContext context) =>
      CupertinoColors.systemRed.resolveFrom(context);
}

abstract final class DetailColors {
  static const page = Color(0xFFF0F2F5);
  static const ink = Color(0xFF111B21);
  static const secondary = Color(0xFF667781);
  static const icon = Color(0xFF54656F);
  static const line = Color(0xFFE9EDEF);
  static const danger = Color(0xFFEA0038);
}

class QuickAction {
  const QuickAction(this.icon, this.label, this.onTap, {this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
}

/// Profile header: avatar or title, a subtitle line, status chips and up to
/// four quick actions.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.title,
    this.avatar,
    this.avatarSeed,
    this.subtitle,
    this.chips = const [],
    this.actions = const [],
    this.onTitleTap,
    this.centered = true,
    this.online = false,
    this.status,
    this.titleEditor,
  });
  final String title;
  final String? avatar, subtitle;

  /// Picks the avatar's colour, as [Avatar.seed] does; the title by default.
  final Object? avatarSeed;
  final List<Widget> chips;
  final List<QuickAction> actions;
  final VoidCallback? onTitleTap;
  final bool centered;

  /// A green dot on the avatar: the customer was active moments ago.
  final bool online;

  /// A short green line under the subtitle, such as "Active 3 min ago".
  final String? status;

  /// Shown in place of the title while it is being edited.
  final Widget? titleEditor;

  @override
  Widget build(BuildContext context) {
    final apple = isCupertino(context);
    if (!apple) return _materialHero();
    final colors = avatarColors(avatarSeed == null ? title : '$avatarSeed');
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (avatar != null) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: colors.$1,
                  child: Text(
                    avatar!,
                    style: TextStyle(
                      fontSize: avatarLetterSize(100, avatar!),
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: colors.$2,
                    ),
                  ),
                ),
                if (online)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      key: const ValueKey('window-dot'),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: T.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: IosDetailColors.page(context),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          titleEditor ??
              GestureDetector(
                onTap: onTitleTap,
                child: Text(
                  title,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.3,
                    color: IosDetailColors.label(context),
                  ),
                ),
              ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                color: IosDetailColors.secondary(context),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 2),
            Text(
              status!,
              key: const ValueKey('window-label'),
              style: const TextStyle(fontSize: 13, color: T.green),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: centered ? WrapAlignment.center : WrapAlignment.start,
              children: chips,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _IosAction(a)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

extension on DetailHero {
  /// WhatsApp's contact info header: a large avatar, the name, the number,
  /// then outlined action boxes, all on one white block.
  Widget _materialHero() {
    final colors = avatarColors(avatarSeed == null ? title : '$avatarSeed');
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (avatar != null) ...[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: colors.$1,
                    child: Text(
                      avatar!,
                      style: TextStyle(
                        fontSize: avatarLetterSize(120, avatar!),
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: colors.$2,
                      ),
                    ),
                  ),
                  if (online)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        key: const ValueKey('window-dot'),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: T.unread,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            titleEditor ??
                GestureDetector(
                  onTap: onTitleTap,
                  child: Text(
                    title,
                    textAlign: textAlign,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: DetailColors.ink,
                    ),
                  ),
                ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: textAlign,
                style: const TextStyle(
                  fontSize: 16,
                  color: DetailColors.secondary,
                ),
              ),
            ],
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(
                status!,
                key: const ValueKey('window-label'),
                style: const TextStyle(fontSize: 14, color: T.unread),
              ),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: centered
                    ? WrapAlignment.center
                    : WrapAlignment.start,
                children: chips,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final (i, a) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _MaterialAction(a)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// WhatsApp's action button: a dark icon in a soft grey circle, its label
/// underneath; the circle and the label are one button.
class _MaterialAction extends StatelessWidget {
  const _MaterialAction(this.action);
  final QuickAction action;
  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: DetailColors.page,
                shape: BoxShape.circle,
              ),
              child: Icon(
                action.icon,
                size: 24,
                color: enabled ? DetailColors.ink : DetailColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? DetailColors.ink : DetailColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp's iOS action button: a white rounded box on the grey page, the
/// icon in green over its name.
class _IosAction extends StatelessWidget {
  const _IosAction(this.action);
  final QuickAction action;
  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final label = action.label.isEmpty
        ? ''
        : action.label[0].toUpperCase() + action.label.substring(1);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 64),
      onPressed: action.onTap,
      child: Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          color: IosDetailColors.cell(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              action.icon,
              size: 24,
              color: enabled ? T.green : IosDetailColors.secondary(context),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: enabled
                    ? IosDetailColors.label(context)
                    : IosDetailColors.secondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled group: a Material card with a taupe label on Android, an inset
/// grouped list section on iOS. [action] is the one link on the right.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    this.title,
    required this.children,
    this.action,
    this.onAction,
  });
  final String? title;
  final List<Widget> children;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final link = action == null
        ? null
        : GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: T.unread,
              ),
            ),
          );
    if (isCupertino(context)) {
      return CupertinoListSection.insetGrouped(
        backgroundColor: IosDetailColors.page(context),
        decoration: BoxDecoration(
          color: IosDetailColors.cell(context),
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.fromLTRB(20, 6, 20, 14),
        separatorColor: IosDetailColors.separator(context),
        // iOS's grouped list header: small capitals in the secondary grey.
        header: title == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        color: IosDetailColors.secondary(context),
                      ),
                    ),
                  ),
                  ?link,
                ],
              ),
        children: children,
      );
    }
    // WhatsApp: a full-width white block, set off from the next by the
    // page's grey, with a quiet grey title.
    // White Material, not a coloured box, so the rows' ripples show.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.only(top: title == null ? 4 : 0, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: DetailColors.secondary,
                          ),
                        ),
                      ),
                      ?link,
                    ],
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// One row: icon, label, optional value or second line, chevron when it
/// opens something. iOS draws the icon in a coloured tile, as Settings does.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.tile = T.brass,
    this.subtitleLines,
  });
  final IconData icon;
  final String label;
  final String? value, subtitle;

  /// Cuts a long second line (a note preview) with an ellipsis.
  final int? subtitleLines;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final Color tile;

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      // WhatsApp on iOS: a plain line icon in the text colour (red when it
      // is destructive), the name, the value in grey, then the chevron.
      final ink = destructive
          ? IosDetailColors.danger(context)
          : IosDetailColors.label(context);
      return CupertinoListTile(
        leading: AppIcon(icon, size: 22, color: ink),
        leadingSize: 26,
        title: Text(label, style: TextStyle(color: ink, fontSize: 17)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: subtitleLines,
                overflow: subtitleLines == null ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: IosDetailColors.secondary(context),
                ),
              ),
        additionalInfo: value == null
            ? null
            : Text(
                value!,
                style: TextStyle(color: IosDetailColors.secondary(context)),
              ),
        trailing:
            trailing ??
            (onTap == null ? null : const CupertinoListTileChevron()),
        onTap: onTap,
      );
    }
    // WhatsApp's rows: a grey icon, a 16 sp title, the value or detail as a
    // grey second line, and no chevrons.
    final second = subtitle ?? value;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minVerticalPadding: 12,
      horizontalTitleGap: 20,
      leading: Icon(
        icon,
        size: 24,
        color: destructive ? DetailColors.danger : DetailColors.icon,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: destructive ? DetailColors.danger : DetailColors.ink,
          fontSize: 16,
        ),
      ),
      subtitle: second == null
          ? null
          : Text(
              second,
              maxLines: subtitleLines,
              overflow: subtitleLines == null ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: DetailColors.secondary,
              ),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Status chip: green while open, neutral otherwise.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.icon,
    this.positive = false,
    this.onTap,
  });
  final String label;
  final IconData? icon;
  final bool positive;

  /// Opens a quick change, marked with a small chevron.
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFD9FDD3) : DetailColors.page,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(
              icon,
              size: 14,
              color: positive ? const Color(0xFF008069) : DetailColors.icon,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: positive ? const Color(0xFF008069) : DetailColors.ink,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            AppIcon(
              Icons.arrow_drop_down,
              size: 16,
              color: positive ? const Color(0xFF008069) : DetailColors.icon,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Removable tag on both platforms, plus an add pill.
class TagWrap extends StatefulWidget {
  const TagWrap({
    super.key,
    required this.tags,
    this.onRemove,
    this.onAdd,
    this.limit = 6,
  });
  final List<String> tags;
  final void Function(int index)? onRemove;
  final VoidCallback? onAdd;

  /// Shown before "+N more", so many tags never stretch the page.
  final int limit;
  @override
  State<TagWrap> createState() => _TagWrapState();
}

class _TagWrapState extends State<TagWrap> {
  bool all = false;

  Widget chip(
    String text, {
    Widget? trailing,
    VoidCallback? onTap,
    bool outlined = false,
    IconData? leading,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.fromLTRB(12, 6, trailing == null ? 12 : 6, 6),
      decoration: BoxDecoration(
        color: outlined ? null : DetailColors.page,
        border: outlined ? Border.all(color: T.unread) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: AppIcon(leading, size: 16, color: T.unread),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: outlined ? T.unread : DetailColors.ink,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    final hidden = all ? 0 : (tags.length - widget.limit).clamp(0, tags.length);
    final shown = tags.length - hidden;
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < shown; i++)
            chip(
              tags[i],
              trailing: widget.onRemove == null
                  ? null
                  : GestureDetector(
                      onTap: () => widget.onRemove!(i),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: AppIcon(
                          Icons.close,
                          size: 16,
                          color: DetailColors.icon,
                          semanticLabel: 'Remove ${tags[i]}',
                        ),
                      ),
                    ),
            ),
          if (hidden > 0)
            chip(
              '+$hidden more',
              outlined: true,
              onTap: () => setState(() => all = true),
            )
          else if (all && tags.length > widget.limit)
            chip(
              'Show less',
              outlined: true,
              onTap: () => setState(() => all = false),
            ),
          if (widget.onAdd != null)
            chip(
              'Add tag',
              outlined: true,
              onTap: widget.onAdd,
              leading: Icons.add,
            ),
        ],
      ),
    );
  }
}

/// The page frame for a detail screen: native bar, then sections on the
/// grouped (iOS) or surface (Android) background.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.busy = false,
    this.onRefresh,
  });
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool busy;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: children,
    );
    final apple = isCupertino(context);
    return Scaffold(
      backgroundColor: apple
          ? IosDetailColors.page(context)
          : DetailColors.page,
      appBar: apple
          ? platformAppBar(
              context,
              title: Text(title),
              actions: actions,
              iosBackground: IosDetailColors.page(context),
            )
          : AppBar(
              title: Text(title),
              actions: actions,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              foregroundColor: DetailColors.ink,
              titleTextStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: DetailColors.ink,
              ),
            ),
      body: Column(
        children: [
          // White under the bar on Android, so it runs into the header.
          ColoredBox(
            color: apple ? Colors.transparent : Colors.white,
            child: SizedBox(
              height: 2,
              width: double.infinity,
              child: busy ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
          ),
          Expanded(
            child: onRefresh == null
                ? list
                : RefreshIndicator(onRefresh: onRefresh!, child: list),
          ),
        ],
      ),
    );
  }
}
