import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

class ChatService {
  ChatService._();
  static final instance = ChatService._();

  final _db = FirebaseFirestore.instance;
  String get myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// One chat per pair of users: the two uids sorted and joined.
  static String chatId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  DocumentReference<Map<String, dynamic>> _chat(String otherUid) =>
      _db.collection('chats').doc(chatId(myUid, otherUid));

  Stream<List<AppUser>> users() => _db.collection('users').snapshots().map(
        (s) => s.docs
            .map((d) => AppUser.fromMap(d.data()))
            .where((u) => u.uid != myUid)
            .toList(),
      );

  /// Chat-list info for every chat I'm in, keyed by the OTHER user's uid.
  Stream<Map<String, ChatMeta>> chatMetas() => _db
          .collection('chats')
          .where('participants', arrayContains: myUid)
          .snapshots()
          .map((s) {
        final out = <String, ChatMeta>{};
        for (final d in s.docs) {
          final m = d.data();
          if (m['lastMessage'] == null) continue; // typing-only doc, no messages yet
          final others = List<String>.from(m['participants'] ?? []).where((id) => id != myUid);
          if (others.isEmpty) continue;
          final other = others.first;
          out[other] = ChatMeta(
            lastMessage: m['lastMessage'] ?? '',
            lastSenderId: m['lastSenderId'] ?? '',
            lastTime: (m['lastTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
            unread: (((m['unread'] as Map?)?[myUid]) as num?)?.toInt() ?? 0,
            typingAt: (((m['typing'] as Map?)?[other]) as Timestamp?)?.toDate(),
          );
        }
        return out;
      });

  /// Typing / read / delivered markers from the other person.
  Stream<ChatInfo> chatInfo(String otherUid) => _chat(otherUid).snapshots().map((s) {
        final m = s.data();
        if (m == null) return ChatInfo.empty;
        DateTime? ts(String field) => (((m[field] as Map?)?[otherUid]) as Timestamp?)?.toDate();
        return ChatInfo(
          typingAt: ts('typing'),
          otherLastReadAt: ts('lastReadAt'),
          otherLastDeliveredAt: ts('lastDeliveredAt'),
        );
      });

  Stream<List<Message>> messages(String otherUid) => _chat(otherUid)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(Message.fromDoc).toList());

  Future<void> send({
    required String otherUid,
    String type = 'text',
    String? text,
    String? url,
    String? fileName,
    int? size,
    ReplyRef? reply,
  }) async {
    final chatRef = _chat(otherUid);
    final msgRef = chatRef.collection('messages').doc();
    final preview = switch (type) {
      'image' => '📷 Photo',
      'file' => '📎 ${fileName ?? 'File'}',
      _ => text ?? '',
    };

    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': myUid,
      'type': type,
      'text': text,
      'url': url,
      'fileName': fileName,
      'size': size,
      'replyTo': reply == null ? null : {'id': reply.id, 'senderId': reply.senderId, 'text': reply.text},
      'deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      chatRef,
      {
        'participants': [myUid, otherUid],
        'lastMessage': preview,
        'lastSenderId': myUid,
        'lastTime': FieldValue.serverTimestamp(),
        'unread': {otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Pass null to remove my reaction.
  Future<void> react(String otherUid, String messageId, String? emoji) {
    return _chat(otherUid).collection('messages').doc(messageId).update({
      'reactions.$myUid': emoji ?? FieldValue.delete(),
    });
  }

  Stream<List<CallLog>> callLogs() => _db
          .collection('callLogs')
          .where('participants', arrayContains: myUid)
          .snapshots()
          .map((s) {
        final list = s.docs.map(CallLog.fromDoc).toList();
        final now = DateTime.now();
        list.sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
        return list;
      });

  Future<void> deleteMessage(String otherUid, String messageId) {
    return _chat(otherUid).collection('messages').doc(messageId).update({
      'deleted': true,
      'text': null,
      'url': null,
      'fileName': null,
    });
  }

  /// "I've seen everything up to now" (drives the blue ticks on the other side).
  Future<void> markRead(String otherUid) async {
    try {
      await _chat(otherUid).set(
        {
          'participants': [myUid, otherUid],
          'unread': {myUid: 0},
          'lastReadAt': {myUid: FieldValue.serverTimestamp()},
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> setTyping(String otherUid, bool typing) async {
    try {
      if (typing) {
        await _chat(otherUid).set(
          {
            'participants': [myUid, otherUid],
            'typing': {myUid: FieldValue.serverTimestamp()},
          },
          SetOptions(merge: true),
        );
      } else {
        await _chat(otherUid).update({'typing.$myUid': FieldValue.delete()});
      }
    } catch (_) {}
  }

  /// Written by the caller when a call ends, so both people see it in the chat.
  Future<void> sendCallLog({
    required String otherUid,
    required bool video,
    required String outcome, // completed | missed | declined | busy | failed
    required int seconds,
  }) async {
    final chatRef = _chat(otherUid);
    final msgRef = chatRef.collection('messages').doc();
    final kind = video ? 'video' : 'voice';
    final preview = switch (outcome) {
      'completed' => '📞 ${kind[0].toUpperCase()}${kind.substring(1)} call',
      'missed' => 'Missed $kind call',
      'declined' => 'Call declined',
      'busy' => 'Busy',
      _ => 'Call failed',
    };

    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': myUid,
      'type': 'call',
      'callVideo': video,
      'callOutcome': outcome,
      'callSeconds': seconds,
      'deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      chatRef,
      {
        'participants': [myUid, otherUid],
        'lastMessage': preview,
        'lastSenderId': myUid,
        'lastTime': FieldValue.serverTimestamp(),
        if (outcome == 'missed') 'unread': {otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );
    batch.set(_db.collection('callLogs').doc(), {
      'participants': [myUid, otherUid],
      'callerId': myUid,
      'calleeId': otherUid,
      'video': video,
      'outcome': outcome,
      'seconds': seconds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
