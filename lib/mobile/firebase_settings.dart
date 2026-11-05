import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';

/// The Firebase project this phone's pushes and crash reports use, as the
/// server's .env sets it (GET app/firebase), so it is changed in one place
/// for every installed phone, with no new build. The last answer is kept on
/// the phone, so start-up never waits for the network; a build's own
/// Firebase defines are the fallback until the server has answered once.
class FirebaseSettings {
  const FirebaseSettings({
    required this.apiKey,
    required this.appId,
    required this.senderId,
    required this.projectId,
  });

  final String apiKey, appId, senderId, projectId;

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );

  Map<String, String> toJson() => {
    'api_key': apiKey,
    'app_id': appId,
    'sender_id': senderId,
    'project_id': projectId,
  };

  static FirebaseSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final settings = FirebaseSettings(
      apiKey: '${json['api_key'] ?? ''}',
      appId: '${json['app_id'] ?? ''}',
      senderId: '${json['sender_id'] ?? ''}',
      projectId: '${json['project_id'] ?? ''}',
    );
    return settings.complete ? settings : null;
  }

  /// This platform's app from the server's answer; null where the server
  /// has no project, or no app for this platform, set.
  static FirebaseSettings? fromServer(Object? body, {bool? ios}) {
    final firebase = body is Map ? body['firebase'] : null;
    if (firebase is! Map) return null;
    final app = firebase[(ios ?? _ios) ? 'ios' : 'android'];
    if (app is! Map) return null;
    return fromJson({
      'api_key': app['api_key'],
      'app_id': app['app_id'],
      'sender_id': firebase['messaging_sender_id'],
      'project_id': firebase['project_id'],
    });
  }

  bool get complete =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty &&
      projectId.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is FirebaseSettings &&
      other.apiKey == apiKey &&
      other.appId == appId &&
      other.senderId == senderId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(apiKey, appId, senderId, projectId);

  static bool get _ios =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The project Firebase is (or will be) started with this run; null when
  /// neither the phone's copy nor the build has one.
  static FirebaseSettings? current;

  /// The build's own defines, if it was given any.
  static FirebaseSettings? get built => AppConfig.firebaseConfigured
      ? FirebaseSettings(
          apiKey: AppConfig.firebasePlatformApiKey,
          appId: AppConfig.firebasePlatformAppId,
          senderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        )
      : null;

  /// Where the phone keeps the server's last answer; replaced in tests.
  @visibleForTesting
  static Future<File> Function() file = () async =>
      File('${(await getApplicationSupportDirectory()).path}/firebase.json');

  /// Fetches the server's answer; replaced in tests.
  @visibleForTesting
  static Future<Object?> Function(String apiBase) fetch = (apiBase) async {
    final base = apiBase.replaceFirst(RegExp(r'/+$'), '');
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json'},
      ),
    ).get<Object?>('$base/api/mobile/v1/app/firebase');
    return response.data;
  };

  /// The phone's copy, else the build's: what this run starts Firebase with.
  static Future<FirebaseSettings?> load() async {
    FirebaseSettings? kept;
    try {
      final f = await file();
      if (await f.exists()) kept = fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      // An unreadable copy is replaced on the next answer.
    }
    return current = kept ?? built;
  }

  static Future<void>? _refreshing;

  /// Asks the server and keeps its answer for next time. Firebase cannot
  /// change project once started, so a changed project takes effect on the
  /// next start; a phone that had none starts with it at once. Never throws.
  static Future<void> refresh([String apiBase = AppConfig.apiBaseUrl]) =>
      _refreshing ??= () async {
        try {
          final answer = fromServer(await fetch(apiBase));
          if (answer == null) return;
          final f = await file();
          await f.parent.create(recursive: true);
          await f.writeAsString(jsonEncode(answer.toJson()), flush: true);
          if (current == null || Firebase.apps.isEmpty) current = answer;
        } catch (_) {
          // Offline or an older server: the kept copy or the build's stands.
        } finally {
          _refreshing = null;
        }
      }();

  /// Settles once the start-up refresh has answered (or failed).
  static Future<void> ready() => _refreshing ?? Future.value();
}
