import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool isCupertino(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Only the screen-review library overrides this; normal use follows the device.
final platformPreviewProvider =
    NotifierProvider<PlatformPreview, TargetPlatform?>(PlatformPreview.new);

class PlatformPreview extends Notifier<TargetPlatform?> {
  @override
  TargetPlatform? build() => null;
  void select(TargetPlatform? platform) => state = platform;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  static final apple = <IconData, IconData>{
    Icons.chat_bubble_outline_rounded: CupertinoIcons.chat_bubble,
    Icons.people_outline_rounded: CupertinoIcons.person_2,
    Icons.people_outline: CupertinoIcons.person_2,
    Icons.person_outline: CupertinoIcons.person,
    Icons.person_add_alt_outlined: CupertinoIcons.person_add,
    Icons.confirmation_number_outlined: CupertinoIcons.ticket,
    Icons.grid_view_rounded: CupertinoIcons.square_grid_2x2,
    Icons.arrow_back: CupertinoIcons.chevron_back,
    Icons.arrow_back_rounded: CupertinoIcons.chevron_back,
    Icons.chevron_right: CupertinoIcons.chevron_forward,
    Icons.chevron_right_rounded: CupertinoIcons.chevron_forward,
    Icons.keyboard_arrow_down_rounded: CupertinoIcons.chevron_down,
    Icons.notifications_none_rounded: CupertinoIcons.bell,
    Icons.call_outlined: CupertinoIcons.phone,
    Icons.call: CupertinoIcons.phone_fill,
    Icons.search_rounded: CupertinoIcons.search,
    Icons.tune_rounded: CupertinoIcons.slider_horizontal_3,
    Icons.tune_outlined: CupertinoIcons.slider_horizontal_3,
    Icons.settings_outlined: CupertinoIcons.gear,
    Icons.edit_outlined: CupertinoIcons.square_pencil,
    Icons.edit: CupertinoIcons.pencil,
    Icons.add: CupertinoIcons.plus,
    Icons.close: CupertinoIcons.xmark,
    Icons.delete_outline_rounded: CupertinoIcons.delete,
    Icons.more_vert: CupertinoIcons.ellipsis,
    Icons.image_outlined: CupertinoIcons.photo,
    Icons.photo_library_outlined: CupertinoIcons.photo_on_rectangle,
    Icons.camera_alt_outlined: CupertinoIcons.camera,
    Icons.description_outlined: CupertinoIcons.doc_text,
    Icons.article_outlined: CupertinoIcons.doc_text,
    Icons.location_on_outlined: CupertinoIcons.location,
    Icons.mic_none_rounded: CupertinoIcons.mic,
    Icons.star_border_rounded: CupertinoIcons.star,
    Icons.star_rounded: CupertinoIcons.star_fill,
    Icons.reply_rounded: CupertinoIcons.reply,
    Icons.forward_rounded: CupertinoIcons.arrowshape_turn_up_right,
    Icons.content_copy_rounded: CupertinoIcons.doc_on_doc,
    Icons.info_outline_rounded: CupertinoIcons.info_circle,
    Icons.check_circle_outline: CupertinoIcons.check_mark_circled,
    Icons.lock_outline: CupertinoIcons.lock,
    Icons.shield_outlined: CupertinoIcons.shield,
    Icons.event_outlined: CupertinoIcons.calendar,
    // Message kinds, actions and detail rows (Material Symbols on Android,
    // their SF Symbols counterparts on iOS).
    Icons.call_missed: CupertinoIcons.phone_down,
    Icons.call_received: CupertinoIcons.phone_arrow_down_left,
    Icons.call_made: CupertinoIcons.phone_arrow_up_right,
    Icons.videocam_outlined: CupertinoIcons.videocam,
    Icons.emoji_emotions_outlined: CupertinoIcons.smiley,
    Icons.person_add_alt_1_outlined: CupertinoIcons.person_badge_plus,
    Icons.chat_outlined: CupertinoIcons.chat_bubble,
    Icons.chat: CupertinoIcons.chat_bubble_fill,
    Icons.task_alt: CupertinoIcons.check_mark_circled,
    Icons.replay: CupertinoIcons.arrow_counterclockwise,
    Icons.sell_outlined: CupertinoIcons.tag,
    Icons.sticky_note_2_outlined: CupertinoIcons.doc_plaintext,
    Icons.perm_media_outlined: CupertinoIcons.photo_on_rectangle,
    Icons.block: CupertinoIcons.nosign,
    Icons.do_not_disturb_on_outlined: CupertinoIcons.minus_circle,
    Icons.schedule: CupertinoIcons.time,
    Icons.flag_outlined: CupertinoIcons.flag,
    Icons.timelapse: CupertinoIcons.timer,
    Icons.swap_horiz: CupertinoIcons.arrow_right_arrow_left,
    Icons.logout: CupertinoIcons.square_arrow_right,
    Icons.mail_outline: CupertinoIcons.mail,
    Icons.visibility_outlined: CupertinoIcons.eye,
    Icons.visibility_off_outlined: CupertinoIcons.eye_slash,
    Icons.account_circle_outlined: CupertinoIcons.person_crop_circle,
    Icons.info_outline: CupertinoIcons.info_circle,
    Icons.group_outlined: CupertinoIcons.person_2,
    Icons.group: CupertinoIcons.person_2_fill,
    Icons.confirmation_number: CupertinoIcons.ticket_fill,
    Icons.bolt: CupertinoIcons.bolt,
    Icons.attach_file: CupertinoIcons.paperclip,
    Icons.mic: CupertinoIcons.mic_fill,
    Icons.send: CupertinoIcons.arrow_up,
  };
  @override
  Widget build(BuildContext context) => Icon(
    isCupertino(context) ? apple[icon] ?? icon : icon,
    size: size,
    color: color,
    semanticLabel: semanticLabel,
  );
}

enum _ButtonKind { filled, outlined, text }

class AppButton extends StatelessWidget {
  const AppButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _ButtonKind.filled,
       icon = null;
  const AppButton.outlined({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _ButtonKind.outlined,
       icon = null;
  const AppButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _ButtonKind.text,
       icon = null;
  const AppButton.filledIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
  }) : _kind = _ButtonKind.filled,
       child = label;
  const AppButton.outlinedIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
  }) : _kind = _ButtonKind.outlined,
       child = label;
  const AppButton.textIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
  }) : _kind = _ButtonKind.text,
       child = label;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final _ButtonKind _kind;
  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      return switch (_kind) {
        _ButtonKind.filled =>
          icon == null
              ? FilledButton(onPressed: onPressed, style: style, child: child)
              : FilledButton.icon(
                  onPressed: onPressed,
                  style: style,
                  icon: icon!,
                  label: child,
                ),
        _ButtonKind.outlined =>
          icon == null
              ? OutlinedButton(onPressed: onPressed, style: style, child: child)
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  style: style,
                  icon: icon!,
                  label: child,
                ),
        _ButtonKind.text =>
          icon == null
              ? TextButton(onPressed: onPressed, style: style, child: child)
              : TextButton.icon(
                  onPressed: onPressed,
                  style: style,
                  icon: icon!,
                  label: child,
                ),
      };
    }
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final primary = CupertinoTheme.of(context).primaryColor;
    final foreground = onPressed == null
        ? CupertinoColors.inactiveGray
        : style?.foregroundColor?.resolve(states) ??
              (_kind == _ButtonKind.filled ? Colors.white : primary);
    final background =
        style?.backgroundColor?.resolve(states) ??
        (_kind == _ButtonKind.filled ? primary : null);
    Widget content = DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: foreground, size: 20),
        child: icon == null
            ? child
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon!,
                  const SizedBox(width: 8),
                  Flexible(child: child),
                ],
              ),
      ),
    );
    content = CupertinoButton(
      onPressed: onPressed,
      color: background,
      foregroundColor: foreground,
      minimumSize: const Size(0, 44),
      padding: EdgeInsets.symmetric(
        horizontal: _kind == _ButtonKind.text ? 8 : 16,
        vertical: 11,
      ),
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
    if (_kind == _ButtonKind.outlined) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: primary.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: content,
      );
    }
    return content;
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.padding,
    this.constraints,
  }) : filled = false,
       tonal = false;
  const AppIconButton.filled({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.padding,
    this.constraints,
  }) : filled = true,
       tonal = false;
  const AppIconButton.filledTonal({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
    this.padding,
    this.constraints,
  }) : filled = false,
       tonal = true;
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final ButtonStyle? style;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final bool filled, tonal;
  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      if (filled) {
        return IconButton.filled(
          onPressed: onPressed,
          icon: icon,
          tooltip: tooltip,
          style: style,
          padding: padding,
          constraints: constraints,
        );
      }
      if (tonal) {
        return IconButton.filledTonal(
          onPressed: onPressed,
          icon: icon,
          tooltip: tooltip,
          style: style,
          padding: padding,
          constraints: constraints,
        );
      }
      return IconButton(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        style: style,
        padding: padding,
        constraints: constraints,
      );
    }
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final scheme = Theme.of(context).colorScheme;
    final background =
        style?.backgroundColor?.resolve(states) ??
        (filled
            ? scheme.primary
            : tonal
            ? scheme.primaryContainer
            : null);
    final foreground = onPressed == null
        ? CupertinoColors.inactiveGray
        : style?.foregroundColor?.resolve(states) ??
              (filled ? Colors.white : CupertinoTheme.of(context).primaryColor);
    Widget button = ConstrainedBox(
      constraints:
          constraints ?? const BoxConstraints(minWidth: 44, minHeight: 44),
      child: CupertinoButton(
        onPressed: onPressed,
        minimumSize: Size.zero,
        padding: padding ?? const EdgeInsets.all(9),
        color: background,
        foregroundColor: foreground,
        borderRadius: BorderRadius.circular(24),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: icon,
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: Semantics(label: tooltip, button: true, child: button),
      );
    }
    return button;
  }
}

