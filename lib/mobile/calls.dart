import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'call_push.dart';
import 'call_recording.dart';
import 'message_content.dart' show readableText;
import 'models.dart';
import 'realtime.dart';

/// Where call audio plays: the earpiece, the loudspeaker, a Bluetooth or
/// wired headset.
class AudioOutput {
  const AudioOutput(this.id, this.label);
  final String id, label;
  bool get speaker => id.toLowerCase().contains('speaker');
  bool get headset =>
      id.toLowerCase().contains('bluetooth') ||
      id.toLowerCase().contains('wired') ||
      id.toLowerCase().contains('headset');
}

/// The audio side of a WhatsApp call, behind a seam so tests need no
/// microphone or network.
abstract class CallMedia {
  /// The local offer, with its ICE candidates, for a call we start.
  Future<String> offer();

  /// The local answer, with its ICE candidates, to the customer's offer.
  Future<String> answer(String offer);

  /// The customer's answer to our offer.
  Future<void> remoteAnswer(String sdp);

  /// True once audio flows both ways.
  ValueListenable<bool> get connected;

  Future<void> mute(bool muted);
  Future<void> speaker(bool on);

  /// The outputs the call can play on right now.
  Future<List<AudioOutput>> outputs();
  Future<void> route(AudioOutput output);

  /// Starts recording the call, this phone's microphone and the customer's
  /// voice each to its own file in [folder]. False where the phone cannot.
  Future<bool> startRecording(String folder);

  /// Stops recording: the files (microphone, customer), or null if none.
  Future<(String, String)?> stopRecording();
  Future<void> close();
}

/// WebRTC through flutter_webrtc, as the web inbox does it in the browser:
/// one audio track, Opus by default. WhatsApp's media servers are ICE-lite
/// with a public address, so the phone's own candidates matter little; the
/// SDP goes once gathering finishes, a public (srflx) candidate is found, or
/// after a short wait — never trickled.
class WebRtcCallMedia implements CallMedia {
  WebRtcCallMedia({List<Object?>? iceServers})
    : _iceServers = iceServers == null || iceServers.isEmpty
          ? defaultIceServers
          : iceServers;

  /// The web inbox's servers; the server can send its own (with TURN) in
  /// `config.calls.ice_servers`.
  static const defaultIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
  static const _gathering = Duration(milliseconds: 800);

  final List<Object?> _iceServers;
  RTCPeerConnection? _peer;
  MediaStream? _local;

  /// The call's two recorders while it records, and their files.
  MediaRecorder? _microphone, _customer;
  (String, String)? _recording;
  final _connected = ValueNotifier(false);

  @override
  ValueListenable<bool> get connected => _connected;

  Future<RTCPeerConnection> _open() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    final peer = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _local!.getAudioTracks()) {
      await peer.addTrack(track, _local!);
    }
    peer.onConnectionState = (state) => _connected.value =
        state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    // The earpiece, or a connected headset, until the agent picks the speaker.
    await Helper.setSpeakerphoneOn(false);
    return _peer = peer;
  }

  /// Waits briefly for candidates so the SDP carries the phone's addresses.
  Future<String> _gathered(RTCPeerConnection peer) async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    peer.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) finish();
    };
    peer.onIceCandidate = (candidate) {
      final line = candidate.candidate ?? '';
      if (line.contains(' typ srflx') || line.contains(' typ relay')) {
        Timer(const Duration(milliseconds: 100), finish);
      }
    };
    if (peer.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      finish();
    }
    await done.future.timeout(_gathering, onTimeout: () {});
    return (await peer.getLocalDescription())!.sdp!;
  }

  @override
  Future<String> offer() async {
    final peer = await _open();
    final offer = await peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await peer.setLocalDescription(offer);
    return _gathered(peer);
  }

  @override
  Future<String> answer(String offer) async {
    final peer = await _open();
    await peer.setRemoteDescription(
      RTCSessionDescription(cleanSdp(offer), 'offer'),
    );
    final answer = await peer.createAnswer({});
    await peer.setLocalDescription(answer);
    return _gathered(peer);
  }

  @override
  Future<void> remoteAnswer(String sdp) async => _peer?.setRemoteDescription(
    RTCSessionDescription(cleanSdp(sdp), 'answer'),
  );

  @override
  Future<void> mute(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> speaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<List<AudioOutput>> outputs() async => [
    for (final d in await navigator.mediaDevices.enumerateDevices())
      if (d.kind == 'audiooutput')
        AudioOutput(d.deviceId, d.label.isEmpty ? d.deviceId : d.label),
  ];

  @override
  Future<void> route(AudioOutput output) => Helper.selectAudioOutput(output.id);

  @override
  Future<bool> startRecording(String folder) async {
    // flutter_webrtc records call audio on Android only.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (_recording != null) return true;
    await Directory(folder).create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final files = (
      '$folder/$stamp-microphone.m4a',
      '$folder/$stamp-customer.m4a',
    );
    final microphone = MediaRecorder(), customer = MediaRecorder();
    try {
      await microphone.start(
        files.$1,
        audioChannel: RecorderAudioChannel.INPUT,
      );
      await customer.start(files.$2, audioChannel: RecorderAudioChannel.OUTPUT);
    } catch (_) {
      await microphone.stop().catchError((_) {});
      await customer.stop().catchError((_) {});
      return false;
    }
    _microphone = microphone;
    _customer = customer;
    _recording = files;
    return true;
  }

  @override
  Future<(String, String)?> stopRecording() async {
    final files = _recording;
    if (files == null) return null;
    _recording = null;
    await _microphone?.stop().catchError((_) {});
    await _customer?.stop().catchError((_) {});
    _microphone = _customer = null;
    return files;
  }

  @override
  Future<void> close() async {
    await stopRecording();
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _local?.dispose();
    await _peer?.close();
    _local = null;
    _peer = null;
    _connected.value = false;
  }
}

