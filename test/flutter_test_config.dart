import 'dart:async';

import 'package:telvox_chat_mobile_app/mobile/device_identity.dart';

/// Every test: no platform to describe the phone, so it describes itself as
/// unknown at once (mobile_device_identity_test replaces this where it checks).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  describeDevice = () async => const DeviceIdentity();
  await testMain();
}
