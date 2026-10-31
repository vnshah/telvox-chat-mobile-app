import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'media.dart';
import 'models.dart';
import 'screens.dart' show mobileNotice;

/// The three kinds of shared content, each a tab of [MediaGalleryPage].
enum SharedKind {
  media('media', 'Media'),
  documents('document', 'Documents'),
  links('link', 'Links');

  const SharedKind(this.query, this.label);

  /// The `type` the media endpoints filter by.
  final String query;
  final String label;
}

/// Media, documents and links shared in one conversation, as WhatsApp lays
/// them out: a month-grouped photo grid, a file list, and link rows. Opened
/// from Contact Details (or a ticket) at the chosen tab; back returns there.
/// Each tab loads once and keeps its rows while the page is open.
class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage(
    this.session, {
    super.key,
    this.contactId,
    this.ticketId,
    this.initial = SharedKind.media,
  });
  final MobileSession session;
  final int? contactId, ticketId;
  final SharedKind initial;
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  late SharedKind kind = widget.initial;
  final rowsByKind = <SharedKind, List<Json>>{};
  final errors = <SharedKind, String>{};
  final loading = <SharedKind>{};

  @override
  void initState() {
    super.initState();
    load(kind);
  }

  Future<void> load(SharedKind k) async {
    if (loading.contains(k)) return;
    setState(() {
      loading.add(k);
      errors.remove(k);
    });
    try {
      final r = widget.ticketId == null
          ? await widget.session.api.post('inbox/getMediaData', {
              'contact_id': widget.contactId,
              'type': k.query,
            })
          : await widget.session.api.post(
              'inbox/tickets/${widget.ticketId}/media-data',
              {'type': k.query},
            );
      final list = rows(r['data'])
        ..sort(
          (a, b) =>
              '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'),
        );
      if (mounted) setState(() => rowsByKind[k] = list);
    } catch (e) {
      if (mounted) setState(() => errors[k] = '$e');
    } finally {
      if (mounted) setState(() => loading.remove(k));
    }
  }

  void select(SharedKind k) {
    setState(() => kind = k);
    if (!rowsByKind.containsKey(k)) load(k);
  }

  String get apiBase => widget.session.api.dio.options.baseUrl;

  @override
  Widget build(BuildContext context) {
    final ios = isCupertino(context);
    final switcher = ios
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<SharedKind>(
                groupValue: kind,
                onValueChanged: (k) => k == null ? null : select(k),
                children: {
                  for (final k in SharedKind.values)
                    k: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        k.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                },
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<SharedKind>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  for (final k in SharedKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {kind},
                onSelectionChanged: (s) => select(s.first),
              ),
            ),
          );
    return Scaffold(
      backgroundColor: ios ? T.iosGrouped : T.wash,
      appBar: platformAppBar(context, title: Text(kind.label)),
      body: Column(
        children: [
          switcher,
          SizedBox(
            height: 2,
            child: loading.contains(kind) && rowsByKind.containsKey(kind)
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(child: body()),
        ],
      ),
    );
  }

  Widget body() {
    final list = rowsByKind[kind];
    if (list == null) {
      final error = errors[kind];
      return error != null
          ? _Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load ${kind.label.toLowerCase()}',
              message: error,
              action: TextButton(
                onPressed: () => load(kind),
                child: const Text('Try again'),
              ),
            )
          : const Center(child: CircularProgressIndicator.adaptive());
    }
    if (list.isEmpty) {
      return switch (kind) {
        SharedKind.media => const _Empty(
          icon: Icons.photo_library_outlined,
          title: 'No media yet',
          message: 'Photos and videos shared in this chat appear here.',
        ),
        SharedKind.documents => const _Empty(
          icon: Icons.description_outlined,
          title: 'No documents yet',
          message: 'Files shared in this chat appear here.',
        ),
        SharedKind.links => const _Empty(
          icon: Icons.link,
          title: 'No links yet',
          message: 'Links shared in this chat appear here.',
        ),
      };
    }
    final groups = _byMonth(list);
    return RefreshIndicator(
      onRefresh: () => load(kind),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(child: _MonthHeader(group.$1)),
            switch (kind) {
              SharedKind.media => _grid(group.$2),
              SharedKind.documents => _card([
                for (final item in group.$2) _DocumentRow(item, apiBase),
              ]),
              SharedKind.links => _card([
                for (final item in group.$2) _LinkRow(item),
              ]),
            },
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// Square thumbnails, three across on a phone and more on wider screens.
  Widget _grid(List<Json> items) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _MediaThumb(items[i], apiBase),
        childCount: items.length,
      ),
    ),
  );

  /// Rows on the same card surface as the Contact Details sections.
  Widget _card(List<Widget> rows) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverToBoxAdapter(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isCupertino(context) ? Colors.white : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: isCupertino(context) ? null : Border.all(color: T.edge),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 64, color: T.edge),
              rows[i],
            ],
          ],
        ),
      ),
    ),
  );
}

