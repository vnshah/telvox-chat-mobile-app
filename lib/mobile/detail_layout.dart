import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Building blocks shared by the customer and ticket detail screens. Each one
/// draws Material 3 on Android (cards, tonal buttons, list rows) and Apple's
/// grouped style on iOS (inset sections, icon tiles, chevrons), so both
/// screens feel native and identical in structure.

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
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, apple ? 4 : 12, 16, 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (avatar != null) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: T.selected,
                  child: Text(
                    avatar!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: T.onSelected,
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
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          titleEditor ??
              GestureDetector(
                onTap: onTitleTap,
                child: Text(
                  title,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: apple ? 22 : 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.3,
                    color: T.ink,
                  ),
                ),
              ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: const TextStyle(fontSize: 14, color: T.secondary),
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
            const SizedBox(height: 14),
            Row(
              children: [
                for (final a in actions)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: apple ? _IosAction(a) : _MaterialAction(a),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MaterialAction extends StatelessWidget {
  const _MaterialAction(this.action);
  final QuickAction action;
  @override
  // The label is part of the button, as WhatsApp's are: either one taps it.
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: action.onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: action.primary ? T.green : T.selected,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: action.onTap,
            child: SizedBox(
              width: 52,
              height: 46,
              child: Icon(
                action.icon,
                size: 22,
                color: action.primary ? Colors.white : T.onSelected,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: T.secondary),
        ),
      ],
    ),
  );
}

class _IosAction extends StatelessWidget {
  const _IosAction(this.action);
  final QuickAction action;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(0, 58),
    onPressed: action.onTap,
    child: Container(
      height: 58,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(action.icon, size: 22, color: T.green),
          const SizedBox(height: 3),
          Text(
            action.label.toLowerCase(),
            style: const TextStyle(fontSize: 11, color: T.green),
          ),
        ],
      ),
    ),
  );
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
                color: T.green,
              ),
            ),
          );
    if (isCupertino(context)) {
      return CupertinoListSection.insetGrouped(
        backgroundColor: T.iosGrouped,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        separatorColor: T.iosSeparator,
        header: title == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: T.muted,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  ?link,
                ],
              ),
        children: children,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                          color: T.brass,
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
    final colour = destructive ? T.danger : T.ink;
    if (isCupertino(context)) {
      return CupertinoListTile(
        leading: Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: destructive ? T.danger : tile,
            borderRadius: BorderRadius.circular(7),
          ),
          child: AppIcon(icon, size: 18, color: Colors.white),
        ),
        title: Text(label, style: TextStyle(color: colour, fontSize: 16)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(fontSize: 13, color: T.muted),
              ),
        additionalInfo: value == null
            ? null
            : Text(value!, style: const TextStyle(color: T.muted)),
        trailing:
            trailing ??
            (onTap == null ? null : const CupertinoListTileChevron()),
        onTap: onTap,
      );
    }
    return ListTile(
      leading: Icon(icon, color: destructive ? T.danger : T.brass),
      title: Text(label, style: TextStyle(color: colour, fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: subtitleLines,
              overflow: subtitleLines == null ? null : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: T.muted),
            ),
      trailing:
          trailing ??
          (value != null
              ? Text(
                  value!,
                  style: const TextStyle(fontSize: 14, color: T.secondary),
                )
              : onTap == null
              ? null
              : const Icon(Icons.chevron_right, color: T.muted)),
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
        color: positive ? T.greenWash : T.wash,
        border: Border.all(color: positive ? Colors.transparent : T.edge),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon, size: 14, color: positive ? T.green : T.secondary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: positive ? T.green : T.secondary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            AppIcon(
              Icons.arrow_drop_down,
              size: 16,
              color: positive ? T.green : T.secondary,
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
      padding: EdgeInsets.fromLTRB(9, 4, trailing == null ? 9 : 3, 4),
      decoration: BoxDecoration(
        color: outlined ? null : T.selected,
        border: outlined ? Border.all(color: T.control) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: AppIcon(leading, size: 14, color: T.brass),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: outlined ? T.brass : T.onSelected,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
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
                          size: 14,
                          color: T.onSelected,
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
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
    return Scaffold(
      appBar: platformAppBar(context, title: Text(title), actions: actions),
      body: Column(
        children: [
          SizedBox(
            height: 2,
            child: busy ? const LinearProgressIndicator(minHeight: 2) : null,
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
