import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'message_content.dart' show readableText;
import 'models.dart';
import 'realtime.dart';

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
  Future<void> close();
}

/// WebRTC through flutter_webrtc, as the web inbox does it in the browser:
/// one audio track, Opus by default, Google STUN for the phone's public
/// address. Meta's side takes the whole SDP in one request, so the SDP is
/// sent once ICE gathering has finished (or after a short wait), never
/// trickled.
class WebRtcCallMedia implements CallMedia {
  static const _ice = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };
  static const _gathering = Duration(seconds: 3);

  RTCPeerConnection? _peer;
  MediaStream? _local;
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
    final peer = await createPeerConnection(_ice);
    for (final track in _local!.getAudioTracks()) {
      await peer.addTrack(track, _local!);
    }
    peer.onConnectionState = (state) => _connected.value =
        state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    // Calls use the earpiece until the agent turns the speaker on.
    await Helper.setSpeakerphoneOn(false);
    return _peer = peer;
  }

  /// Waits for ICE gathering so the SDP carries the candidates.
  Future<String> _gathered(RTCPeerConnection peer) async {
    if (peer.iceGatheringState !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      final done = Completer<void>();
      peer.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !done.isCompleted) {
          done.complete();
        }
      };
      await done.future.timeout(_gathering, onTimeout: () {});
    }
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
  Future<void> close() async {
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
class PhoneCalls extends ChangeNotifier {
  PhoneCalls(this.session, {CallMedia Function()? media})
    : _media = media ?? WebRtcCallMedia.new;
  final MobileSession session;
  final CallMedia Function() _media;

  CallState state = CallState.idle;
  Json contact = const {};
  String? callId, notice;
  DateTime? connectedAt;
  bool muted = false, speaker = false;

  /// The call screen is showing; a second ring or tap does not open another.
  bool screenOpen = false;
  String? _offer;
  CallMedia? _call;
  Timer? _expiry, _buzz, _reset;
  final _subscriptions = <RealtimeSubscription>[];

  /// False once the server says this account cannot take calls.
  bool _canAnswer = true;

  bool get busy => state != CallState.idle && state != CallState.ended;

  String? get sessionId {
    final device = number(object(session.user?['device'])['id']);
    return device == null ? null : 'mobile:$device';
  }

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
    _reset?.cancel();
    contact = customer;
    callId = null;
    notice = null;
    muted = speaker = false;
    _set(CallState.dialing);
    final media = _call = _media();
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
      await _end(e is ApiFailure ? e.message : 'The call could not start.');
    }
  }

  void _outgoing(String event, Object? data) {
    if (event != 'calls') return;
    final d = object(data);
    if (d['direction'] != 'BUSINESS_INITIATED') return;
    if (state != CallState.dialing &&
        state != CallState.ringing &&
        state != CallState.active) {
      return;
    }
    // Every session on the number hears this channel: only our call counts.
    final id = '${d['call_id'] ?? ''}';
    if (callId != null && id != callId) return;
    if (callId == null &&
        number(object(d['contact'])['id']) != number(contact['id'])) {
      return;
    }
    callId ??= id;
    if (d['event'] == 'connect' && d['sdp'] != null) {
      _connectOutgoing('${d['sdp']}');
    } else if (d['event'] == 'terminate') {
      _end(state == CallState.active ? 'Call ended' : 'No answer');
    }
  }

  Future<void> _connectOutgoing(String sdp) async {
    try {
      await _call?.remoteAnswer(sdp);
      connectedAt = DateTime.now();
      _set(CallState.active);
    } catch (_) {
      await hangUp(reason: 'The call could not connect.');
    }
  }

  // Incoming.

  void _incoming(String event, Object? data) {
    final d = object(data);
    final id = '${d['call_id'] ?? ''}';
    switch (event) {
      case 'call_ringing' || 'call_initiated':
        if (d['target_client_session_id'] != sessionId) return;
        if (busy || d['sdp'] == null) return;
        _reset?.cancel();
        callId = id;
        contact = object(d['contact']);
        _offer = '${d['sdp']}';
        notice = null;
        muted = speaker = false;
        _set(CallState.incoming);
        _ring();
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

  /// Vibrates like a ringing phone until answered, declined or gone.
  void _ring() {
    _buzz?.cancel();
    HapticFeedback.heavyImpact();
    _buzz = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (state != CallState.incoming) {
        _buzz?.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
    });
  }

  Future<void> accept() async {
    final id = callId, offer = _offer;
    if (state != CallState.incoming || id == null || offer == null) return;
    _buzz?.cancel();
    _expiry?.cancel();
    _set(CallState.connecting);
    final media = _call = _media();
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

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    notifyListeners();
    await _call?.speaker(speaker);
  }

  Future<void> _post(String path, Json body) async {
    try {
      await session.api.post(path, body);
    } catch (_) {
      /* The server's own timeouts settle the call. */
    }
  }

  Future<void> _end(String reason) async {
    _buzz?.cancel();
    _expiry?.cancel();
    final media = _call;
    _call = null;
    _offer = null;
    notice = reason;
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

  void _set(CallState next) {
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _buzz?.cancel();
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
    return PopScope(
      // A call in progress is ended from the screen, not by going back.
      canPop: !c.busy,
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
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 56),
                  CircleAvatar(
                    radius: 58,
                    backgroundColor: T.greenWash,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        color: T.forest,
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
            label: 'Speaker',
            icon: calls.speaker ? Icons.volume_up : Icons.volume_up_outlined,
            on: calls.speaker,
            onPressed: live ? calls.toggleSpeaker : null,
          ),
          _RoundButton(
            label: calls.muted ? 'Unmute' : 'Mute',
            icon: calls.muted ? Icons.mic_off : Icons.mic_none,
            on: calls.muted,
            onPressed: live ? calls.toggleMute : null,
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
Future<void> showCallScreen(BuildContext context, PhoneCalls calls) async {
  if (calls.screenOpen) return;
  calls.screenOpen = true;
  try {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(calls),
      ),
    );
  } finally {
    calls.screenOpen = false;
  }
}
