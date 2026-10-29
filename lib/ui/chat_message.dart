import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'theme.dart';

// Count complete emoji sequences, including skin tones, flags and ZWJ families.
// Numbers and punctuation stay normal text unless part of an emoji keycap.
int _emojiCount(String text) {
  final clusters = text
      .trim()
      .characters
      .where((c) => c.trim().isNotEmpty)
      .toList();
  if (clusters.isEmpty || clusters.length > 3) return 0;
  for (final cluster in clusters) {
    final runes = cluster.runes.toList();
    final keycap = runes.contains(0x20e3);
    if (!runes.any(
      (r) =>
          r >= 0x1f000 && r <= 0x1faff ||
          r >= 0x2600 && r <= 0x27bf ||
          r == 0x20e3,
    )) {
      return 0;
    }
    if (runes.any(
      (r) =>
          !(r >= 0x1f000 && r <= 0x1faff ||
              r >= 0x2600 && r <= 0x27bf ||
              r == 0x200d ||
              r == 0xfe0f ||
              r == 0xfe0e ||
              r == 0x20e3 ||
              keycap && (r >= 0x30 && r <= 0x39 || r == 0x23 || r == 0x2a)),
    )) {
      return 0;
    }
  }
  return clusters.length;
}

/// Reserve the actual receipt width on the last line, including text scaling.
/// The receipt can move onto its own line without covering message characters.
class _MessageText extends StatelessWidget {
  const _MessageText({
    required this.message,
    required this.starred,
    required this.emojiCount,
    required this.metadataOnly,
  });
  final Message message;
  final bool starred, metadataOnly;
  final int emojiCount;

  @override
  Widget build(BuildContext context) {
    final stampStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 10.5,
      height: 1.15,
      fontWeight: FontWeight.w400,
      color: T.muted,
    );
    final time = message.time == 'Now' ? 'now' : message.time;
    final painter = TextPainter(
      text: TextSpan(text: time, style: stampStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final stampWidth =
        painter.width.ceilToDouble() +
        (message.out ? 18 : 0) +
        (starred ? 13 : 0);
    final stampHeight = math.max(14.0, painter.height);
    painter.dispose();
    final stamp = Row(
      key: const ValueKey('message-receipt'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred)
          const Padding(
            padding: EdgeInsets.only(right: 3),
            child: AppIcon(Icons.star_rounded, size: 10, color: T.brass),
          ),
        Text(time, style: stampStyle),
        if (message.out)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: AppIcon(
              message.read ? Icons.done_all : Icons.check,
              size: 15,
              color: message.read ? T.blue : T.muted,
              semanticLabel: message.read ? 'Read' : 'Sent',
            ),
          ),
      ],
    );
    if (metadataOnly) {
      return Align(alignment: Alignment.centerRight, child: stamp);
    }
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            text: message.text,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.bottom,
                child: SizedBox(width: stampWidth + 7, height: stampHeight),
              ),
            ],
          ),
          key: const ValueKey('message-body-text'),
          textWidthBasis: TextWidthBasis.longestLine,
          style: TextStyle(
            fontSize: switch (emojiCount) {
              1 => 44,
              2 => 36,
              3 => 30,
              _ => 15.5,
            },
            height: emojiCount > 0 ? 1.15 : 1.28,
            color: T.ink,
          ),
        ),
        Positioned(right: 0, bottom: 0, child: stamp),
      ],
    );
  }
}