/// Newest month first, as WhatsApp groups shared media.
List<(String, List<Json>)> _byMonth(List<Json> items) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];
  final now = DateTime.now();
  final groups = <String, List<Json>>{};
  for (final item in items) {
    final date = const MobileClock().local(item['created_at']);
    final label = date == null
        ? 'Earlier'
        : date.year == now.year && date.month == now.month
        ? 'This month'
        : date.year == now.year
        ? months[date.month - 1]
        : '${months[date.month - 1]} ${date.year}';
    groups.putIfAbsent(label, () => []).add(item);
  }
  return [for (final e in groups.entries) (e.key, e.value)];
}

String _shortDate(Object? raw) {
  final date = const MobileClock().local(raw);
  if (date == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Text(
      isCupertino(context) ? label.toUpperCase() : label,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .2,
        color: T.brass,
      ),
    ),
  );
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb(this.item, this.apiBase);
  final Json item;
  final String apiBase;
  @override
  Widget build(BuildContext context) {
    final url = mediaUri(item['media_link'], apiBase);
    final video = '${item['type']}' == 'video';
    final size = (MediaQuery.devicePixelRatioOf(context) * 132).round();
    return Semantics(
      button: true,
      label: video ? 'Video' : 'Photo',
      child: GestureDetector(
        onTap: url == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaViewer(
                    MessageMedia(
                      '${item['type']}',
                      url,
                      '${item['media_name'] ?? 'Media'}',
                    ),
                  ),
                ),
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ColoredBox(
            color: T.surfaceHigh,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!video && url != null)
                  Image.network(
                    url.toString(),
                    fit: BoxFit.cover,
                    cacheWidth: size,
                    errorBuilder: (_, _, _) => const Center(
                      child: AppIcon(
                        Icons.broken_image_outlined,
                        color: T.muted,
                      ),
                    ),
                  )
                else
                  const Center(
                    child: AppIcon(
                      Icons.videocam_outlined,
                      size: 28,
                      color: T.muted,
                    ),
                  ),
                if (video)
                  const Positioned(
                    left: 6,
                    bottom: 5,
                    child: AppIcon(
                      Icons.play_circle_fill_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A coloured square with the file's extension, as a file manager shows it.
class _FileBadge extends StatelessWidget {
  const _FileBadge(this.extension);
  final String extension;
  @override
  Widget build(BuildContext context) {
    final colour = switch (extension) {
      'PDF' => const Color(0xFFB3412F),
      'DOC' || 'DOCX' => const Color(0xFF2F5FA8),
      'XLS' || 'XLSX' || 'CSV' => T.green,
      'PPT' || 'PPTX' => const Color(0xFFC26A1E),
      _ => T.brass,
    };
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: extension.isEmpty
          ? AppIcon(Icons.description_outlined, color: colour, size: 20)
          : Text(
              extension.length > 4 ? extension.substring(0, 4) : extension,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .3,
                color: colour,
              ),
            ),
    );
  }
}

Future<void> _copy(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) mobileNotice(context, '$what copied');
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow(this.item, this.apiBase);
  final Json item;
  final String apiBase;
  @override
  Widget build(BuildContext context) {
    final name = '${item['media_name'] ?? 'Document'}';
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : '';
    final size = '${item['media_size'] ?? ''}';
    final meta = [
      if (extension.isNotEmpty) extension,
      if (size.isNotEmpty && size != 'UNKNOWN') size,
      _shortDate(item['created_at']),
    ].where((p) => p.isNotEmpty).join(' · ');
    final url = mediaUri(item['media_link'], apiBase);
    void open() => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewer(MessageMedia('document', url!, name)),
      ),
    );
    return _Row(
      leading: _FileBadge(extension),
      title: name,
      subtitle: meta,
      onTap: url == null ? null : open,
      menu: {
        if (url != null) 'Open': open,
        if (url != null)
          'Copy link': () => _copy(context, url.toString(), 'Link'),
      },
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(this.item);
  final Json item;
  // A full URL, www. address, or bare domain with an optional path; not the
  // domain half of an email address.
  static final _url = RegExp(
    r'''(?:https?://|www\.)[^\s<>"']+|(?<![@\w.])[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}(?:/[^\s<>"']*)?''',
    caseSensitive: false,
  );
  @override
  Widget build(BuildContext context) {
    final text = '${item['media_link'] ?? item['media_name'] ?? ''}'.trim();
    final match = _url.firstMatch(text)?.group(0);
    final raw = (match ?? text).replaceAll(RegExp(r'[).,;!?]+$'), '');
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    final host = (uri?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
    final note = text == match || text == raw ? '' : text;
    Future<void> open() async {
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          mobileNotice(context, 'No app could open this link.');
        }
      }
    }

    return _Row(
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: T.greenWash,
          borderRadius: BorderRadius.circular(9),
        ),
        child: host.isEmpty
            ? const AppIcon(Icons.link, color: T.green, size: 20)
            : Text(
                host[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: T.green,
                ),
              ),
      ),
      title: host.isEmpty ? raw : host,
      subtitle: raw,
      detail: note,
      trailingText: _shortDate(item['created_at']),
      onTap: open,
      menu: {
        'Open': open,
        'Copy link': () => _copy(context, uri?.toString() ?? raw, 'Link'),
      },
    );
  }
}