/// Call audio the WebRTC package does not cover, from the app's Android
/// activity: the ringback tone while a customer's phone rings, and the screen
/// turning off at the ear. Quietly absent elsewhere (tests, iOS).
abstract final class CallAudio {
  static const _channel = MethodChannel('telvox/call_audio');
  static Future<void> ringback(bool on) => _quiet('ringback', on);
  static Future<void> proximity(bool on) => _quiet('proximity', on);
  static Future<void> _quiet(String method, bool on) async {
    try {
      await _channel.invokeMethod<void>(method, on);
    } catch (_) {
      /* Not on this platform. */
    }
  }
}

/// An SDP as Meta and the webhook relay hand it over: sometimes quoted, with
/// escaped line breaks. WebRTC wants plain CRLF lines ending in CRLF.
String cleanSdp(String sdp) {
  var s = sdp.trim();
  if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1);
  }
  s = s.replaceAll(r'\r\n', '\r\n').replaceAll(r'\n', '\n');
  s = s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  return s.endsWith('\r\n') ? s : '$s\r\n';
}

enum CallState {
  idle,

  /// Our offer is on its way to WhatsApp.
  dialing,

  /// The customer's phone is ringing.
  ringing,

  /// A customer is calling this phone.
  incoming,

  /// Answered here; audio is connecting.
  connecting,
  active,

  /// Over; the reason shows for a moment.
  ended,
}

/// Whether this number and contact can be called now, worded for the call
/// button's tooltip when not.
({bool shown, String? blocked}) callEligibility(Json? config, Json contact) {
  final waba = object(object(config?['inbox'])['waba_user']);
  if (waba['allow_voice_calling'] != true && waba['allow_voice_calling'] != 1) {
    return (shown: false, blocked: null);
  }
  if (waba['call_status_and_working_hours'] == false) {
    return (
      shown: true,
      blocked: 'Calling is off or outside call hours for this number',
    );
  }
  final expires = MobileClock.instant(contact['call_permission_expiration']);
  final permitted =
      contact['call_permission'] == 'accept' &&
      (contact['call_permission_permanent'] == true ||
          contact['call_permission_permanent'] == 1 ||
          (expires != null && expires.isAfter(DateTime.now())));
  return (
    shown: true,
    blocked: permitted
        ? null
        : 'This contact has not given call permission yet',
  );
}

/// WhatsApp calls on this phone, as the web inbox's call widget runs them:
/// the same endpoints, states and events, with the phone answering as its own
/// presence session ("mobile:{device id}").
///
/// Every call is also registered with Android's call system (the incoming
/// call screen, the ongoing-call notification): that runs the foreground
/// service which keeps the microphone working with the screen locked.
class PhoneCalls extends ChangeNotifier {
  PhoneCalls(this.session, {this.mediaFactory});
  final MobileSession session;

  /// Tests replace WebRTC; the app builds it from the server's ICE servers.
  final CallMedia Function()? mediaFactory;

  CallState state = CallState.idle;
  Json contact = const {};
  String? callId, notice;
  DateTime? connectedAt;
  bool muted = false, speaker = false;

