import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/perf_log.dart';

import 'mobile_api_test.dart' show fakeApi, answer;

void main() {
  setUp(PerfLog.clear);

  test('every request is timed with its status and size', () async {
    final api = fakeApi(
      (r, h) => answer(r, h, {'success': true, 'data': List.filled(20, 'row')}),
    );
    await api.post('inbox/messages', {'contact_id': 12});
    await api.post('inbox/messages', {'contact_id': 12});
    final requests = PerfLog.entries.where((e) => e.kind == 'request');
    expect(requests, hasLength(2));
    expect(requests.first.label, 'inbox/messages');
    expect(requests.first.detail, startsWith('200 '));
    expect(requests.first.detail, endsWith('KB'));
  });

  test('the summary gives the median and slowest per step', () {
    for (final ms in [100, 300, 200]) {
      PerfLog.add(PerfEntry('request', 'inbox/messages', ms));
    }
    PerfLog.add(PerfEntry('current', 'contact 12', 640));
    final summary = PerfLog.summary();
    expect(summary.first, ('current (chat)', 1, 640, 640));
    expect(summary.last, ('inbox/messages', 3, 200, 300));
    expect(
      PerfLog.report(),
      contains('inbox/messages: n=3 median=200ms slowest=300ms'),
    );
  });
}
