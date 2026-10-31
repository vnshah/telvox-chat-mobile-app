import 'api.dart';
import 'models.dart';

bool flag(Object? v) => v == true || v == 1 || v == '1';

/// Send-policy inputs from a ticket's details: its contact, and the people
/// this account may answer for (the ticket's assignable team, which includes
/// the account itself), in place of the shared inbox's child user ids. Used
/// because ticketing mode does not expose the shared inbox's contact details.
Json ticketSendDetail(Json data) => {
  'contact': object(data['contact']),
  'child_user_ids': [
    for (final u in rows(data['users']))
      if (number(u['id']) case final int id) id,
  ],
  'is_favourite': data['is_favourite'],
};

/// Mirrors shared/ticket inbox assignment and service/referral window checks.
/// Templates bypass the window only, never ownership or contact restrictions.
class SendPolicy {
  const SendPolicy(this.reason, this.canTemplate, this.expiresAt);
  final String? reason;
  final bool canTemplate;
  final DateTime? expiresAt;
  bool get canSend => reason == null;
  static SendPolicy evaluate(
    MobileSession session,
    Json? details, {
    Json? ticket,
    DateTime? now,
  }) {
    if (details == null) {
      return const SendPolicy(
        'Checking conversation permissions…',
        false,
        null,
      );
    }
    final c = object(details['contact']);
    String? restricted;
    if (flag(details['is_blocked'])) {
      restricted = 'This contact is blocked. Unblock it before sending.';
    }
    if (number(c['conversation_owner_type']) == 1) {
      restricted = 'This conversation is assigned to a bot. Assign it to an agent to reply.';
    }
    if (ticket == null && number(c['conversation_status']) == 0) {
      restricted = 'Conversation closed. Reopen it before replying.';
    }
    if (ticket != null &&
        (flag(ticket['status_is_closed']) ||
            flag(object(ticket['status'])['is_closed']))) {
      restricted = 'Ticket closed. Reopen it before replying.';
    }
    final manageable = <int>{
      ?number(session.user?['id']),
      ...((details['child_user_ids'] as List?) ?? [])
          .map(number)
          .whereType<int>(),
    };
    final assigned = ticket != null
        ? <int>[?number(ticket['assign_user_id'])]
        : flag(details['multiple_assignment_enabled'])
        ? ((details['assigned_user_ids'] as List?) ?? [])
              .map(number)
              .whereType<int>()
              .toList()
        : <int>[
            ?number(object(details['assignUser'])['id']),
            ?number(c['assigned_to']),
          ];
    if (!assigned.any(manageable.contains)) {
      restricted ??= 'Assign this conversation to you or an agent you manage before replying.';
    }
    final dates = [
      MobileClock.instant(c['service_expiration_timestamp']),
      MobileClock.instant(c['referral_conversion_expiration_timestamp']),
    ].whereType<DateTime>().toList()..sort();
    final expiry = dates.lastOrNull;
    final templateAllowed =
        restricted == null && session.allows('inbox/send-template-by-contact');
    if (restricted != null) return SendPolicy(restricted, false, expiry);
    if (!session.allows('inbox/send')) {
      return SendPolicy(
        'You do not have permission to send messages.',
        templateAllowed,
        expiry,
      );
    }
    if (expiry == null || !expiry.isAfter(now ?? DateTime.now())) {
      return SendPolicy(
        'Messaging window closed. Send an approved template, or wait for a new customer message.',
        templateAllowed,
        expiry,
      );
    }
    return SendPolicy(null, templateAllowed, expiry);
  }
}