  /// Recording the call on this phone, as the web inbox's record button does,
  /// and since when.
  bool recording = false;
  DateTime? recordingSince;
  bool _recordingBusy = false;

  /// This number records its calls on the device (custom capture); Meta
  /// records the others itself. Android only: flutter_webrtc cannot record
  /// call audio on iOS.
  bool get canRecord =>
      object(session.config?['calls'])['record_in_app'] == true &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  /// The headset the call plays on, when not the earpiece or speaker.
  AudioOutput? output;

  /// The call screen is showing; a second ring or tap does not open another.
  bool screenOpen = false;

  void showingScreen(bool open) {
    screenOpen = open;
    notifyListeners();
  }

  /// The app's navigator, for the ongoing-call bar to reopen the call screen.
  GlobalKey<NavigatorState>? navigator;

  String? _offer;
  CallMedia? _call;
  Timer? _expiry, _reset;
  final _subscriptions = <RealtimeSubscription>[];

  /// WhatsApp's media answer was applied: a repeat delivery is ignored.
  bool _answerApplied = false;

  /// The customer declined; the end that follows says so.
  bool _declined = false;

  /// The call's id with Android's call system, and whether that system's own
  /// screen accepted it (which already started the ongoing-call service).
  String? _system;
  bool _systemAccepted = false;

  /// False once the server says this account cannot take calls.
  bool _canAnswer = true;

  bool get busy => state != CallState.idle && state != CallState.ended;

  String? get sessionId {
    final device = number(object(session.user?['device'])['id']);
    return device == null ? null : 'mobile:$device';
  }

  CallMedia _newMedia() =>
      mediaFactory?.call() ??
      WebRtcCallMedia(
        iceServers: (object(session.config?['calls'])['ice_servers'] as List?)
            ?.cast<Object?>(),
      );

  /// Joins the call channels for the selected number and this account.
  void attach() {
    detach();
    final waba = session.api.wabaId, user = number(session.user?['id']);
    if (waba != null) {
      _subscriptions.add(session.realtime.listen('calls.$waba', _outgoing));
    }
    if (user != null) {
      _subscriptions.add(
        session.realtime.listen('App.Models.User.$user', _incoming),
      );
    }
  }

