import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models.dart';
import '../screens/chat_screen.dart';
import '../widgets/animated_route.dart';
import 'chat_service.dart';

/// Watches my chats while the app process is alive and
///  1. shows a notification for new messages, and
///  2. marks incoming messages as "delivered" (grey double tick for the sender).
class ChatWatcher {
  ChatWatcher._();
  static final instance = ChatWatcher._();
  static final navigatorKey = GlobalKey<NavigatorState>();

  final _plugin = FlutterLocalNotificationsPlugin();

  bool appInForeground = true;
  String? activeChatUid; // chat currently open on screen

  final Map<String, AppUser> _users = {};
  final Map<String, DateTime> _seen = {};
  final Set<String> _delivered = {};
  StreamSubscription? _userSub, _chatSub;
  bool _firstSnapshot = true;

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) => _openChat(response.payload),
    );
  }

  void start() {
    stop();
    _firstSnapshot = true;
    final me = ChatService.instance.myUid;
    final db = FirebaseFirestore.instance;

    _userSub = db.collection('users').snapshots().listen((s) {
      for (final d in s.docs) {
        _users[d.id] = AppUser.fromMap(d.data());
      }
    });
    _chatSub = db
        .collection('chats')
        .where('participants', arrayContains: me)
        .snapshots()
        .listen((s) => _onChats(s, me));
  }

  void stop() {
    _userSub?.cancel();
    _chatSub?.cancel();
    _userSub = null;
    _chatSub = null;
    _seen.clear();
    _delivered.clear();
  }

  void _onChats(QuerySnapshot<Map<String, dynamic>> snap, String me) {
    final first = _firstSnapshot;
    _firstSnapshot = false;

    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      final m = change.doc.data();
      if (m == null) continue;

      final lastTime = (m['lastTime'] as Timestamp?)?.toDate();
      if (lastTime == null) continue;

      final other = List<String>.from(m['participants'] ?? []).firstWhere(
        (id) => id != me,
        orElse: () => '',
      );
      if (other.isEmpty) continue;

      final fromOther = m['lastSenderId'] != me;
      final previous = _seen[other];
      _seen[other] = lastTime;

      if (fromOther) _markDelivered(change.doc, me, lastTime, m);

      if (first) continue; // existing state, not a new message
      if (previous != null && !lastTime.isAfter(previous)) continue; // typing/read updates
      if (!fromOther) continue;
      if (appInForeground && activeChatUid == other) continue; // already looking at it

      _show(other, (m['lastMessage'] ?? '') as String);
    }
  }

  void _markDelivered(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String me,
    DateTime lastTime,
    Map<String, dynamic> m,
  ) {
    final delivered = (((m['lastDeliveredAt'] as Map?)?[me]) as Timestamp?)?.toDate();
    if (delivered != null && !delivered.isBefore(lastTime)) return;
    final key = '${doc.id}_${lastTime.millisecondsSinceEpoch}';
    if (!_delivered.add(key)) return;
    doc.reference
        .update({'lastDeliveredAt.$me': FieldValue.serverTimestamp()})
        .catchError((_) {});
  }

  int _idFor(String uid) => uid.hashCode & 0x7fffffff;

  Future<void> _show(String otherUid, String body) async {
    final name = _users[otherUid]?.name ?? 'New message';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'New message alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      await _plugin.show(
        id: _idFor(otherUid),
        title: name,
        body: body,
        notificationDetails: details,
        payload: otherUid,
      );
    } catch (_) {}
  }

  Future<void> clearFor(String uid) async {
    try {
      await _plugin.cancel(id: _idFor(uid));
    } catch (_) {}
  }

  void _openChat(String? uid) {
    final user = uid == null ? null : _users[uid];
    final nav = navigatorKey.currentState;
    if (user == null || nav == null || activeChatUid == uid) return;
    nav.push(fadeSlideRoute(ChatScreen(other: user)));
  }
}
