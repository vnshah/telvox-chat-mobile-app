import 'package:dio/dio.dart';

import 'media.dart';
import 'media_quality.dart';
import 'message_content.dart';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/config/app_config.dart';
import 'api.dart';

/// The display timezone is configurable in one place; database parsing is separate.
class MobileClock {
  const MobileClock({this.timezone = AppConfig.displayTimezone});
  final String timezone;
  static bool _initialized = false;
  static void _ensure() {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
  }

  /// The instant in the display timezone, for grouping by day or month.
  DateTime? local(Object? raw) {
    _ensure();
    final instant = MobileClock.instant(raw);
    return instant == null
        ? null
        : tz.TZDateTime.from(instant, tz.getLocation(timezone));
  }

  String time(Object? raw) {
    _ensure();
    final instant = MobileClock.instant(raw);
    if (instant == null) return '';
    final date = tz.TZDateTime.from(instant, tz.getLocation(timezone));
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Conversation-list label, as on WhatsApp: today's time, "Yesterday",
  /// the weekday within the last week, then a short date.
  String listTime(Object? raw, {DateTime? now}) {
    final value = instant(raw);
    if (value == null) return '';
    _ensure();
    final location = tz.getLocation(timezone);
    final date = tz.TZDateTime.from(value, location);
    final today = tz.TZDateTime.from(now ?? DateTime.now(), location);
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) return time(raw);
    if (days == 1) return 'Yesterday';
    if (days < 7) {
      return const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][date.weekday - 1];
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${two(date.year % 100)}';
  }

  /// Date separator label: Today, Yesterday, weekday, then "30 Oct 2026".
  String dayLabel(Object? raw, {DateTime? now}) {
    final value = instant(raw);
    if (value == null) return '';
    _ensure();
    final location = tz.getLocation(timezone);
    final date = tz.TZDateTime.from(value, location);
    final today = tz.TZDateTime.from(now ?? DateTime.now(), location);
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return listTime(raw, now: now);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String day(Object? raw) {
    final value = instant(raw);
    if (value == null) return '';
    _ensure();
    final date = tz.TZDateTime.from(value, tz.getLocation(timezone));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? instant(Object? raw) {
    final text = '$raw';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text);
    return zoned
        ? parsed.toUtc()
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          ).subtract(
            const Duration(minutes: AppConfig.databaseUtcOffsetMinutes),
          );
  }
}

/// Readable phone number: `+91 99999 99999` for Indian numbers, `+` and the digits
/// otherwise. Masked numbers (with *) are shown exactly as the server sends.
String formatPhone(Object? raw) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty || text.contains('*') || text.contains(' ')) return text;
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
  }
  return digits.isEmpty ? text : '+$digits';
}

class ApiMessage {
  ApiMessage(this.json);
  final Json json;
  String get id => '${json['id']}';
  String get wamid => '${json['message_id'] ?? ''}';

  /// The id this phone gave a send before the server saved it. The send's
  /// own reply carries it as a field; the history and catch-up rows carry it
  /// only inside the stored request (message_body_json), so it is read from
  /// there too. Either way the server's row is the same message as the
  /// bubble shown while sending, never a second one.
  late final String tempId = () {
    final own = '${json['temp_message_id'] ?? ''}';
    if (own.isNotEmpty || number(json['type']) != 1) return own;
    final stored = object(
      decoded(json['message_body_json']),
    )['temp_message_id'];
    return stored == null ? '' : '$stored';
  }();
  bool get outgoing => number(json['type']) == 1;
  bool get log => number(json['type']) == 3;
  late final content = MessageContent(json);
  String get text => content.summary;
  String get type => '${json['message_type'] ?? 'text'}';
  int get status => number(json['message_status']) ?? 0;
  List<Json> get reactions => rows(decoded(json['reaction']));
}

