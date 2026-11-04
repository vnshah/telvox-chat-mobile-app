import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import 'connection.dart';

/// A slim bar across the top while the server cannot be reached, as
/// WhatsApp shows "Waiting for network": the app stays usable beneath it,
/// so chats and media already on the phone can still be read and played.
/// Back online it turns green for a moment, then slides away. Tap it to
/// check again at once.
class OfflineBar extends StatefulWidget {
  const OfflineBar(this.connection, {super.key, required this.child});
  final ConnectionMonitor connection;

  /// The app, below the bar: it moves down while the bar shows.
  final Widget child;

  /// How long "Back online" stays before the bar goes.
  static const backFor = Duration(seconds: 2);

  @override
  State<OfflineBar> createState() => _OfflineBarState();
}

enum _Bar { hidden, offline, back }

class _OfflineBarState extends State<OfflineBar> {
  late _Bar bar = widget.connection.online ? _Bar.hidden : _Bar.offline;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_changed);
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.connection.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    _hide?.cancel();
    if (!widget.connection.online) {
      setState(() => bar = _Bar.offline);
    } else if (bar == _Bar.offline) {
      setState(() => bar = _Bar.back);
      _hide = Timer(OfflineBar.backFor, () {
        if (mounted) setState(() => bar = _Bar.hidden);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = bar != _Bar.hidden;
    final strip = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !shown ? const SizedBox(width: double.infinity) : _strip(context),
    );
    return Column(
      children: [
        strip,
        Expanded(
          // The bar takes the status bar's place; the app starts below it.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: shown,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Widget _strip(BuildContext context) {
    final back = bar == _Bar.back;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        key: const ValueKey('offline-bar'),
        color: back ? T.green : const Color(0xFF3B4A54),
        child: InkWell(
          onTap: back ? null : widget.connection.check,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              height: 30,
              child: Semantics(
                liveRegion: true,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Row(
                    key: ValueKey(bar),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: back
                        ? const [
                            Icon(
                              Icons.wifi_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Back online',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ]
                        : const [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'No internet connection',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              ' · Waiting for network…',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
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
