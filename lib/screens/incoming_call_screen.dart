import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/call_service.dart';
import '../services/call_sounds.dart';
import '../services/permission_service.dart';
import '../widgets/animated_route.dart';
import '../widgets/pulsing_avatar.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.video,
  });

  final String callId, callerName;
  final bool video;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  StreamSubscription? _sub;
  Timer? _vibrate, _giveUp;
  bool _done = false;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('calls').doc(widget.callId);

  @override
  void initState() {
    super.initState();
    // If the caller hangs up (or the call times out) while we're ringing, close.
    _sub = _doc.snapshots().listen((snap) {
      if (snap.data()?['status'] != 'ringing') _dismiss();
    });
    CallSounds.playRingtone();
    HapticFeedback.vibrate();
    _vibrate = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
    // Safety net if the caller's app died without ending the call.
    _giveUp = Timer(const Duration(seconds: 50), _dismiss);
  }

  void _dismiss() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).maybePop();
  }

  Future<void> _decline() async {
    CallSounds.stop();
    _done = true;
    try {
      await _doc.update({'status': 'rejected'});
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _accept() async {
    CallSounds.stop();
    final ok = await PermissionService.ensureForCall(context, video: widget.video);
    if (!ok) {
      await _decline();
      return;
    }
    if (!mounted) return;
    _done = true;
    Navigator.of(context).pushReplacement(
      fadeSlideRoute(CallScreen(
        session: CallSession.incoming(
          callId: widget.callId,
          peerName: widget.callerName,
          video: widget.video,
        ),
      )),
    );
  }

  @override
  void dispose() {
    CallSounds.stop();
    _sub?.cancel();
    _vibrate?.cancel();
    _giveUp?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1464), Color(0xFF6C5CE7)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 56),
              PulsingAvatar(animation: _pulse, name: widget.callerName),
              Text(
                widget.callerName,
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                widget.video ? 'Incoming video call' : 'Incoming audio call',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.translate(offset: Offset(0, 60 * (1 - v)), child: child),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallAction(icon: Icons.call_end_rounded, color: Colors.red, label: 'Decline', onTap: _decline),
                    _CallAction(
                      icon: widget.video ? Icons.videocam_rounded : Icons.call_rounded,
                      color: Colors.green,
                      label: 'Accept',
                      onTap: _accept,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
