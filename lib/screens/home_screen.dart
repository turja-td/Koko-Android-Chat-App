import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/chat_watcher.dart';
import '../services/permission_service.dart';
import '../services/presence_service.dart';
import '../widgets/animated_route.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'incoming_call_screen.dart';
import 'settings_tab.dart';

/// The signed-in shell: starts the background services and hosts the three tabs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pages = PageController();
  late final Stream<Map<String, ChatMeta>> _metas = ChatService.instance.chatMetas();
  StreamSubscription? _callSub;
  int _index = 0;
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    PresenceService.instance.start();
    ChatWatcher.instance.start();
    _listenForCalls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PermissionService.requestAllOnce(context);
    });
  }

  /// Rings while the app is open. (Waking a closed app needs push notifications.)
  void _listenForCalls() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added || !mounted) continue;
        final d = change.doc.data();
        if (d == null) continue;
        final created = (d['createdAt'] as Timestamp?)?.toDate();
        if (created == null || DateTime.now().difference(created).abs().inSeconds > 60) continue;

        // Already on a call or already ringing: tell the caller we're busy.
        if (_ringing || CallSession.inCall) {
          change.doc.reference.update({'status': 'busy'}).catchError((_) {});
          continue;
        }

        _ringing = true;
        Navigator.of(context)
            .push(fadeSlideRoute(IncomingCallScreen(
              callId: change.doc.id,
              callerName: d['callerName'] ?? 'Someone',
              video: d['video'] == true,
            )))
            .whenComplete(() => _ringing = false);
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pages,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          _KeepAlive(child: ChatsTab()),
          _KeepAlive(child: CallsTab()),
          _KeepAlive(child: SettingsTab()),
        ],
      ),
      bottomNavigationBar: StreamBuilder<Map<String, ChatMeta>>(
        stream: _metas,
        builder: (context, snap) {
          final unread = (snap.data ?? {}).values.fold<int>(0, (total, m) => total + m.unread);
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            ),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble_rounded),
                ),
                label: 'Chats',
              ),
              const NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call_rounded),
                label: 'Calls',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
