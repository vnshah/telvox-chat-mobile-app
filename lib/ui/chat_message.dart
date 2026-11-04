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
    final stamp = MessageStamp(message, starred: starred);
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

/// The time and delivery ticks in a bubble's corner. Public so content that
/// lays out its own last line (a voice note, a call) can place it there, as
/// WhatsApp does, instead of on a row of its own.
class MessageStamp extends StatelessWidget {
  const MessageStamp(this.message, {super.key, this.starred = false});
  final Message message;
  final bool starred;
  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 10.5,
      height: 1.15,
      fontWeight: FontWeight.w400,
      color: T.muted,
    );
    return Row(
      key: const ValueKey('message-receipt'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred)
          const Padding(
            padding: EdgeInsets.only(right: 3),
            child: AppIcon(Icons.star_rounded, size: 10, color: T.brass),
          ),
        Text(message.time == 'Now' ? 'now' : message.time, style: style),
        if (message.out)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: AppIcon(
              switch (message.deliveryStatus) {
                0 => Icons.schedule,
                2 || 3 => Icons.done_all,
                4 || 5 => Icons.error_outline,
                _ => message.read ? Icons.done_all : Icons.check,
              },
              size: 15,
              color: message.read ? T.blue : T.muted,
              semanticLabel: message.read ? 'Read' : 'Sent',
            ),
          ),
      ],
    );
  }
}

/// What tapping a bubble's reply quote does: shows the quoted message.
/// Given above a bubble by the chat; without it a quote is not tappable.
class ReplyTap extends InheritedWidget {
  const ReplyTap({super.key, required this.onTap, required super.child});
  final VoidCallback? onTap;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReplyTap>()?.onTap;

  @override
  bool updateShouldNotify(ReplyTap old) => old.onTap != onTap;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.first = false,
    this.starred = false,
    this.maxWidth = 320,
    this.contentBefore,
    this.contentAfter,
    this.tight = false,
    this.showStamp = true,
    this.footer,
  });
  final Message message;
  final Widget? contentBefore, contentAfter;

  /// Under the time, the bubble's full width: WhatsApp's reply buttons.
  final Widget? footer;

  /// Media fills the bubble with a thin margin, as WhatsApp frames photos.
  final bool tight;

  /// False when the media draws the time over itself instead.
  final bool showStamp;
  final bool first, starred;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = m.out ? T.outgoing : T.incoming;
    final media = m.type != 'text';
    final width = media ? math.min(maxWidth, 280.0) : maxWidth;
    final emojiCount = m.type == 'text' && m.reply == null
        ? _emojiCount(m.text)
        : 0;
    final framed = tight || m.type == 'image' || m.type == 'order';
    final metadataOnly =
        contentAfter != null ||
        (contentBefore != null && m.text.isEmpty) ||
        m.type == 'document' ||
        m.type == 'audio';
    Widget body = _MessageText(
      message: m,
      starred: starred,
      emojiCount: emojiCount,
      metadataOnly: metadataOnly,
    );
    if (tight) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(6, m.text.isEmpty ? 2 : 5, 5, 2),
        child: body,
      );
    }
    final inset = EdgeInsets.fromLTRB(
      framed ? 3 : 9,
      framed ? 3 : 5,
      framed ? 3 : 8,
      framed ? 3 : 6,
    );
    return CustomPaint(
      painter: first ? _BubbleTail(m.out, color) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: width),
        padding: footer == null ? inset : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(first && !m.out ? 2 : 9),
            topRight: Radius.circular(first && m.out ? 2 : 9),
            bottomLeft: const Radius.circular(9),
            bottomRight: const Radius.circular(9),
          ),
          boxShadow: T.bubbleShadow,
        ),
        child: _withFooter(
          inset,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.reply != null)
                GestureDetector(
                  // Tapping a quote shows the message it quotes, as on WhatsApp.
                  onTap: ReplyTap.of(context),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: T.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ?contentBefore,
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
              if (contentAfter != null)
                // Framed tight around a photo, the words keep their margin.
                Padding(
                  padding: tight
                      ? const EdgeInsets.fromLTRB(6, 5, 5, 0)
                      : EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.text.isNotEmpty)
                        Text(
                          m.text,
                          style: const TextStyle(fontSize: 15, height: 1.3),
                        ),
                      contentAfter!,
                    ],
                  ),
                ),
              if (showStamp || !metadataOnly) body,
            ],
          ),
        ),
      ),
    );
  }

  /// The content in its usual inset, with the footer across the full width
  /// under it; without a footer, the content as it is (the inset is the
  /// bubble's own padding then).
  Widget _withFooter(EdgeInsets inset, Widget content) => footer == null
      ? content
      : IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: inset, child: content),
              footer!,
            ],
          ),
        );
}

/// WhatsApp's buttons under a message: full width, a hairline above each,
/// the label centred with its icon. They show what the customer can tap.
class BubbleButtons extends StatelessWidget {
  const BubbleButtons(this.buttons, {super.key, this.iconAfter = false});
  final List<(IconData?, String)> buttons;

  /// The icon follows the label, as a dropdown's arrow does.
  final bool iconAfter;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (icon, label) in buttons)
        Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: T.edge)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null && !iconAfter)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(icon, size: 18, color: T.green),
                ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: T.green,
                  ),
                ),
              ),
              if (icon != null && iconAfter)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(icon, size: 18, color: T.green),
                ),
            ],
          ),
        ),
    ],
  );
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
