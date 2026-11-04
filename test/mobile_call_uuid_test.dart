import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/call_push.dart';

/// The server computes the same UUIDs for iPhone VoIP pushes (a cancel must
/// find the ring it ends), and its tests hold the same values: change one
/// side and both tests must change.
void main() {
  test('call ids map to the UUIDs the server computes', () {
    expect(callUuid('wacid.1'), '56982706-a1f0-4b95-af71-8f581df514d7');
    expect(
      callUuid('wacid.HBgMOTE5ODc2NTQzMjEw'),
      '1550d4f8-ab38-4add-a956-1e1e063f67fb',
    );
    expect(callUuid(''), '811c9dc5-1f2b-447c-ad72-6eb75bbaf0ee');
    expect(callUuid('é-call'), 'a441f17b-3a66-428a-a77b-a459b992e9d8');
  });
}
