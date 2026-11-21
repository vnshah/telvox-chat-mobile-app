import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'boot_screen.dart' show TelvoxMark;

/// Where to get the update, as the server's update policy names them: on
/// Android, Google Play and/or a direct APK download; on iPhone, the App Store.
List<({String label, String url, bool primary})> updateLinks(Json update) {
  String? link(String key) {
    final url = '${update[key] ?? ''}'.trim();
    return url.isEmpty ? null : url;
  }

  final ios = update['platform'] == 'ios';
  final store = link(ios ? 'app_store_url' : 'play_store_url');
  final apk = ios ? null : link('apk_url');
  return [
    if (store != null)
      (
        label: ios ? 'Update on the App Store' : 'Update on Google Play',
        url: store,
        primary: true,
      ),
    if (apk != null)
      (label: 'Download the update (APK)', url: apk, primary: store == null),
  ];
}

/// Opens an update link outside the app: the store app, or the browser for
/// an APK, which then offers to install it.
Future<bool> openUpdateLink(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// The whole app while this build is too old to be used: the server refuses
/// it (426) until it is updated, so nothing behind this page would work. No
/// way past it but updating; "Check again" asks the server once more, for
/// when the update is installed or the requirement was lifted.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.update,
    required this.checkAgain,
  });
  final Json update;
  final Future<void> Function() checkAgain;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool checking = false;
  String? problem;

  Future<void> open(String url) async {
    setState(() => problem = null);
    if (!await openUpdateLink(url) && mounted) {
      setState(() => problem = 'No app on this phone could open $url.');
    }
  }

  Future<void> check() async {
    setState(() => checking = true);
    try {
      await widget.checkAgain();
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = '${widget.update['message'] ?? ''}'.trim();
    final links = updateLinks(widget.update);
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: CustomPaint(
                          size: Size.square(104),
                          painter: TelvoxMark(width: 92),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Update Telvox Chat',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: T.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message.isNotEmpty
                            ? message
                            : 'This version of the app is no longer '
                                  'supported. Update to the latest version '
                                  'to keep using Telvox Chat.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: T.secondary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      for (final link in links) ...[
                        link.primary
                            ? FilledButton(
                                onPressed: () => open(link.url),
                                child: Text(link.label),
                              )
                            : OutlinedButton(
                                onPressed: () => open(link.url),
                                child: Text(link.label),
                              ),
                        const SizedBox(height: 10),
                      ],
                      if (links.isEmpty)
                        const Text(
                          'Ask your administrator for the new version.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: T.muted, fontSize: 14),
                        ),
                      if (problem != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          problem!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: T.danger, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: checking ? null : check,
                        child: Text(checking ? 'Checking…' : 'Check again'),
                      ),
                      if (widget.update['current_build'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'This app is build ${widget.update['current_build']}'
                            '${widget.update['min_build'] == null ? '' : ' · build ${widget.update['min_build']} or newer is needed'}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: T.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
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

/// A slim bar across the top when a newer build is out but this one still
/// works: "New version available · Update", with a close button that hides
/// it until a newer build than the one dismissed is offered.
class UpdateOfferBar extends StatefulWidget {
  const UpdateOfferBar(this.offered, {super.key, required this.child});
  final ValueListenable<Json?> offered;
  final Widget child;

  @override
  State<UpdateOfferBar> createState() => _UpdateOfferBarState();
}

class _UpdateOfferBarState extends State<UpdateOfferBar> {
  Object? dismissed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Json?>(
    valueListenable: widget.offered,
    builder: (context, offer, _) {
      final links = offer == null ? const [] : updateLinks(offer);
      final shown =
          offer != null &&
          links.isNotEmpty &&
          dismissed != offer['latest_build'];
      return Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !shown
                ? const SizedBox(width: double.infinity)
                : _strip(offer, links.first.url),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: shown,
              child: widget.child,
            ),
          ),
        ],
      );
    },
  );

  Widget _strip(Json offer, String url) =>
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          key: const ValueKey('update-bar'),
          color: T.forest,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.system_update_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'New version available',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: T.mint,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => openUpdateLink(url),
                    child: const Text('Update'),
                  ),
                  // No tooltip: the bar sits above the app's navigator, so
                  // there is no overlay here for one to show in.
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: Colors.white,
                    onPressed: () =>
                        setState(() => dismissed = offer['latest_build']),
                    icon: const Icon(
                      Icons.close_rounded,
                      semanticLabel: 'Not now',
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      );
}
