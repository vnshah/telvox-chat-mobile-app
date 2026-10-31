import 'dart:convert';
import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';

import 'api.dart';

/// A conversation as last synced: its newest messages and the cursor that
/// lets the next open fetch only what changed since.
class CachedConversation {
  const CachedConversation(this.messages, this.cursor);
  final List<Json> messages;
  final Json cursor;
}

/// The phone's copy of what the server last returned, so screens render at
/// once and then fetch only the difference. The server stays the source of
/// truth: nothing is written here that the server did not send.
///
/// One owner (server and signed-in user) at a time. Opening for anyone else
/// wipes it first, and signing out or a revoked session wipes it, so one
/// account never sees another's chats. Rows are keyed by the same keys the
/// screens use, which already carry the WhatsApp number.
abstract class LocalCache {
  Future<void> open(String owner);
  Future<void> wipe();
  Future<List<Json>?> list(String key);
  Future<void> putList(String key, List<Json> rows);
  Future<CachedConversation?> conversation(String key);

  /// Upserts [messages] by server id and replaces the cursor; [replace]
  /// first drops what was kept, for a copy too old to catch up.
  Future<void> putMessages(
    String key,
    List<Json> messages,
    Json cursor, {
    bool replace = false,
  });
}

/// Retention: the most recently opened conversations, each to its newest
/// messages, and nothing left unopened for a month.
const cacheConversations = 100,
    cacheMessagesPerConversation = 500,
    cacheMaxAge = Duration(days: 30);

/// For tests, and a fallback when the database cannot open: same behaviour,
/// nothing kept across launches.
class MemoryLocalCache implements LocalCache {
  String? owner;
  final lists = <String, List<Json>>{};
  final chats = <String, CachedConversation>{};
  @override
  Future<void> open(String owner) async {
    if (this.owner != owner) await wipe();
    this.owner = owner;
  }

  @override
  Future<void> wipe() async {
    owner = null;
    lists.clear();
    chats.clear();
  }

  @override
  Future<List<Json>?> list(String key) async => lists[key];
  @override
  Future<void> putList(String key, List<Json> rows) async =>
      lists[key] = [...rows];
  @override
  Future<CachedConversation?> conversation(String key) async => chats[key];
  @override
  Future<void> putMessages(
    String key,
    List<Json> messages,
    Json cursor, {
    bool replace = false,
  }) async {
    final byId = {
      if (!replace)
        for (final m in chats[key]?.messages ?? const <Json>[]) '${m['id']}': m,
      for (final m in messages) '${m['id']}': m,
    };
    final sorted = byId.values.toList()..sort(_byTime);
    chats[key] = CachedConversation(
      sorted.length > cacheMessagesPerConversation
          ? sorted.sublist(sorted.length - cacheMessagesPerConversation)
          : sorted,
      cursor,
    );
  }
}

int _byTime(Json a, Json b) {
  final date = '${a['created_at']}'.compareTo('${b['created_at']}');
  return date != 0
      ? date
      : (number(a['id']) ?? 0).compareTo(number(b['id']) ?? 0);
}

/// SQLCipher database, its key generated on first use and kept in the
/// phone's secure storage beside the login token.
class SqlLocalCache implements LocalCache {
  SqlLocalCache(this.store);
  final SessionStore store;
  Database? _db;
  static const _file = 'telvox-cache.db';

  Future<Database> get _database async => _db ??= await _openDatabase();

  Future<Database> _openDatabase() async {
    var key = await store.read('cache_key');
    if (key == null) {
      final random = Random.secure();
      key = base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
      await store.write('cache_key', key);
    }
    final path = '${await getDatabasesPath()}/$_file';
    Future<Database> attempt() => openDatabase(
      path,
      password: key,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE meta (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE list_rows (list_key TEXT NOT NULL, position INTEGER NOT NULL, '
          'json TEXT NOT NULL, PRIMARY KEY (list_key, position))',
        );
        await db.execute(
          'CREATE TABLE conversations (convo TEXT PRIMARY KEY, opened_at INTEGER NOT NULL, '
          'cursor TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE messages (convo TEXT NOT NULL, id TEXT NOT NULL, '
          'created_at TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (convo, id))',
        );
        await db.execute(
          'CREATE INDEX messages_by_time ON messages (convo, created_at, id)',
        );
      },
    );
    try {
      return await attempt();
    } catch (_) {
      // A copy restored without its key, or a damaged file: start over. The
      // server holds everything, so this only costs one slow first open.
      await deleteDatabase(path);
      return attempt();
    }
  }

