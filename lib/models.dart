import 'package:cloud_firestore/cloud_firestore.dart';

enum MsgStatus { pending, sent, delivered, read }

class AppUser {
  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.about = '',
    this.photoUrl,
    this.lastSeen,
    this.online = false,
    this.hidePresence = false,
  });

  final String uid, name, email, about;
  final String? photoUrl;
  final DateTime? lastSeen;
  final bool online, hidePresence;

  /// The "online" flag AND a recent heartbeat, so a crashed app can't stay "online" forever.
  bool get isOnline =>
      !hidePresence && online && lastSeen != null && DateTime.now().difference(lastSeen!).inSeconds.abs() < 150;

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        uid: m['uid'] ?? '',
        name: m['name'] ?? 'Unknown',
        email: m['email'] ?? '',
        about: m['about'] ?? '',
        photoUrl: m['photoUrl'],
        lastSeen: (m['lastSeen'] as Timestamp?)?.toDate(),
        online: m['online'] == true,
        hidePresence: m['hidePresence'] == true,
      );
}

class ChatMeta {
  ChatMeta({
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastTime,
    this.unread = 0,
    this.typingAt,
  });

  final String lastMessage, lastSenderId;
  final DateTime lastTime;
  final int unread;
  final DateTime? typingAt;

  bool get isTyping => typingAt != null && DateTime.now().difference(typingAt!).inSeconds.abs() < 10;
}

/// Live info about one chat, from the other person's side.
class ChatInfo {
  const ChatInfo({this.typingAt, this.otherLastReadAt, this.otherLastDeliveredAt});
  static const empty = ChatInfo();

  final DateTime? typingAt, otherLastReadAt, otherLastDeliveredAt;

  bool get isTyping => typingAt != null && DateTime.now().difference(typingAt!).inSeconds.abs() < 10;
}

class ReplyRef {
  ReplyRef({required this.id, required this.senderId, required this.text});
  final String id, senderId, text;
}

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.type,
    this.text,
    this.url,
    this.fileName,
    this.size,
    this.createdAt,
    this.reply,
    this.deleted = false,
    this.callVideo = false,
    this.callOutcome,
    this.callSeconds,
    this.reactions = const {},
  });

  final String id, senderId, type; // type: text | image | file | call
  final String? text, url, fileName, callOutcome;
  final int? size, callSeconds;
  final DateTime? createdAt;
  final ReplyRef? reply;
  final bool deleted, callVideo;
  final Map<String, String> reactions; // uid -> emoji

  factory Message.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final r = m['replyTo'] as Map?;
    return Message(
      id: d.id,
      senderId: m['senderId'] ?? '',
      type: m['type'] ?? 'text',
      text: m['text'],
      url: m['url'],
      fileName: m['fileName'],
      size: (m['size'] as num?)?.toInt(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      reply: r == null
          ? null
          : ReplyRef(id: r['id'] ?? '', senderId: r['senderId'] ?? '', text: r['text'] ?? ''),
      deleted: m['deleted'] == true,
      callVideo: m['callVideo'] == true,
      callOutcome: m['callOutcome'],
      callSeconds: (m['callSeconds'] as num?)?.toInt(),
      reactions: (m['reactions'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
    );
  }
}

class CallLog {
  CallLog({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.video,
    required this.outcome,
    required this.seconds,
    this.createdAt,
  });

  final String id, callerId, calleeId, outcome; // outcome: completed | missed | declined | busy | failed
  final bool video;
  final int seconds;
  final DateTime? createdAt;

  factory CallLog.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return CallLog(
      id: d.id,
      callerId: m['callerId'] ?? '',
      calleeId: m['calleeId'] ?? '',
      video: m['video'] == true,
      outcome: m['outcome'] ?? 'failed',
      seconds: (m['seconds'] as num?)?.toInt() ?? 0,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
