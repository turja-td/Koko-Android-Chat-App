import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/call_screen.dart';
import '../widgets/animated_route.dart';
import 'call_service.dart';
import 'permission_service.dart';

/// Starts an outgoing call from anywhere in the app (chat header, calls tab).
Future<void> startCall(BuildContext context, AppUser user, {required bool video}) async {
  if (CallSession.inCall) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('You are already on a call.'),
        behavior: SnackBarBehavior.floating,
      ));
    return;
  }
  final ok = await PermissionService.ensureForCall(context, video: video);
  if (!ok || !context.mounted) return;

  final me = FirebaseAuth.instance.currentUser!;
  final session = CallSession.outgoing(
    calleeId: user.uid,
    peerName: user.name,
    callerName: me.displayName ?? 'Someone',
    video: video,
  );
  Navigator.of(context).push(fadeSlideRoute(CallScreen(session: session)));
}
