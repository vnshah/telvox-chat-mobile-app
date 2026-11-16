import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What this phone is, for the server's sign-in history: its model, system
/// version and the app's version and build. Read once from the platform.
@immutable
class DeviceIdentity {
  const DeviceIdentity({this.model, this.os, this.version, this.build});
  final String? model, os, version, build;

  /// "1.0.0 (70)", or just the version.
  String? get appVersion => version == null
      ? null
      : build == null || build!.isEmpty
      ? version
      : '$version ($build)';

  /// "TelvoxChat/1.0.0 (70; Android 16; Google Pixel 9)".
  String get userAgent {
    final parts = [?build, ?os, ?model].where((p) => p.isNotEmpty);
    return 'TelvoxChat/${version ?? '0'}'
        '${parts.isEmpty ? '' : ' (${parts.join('; ')})'}';
  }

  /// The sign-in fields the server keeps (each cut to its column's size).
  Map<String, String> get loginFields => {
    if (model case final m?) 'device_model': _cut(m, 100),
    if (os case final o?) 'os_version': _cut(o, 32),
    if (appVersion case final v?) 'app_version': _cut(v, 32),
  };

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}

/// Reads the phone's identity; replaced in tests. Never fails: a phone that
/// cannot say signs in without these details.
Future<DeviceIdentity> Function() describeDevice = () async {
  try {
    final info = await const MethodChannel('telvox/device')
        .invokeMapMethod<String, Object?>('describe');
    String? text(Object? v) {
      final s = '${v ?? ''}'.trim();
      return s.isEmpty ? null : s;
    }

    return DeviceIdentity(
      model: text(info?['model']),
      os: text(info?['os']),
      version: text(info?['version']),
      build: text(info?['build']),
    );
  } catch (_) {
    return const DeviceIdentity();
  }
};

Future<DeviceIdentity>? _identity;

/// The phone's identity, read once per launch.
Future<DeviceIdentity> deviceIdentity() => _identity ??= describeDevice();

@visibleForTesting
void forgetDeviceIdentity() => _identity = null;