  void detach() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }

  /// Tells the server this phone can ring for the selected number. Sent with
  /// every heartbeat while the app is in the foreground.
  Future<void> ready() async {
    if (!_canAnswer || session.api.wabaId == null) return;
    try {
      await session.api.post('inbox/calls/ready');
    } on ApiFailure catch (e) {
      if (e.httpStatus == 403) _canAnswer = false;
    } catch (_) {
      /* The next heartbeat tries again. */
    }
  }

  /// The app left the foreground: stop ringing it now, not when the window
  /// lapses. A call in progress keeps going.
  Future<void> gone() async {
    if (busy || session.api.wabaId == null) return;
    try {
      await session.api.request('inbox/calls/ready', method: 'DELETE');
    } catch (_) {
      /* It lapses on its own. */
    }
  }

  // Outgoing.

  Future<void> start(Json customer) async {
    if (busy) return;
    _fresh();
    contact = customer;
    _set(CallState.dialing);
    _system = callUuid('out:${DateTime.now().microsecondsSinceEpoch}');
    unawaited(_systemOngoing());
    unawaited(CallAudio.ringback(true));
    unawaited(CallAudio.proximity(true));
    final media = _call = _newMedia();
    try {
      final sdp = await media.offer();
      if (state != CallState.dialing) return;
      final result = object(
        await session.api.post('inbox/calls/initiate', {
          'contact_id': number(customer['id']),
          'sdp': sdp,
        }),
      );
      if (result['success'] == false) {
        throw ApiFailure('${result['message'] ?? 'The call could not start.'}');
      }
      final calls = object(result['data'])['calls'];
      callId ??= calls is List && calls.isNotEmpty
          ? '${object(calls.first)['id']}'
          : null;
      if (state == CallState.dialing) _set(CallState.ringing);
    } catch (e) {
      if (state != CallState.dialing) return;
      await _end(e is ApiFailure ? e.message : 'The call could not start.');
    }
  }

  /// Events for calls placed from this number. WhatsApp's media answer
  /// (connect) comes as the customer's phone starts to ring, and Meta can
  /// deliver it twice: it is applied once. Applying it again made WebRTC throw
  /// and the call hang up three seconds into ringing. The call goes live on
  /// the ACCEPTED status, when the customer answers.
  void _outgoing(String event, Object? data) {
    if (event != 'calls') return;
    final d = object(data);
    if (d['direction'] != 'BUSINESS_INITIATED') return;
    // Every session on the number hears this channel: only our call counts.
    final id = '${d['call_id'] ?? ''}';
    if (callId != null && id.isNotEmpty && id != callId) return;
    if (callId == null &&
        number(object(d['contact'])['id']) != null &&
        number(object(d['contact'])['id']) != number(contact['id'])) {
      return;
    }
    final placing = state == CallState.dialing || state == CallState.ringing;
    switch (d['event']) {
      case 'connect':
        if (!placing || _answerApplied || d['sdp'] == null) return;
        _answerApplied = true;
        if (id.isNotEmpty) callId ??= id;
        unawaited(_applyAnswer('${d['sdp']}'));
      case 'status':
        if (!placing) return;
        switch ('${d['status'] ?? ''}'.toUpperCase()) {
          case 'ACCEPTED':
            _answered();
          case 'REJECTED':
            _declined = true;
          case 'RINGING':
            if (state == CallState.dialing) _set(CallState.ringing);
        }
      case 'terminate':
        if (!busy) return;
        _end(
          state == CallState.active
              ? 'Call ended'
              : _declined
              ? 'Declined'
              : 'No answer',
        );
    }
  }

  Future<void> _applyAnswer(String sdp) async {
    try {
      await _call?.remoteAnswer(sdp);
    } catch (_) {
      if (busy) await hangUp(reason: 'The call could not connect.');
    }
  }

  void _answered() {
    unawaited(CallAudio.ringback(false));
    connectedAt = DateTime.now();
    _set(CallState.active);
    unawaited(_systemConnected());
  }

  // Incoming.

  void _incoming(String event, Object? data) {
    final d = object(data);
    final id = '${d['call_id'] ?? ''}';
    switch (event) {
      case 'call_ringing' || 'call_initiated':
        if (d['target_client_session_id'] != sessionId) return;
        if (busy || d['sdp'] == null) return;
        _fresh();
        callId = id;
        contact = object(d['contact']);
        _offer = '${d['sdp']}';
        _set(CallState.incoming);
        // The system's incoming-call screen, with the phone's ringtone.
        _system = callUuid(id);
        unawaited(
          showCallFromPush({
            'type': 'call',
            'call_id': id,
            'waba_user_id': '${session.api.wabaId ?? ''}',
            'contact_id': '${contact['id'] ?? ''}',
            'contact_name': '${contact['profile_name'] ?? ''}',
            'contact_phone': '${contact['phone'] ?? ''}',
            'expires_at': '${d['expires_at'] ?? ''}',
          }),
        );
        final expires = DateTime.tryParse('${d['expires_at'] ?? ''}');
        final wait = expires == null
            ? const Duration(seconds: 30)
            : expires.difference(DateTime.now()) + const Duration(seconds: 3);
        _expiry?.cancel();
        _expiry = Timer(wait.isNegative ? Duration.zero : wait, () {
          if (state == CallState.incoming && callId == id) _end('Missed call');
        });
      case 'call_answered':
        if (id != callId) return;
        // Someone else picked it up first.
        if (d['answered_client_session_id'] != sessionId &&
            (state == CallState.incoming || state == CallState.connecting)) {
          _end('Answered by another agent');
        }
      case 'call_released':
        if (id == callId &&
            (state == CallState.incoming || state == CallState.connecting)) {
          _end('Missed call');
        }
      case 'call_missed':
        if (id == callId && state == CallState.incoming) _end('Missed call');
      case 'call_ended':
        if (id == callId && busy) _end('Call ended');
    }
  }

  Future<void> accept() async {
    final id = callId, offer = _offer;
    if (state != CallState.incoming || id == null || offer == null) return;
    _expiry?.cancel();
    _set(CallState.connecting);
    if (!_systemAccepted) {
      // Answered on the app's own screen: take down the system's ringing
      // screen and start its ongoing-call service instead. Answering does
      // not wait for either.
      final uuid = _system;
      unawaited(() async {
        if (uuid != null) {
          await callkit(
            () => FlutterCallkitIncoming.hideCallkitIncoming(
              CallKitParams(id: uuid),
            ),
          );
        }
        await _systemOngoing();
      }());
    }
    await _answer(id, offer);
  }

  /// Accept on the system's incoming-call screen. For a call that rang the
  /// open app the offer is here already; for one that woke the phone by push
  /// it is fetched first.
  Future<void> acceptPushed(Json data) async {
    final id = '${data['call_id'] ?? ''}';
    if (id.isEmpty) return;
    if (state == CallState.incoming && callId == id) {
      _systemAccepted = true;
      return accept();
    }
    if (busy) {
      if (callId != id) {
        // Already on another call: give this one back.
        unawaited(_post('inbox/calls/decline', {'call_id': id}));
      }
      return;
    }
    _fresh();
    callId = id;
    _system = callUuid(id);
    _systemAccepted = true;
    contact = {
      'id': number(data['contact_id']),
      'profile_name': data['contact_name'],
      'phone': data['contact_phone'],
    };
    _set(CallState.connecting);
    try {
      final offer = object(
        object(
          await session.api.post('inbox/calls/offer', {'call_id': id}),
        )['data'],
      );
      if (state != CallState.connecting || callId != id) return;
      contact = {...contact, ...object(offer['contact'])};
      await _answer(id, '${offer['sdp']}');
    } catch (e) {
      if (state != CallState.connecting || callId != id) return;
      await _end(
        e is ApiFailure && e.httpStatus == 410
            ? 'This call is no longer ringing'
            : 'Could not answer the call.',
      );
    }
  }

  /// Decline on the system's incoming-call screen.
  Future<void> declinePushed(String id) async {
    if (id.isEmpty || (busy && callId == id && state != CallState.incoming)) {
      return;
    }
    await _post('inbox/calls/decline', {'call_id': id});
    if (callId == id && state == CallState.incoming) await _end('Declined');
  }

  Future<void> _answer(String id, String offer) async {
    final media = _call = _newMedia();
    unawaited(CallAudio.proximity(true));
    try {
      final answer = await media.answer(offer);
      if (state != CallState.connecting) return;
      final result = object(
        await session.api.post('inbox/calls/accept', {
          'call_id': id,
          'sdp': answer,
          'contact_id': number(contact['id']),
        }),
      );
      if (result['success'] == false) {
        throw ApiFailure('${result['message'] ?? 'Could not answer.'}');
      }
      await _whenConnected(media);
      if (state != CallState.connecting) return;
      await session.api.post('inbox/calls/connected', {'call_id': id});
      connectedAt = DateTime.now();
      _set(CallState.active);
      unawaited(_systemConnected());
    } catch (e) {
      if (state != CallState.connecting) return;
      // Give the call back to the other agents rather than hanging up on it.
      unawaited(_post('inbox/calls/decline', {'call_id': id}));
      await _end(e is ApiFailure ? e.message : 'Could not answer the call.');
    }
  }

  Future<void> _whenConnected(CallMedia media) async {
    if (media.connected.value) return;
    final done = Completer<void>();
    void check() {
      if (media.connected.value && !done.isCompleted) done.complete();
    }

    media.connected.addListener(check);
    try {
      // The server moves the call on after its connection timeout (10 s).
      await done.future.timeout(const Duration(seconds: 10));
    } finally {
      media.connected.removeListener(check);
    }
  }

  Future<void> decline() async {
    final id = callId;
    if (state != CallState.incoming || id == null) return;
    unawaited(_post('inbox/calls/decline', {'call_id': id}));
    await _end('Declined');
  }

  // In a call.

  Future<void> hangUp({String reason = 'Call ended'}) async {
    final id = callId;
    if (state == CallState.incoming) return decline();
    if (!busy) return;
    if (id != null) {
      unawaited(
        _post('inbox/calls/terminate', {
          'call_id': id,
          if (connectedAt != null)
            'call_duration': DateTime.now().difference(connectedAt!).inSeconds,
        }),
      );
    }
    await _end(reason);
  }

  Future<void> toggleMute() async {
    muted = !muted;
    notifyListeners();
    await _call?.mute(muted);
  }

  /// Starts or stops recording, telling the server as the web inbox does:
  /// start-recording first, then stop-recording with the recording. Returns
  /// what went wrong, for the call screen to say, or null.
  Future<String?> toggleRecording() async {
    final id = callId, media = _call;
    if (_recordingBusy || id == null || media == null) return null;
    if (state != CallState.active) return null;
    _recordingBusy = true;
    notifyListeners();
    try {
      if (!recording) {
        await session.api.post('inbox/calls/start-recording', {
          'call_id': id,
          if (number(contact['id']) != null)
            'contact_id': number(contact['id']),
        });
        if (!await media.startRecording(await callRecordingFolder())) {
          return 'This phone cannot record the call.';
        }
        recording = true;
        recordingSince = DateTime.now();
        return null;
      }
      final seconds = _recordedSeconds();
      final blob = await _finishRecording(media);
      await session.api.post('inbox/calls/stop-recording', {
        'call_id': id,
        'recording_blob': ?blob,
        'call_duration': seconds,
      });
      return null;
    } catch (e) {
      if (recording) await _finishRecording(media);
      return '$e';
    } finally {
      _recordingBusy = false;
      notifyListeners();
    }
  }

  int _recordedSeconds() => recordingSince == null
      ? 0
      : DateTime.now().difference(recordingSince!).inSeconds;

  /// Stops the recorders and returns the recording, mixed, as base64; the
  /// files are removed. Null when nothing was recorded.
  Future<String?> _finishRecording(CallMedia media) async {
    recording = false;
    recordingSince = null;
    final files = await media.stopRecording();
    if (files == null) return null;
    return _encodeRecording(files);
  }

  static Future<String?> _encodeRecording((String, String) files) async {
    final out = '${files.$1.replaceAll('-microphone.m4a', '')}-call.m4a';
    try {
      final file = await callRecordingFile(files.$1, files.$2, out);
      return file == null ? null : base64Encode(await file.readAsBytes());
    } finally {
      for (final path in [files.$1, files.$2, out]) {
        unawaited(File(path).delete().then((_) {}, onError: (_) {}));
      }
    }
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    output = null;
    notifyListeners();
    // The screen stays on with the phone away from the ear.
    unawaited(CallAudio.proximity(!speaker));
    await _call?.speaker(speaker);
  }

  /// The outputs to offer when a headset is connected; empty otherwise.
  Future<List<AudioOutput>> headsetOutputs() async {
    try {
      final all = await _call?.outputs() ?? const <AudioOutput>[];
      return all.any((o) => o.headset) ? all : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> routeTo(AudioOutput choice) async {
    speaker = choice.speaker;
    output = choice.headset ? choice : null;
    notifyListeners();
    unawaited(CallAudio.proximity(!speaker && output == null));
    await _call?.route(choice);
  }

  Future<void> _post(String path, Json body) async {
    try {
      await session.api.post(path, body);
    } catch (_) {
      /* The server's own timeouts settle the call. */
    }
  }

  // Android's call system.

  Future<void> _systemOngoing() async {
    final uuid = _system;
    if (uuid == null) return;
    await callkit(
      () => FlutterCallkitIncoming.startCall(
        CallKitParams(
          id: uuid,
          nameCaller: _name,
          appName: 'Telvox Chat',
          handle: '${contact['phone'] ?? contact['wa_id'] ?? ''}',
          type: 0,
          extra: {'call_id': callId ?? ''},
          callingNotification: const NotificationParams(
            showNotification: true,
            isShowCallback: false,
            subtitle: 'WhatsApp call',
          ),
          android: const AndroidParams(
            isCustomNotification: true,
            isShowFullLockedScreen: false,
          ),
        ),
      ),
    );
  }

  Future<void> _systemConnected() async {
    final uuid = _system;
    if (uuid != null) {
      await callkit(() => FlutterCallkitIncoming.setCallConnected(uuid));
    }
  }

  String get _name {
    final name = readableText(contact['profile_name']);
    if (name.isNotEmpty) return name;
    final phone = '${contact['phone'] ?? contact['wa_id'] ?? ''}';
    return phone.isEmpty ? 'WhatsApp call' : '+$phone';
  }

  void _fresh() {
    _reset?.cancel();
    callId = null;
    notice = null;
    connectedAt = null;
    muted = speaker = false;
    output = null;
    _offer = null;
    _answerApplied = _declined = _systemAccepted = false;
    _system = null;
  }

  Future<void> _end(String reason) async {
    _expiry?.cancel();
    unawaited(CallAudio.ringback(false));
    unawaited(CallAudio.proximity(false));
    final system = _system;
    _system = null;
    if (system != null) {
      unawaited(callkit(() => FlutterCallkitIncoming.endCall(system)));
    }
    final media = _call;
    _call = null;
    _offer = null;
    notice = reason;
    // Ended while recording (often the customer hanging up): the recording
    // goes up on its own, as the web inbox uploads it.
    final id = callId;
    if (recording && media != null && id != null) {
      final seconds = _recordedSeconds();
      recording = false;
      recordingSince = null;
      final files = await media.stopRecording();
      if (files != null) unawaited(_uploadRecording(id, files, seconds));
    }
    _set(CallState.ended);
    await media?.close();
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (state == CallState.ended) {
        callId = null;
        connectedAt = null;
        _set(CallState.idle);
      }
    });
  }

  Future<void> _uploadRecording(
    String id,
    (String, String) files,
    int seconds,
  ) async {
    final blob = await _encodeRecording(files);
    if (blob == null) return;
    await _post('inbox/calls/upload-recording', {
      'call_id': id,
      'recording_blob': blob,
      'call_duration': seconds,
    });
  }

  void _set(CallState next) {
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _expiry?.cancel();
    _reset?.cancel();
    unawaited(_call?.close());
    super.dispose();
  }
}