class MessageReaction extends StatelessWidget {
  const MessageReaction({
    super.key,
    required this.emoji,
    required this.index,
    required this.out,
    required this.onTap,
  });
  final String emoji;
  final int index;
  final bool out;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: out ? Alignment.topRight : Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .9, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: emoji.isEmpty
            ? const SizedBox.shrink()
            : Transform.translate(
                key: ValueKey(emoji),
                offset: const Offset(0, -3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Semantics(
                    button: true,
                    label: 'Reaction $emoji. View or remove reaction',
                    child: GestureDetector(
                      key: ValueKey('message-reaction-$index'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: T.paper, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: T.ink.withValues(alpha: .06),
                              blurRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          emoji,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(fontSize: 15, height: 1.15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

typedef MessageAction = (String value, String label, IconData icon);

Future<String?> showMessageActions({
  required BuildContext context,
  required Message message,
  required Rect? anchor,
  required bool first,
  required bool starred,
  required String reaction,
  required List<MessageAction> actions,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss message actions',
  barrierColor: T.ink.withValues(alpha: .24),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 130),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (dialog, _, _) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(dialog).bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final origin = Offset(0, MediaQuery.paddingOf(dialog).top);
          final localAnchor =
              (anchor ?? Rect.fromLTWH(16, constraints.maxHeight / 3, 220, 60))
                  .shift(-origin);
          return CustomMultiChildLayout(
            delegate: _MessageActionsLayout(
              anchor: localAnchor,
              out: message.out,
            ),
            children: [
              LayoutId(
                id: 'reactions',
                child: Material(
                  key: const ValueKey('message-reaction-picker'),
                  color: Colors.white,
                  elevation: 5,
                  shadowColor: T.ink.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(32),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      children: [
                        for (final emoji in [
                          '👍',
                          '🤍',
                          '😊',
                          '😂',
                          '😮',
                          '🙏',
                        ])
                          Expanded(
                            child: Tooltip(
                              message: 'React with $emoji',
                              child: Semantics(
                                selected: reaction == emoji,
                                button: true,
                                child: InkResponse(
                                  onTap: () =>
                                      Navigator.pop(dialog, 'emoji:$emoji'),
                                  radius: 22,
                                  child: Container(
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: reaction == emoji
                                          ? T.selected
                                          : null,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      emoji,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: AppIconButton(
                            tooltip: 'More reactions',
                            padding: EdgeInsets.zero,
                            onPressed: () =>
                                Navigator.pop(dialog, 'more-reactions'),
                            icon: const AppIcon(
                              Icons.add,
                              size: 23,
                              color: T.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              LayoutId(
                id: 'preview',
                child: SingleChildScrollView(
                  key: const ValueKey('selected-message-preview'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: MessageBubble(
                        message: message,
                        first: first,
                        starred: starred,
                        maxWidth: math.min(
                          localAnchor.width,
                          math.max(1, constraints.maxWidth - 38),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              LayoutId(
                id: 'actions',
                child: Material(
                  key: const ValueKey('message-action-menu'),
                  color: Colors.white,
                  elevation: 5,
                  shadowColor: T.ink.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(
                    isCupertino(context) ? 14 : 16,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < actions.length;
                          index++
                        ) ...[
                          if (index > 0 &&
                              (isCupertino(context) ||
                                  actions[index].$1 == 'delete'))
                            const Divider(height: 1, thickness: .5),
                          _MessageActionTile(
                            action: actions[index],
                            onTap: () =>
                                Navigator.pop(dialog, actions[index].$1),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  ),
);

class _MessageActionTile extends StatelessWidget {
  const _MessageActionTile({required this.action, required this.onTap});
  final MessageAction action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final apple = isCupertino(context);
    final color = action.$1 == 'delete' ? T.danger : T.ink;
    final icon = AppIcon(action.$3, size: 20, color: color);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (!apple) ...[icon, const SizedBox(width: 14)],
              Expanded(
                child: Text(
                  action.$2,
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ),
              if (apple) ...[const SizedBox(width: 14), icon],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fit all three surfaces into the available viewport. A very long selected
/// message scrolls independently so its actions remain reachable above a keyboard.
class _MessageActionsLayout extends MultiChildLayoutDelegate {
  _MessageActionsLayout({required this.anchor, required this.out});
  final Rect anchor;
  final bool out;
  @override
  void performLayout(Size size) {
    final width = math.max(0.0, size.width - 24);
    final height = math.max(0.0, size.height - 24);
    final reactions = layoutChild(
      'reactions',
      BoxConstraints(
        minWidth: math.min(width, 320),
        maxWidth: math.min(width, 320),
        maxHeight: math.min(56, height),
      ),
    );
    final actions = layoutChild(
      'actions',
      BoxConstraints(
        minWidth: math.min(width, 250),
        maxWidth: math.min(width, 250),
        maxHeight: math.max(
          0,
          math.min(height * .54, height - reactions.height - 56),
        ),
      ),
    );
    final preview = layoutChild(
      'preview',
      BoxConstraints(
        minWidth: math.min(width, anchor.width + 14),
        maxWidth: math.min(width, anchor.width + 14),
        maxHeight: math.max(0, height - reactions.height - actions.height - 16),
      ),
    );
    final totalHeight = reactions.height + preview.height + actions.height + 16;
    final top = (anchor.top - reactions.height - 8)
        .clamp(12.0, math.max(12.0, size.height - totalHeight - 12))
        .toDouble();
    double left(double childWidth, {bool preview = false}) =>
        (out
                ? anchor.right + (preview ? 7 : 0) - childWidth
                : anchor.left - (preview ? 7 : 0))
            .clamp(12.0, math.max(12.0, size.width - childWidth - 12));
    positionChild('reactions', Offset(left(reactions.width), top));
    positionChild(
      'preview',
      Offset(left(preview.width, preview: true), top + reactions.height + 8),
    );
    positionChild(
      'actions',
      Offset(left(actions.width), top + reactions.height + preview.height + 16),
    );
  }

  @override
  bool shouldRelayout(_MessageActionsLayout oldDelegate) =>
      anchor != oldDelegate.anchor || out != oldDelegate.out;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.first = false,
    this.starred = false,
    this.maxWidth = 320,
  });
  final Message message;
  final bool first, starred;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = m.out ? T.outgoing : Colors.white;
    final media = m.type != 'text';
    final width = media ? math.min(maxWidth, 280.0) : maxWidth;
    final emojiCount = m.type == 'text' && m.reply == null
        ? _emojiCount(m.text)
        : 0;
    return CustomPaint(
      painter: first ? _BubbleTail(m.out, color) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: width),
        padding: EdgeInsets.fromLTRB(
          m.type == 'image' || m.type == 'order' ? 4 : 9,
          m.type == 'image' || m.type == 'order' ? 4 : 5,
          m.type == 'image' || m.type == 'order' ? 4 : 8,
          6,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(first && !m.out ? 2 : 9),
            topRight: Radius.circular(first && m.out ? 2 : 9),
            bottomLeft: const Radius.circular(9),
            bottomRight: const Radius.circular(9),
          ),
          boxShadow: [
            BoxShadow(
              color: T.ink.withValues(alpha: .08),
              offset: const Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.reply != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: T.green.withValues(alpha: .07),
                  border: const Border(
                    left: BorderSide(color: T.green, width: 3),
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.replyAuthor ?? 'Reply',
                      style: const TextStyle(
                        color: T.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.reply!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: T.secondary),
                    ),
                  ],
                ),
              ),
            if (m.type == 'image' || m.type == 'order') ...[
              SizedBox(
                width: width - 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: const SizedBox(
                    height: 122,
                    child: ProductArt(icon: Icons.shopping_bag_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (m.type == 'document')
              Container(
                padding: const EdgeInsets.all(9),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: T.green.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon(
                      Icons.description_outlined,
                      color: T.brass,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.text,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'PDF · 248 KB',
                            style: TextStyle(fontSize: 9, color: T.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const AppIcon(
                      Icons.download_rounded,
                      size: 20,
                      color: T.brass,
                    ),
                  ],
                ),
              ),
            if (m.type == 'audio')
              SizedBox(
                width: width - 17,
                child: Row(
                  children: [
                    const AppIcon(
                      Icons.play_arrow_rounded,
                      color: T.green,
                      size: 30,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: SizedBox(height: 32, child: VoiceWave()),
                    ),
                    const SizedBox(width: 8),
                    Text('0:12', style: mono(size: 9)),
                  ],
                ),
              ),
            if (m.type == 'location')
              Container(
                height: 88,
                width: width - 17,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: T.selected,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: AppIcon(Icons.location_on, color: T.green, size: 32),
                ),
              ),
            _MessageText(
              message: m,
              starred: starred,
              emojiCount: emojiCount,
              metadataOnly: m.type == 'document' || m.type == 'audio',
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  _BubbleTail(this.out, this.color);
  final bool out;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final x = out ? size.width - 2 : 2.0;
    final direction = out ? 1.0 : -1.0;
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x + 7 * direction, 0)
        ..quadraticBezierTo(x + 8 * direction, 0, x + 5 * direction, 4)
        ..lineTo(x, 10)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTail old) =>
      old.out != out || old.color != color;
}

class VoiceWave extends StatelessWidget {
  const VoiceWave({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < (size.maxWidth / 7).floor().clamp(5, 45); i++)
          Container(
            width: 3,
            height: (8 + (i * 17 % 27)).toDouble(),
            decoration: BoxDecoration(
              color: i < 7 ? T.green : T.brass.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
      ],
    ),
  );
}

class ProductArt extends StatelessWidget {
  const ProductArt({
    super.key,
    required this.icon,
    this.color = T.paper,
    this.small = false,
  });
  final IconData icon;
  final Color color;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
    height: small ? 52 : 160,
    width: small ? 52 : double.infinity,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(small ? 9 : 14),
    ),
    alignment: Alignment.center,
    child: AppIcon(
      icon,
      size: small ? 30 : 76,
      color: T.brass.withValues(alpha: .8),
    ),
  );
}
