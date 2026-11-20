import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../widgets/pulsing_avatar.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.session});
  final CallSession session;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  Timer? _timer;
  int _seconds = 0;
  bool _ready = false, _closing = false;

  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.connected.addListener(_onConnected);
    s.ended.addListener(_onEnded);
    _start();
  }

  Future<void> _start() async {
    try {
      await s.init();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      s.status.value = 'Could not start the call';
      s.ended.value = true;
    }
  }

  void _onConnected() {
    if (!s.connected.value || _timer != null) return;
    _pulse.stop();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() {});
  }

  void _onEnded() {
    if (!s.ended.value) return;
    _timer?.cancel();
    Future.delayed(const Duration(milliseconds: 900), _close);
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  Future<void> _hangUp() async {
    await s.hangUp();
    _close();
  }

  @override
  void dispose() {
    s.connected.removeListener(_onConnected);
    s.ended.removeListener(_onEnded);
    _timer?.cancel();
    _pulse.dispose();
    s.dispose();
    super.dispose();
  }

  String _fmt(int sec) =>
      '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1464), Color(0xFF6C5CE7)],
          ),
        ),
        child: Stack(
          children: [
            if (s.video && _ready)
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: s.connected,
                  builder: (_, connected, __) => AnimatedOpacity(
                    opacity: connected ? 1 : 0,
                    duration: const Duration(milliseconds: 500),
                    child: RTCVideoView(
                      s.remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  ValueListenableBuilder<bool>(
                    valueListenable: s.connected,
                    builder: (_, connected, __) {
                      final hideAvatar = s.video && connected;
                      return Column(
                        children: [
                          AnimatedOpacity(
                            opacity: hideAvatar ? 0 : 1,
                            duration: const Duration(milliseconds: 400),
                            child: PulsingAvatar(
                              animation: _pulse,
                              name: s.peerName,
                              active: !connected,
                            ),
                          ),
                          Text(
                            s.peerName,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ValueListenableBuilder<bool>(
                            valueListenable: s.reconnecting,
                            builder: (_, re, __) => ValueListenableBuilder<String>(
                              valueListenable: s.status,
                              builder: (_, status, __) {
                                final text = re ? 'Reconnecting…' : (connected ? _fmt(_seconds) : status);
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Text(
                                    text,
                                    key: ValueKey(re ? 'reconnecting' : (connected ? 'timer' : status)),
                                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: s.micOn,
                          builder: (_, on, __) => _RoundButton(
                            icon: on ? Icons.mic_rounded : Icons.mic_off_rounded,
                            active: !on,
                            onTap: s.toggleMic,
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: s.speakerOn,
                          builder: (_, on, __) => _RoundButton(
                            icon: on ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                            active: on,
                            onTap: () => s.toggleSpeaker(),
                          ),
                        ),
                        if (s.video)
                          ValueListenableBuilder<bool>(
                            valueListenable: s.camOn,
                            builder: (_, on, __) => _RoundButton(
                              icon: on ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              active: !on,
                              onTap: s.toggleCam,
                            ),
                          ),
                        if (s.video)
                          _RoundButton(
                            icon: Icons.cameraswitch_rounded,
                            onTap: () => s.switchCamera(),
                          ),
                        _RoundButton(
                          icon: Icons.call_end_rounded,
                          color: Colors.red,
                          size: 66,
                          onTap: _hangUp,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            if (s.video && _ready)
              Positioned(
                top: top + 12,
                right: 12,
                width: 108,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    s.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.color,
    this.size = 58,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: .18));
    final fg = color != null ? Colors.white : (active ? const Color(0xFF1B1464) : Colors.white);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, color: fg, size: size * .45),
      ),
    );
  }
}
