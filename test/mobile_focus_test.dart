import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

void main() {
  test(
    'a chat left while offline is released later, so its badge returns',
    () async {
      var offline = false;
      final sent = <Object?>[];
      final api = fakeApi((r, h) {
        if (r.path != 'inbox/conversation/focus') {
          return answer(r, h, {'success': true});
        }
        if (offline) {
          return h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.connectionError,
            ),
          );
        }
        sent.add(r.data);
        answer(r, h, {'success': true});
      });
      api
        ..token = 't'
        ..wabaId = 7;
      final session = MobileSession(api, MemoryStore());

      await session.focusChat(12, open: true);
      await session.focusChat(30, open: true);
      // Leaving chat 12 never reaches the server; the app still lists it.
      offline = true;
      await session.focusChat(12, open: false);
      offline = false;
      expect(sent, [
        {'contact_id': 12},
        {'contact_id': 30},
      ]);

      // Chat 30 is still on screen, so only 12 is let go, and only once.
      session.visibleContacts.add('contact:30');
      await session.releaseOpenChats();
      await session.releaseOpenChats();
      expect(sent.skip(2), [
        {'previous_contact_id': 12},
      ]);
      session.dispose();
    },
  );

  test('the heartbeat names only the shared-inbox chat on screen', () {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
    );
    expect(session.openContactId, isNull);
    session.visibleConversation = 'contact:12';
    expect(session.openContactId, 12);
    // A ticket conversation holds no shared-inbox focus.
    session.visibleConversation = 'ticket:7';
    expect(session.openContactId, isNull);
    session.dispose();
  });
}