class AppFab extends StatelessWidget {
  const AppFab({
    super.key,
    required this.onPressed,
    required this.child,
    required this.tooltip,
  });
  final VoidCallback onPressed;
  final Widget child;
  final String tooltip;
  @override
  Widget build(BuildContext context) => isCupertino(context)
      ? const SizedBox.shrink()
      : FloatingActionButton(
          onPressed: onPressed,
          tooltip: tooltip,
          child: child,
        );
}

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.showCheckmark,
    this.visualDensity,
    this.padding,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool? showCheckmark;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      return ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        showCheckmark: showCheckmark,
        visualDensity: visualDensity,
        padding: padding,
      );
    }
    final primary = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      selected: selected,
      child: CupertinoButton(
        onPressed: onSelected == null ? null : () => onSelected!(!selected),
        minimumSize: const Size(0, 36),
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected
            ? primary.withValues(alpha: .12)
            : const Color(0xFFF0F1F2),
        foregroundColor: selected
            ? primary
            : Theme.of(context).colorScheme.onSurface,
        borderRadius: BorderRadius.circular(8),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? primary : Theme.of(context).colorScheme.onSurface,
          ),
          child: label,
        ),
      ),
    );
  }
}

class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.labelStyle,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final TextStyle? labelStyle;
  @override
  Widget build(BuildContext context) => isCupertino(context)
      ? AppChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(CupertinoIcons.check_mark, size: 13),
                const SizedBox(width: 5),
              ],
              label,
            ],
          ),
          selected: selected,
          onSelected: onSelected,
        )
      : FilterChip(
          label: label,
          selected: selected,
          onSelected: onSelected,
          labelStyle: labelStyle,
        );
}