/// One compact row: badge, two lines, optional context line, and the
/// row's actions behind a long-press menu (and ⋮ on Android).
class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.menu,
    this.detail = '',
    this.trailingText = '',
  });
  final Widget leading;
  final String title, subtitle, detail, trailingText;
  final VoidCallback? onTap;
  final Map<String, VoidCallback> menu;

  Future<void> showMenuSheet(BuildContext context) async {
    if (menu.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in menu.keys)
              ListTile(
                leading: AppIcon(
                  label == 'Open' ? Icons.open_in_new : Icons.copy_rounded,
                ),
                title: Text(label),
                onTap: () => Navigator.pop(sheet, label),
              ),
          ],
        ),
      ),
    );
    if (choice != null) menu[choice]?.call();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: () => showMenuSheet(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: T.ink,
                        ),
                      ),
                    ),
                    if (trailingText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          trailingText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: T.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: T.muted),
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: T.secondary,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isCupertino(context))
            const SizedBox(width: 8)
          else
            IconButton(
              tooltip: 'More options',
              visualDensity: VisualDensity.compact,
              onPressed: () => showMenuSheet(context),
              icon: const Icon(Icons.more_vert, size: 20, color: T.muted),
            ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: T.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: AppIcon(icon, size: 28, color: T.brass),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: T.muted,
              height: 1.35,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    ),
  );
}
