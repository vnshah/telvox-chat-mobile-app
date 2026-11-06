import 'package:flutter/widgets.dart';

import 'api.dart';
import 'editors.dart';

/// Who a chat can be given to, as the web inbox's assign dropdown offers it,
/// read from the contact details (`inbox/getContactDetails`).
///
/// The agents come with their role and department. The bot is offered only
/// when the server says a bot can take the chat back (`ai_bot_enabled`: the
/// agent may unassign and a published bot answers on this number); choosing
/// it clears the assignment and the server hands the chat to the bot. There is
/// no plain "Unassigned": on the web, clearing an assignee is the bot option.
class Assignment {
  Assignment(this.details);
  final Json details;

  /// The id the bot option goes by in the picker; no agent has it.
  static const bot = 0;

  Json get contact => object(details['contact']);
  bool get multi => details['multiple_assignment_enabled'] == true;
  bool get botEnabled => details['ai_bot_enabled'] == true;
  List<Json> get users => rows(details['users']);

  /// The bot option's label: the AI bot's name when it has one.
  String get botLabel {
    final label = '${details['ai_bot_label'] ?? ''}'.trim();
    return label.isEmpty ? 'Assign to Bot' : label;
  }

  /// The web shows the assign dropdown when it has anyone to offer.
  bool get available => users.isNotEmpty || botEnabled;

  /// The chatbot is answering this chat.
  bool get botOwned => '${contact['conversation_owner_type']}' == '1';

  /// Whether this agent may take a bot's chat (assign it to themselves).
  bool get canTakeOver => details['can_assign_contact'] != false;

  List<int> get assignedIds => [
    for (final id
        in details['assigned_user_ids'] is List
            ? details['assigned_user_ids'] as List
            : const [])
      ?number(id),
  ];

  List<Json> get options => [
    if (botEnabled) {'id': bot, 'name': botLabel},
    for (final u in users)
      {
        ...u,
        // "Manager - Sales", only for agents in a department, as on the web.
        if ('${u['department_name'] ?? ''}'.isNotEmpty)
          'detail': [
            '${u['role_name'] ?? ''}',
            '${u['department_name']}',
          ].where((s) => s.isNotEmpty).join(' - '),
      },
  ];

  /// What the picker starts on.
  Object? get value {
    if (multi) {
      return assignedIds.isEmpty && botOwned && botEnabled
          ? [bot]
          : assignedIds;
    }
    final assigned = number(contact['assigned_to']);
    if (assigned != null && assigned != 0) return assigned;
    return botOwned && botEnabled ? bot : null;
  }

  /// The assign request for what was picked: the bot clears the assignment.
  Json body(Object? picked) {
    if (multi) {
      final ids = picked is List ? picked : const [];
      return {
        'user_ids': ids.contains(bot) ? <int>[] : [...ids],
      };
    }
    return {'user_id': picked == bot ? null : picked};
  }

  /// Taking over the bot's chat: assigning it to this agent, alongside the
  /// others already on it when a chat can have several.
  Json takeOverBody(Object? me) => multi
      ? {
          'user_ids': [
            ...assignedIds,
            if (!assignedIds.contains(number(me))) ?number(me),
          ],
        }
      : {'user_id': number(me)};
}

/// Closes a chat as the web inbox does: with an optional short reason (at
/// most 100 characters, trimmed; empty keeps none), shown on the chat as its
/// last close reason. The saved contact, or null when the agent backed out.
Future<Json?> closeConversation(
  BuildContext context,
  MobileApi api,
  Object? contactId,
) async {
  Json? saved;
  final done = await showEditorSheet(
    context,
    title: 'Close conversation',
    submit: 'Close',
    fields: const [
      EditField(
        'reason',
        'Reason',
        hint: 'Reason, e.g. issue resolved',
        maxLength: 100,
        help: 'Short replies like “thanks” will keep this conversation closed.',
      ),
    ],
    save: (v) async {
      final reason = '${v['reason'] ?? ''}'.trim();
      final r = object(
        await api.request(
          'inbox/conversation/close',
          method: 'POST',
          data: {
            'contact_id': contactId,
            'reason': reason.isEmpty ? null : reason,
          },
        ),
      );
      saved = object(object(r['data'])['contact']);
    },
  );
  return done ? saved ?? {} : null;
}
