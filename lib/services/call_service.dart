import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import 'call_sounds.dart';
import 'chat_service.dart';

/// One call = one Firestore doc at calls/{callId}, used only as the signaling
/// channel (offer, answer, ICE candidates). Audio/video flows peer-to-peer.
///
/// Robustness features:
///  - TURN relay (Metered) so calls work between different networks/emulators
///  - every offer/answer/candidate carries a round number ("seq") so stale
///    data from an earlier round is never applied
///  - automatic ICE restart (up to 3 times) when the connection drops
///  - timeouts for ringing, connecting and reconnecting
///  - busy detection, call log message, screen kept awake
class CallSession {
  CallSession.outgoing({
    required this.calleeId,
    required this.peerName,
    required this.callerName,
    required this.video,
  })  : isCaller = true,
        callId = FirebaseFirestore.instance.collection('calls').doc().id;

  CallSession.incoming({
    required this.callId,
    required this.peerName,
    required this.video,
  })  : isCaller = false,
        calleeId = null,
        callerName = null;

  /// True while any call screen is active (used to answer "busy" to a second caller).
  static bool inCall = false;

  final String callId;
  final bool isCaller, video;
  final String peerName;
  final String? calleeId, callerName;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  final status = ValueNotifier<String>('Starting…');
  final connected = ValueNotifier<bool>(false);
  final reconnecting = ValueNotifier<bool>(false);
  final ended = ValueNotifier<bool>(false);
  final micOn = ValueNotifier<bool>(true);
  final camOn = ValueNotifier<bool>(true);
  final speakerOn = ValueNotifier<bool>(false);

  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subs = [];
  RTCPeerConnection? _pc;
  MediaStream? _local;

  Timer? _ringTimer, _connectTimer, _disconnectTimer, _failTimer;

  int _seq = 0; // my current offer/answer round
  int _remoteSeq = -1; // the round of the remote description I applied last
  final List<Map<String, dynamic>> _pending = []; // candidates that arrived early
  bool _busy = false, _restarting = false;
  int _restarts = 0;

  bool _docCreated = false, _hungUp = false, _disposed = false;
  String _outcome = 'missed';
  DateTime? _connectedAt, _endedAt;

  DocumentReference<Map<String, dynamic>> get _doc => _db.collection('calls').doc(callId);

