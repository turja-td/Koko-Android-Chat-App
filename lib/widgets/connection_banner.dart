import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Slides in when the app can't reach Firebase for a few seconds.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription? _sub;
  Timer? _timer;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen((s) {
      if (s.metadata.isFromCache) {
        // Ignore the short "from cache" moment at startup.
        _timer ??= Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _offline = true);
        });
      } else {
        _timer?.cancel();
        _timer = null;
        if (_offline && mounted) setState(() => _offline = false);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: _offline
          ? Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.onErrorContainer),
                  ),
                  const SizedBox(width: 10),
                  Text('Waiting for network…',
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