class PlatformFilters extends StatelessWidget {
  const PlatformFilters({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.scrollable = false,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool scrollable;
  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final option in options)
        AppChoiceChip(
          label: Text(option),
          selected: selected == option,
          showCheckmark: selected == option,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onSelected(option),
        ),
    ];
    if (!isCupertino(context)) {
      return scrollable
          ? SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => chips[i],
              ),
            )
          : Wrap(spacing: 7, runSpacing: 7, children: chips);
    }
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Wrap(spacing: 7, runSpacing: 7, children: chips);
    }
    final primary = options.length > 4 ? options.take(3).toList() : options;
    if (!primary.contains(selected)) primary[primary.length - 1] = selected;
    return Row(
      children: [
        Expanded(
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: selected,
            backgroundColor: const Color(0x24766C60),
            children: {
              for (final option in primary)
                option: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected == option
                          ? CupertinoTheme.of(context).primaryColor
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: selected == option
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
            },
            onValueChanged: (value) {
              if (value != null && context.mounted) onSelected(value);
            },
          ),
        ),
        if (options.length > 4)
          AppIconButton(
            tooltip: 'More filters',
            icon: const Icon(CupertinoIcons.ellipsis_circle, size: 23),
            onPressed: () async {
              final value = await showCupertinoModalPopup<String>(
                context: context,
                builder: (popup) => CupertinoActionSheet(
                  title: const Text('Conversation view'),
                  actions: [
                    for (final option in options)
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popup, option),
                        child: Text(option),
                      ),
                  ],
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(popup),
                    child: const Text('Cancel'),
                  ),
                ),
              );
              if (value != null && context.mounted) onSelected(value);
            },
          ),
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.style,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.decoration = const InputDecoration(),
    this.textCapitalization = TextCapitalization.none,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final int? minLines, maxLines;
  final InputDecoration decoration;
  final TextCapitalization textCapitalization;
  @override
  Widget build(BuildContext context) => !isCupertino(context)
      ? TextField(
          controller: controller,
          focusNode: focusNode,
          style: style,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: maxLines,
          decoration: decoration,
          textCapitalization: textCapitalization,
        )
      : CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          style: style,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          placeholder: decoration.hintText,
          decoration: null,
          padding:
              decoration.contentPadding?.resolve(Directionality.of(context)) ??
              const EdgeInsets.symmetric(vertical: 12),
        );
}