  // ---- setup ---------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _iceServers() async {
    final servers = <Map<String, dynamic>>[
      {
        'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
      },
    ];
    if (Config.meteredAppName.isNotEmpty && Config.meteredApiKey.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(
              'https://${Config.meteredAppName}.metered.live/api/v1/turn/credentials?apiKey=${Config.meteredApiKey}',
            ))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          for (final e in jsonDecode(res.body) as List) {
            servers.add(Map<String, dynamic>.from(e as Map));
          }
        }
      } catch (_) {
        // Fall back to STUN only.
      }
    }
    return servers;
  }

  Future<void> init() async {
    inCall = true;
    WakelockPlus.enable();

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    status.value = 'Getting ready…';
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = _local;

    speakerOn.value = video;
    try {
      await Helper.setSpeakerphoneOn(video);
    } catch (_) {}

    _pc = await createPeerConnection({
      'iceServers': await _iceServers(),
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) remoteRenderer.srcObject = e.streams.first;
    };
    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      final map = Map<String, dynamic>.from(c.toMap() as Map);
      map['seq'] = _seq;
      _doc.collection(isCaller ? 'callerCandidates' : 'calleeCandidates').add(map).catchError((_) => _doc);
    };
    _pc!.onConnectionState = _onConnectionState;

    if (isCaller) {
      await _startAsCaller();
    } else {
      await _startAsCallee();
    }
  }

  // ---- caller --------------------------------------------------------------

  Future<void> _startAsCaller() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // The doc is created only once the offer exists, so the callee never sees
    // a ringing call that has nothing to answer.
    await _doc.set({
      'callerId': FirebaseAuth.instance.currentUser!.uid,
      'callerName': callerName,
      'calleeId': calleeId,
      'video': video,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'offerSeq': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _docCreated = true;
    status.value = 'Ringing…';
    CallSounds.playRingback();

    _ringTimer = Timer(const Duration(seconds: 45), () async {
      if (!connected.value && _remoteSeq < 0) {
        status.value = 'No answer';
        _outcome = 'missed';
        await hangUp();
        _finish();
      }
    });

    _subs.add(_doc.snapshots().listen(_onCallerDoc));
    _listenCandidates('calleeCandidates');
  }

  Future<void> _onCallerDoc(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final d = snap.data();
    if (d == null || _hungUp) return;

    final answer = d['answer'];
    final answerSeq = (d['answerSeq'] as num?)?.toInt();
    if (answer != null && answerSeq == _seq && _remoteSeq < _seq && !_busy) {
      _busy = true;
      try {
        await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
        _remoteSeq = _seq;
        CallSounds.stop();
        _ringTimer?.cancel();
        if (!connected.value) status.value = 'Connecting…';
        _armConnectTimer();
        await _flushPending();
      } catch (_) {
        _giveUp('Could not connect');
      } finally {
        _busy = false;
      }
    }

    switch (d['status']) {
      case 'rejected':
        _outcome = 'declined';
        status.value = 'Declined';
        _finish();
      case 'busy':
        _outcome = 'busy';
        status.value = 'User is busy';
        _finish();
      case 'ended':
        if (!connected.value && _outcome == 'missed') status.value = 'Call ended';
        _finish();
    }
  }

  // ---- callee --------------------------------------------------------------

  Future<void> _startAsCallee() async {
    status.value = 'Connecting…';
    _subs.add(_doc.snapshots().listen(_onCalleeDoc));
    _listenCandidates('callerCandidates');
  }

  Future<void> _onCalleeDoc(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final d = snap.data();
    if (d == null || _hungUp) return;

    final offer = d['offer'];
    final offerSeq = (d['offerSeq'] as num?)?.toInt() ?? 0;
    if (offer != null && offerSeq > _remoteSeq && !_busy) {
      _busy = true;
      try {
        await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
        _remoteSeq = offerSeq;
        _seq = offerSeq;
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await _doc.update({
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'answerSeq': offerSeq,
          'status': 'accepted',
        });
        _armConnectTimer();
        await _flushPending();
      } catch (_) {
        _giveUp('Could not connect');
      } finally {
        _busy = false;
      }
    }

    if (d['status'] == 'ended') {
      status.value = 'Call ended';
      _finish();
    }
  }

  // ---- ICE candidates ------------------------------------------------------

  void _listenCandidates(String collection) {
    _subs.add(_doc.collection(collection).snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        _onCandidate(change.doc.data()!);
      }
    }));
  }

  int _seqOf(Map<String, dynamic> d) => (d['seq'] as num?)?.toInt() ?? 0;

  void _onCandidate(Map<String, dynamic> d) {
    final seq = _seqOf(d);
    if (seq > _remoteSeq) {
      _pending.add(d); // remote description for this round isn't applied yet
    } else if (seq == _remoteSeq) {
      _addCandidate(d);
    } // older rounds are stale: ignore
  }

  Future<void> _flushPending() async {
    final ready = _pending.where((d) => _seqOf(d) == _remoteSeq).toList();
    _pending.removeWhere((d) => _seqOf(d) <= _remoteSeq);
    for (final d in ready) {
      await _addCandidate(d);
    }
  }

  Future<void> _addCandidate(Map<String, dynamic> d) async {
    try {
      await _pc?.addCandidate(RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
    } catch (_) {}
  }

  // ---- connection health ---------------------------------------------------

  void _onConnectionState(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        CallSounds.stop();
        _ringTimer?.cancel();
        _connectTimer?.cancel();
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        _failTimer?.cancel();
        _connectedAt ??= DateTime.now();
        reconnecting.value = false;
        status.value = 'Connected';
        connected.value = true;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (!connected.value) break;
        reconnecting.value = true;
        _disconnectTimer ??= Timer(const Duration(seconds: 4), () {
          _disconnectTimer = null;
          _restartIce();
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        reconnecting.value = connected.value;
        _restartIce();
      default:
        break;
    }
  }

  void _armConnectTimer() {
    _connectTimer ??= Timer(const Duration(seconds: 25), () {
      if (!connected.value) _giveUp('Could not connect');
    });
  }

  void _armFailTimer() {
    _failTimer?.cancel();
    _failTimer = Timer(const Duration(seconds: 20), () => _giveUp('Connection lost'));
  }

  /// Only the caller restarts (sends a fresh offer); the callee answers it.
  Future<void> _restartIce() async {
    if (_hungUp || _restarting) return;
    if (!isCaller) {
      _armFailTimer();
      return;
    }
    if (_restarts >= 3) {
      _giveUp('Connection lost');
      return;
    }
    _restarting = true;
    _restarts++;
    try {
      await _pc!.restartIce();
      _seq++; // before creating the offer so new candidates carry the new round
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _doc.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'offerSeq': _seq,
      });
      _armFailTimer();
    } catch (_) {
      _giveUp('Connection lost');
    } finally {
      _restarting = false;
    }
  }

  void _giveUp(String message) {
    if (_hungUp || ended.value) return;
    _outcome = 'failed';
    status.value = message;
    _finish();
  }

  void _finish() {
    _endedAt ??= DateTime.now();
    CallSounds.stop();
    if (!_disposed) ended.value = true;
  }

  // ---- in-call controls ----------------------------------------------------

  void toggleMic() {
    micOn.value = !micOn.value;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn.value;
    }
  }

  void toggleCam() {
    if (!video) return;
    camOn.value = !camOn.value;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn.value;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    speakerOn.value = !speakerOn.value;
    try {
      await Helper.setSpeakerphoneOn(speakerOn.value);
    } catch (_) {}
  }

  // ---- teardown ------------------------------------------------------------

  Future<void> hangUp() async {
    if (_hungUp) return;
    _hungUp = true;
    inCall = false;
    CallSounds.stop();
    for (final t in [_ringTimer, _connectTimer, _disconnectTimer, _failTimer]) {
      t?.cancel();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await _doc.update({'status': 'ended'});
    } catch (_) {}

    if (isCaller && _docCreated) _logCall();

    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    await _pc?.close();
    WakelockPlus.disable();
  }

  void _logCall() {
    final end = _endedAt ?? DateTime.now();
    final seconds = _connectedAt == null ? 0 : end.difference(_connectedAt!).inSeconds;
    ChatService.instance
        .sendCallLog(
          otherUid: calleeId!,
          video: video,
          outcome: _connectedAt != null ? 'completed' : _outcome,
          seconds: seconds,
        )
        .catchError((_) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    await hangUp();
    inCall = false;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