  @override
  Future<void> open(String owner) async {
    final db = await _database;
    final rows = await db.query(
      'meta',
      where: 'name = ?',
      whereArgs: ['owner'],
    );
    final current = rows.isEmpty ? null : '${rows.first['value']}';
    if (current != owner) {
      await _clear(db);
      await db.insert('meta', {
        'name': 'owner',
        'value': owner,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _prune(db);
  }

  @override
  Future<void> wipe() async => _clear(await _database);

  Future<void> _clear(Database db) => db.transaction((txn) async {
    for (final table in ['meta', 'list_rows', 'conversations', 'messages']) {
      await txn.delete(table);
    }
  });

  Future<void> _prune(Database db) => db.transaction((txn) async {
    final cutoff = DateTime.now().subtract(cacheMaxAge).millisecondsSinceEpoch;
    final stale = await txn.rawQuery(
      'SELECT convo FROM conversations WHERE opened_at < ? OR convo NOT IN '
      '(SELECT convo FROM conversations ORDER BY opened_at DESC LIMIT ?)',
      [cutoff, cacheConversations],
    );
    for (final row in stale) {
      await txn.delete(
        'conversations',
        where: 'convo = ?',
        whereArgs: [row['convo']],
      );
      await txn.delete(
        'messages',
        where: 'convo = ?',
        whereArgs: [row['convo']],
      );
    }
  });

  @override
  Future<List<Json>?> list(String key) async {
    final rows = await (await _database).query(
      'list_rows',
      where: 'list_key = ?',
      whereArgs: [key],
      orderBy: 'position',
    );
    if (rows.isEmpty) return null;
    return [for (final r in rows) object(jsonDecode('${r['json']}'))];
  }

  @override
  Future<void> putList(String key, List<Json> rows) async =>
      (await _database).transaction((txn) async {
        await txn.delete('list_rows', where: 'list_key = ?', whereArgs: [key]);
        final batch = txn.batch();
        for (var i = 0; i < rows.length; i++) {
          batch.insert('list_rows', {
            'list_key': key,
            'position': i,
            'json': jsonEncode(rows[i]),
          });
        }
        await batch.commit(noResult: true);
      });

  @override
  Future<CachedConversation?> conversation(String key) async {
    final db = await _database;
    final convo = await db.query(
      'conversations',
      where: 'convo = ?',
      whereArgs: [key],
    );
    if (convo.isEmpty) return null;
    await db.update(
      'conversations',
      {'opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'convo = ?',
      whereArgs: [key],
    );
    final rows = await db.query(
      'messages',
      where: 'convo = ?',
      whereArgs: [key],
      orderBy: 'created_at, CAST(id AS INTEGER)',
    );
    return CachedConversation([
      for (final r in rows) object(jsonDecode('${r['json']}')),
    ], object(jsonDecode('${convo.first['cursor']}')));
  }

  @override
  Future<void> putMessages(
    String key,
    List<Json> messages,
    Json cursor, {
    bool replace = false,
  }) async => (await _database).transaction((txn) async {
    if (replace) {
      await txn.delete('messages', where: 'convo = ?', whereArgs: [key]);
    }
    final batch = txn.batch();
    for (final m in messages) {
      batch.insert('messages', {
        'convo': key,
        'id': '${m['id']}',
        'created_at': '${m['created_at']}',
        'json': jsonEncode(m),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    batch.insert('conversations', {
      'convo': key,
      'opened_at': DateTime.now().millisecondsSinceEpoch,
      'cursor': jsonEncode(cursor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
    // Keep the newest messages; older history pages in from the server.
    await txn.rawDelete(
      'DELETE FROM messages WHERE convo = ? AND id NOT IN (SELECT id FROM '
      'messages WHERE convo = ? ORDER BY created_at DESC, CAST(id AS INTEGER) DESC LIMIT ?)',
      [key, key, cacheMessagesPerConversation],
    );
  });
}