class AppTextFormField extends StatefulWidget {
  const AppTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.obscureText = false,
    this.keyboardType,
    this.decoration = const InputDecoration(),
    this.validator,
    this.onChanged,
    this.style,
    this.textAlign = TextAlign.start,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
  });
  final TextEditingController? controller;
  final String? initialValue;
  final bool obscureText;
  final TextInputType? keyboardType;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? minLines, maxLines, maxLength;
  @override
  State<AppTextFormField> createState() => _AppTextFormFieldState();
}

class _AppTextFormFieldState extends State<AppTextFormField> {
  late final owned = widget.controller == null
      ? TextEditingController(text: widget.initialValue)
      : null;
  @override
  void dispose() {
    owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      return TextFormField(
        controller: widget.controller ?? owned,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        decoration: widget.decoration,
        validator: widget.validator,
        onChanged: widget.onChanged,
        style: widget.style,
        textAlign: widget.textAlign,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
      );
    }
    final controller = widget.controller ?? owned!;
    return FormField<String>(
      initialValue: controller.text,
      validator: widget.validator,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.decoration.labelText != null) ...[
            Text(
              widget.decoration.labelText!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 7),
          ],
          CupertinoTextField(
            controller: controller,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            style: widget.style ?? Theme.of(context).textTheme.bodyLarge,
            textAlign: widget.textAlign,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            placeholder: widget.decoration.hintText,
            placeholderStyle: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: const Color(0xFFA39A90)),
            // iOS fields: borderless white rounded rows on the grouped
            // background, 44 pt tall; red only when invalid.
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            prefix: widget.decoration.prefixIcon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: widget.decoration.prefixIcon,
                  ),
            suffix: widget.decoration.suffixIcon,
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              border: Border.all(
                color: field.hasError
                    ? CupertinoColors.systemRed
                    : const Color(0x00000000),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            onChanged: (value) {
              field.didChange(value);
              widget.onChanged?.call(value);
            },
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 3),
              child: Text(
                field.errorText!,
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      return DropdownButtonFormField<T>(
        initialValue: initialValue,
        items: items,
        onChanged: onChanged,
        decoration: decoration,
        isExpanded: isExpanded,
      );
    }
    return FormField<T>(
      initialValue: initialValue,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (decoration.labelText != null) ...[
            Text(
              decoration.labelText!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 7),
          ],
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            color: const Color(0xFFF2F2F5),
            borderRadius: BorderRadius.circular(9),
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final value = await showCupertinoModalPopup<T>(
                context: context,
                builder: (popup) => CupertinoActionSheet(
                  title: Text(decoration.labelText ?? 'Choose an option'),
                  actions: [
                    for (final item in items)
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(popup, item.value),
                        child: item.child,
                      ),
                  ],
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(popup),
                    child: const Text('Cancel'),
                  ),
                ),
              );
              if (value != null && field.mounted) {
                field.didChange(value);
                onChanged(value);
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodyLarge,
                    child:
                        items
                            .where((item) => item.value == field.value)
                            .firstOrNull
                            ?.child ??
                        Text(decoration.hintText ?? 'Choose'),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_down, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.icon,
    this.iconColor,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final Widget? icon;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) {
      return PopupMenuButton<T>(
        itemBuilder: itemBuilder,
        onSelected: onSelected,
        tooltip: tooltip,
        icon: icon,
        iconColor: iconColor,
      );
    }
    return AppIconButton(
      tooltip: tooltip,
      icon: icon ?? Icon(CupertinoIcons.ellipsis, color: iconColor),
      onPressed: () async {
        FocusManager.instance.primaryFocus?.unfocus();
        final entries = itemBuilder(context)
            .whereType<PopupMenuItem<T>>()
            .toList();
        final value = await showCupertinoModalPopup<T>(
          context: context,
          builder: (popup) => CupertinoActionSheet(
            actions: [
              for (final item in entries)
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(popup, item.value),
                  child: item.child ?? const SizedBox(),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(popup),
              child: const Text('Cancel'),
            ),
          ),
        );
        if (value != null && context.mounted) onSelected(value);
      },
    );
  }
}

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.dense,
    this.minVerticalPadding,
    this.visualDensity,
    this.selected = false,
    this.shape,
    this.tileColor,
  });
  final Widget? title, subtitle, leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final double? minVerticalPadding;
  final VisualDensity? visualDensity;
  final bool selected;
  final ShapeBorder? shape;
  final Color? tileColor;
  @override
  Widget build(BuildContext context) => !isCupertino(context)
      ? ListTile(
          title: title,
          subtitle: subtitle,
          leading: leading,
          trailing: trailing,
          onTap: onTap,
          contentPadding: contentPadding,
          dense: dense,
          minVerticalPadding: minVerticalPadding,
          visualDensity: visualDensity,
          selected: selected,
          shape: shape,
          tileColor: tileColor,
        )
      : CupertinoListTile(
          title: title ?? const SizedBox(),
          subtitle: subtitle,
          leading: leading,
          leadingSize: 40,
          leadingToTitle: 12,
          trailing:
              trailing ??
              (onTap == null ? null : const CupertinoListTileChevron()),
          onTap: onTap,
          backgroundColor: selected
              ? CupertinoTheme.of(context).primaryColor.withValues(alpha: .08)
              : tileColor ?? Colors.transparent,
          padding:
              contentPadding?.resolve(Directionality.of(context)) ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        );
}

