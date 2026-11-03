import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';

/// One measured moment: a request (its path, time, status and size), or a
/// chat milestone (opened, shown from the phone, up to date).
class PerfEntry {
  PerfEntry(this.kind, this.label, this.ms, {this.detail = ''})
    : at = DateTime.now();
  final DateTime at;

  /// `request`, `open`, `shown`, `current` or `sync`.
  final String kind;
  final String label;
  final int ms;
  final String detail;

  @override
  String toString() =>
      '${at.toIso8601String().substring(11, 23)} $kind $label ${ms}ms $detail'
          .trim();
}

/// What the app spends its time on, measured on the phone itself: every
/// request to the server, and for each chat how long until it showed the
/// phone's copy and until it was up to date. Kept in memory (the last 400
/// entries) and shown under Performance log, to copy into a report.
class PerfLog {
  PerfLog._();
  static final entries = ListQueue<PerfEntry>();
  static final changes = ValueNotifier<int>(0);
  static const _keep = 400;

  static void add(PerfEntry e) {
    entries.addLast(e);
    while (entries.length > _keep) {
      entries.removeFirst();
    }
    changes.value++;
  }

  static void request(String path, int ms, int status, int bytes) => add(
    PerfEntry(
      'request',
      path,
      ms,
      detail: '$status ${(bytes / 1024).toStringAsFixed(1)}KB',
    ),
  );

  /// A chat's milestone, timed from when it was opened.
  static void chat(String kind, String chat, Stopwatch since, [String? note]) =>
      add(PerfEntry(kind, chat, since.elapsedMilliseconds, detail: note ?? ''));

  static void clear() {
    entries.clear();
    changes.value++;
  }

  /// Median and slowest per request path and per chat milestone.
  static List<(String, int, int, int)> summary() {
    final groups = <String, List<int>>{};
    for (final e in entries) {
      final key = e.kind == 'request' ? e.label : '${e.kind} (chat)';
      groups.putIfAbsent(key, () => []).add(e.ms);
    }
    return [
      for (final g in groups.entries)
        () {
          final ms = [...g.value]..sort();
          return (g.key, ms.length, ms[ms.length ~/ 2], ms.reduce(math.max));
        }(),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
  }

  static String report() => [
    'Telvox Chat performance log',
    for (final (label, n, median, slowest) in summary())
      '$label: n=$n median=${median}ms slowest=${slowest}ms',
    '',
    for (final e in entries) '$e',
  ].join('\n');
}

class PerfLogPage extends StatelessWidget {
  const PerfLogPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Performance log'),
      actions: [
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: PerfLog.report()));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied')));
            }
          },
        ),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: PerfLog.clear,
        ),
      ],
    ),
    body: ValueListenableBuilder(
      valueListenable: PerfLog.changes,
      builder: (context, _, _) {
        final summary = PerfLog.summary();
        final lines = PerfLog.entries.toList().reversed.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Median and slowest, by request and chat step',
              style: TextStyle(fontWeight: FontWeight.w600, color: T.secondary),
            ),
            const SizedBox(height: 6),
            for (final (label, n, median, slowest) in summary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '×$n  ${median}ms  max ${slowest}ms',
                      style: const TextStyle(fontSize: 13, color: T.muted),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            for (final e in lines)
              Text(
                '$e',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: T.ink,
                ),
              ),
          ],
        );
      },
    ),
  );
}
