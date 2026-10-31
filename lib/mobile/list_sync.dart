import 'api.dart';
import 'models.dart' show MobileClock;

/// How a listing stays current without re-reading every row: a live event
/// patches the one row it names in place, and the server's first page then
/// reconciles the window it covers. Shared by the inbox and ticket lists.
class ListSync {
  const ListSync({required this.sortField, this.patchFields = const []});

  /// Contacts sort by their last message, tickets by their last reply.
  final String sortField;

  /// Fields a live event may overwrite on a row the list already shows. Kept
  /// to activity fields: the event is not filtered per user (a masked number
  /// stays masked), and the list endpoint stays the only source of rows.
  final List<String> patchFields;

  static const contacts = ListSync(
    sortField: 'last_message_date',
    patchFields: [
      'last_message',
      'last_message_date',
      'unread_message_count',
      'conversation_status',
      'is_open',
    ],
  );
  static const tickets = ListSync(sortField: 'last_replied_at');

  String idOf(Json row) => '${row['id']}';

  /// The row's activity time as an instant. Rows and messages carry dates in
  /// different formats, so they are never compared as text.
  DateTime sortOf(Json row) =>
      MobileClock.instant(row[sortField]) ?? DateTime.utc(1970);

  /// Newest activity first; ties by id so the order never flickers.
  List<Json> sorted(Iterable<Json> rows) => rows.toList()
    ..sort((a, b) {
      final byTime = sortOf(b).compareTo(sortOf(a));
      return byTime != 0
          ? byTime
          : (number(b['id']) ?? 0).compareTo(number(a['id']) ?? 0);
    });

  /// One row changed: update it where it is and move it to its new place.
  /// Returns null when the row is not in this list (the caller reconciles
  /// with the server instead of guessing whether it belongs).
  ///
  /// [filter] lets a patched row leave a tab it no longer matches: a closed
  /// chat leaves the open tabs, a read one leaves Unread.
  List<Json>? patch(List<Json> rows, Json update, {String filter = 'all'}) {
    final id = idOf(update);
    final at = rows.indexWhere((r) => idOf(r) == id);
    if (at < 0) return null;
    final row = {
      ...rows[at],
      for (final f in patchFields)
        if (update.containsKey(f)) f: update[f],
    };
    final rest = [...rows]..removeAt(at);
    final closed = number(row['conversation_status']) == 0;
    final leaves =
        (filter == 'closed' && !closed) ||
        (filter != 'closed' && closed) ||
        (filter == 'unread' && (number(row['unread_message_count']) ?? 0) == 0);
    return leaves ? rest : sorted([...rest, row]);
  }

  /// Merge the server's first page into the local list. The page is the truth
  /// for the window it covers: a local row newer than the page's last row but
  /// missing from it has left this tab. Rows below the window are kept, so
  /// "Load more" pages stay loaded. [complete] means the server has nothing
  /// past this page, so the page is the whole list.
  List<Json> reconcile(
    List<Json> local,
    List<Json> page, {
    required bool complete,
  }) {
    if (complete || page.isEmpty) return page;
    final boundary = sortOf(page.last);
    final inPage = {for (final r in page) idOf(r)};
    return [
      ...page,
      ...local.where(
        (r) => !inPage.contains(idOf(r)) && !sortOf(r).isAfter(boundary),
      ),
    ];
  }

  /// What an open chat just synced (any sender) applied to its row, unless
  /// the row already shows something newer. Null when the list does not show
  /// that conversation.
  List<Json>? follow(List<Json> rows, Json activity, {String filter = 'all'}) {
    final id = idOf(activity);
    final current = rows.where((r) => idOf(r) == id).firstOrNull;
    if (current == null || sortOf(activity).isBefore(sortOf(current))) {
      return null;
    }
    return patch(rows, activity, filter: filter);
  }

  /// Appends a further page, never showing a row twice.
  List<Json> append(List<Json> rows, List<Json> page) {
    final seen = {for (final r in rows) idOf(r)};
    return [...rows, ...page.where((r) => seen.add(idOf(r)))];
  }
}