class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => isCupertino(context)
      ? AppListTile(
          title: title,
          subtitle: subtitle,
          contentPadding: contentPadding,
          onTap: () => onChanged(!value),
          trailing: CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: CupertinoTheme.of(context).primaryColor,
          ),
        )
      : SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          title: title,
          subtitle: subtitle,
          contentPadding: contentPadding,
        );
}

class AppCheckboxTile extends StatelessWidget {
  const AppCheckboxTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.contentPadding,
    this.controlAffinity = ListTileControlAffinity.platform,
  });
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final Widget title;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity controlAffinity;
  @override
  Widget build(BuildContext context) => isCupertino(context)
      ? AppListTile(
          title: title,
          contentPadding: contentPadding,
          onTap: () => onChanged(value != true),
          trailing: CupertinoCheckbox(
            value: value,
            tristate: value == null,
            onChanged: onChanged,
            activeColor: CupertinoTheme.of(context).primaryColor,
          ),
        )
      : CheckboxListTile(
          value: value,
          onChanged: onChanged,
          title: title,
          contentPadding: contentPadding,
          controlAffinity: controlAffinity,
        );
}

PreferredSizeWidget platformAppBar(
  BuildContext context, {
  required Widget title,
  Widget? leading,
  List<Widget>? actions,
  double? leadingWidth,
  double? titleSpacing,
}) {
  if (!isCupertino(context)) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      leadingWidth: leadingWidth,
      titleSpacing: titleSpacing,
    );
  }
  return CupertinoNavigationBar(
    middle: title,
    leading: leading,
    // Warm translucent bar and hairline, in the telvox palette.
    backgroundColor: const Color(0xF2FAF8F4),
    border: const Border(
      bottom: BorderSide(color: Color(0x293C3228), width: .5),
    ),
    trailing: actions == null
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: actions),
  );
}

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  if (!isCupertino(context)) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }
  FocusManager.instance.primaryFocus?.unfocus();
  var selected = initialDate;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (popup) => Material(
      color: CupertinoColors.systemBackground,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(popup),
                    child: const Text('Cancel'),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(popup, selected),
                    child: const Text('Done'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: firstDate,
                  maximumDate: lastDate,
                  onDateTimeChanged: (date) => selected = date,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
