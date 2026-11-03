import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';
import 'call_push.dart';
import 'local_cache.dart';
import 'models.dart';
import 'perf_log.dart';

/// Keeps the phone's copy of the busiest chats current before they are
/// opened, as WhatsApp's own database is: when the inbox list loads (start,
/// return to the app, a refresh) and when a push says a chat moved, the chats
/// that changed since the phone last synced them are fetched in the
/// background and saved. Opening one then shows what is new at once, from
/// the phone, instead of the old copy followed by the server's answer.
class ConversationSync {
  ConversationSync(this.session);
  final MobileSession session;

  /// The newest chats in the list are kept current, two fetched at a time;
  /// of those never opened on this phone, only the first few are fetched.
  static const chats = 8, uncached = 5, parallel = 2;

  /// A chat synced this recently is not fetched again.
  static const quiet = Duration(seconds: 20);

  final _running = <String>{};
  final _synced = <String, DateTime>{};
  final _queue = <(int, String)>[];
  int _active = 0;

  static String keyFor(int? waba, Object? contactId) =>
      'chat:$waba:$contactId:null';

  /// The server answered that it has no account-wide sync (an older
  /// version): chats are then synced one by one, as before.
  static bool accountSyncMissing = false;

  /// Older than this, a saved chat is fetched afresh rather than caught up.
  static const catchUpLimit = Duration(days: 3);

  /// The inbox list just loaded these rows (newest first).
  Future<void> prefetch(List<Json> contacts) async {
    final waba = session.api.wabaId;
    if (waba == null || !session.signedIn) return;
    var fresh = 0;
    // Saved chats that moved since their sync, with where each left off.
    final behind = <int, Json>{};
    for (final contact in contacts.take(chats)) {
      final id = number(contact['id']);
      if (id == null) continue;
      final key = keyFor(waba, id);
      if (session.visibleContacts.contains('contact:$id')) continue;
      Json? cursor;
      try {
        cursor = await session.cache.cursor(key);
      } catch (_) {}
      if (cursor == null) {
        if (++fresh <= uncached) _enqueue(id, key);
        continue;
      }
      final synced = DateTime.tryParse('${cursor['synced_at'] ?? ''}');
      final moved = MobileClock.instant(contact['last_message_date']);
      if (synced != null && (moved == null || !moved.isAfter(synced))) {
        continue;
      }
      final since = DateTime.tryParse('${cursor['sync'] ?? ''}');
      if (since == null ||
          DateTime.now().toUtc().difference(since) > catchUpLimit ||
          accountSyncMissing) {
        _enqueue(id, key);
      } else {
        behind[id] = cursor;
      }
    }
    if (behind.isNotEmpty) await _catchUp(waba, behind);
  }

  /// Every chat in [behind] caught up in one request (POST inbox/sync, paged
  /// by cursor), from the earliest point any of them left off: new messages
  /// saved whole, ticks and reactions patched onto the saved rows.
  Future<void> _catchUp(int waba, Map<int, Json> behind) async {
    final clock = Stopwatch()..start();
    var since = behind.values
        .map((c) => '${c['sync']}')
        .reduce(
          (a, b) => DateTime.parse(a).isBefore(DateTime.parse(b)) ? a : b,
        );
    int? after;
    final created = <int, List<Json>>{};
    final changed = <int, List<Json>>{};
    var pages = 0;
    try {
      while (true) {
        final result = await session.api.post('inbox/sync', {
          'contact_ids': behind.keys.toList(),
          'since': since,
          'after_id': ?after,
        });
        pages++;
        final data = object(result['data']);
        for (final m in rows(data['messages'])) {
          created
              .putIfAbsent(number(m['contact_master_id']) ?? 0, () => [])
              .add(m);
        }
        for (final c in rows(data['changes'])) {
          changed
              .putIfAbsent(number(c['contact_master_id']) ?? 0, () => [])
              .add(c);
        }
        final meta = object(result['meta']);
        since = '${meta['sync_from']}';
        after = number(meta['sync_after_id']);
        if (meta['has_more'] != true || pages >= 10) break;
      }
    } on ApiFailure catch (e) {
      if (e.httpStatus == 404) accountSyncMissing = true;
      // One by one instead, as an older server needs.
      for (final id in behind.keys) {
        _enqueue(id, keyFor(waba, id));
      }
      return;
    }
    if (session.api.wabaId != waba) return;
    for (final entry in behind.entries) {
      final key = keyFor(waba, entry.key);
      final cursor = {
        ...entry.value,
        'sync': since,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        final patches = changed[entry.key] ?? const [];
        var rowsToSave = created[entry.key] ?? const <Json>[];
        if (patches.isNotEmpty) {
          final saved = await session.cache.conversation(key);
          final byId = {
            for (final m in saved?.messages ?? const <Json>[]) '${m['id']}': m,
          };
          rowsToSave = [
            ...rowsToSave,
            for (final p in patches)
              if (byId['${p['id']}'] case final Json row) {...row, ...p},
          ];
        }
        await session.cache.putMessages(key, rowsToSave, cursor);
        session.viewCache
          ..remove(key)
          ..remove('cursor:$key');
        _synced[key] = DateTime.now();
      } catch (_) {}
    }
    PerfLog.add(
      PerfEntry(
        'sync',
        '${behind.length} chats',
        clock.elapsedMilliseconds,
        detail:
            '$pages request${pages == 1 ? '' : 's'}, '
            '${created.values.fold(0, (n, l) => n + l.length)} new, '
            '${changed.values.fold(0, (n, l) => n + l.length)} changed',
      ),
    );
  }