/// The call screen, as WhatsApp lays it out: the contact large in the middle,
/// the state or timer beneath, and the call controls at the bottom.
class CallScreen extends StatefulWidget {
  const CallScreen(this.calls, {super.key});
  final PhoneCalls calls;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.calls.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.calls.state == CallState.active) setState(() {});
    });
  }

  void _changed() {
    if (!mounted) return;
    if (widget.calls.state == CallState.idle) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.calls.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  String get _status {
    final c = widget.calls;
    return switch (c.state) {
      CallState.dialing => 'Calling…',
      CallState.ringing => 'Ringing…',
      CallState.incoming => 'Incoming voice call',
      CallState.connecting => 'Connecting…',
      CallState.active => _clock(
        DateTime.now().difference(c.connectedAt ?? DateTime.now()),
      ),
      CallState.ended => c.notice ?? 'Call ended',
      CallState.idle => '',
    };
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calls;
    final name = readableText(c.contact['profile_name'] ?? c.contact['name'])
        .ifEmpty('+${c.contact['phone'] ?? c.contact['wa_id'] ?? ''}');
    final initials = name.trim().isEmpty
        ? '?'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w.characters.first.toUpperCase())
              .join();
    // The caller's colour, as their inbox row and chat show it.
    final id = c.contact['id'];
    final colors = avatarColors(id == null ? name : '$id');
    // Back leaves the call running; the ongoing-call bar brings it back.
    return PopScope(
      canPop: c.state != CallState.incoming,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF0E2E1F),
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF14432C), Color(0xFF0B241A)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: c.state == CallState.incoming
                        ? const SizedBox(height: 48)
                        : IconButton(
                            tooltip: 'Back to chats',
                            color: Colors.white70,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.call, size: 14, color: Colors.white60),
                      const SizedBox(width: 6),
                      Text(
                        'WhatsApp voice call · ${widget.calls.session.wabaName}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  CircleAvatar(
                    radius: 58,
                    backgroundColor: colors.$1,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: avatarLetterSize(116, initials),
                        fontWeight: FontWeight.w600,
                        height: 1,
                        color: colors.$2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      name,
                      key: const ValueKey('call-name'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    key: const ValueKey('call-status'),
                    style: const TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                  const Spacer(),
                  if (c.state == CallState.incoming)
                    _IncomingControls(c)
                  else
                    _CallControls(c),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls(this.calls);
  final PhoneCalls calls;

  /// With a headset connected, choose where the call plays; otherwise the
  /// button switches between the earpiece and the speaker.
  Future<void> _audio(BuildContext context) async {
    final outputs = await calls.headsetOutputs();
    if (outputs.isEmpty || !context.mounted) {
      await calls.toggleSpeaker();
      return;
    }
    final choice = await showModalBottomSheet<AudioOutput>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in outputs)
              ListTile(
                leading: Icon(
                  o.speaker
                      ? Icons.volume_up
                      : o.headset
                      ? Icons.headset
                      : Icons.phone_in_talk,
                ),
                title: Text(o.label),
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await calls.routeTo(choice);
  }

  @override
  Widget build(BuildContext context) {
    final live = calls.busy;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            label: calls.output?.label ?? 'Speaker',
            icon: calls.output != null
                ? Icons.bluetooth_audio
                : calls.speaker
                ? Icons.volume_up
                : Icons.volume_up_outlined,
            on: calls.speaker || calls.output != null,
            onPressed: live ? () => _audio(context) : null,
          ),
          _RoundButton(
            label: calls.muted ? 'Unmute' : 'Mute',
            icon: calls.muted ? Icons.mic_off : Icons.mic_none,
            on: calls.muted,
            onPressed: live ? calls.toggleMute : null,
          ),
          // Recording, on a number that records its calls on the device.
          if (calls.canRecord && calls.state == CallState.active)
            _RoundButton(
              label: calls.recording ? 'Stop' : 'Record',
              icon: calls.recording
                  ? Icons.stop_rounded
                  : Icons.fiber_manual_record,
              colour: calls.recording ? const Color(0xFFE53935) : null,
              onPressed: () async {
                final problem = await calls.toggleRecording();
                if (problem != null && context.mounted) {
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(SnackBar(content: Text(problem)));
                }
              },
            ),
          _RoundButton(
            label: 'End call',
            icon: Icons.call_end,
            colour: const Color(0xFFE53935),
            onPressed: live ? calls.hangUp : null,
          ),
        ],
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  const _IncomingControls(this.calls);
  final PhoneCalls calls;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundButton(
        label: 'Decline',
        icon: Icons.call_end,
        colour: const Color(0xFFE53935),
        size: 68,
        onPressed: calls.decline,
      ),
      _RoundButton(
        label: 'Accept',
        icon: Icons.call,
        colour: const Color(0xFF25A35A),
        size: 68,
        onPressed: calls.accept,
      ),
    ],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.colour,
    this.on = false,
    this.size = 56,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? colour;
  final bool on;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fill =
        colour ?? (on ? Colors.white : Colors.white.withValues(alpha: .14));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: Material(
            key: ValueKey('call-${label.toLowerCase().replaceAll(' ', '-')}'),
            color: onPressed == null ? fill.withValues(alpha: .4) : fill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  icon,
                  size: size * .46,
                  color: colour == null && on ? T.forest : Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

/// The call button in a chat's top bar: shown when the number can call,
/// disabled with the reason when this contact cannot be called now.
class CallButton extends StatelessWidget {
  const CallButton({super.key, required this.session, required this.contact});
  final MobileSession session;
  final Json contact;
  @override
  Widget build(BuildContext context) {
    final rule = callEligibility(session.config, contact);
    if (!rule.shown) return const SizedBox.shrink();
    return AppIconButton(
      tooltip: rule.blocked ?? 'Voice call',
      onPressed: () {
        if (rule.blocked != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(rule.blocked!)));
          return;
        }
        startCall(context, session, contact);
      },
      icon: Icon(
        isCupertino(context) ? CupertinoIcons.phone : Icons.call_outlined,
        color: rule.blocked == null ? null : T.muted,
      ),
    );
  }
}

