import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'chat_watcher.dart';

/// Keeps users/{uid}.online and .lastSeen up to date.
/// A heartbeat every 60s means a crashed/killed app stops looking online
/// after ~2.5 minutes (see AppUser.isOnline).
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final instance = PresenceService._();

  Timer? _timer;
  bool _running = false;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _goOnline();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    await _write(false);
  }

  void _goOnline() {
    _write(true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _write(true));
  }

  void _goOffline() {
    _timer?.cancel();
    _timer = null;
    _write(false);
  }

  Future<void> _write(bool online) async {
    try {
      await _doc?.set(
        {'online': online, 'lastSeen': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ChatWatcher.instance.appInForeground = true;
        _goOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        ChatWatcher.instance.appInForeground = false;
        _goOffline();
      case AppLifecycleState.inactive:
        break;
    }
  }
}