  /// A message carried in a push: saved to its chat's copy at once, with no
  /// request. The copy's cursor stays where it was, so the chat still asks
  /// for whatever else changed when it is next synced or opened.
  Future<void> arrived(Json data) async {
    final saved = await saveCarried(session.cache, data);
    if (saved != null) {
      session.viewCache
        ..remove(saved)
        ..remove('cursor:$saved');
    } else {
      pushed(data['contact_id']);
    }
  }

  /// A push about a chat: bring its copy up to date now.
  void pushed(Object? contactId) {
    final id = number(contactId);
    final waba = session.api.wabaId;
    if (id == null || waba == null || !session.signedIn) return;
    _synced.remove(keyFor(waba, id));
    _enqueue(id, keyFor(waba, id));
  }

  void _enqueue(int id, String key) {
    // The chat on screen keeps itself current over its own channels.
    if (session.visibleContacts.contains('contact:$id')) return;
    if (_running.contains(key) || _queue.any((q) => q.$2 == key)) return;
    final last = _synced[key];
    if (last != null && DateTime.now().difference(last) < quiet) return;
    _queue.add((id, key));
    _next();
  }

  void _next() {
    while (_active < parallel && _queue.isNotEmpty) {
      final (id, key) = _queue.removeAt(0);
      _active++;
      _running.add(key);
      unawaited(
        _sync(id, key).whenComplete(() {
          _active--;
          _running.remove(key);
          _next();
        }),
      );
    }
  }

  /// The chat's newest page, saved over the phone's copy of that stretch;
  /// what this run holds in memory is dropped so the chat reads the copy.
  Future<void> _sync(int id, String key) async {
    final clock = Stopwatch()..start();
    try {
      final result = await InboxRepository(session.api).messages(id);
      final page = rows(result['data']);
      final meta = object(result['meta']);
      if (session.api.wabaId == null || key != keyFor(session.api.wabaId, id)) {
        return;
      }
      await session.cache.putMessages(key, page, {
        'sync': meta['sync_from'],
        'oldest': meta['oldest_id'],
        'more': meta['has_more'] == true,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      });
      session.viewCache
        ..remove(key)
        ..remove('cursor:$key');
      _synced[key] = DateTime.now();
      PerfLog.add(
        PerfEntry(
          'sync',
          'contact $id',
          clock.elapsedMilliseconds,
          detail: '${page.length} rows',
        ),
      );
    } catch (_) {
      // Offline or refused: the chat syncs itself when opened.
    }
  }
}

/// Saves the message a push carries into its chat's copy on the phone, if
/// the phone has one; the chat's key, or null when nothing was saved. Also
/// runs in Firebase's background isolate (see backgroundPush).
Future<String?> saveCarried(LocalCache cache, Map<String, dynamic> data) async {
  if (data['type'] != 'message') return null;
  final row = object(decoded(data['message']));
  final waba = number(data['waba_user_id']);
  if (row.isEmpty || waba == null || data['contact_id'] == null) return null;
  final key = ConversationSync.keyFor(waba, data['contact_id']);
  final cursor = await cache.cursor(key);
  if (cursor == null) return null;
  await cache.putMessages(key, [row], cursor);
  return key;
}

/// Every push that reaches a closed or backgrounded app: a call rings (see
/// [backgroundCallPush]); a message it carries is saved into its chat on the
/// phone, so opening the app from the notification shows it at once.
@pragma('vm:entry-point')
Future<void> backgroundPush(RemoteMessage message) async {
  final data = Map<String, dynamic>.from(message.data);
  if (data['type'] == 'call' || data['type'] == 'call_cancel') {
    await backgroundCallPush(message);
    return;
  }
  try {
    await saveCarried(SqlLocalCache(SecureSessionStore()), data);
  } catch (_) {
    // The chat catches up when the app is next opened.
  }
}