/// Starts a call to [contact] and opens the call screen.
Future<void> startCall(
  BuildContext context,
  MobileSession session,
  Json contact,
) async {
  final calls = session.calls;
  if (calls.busy) {
    await showCallScreen(context, calls);
    return;
  }
  unawaited(calls.start(contact));
  await showCallScreen(context, calls);
}

/// Opens the call screen unless it is already showing.
Future<void> showCallScreen(BuildContext context, PhoneCalls calls) =>
    _openCallScreen(Navigator.of(context, rootNavigator: true), calls);

Future<void> _openCallScreen(NavigatorState navigator, PhoneCalls calls) async {
  if (calls.screenOpen) return;
  calls.showingScreen(true);
  try {
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(calls),
      ),
    );
  } finally {
    calls.showingScreen(false);
  }
}

/// A call in progress while the call screen is closed: a green bar over every
/// screen, as WhatsApp shows one, that reopens the call.
class OngoingCallBar extends StatefulWidget {
  const OngoingCallBar(this.calls, {super.key, required this.child});
  final PhoneCalls calls;
  final Widget child;
  @override
  State<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends State<OngoingCallBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.calls.state == CallState.active && !widget.calls.screenOpen) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.calls,
    builder: (context, _) {
      final c = widget.calls;
      final show = c.busy && c.state != CallState.incoming && !c.screenOpen;
      if (!show) return widget.child;
      final at = c.connectedAt;
      final label = c.state == CallState.active && at != null
          ? 'Ongoing call · ${_CallScreenState._clock(DateTime.now().difference(at))}'
          : c.state == CallState.connecting
          ? 'Connecting…'
          : 'Calling…';
      return Column(
        children: [
          Material(
            color: const Color(0xFF1E7A4F),
            child: InkWell(
              key: const ValueKey('ongoing-call-bar'),
              onTap: () {
                final navigator = c.navigator?.currentState;
                if (navigator != null) _openCallScreen(navigator, c);
              },
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.call, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        '$label  ·  Tap to return',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      );
    },
  );
}