/// Reconcile by database id and optimistic id. Status/reaction updates replace rows.
List<ApiMessage> mergeMessages(
  List<ApiMessage> current,
  List<ApiMessage> incoming,
) {
  final merged = {for (final m in current) m.id: m};
  for (final m in incoming) {
    // A row the phone made stands in for the server's until it arrives. Saved
    // rows are never dropped this way: a resend may copy another's request.
    if (m.tempId.isNotEmpty) {
      merged.removeWhere(
        (id, old) => old.tempId == m.tempId && number(id) == null,
      );
    }
    merged[m.id] = m;
  }
  final result = merged.values.toList();
  result.sort((a, b) {
    final date = '${a.json['created_at']}'.compareTo('${b.json['created_at']}');
    return date != 0 ? date : (number(a.id) ?? 0).compareTo(number(b.id) ?? 0);
  });
  // One WhatsApp message is one bubble. A replayed webhook (a call, or a
  // message Meta delivers twice) can store it twice under the same WhatsApp
  // id; show it once, keeping the newest row.
  final seen = <String>{};
  for (var i = result.length - 1; i >= 0; i--) {
    final m = result[i];
    if (m.log || m.wamid.isEmpty) continue;
    if (!seen.add(m.wamid)) result.removeAt(i);
  }
  return result;
}

class PendingSend {
  PendingSend(
    this.body, {
    String? key,
    this.attachment,
    this.quote,
    this.voice = false,
    this.quality = MediaQuality.standard,
  }) : key = key ?? newRequestId(),
       createdAt = DateTime.now().toUtc().toIso8601String();
  final Json body;

  /// The file as picked, then as it will be sent once [prepare]d.
  Attachment? attachment;

  /// How a photo or video goes: Standard or HD, as the sender chose.
  final MediaQuality quality;

  /// Whether [attachment] has been compressed for sending, once.
  bool prepared = false;

  /// A photo or video made to fit WhatsApp at [quality], once: a retry after
  /// a failed upload sends what was already made. [progress] follows a
  /// video's encoding, 0 to 1.
  Future<void> prepare({void Function(double done)? progress}) async {
    final file = attachment;
    if (prepared || file == null || voice) return;
    if (file.kind == 'image' || file.kind == 'video') {
      attachment = await prepareMedia(file, quality, progress: progress);
    }
    prepared = true;
  }

  /// A recorded voice note, drawn with its waveform while it sends.
  final bool voice;

  /// Reply-quote fields, in the server's message shape.
  final Json? quote;

  /// When it was sent; fixed so its time and day stay put on every rebuild.
  final String createdAt;
  double progress = 0;
  final String key;
  String? error;
  bool sending = false;
  bool accepted = false;
}

class InboxRepository {
  InboxRepository(this.api);
  final MobileApi api;
  Future<List<Json>> contacts({
    String filter = 'all',
    String search = '',
    int offset = 0,
    int limit = 30,
    List<int> tags = const [],
    int? assignedTo,
  }) async => rows(
    await api.request(
      'inbox/contacts',
      method: 'POST',
      data: {
        'listType': filter,
        'search': search,
        // The web's filter: chats with any of these tags, and one assignee.
        if (tags.isNotEmpty) 'tags': tags,
        'assignedTo': ?assignedTo,
        'limit': limit,
        'offset': offset,
      },
    ),
  );
  Future<Json> messages(
    int contactId, {
    int? before,
    String? since,
    int? after,
  }) => api.post('inbox/messages', {
    'contact_id': contactId,
    // Catching up takes the server's largest page (100), so a day away is one
    // round trip, not several; a history page stays 50, enough to fill a screen.
    'limit': since != null ? 100 : 50,
    'before_id': ?before,
    'updated_since': ?since,
    'updated_after_id': ?after,
  });
  Future<Json> send(PendingSend pending, {ProgressCallback? progress}) async =>
      object(
        await api.request(
          'inbox/send',
          method: 'POST',
          idempotencyKey: pending.key,
          onSendProgress: progress,
          data: pending.attachment == null
              ? {...pending.body, 'temp_message_id': pending.key}
              : FormData.fromMap({
                  ...pending.body,
                  'message_type': pending.attachment!.kind,
                  'temp_message_id': pending.key,
                  'media': pending.attachment!.multipart(),
                }),
        ),
      );
}
