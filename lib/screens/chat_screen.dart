import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models.dart';
import '../services/call_launcher.dart';
import '../services/chat_service.dart';
import '../services/chat_watcher.dart';
import '../services/cloudinary_service.dart';
import '../services/user_service.dart';
import '../theme/chat_theme.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_background.dart';
import '../widgets/chat_theme_sheet.dart';
import '../widgets/connection_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/shimmer.dart';
import '../widgets/swipe_to_reply.dart';
import '../widgets/typing_bubble.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.other});
  final AppUser other;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _service = ChatService.instance;
  late final Stream<List<Message>> _messages = _service.messages(widget.other.uid);
  late final Stream<ChatInfo> _info = _service.chatInfo(widget.other.uid);
  late final Stream<AppUser?> _otherUser = UserService.instance.watch(widget.other.uid);

  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _showJump = ValueNotifier<bool>(false);
  final _newCount = ValueNotifier<int>(0);

  ChatTheme _theme = kDefaultChatTheme;
  bool _uploading = false;
  Message? _replying;
  Timer? _tick, _typingIdle, _highlightTimer;
  DateTime? _lastTypingSent;
  List<Message> _latest = const [];
  String? _markedId, _prevNewestId, _highlightId;

  bool get _hasText => _ctrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatWatcher.instance.activeChatUid = widget.other.uid;
    ChatWatcher.instance.clearFor(widget.other.uid);
    _ctrl.addListener(_onTextChanged);
    _positions.itemPositions.addListener(_onPositions);
    ChatThemeStore.load(widget.other.uid).then((t) {
      if (mounted) setState(() => _theme = t);
    });
    // Refresh "online" / "typing" labels as time passes.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopTyping();
    if (ChatWatcher.instance.activeChatUid == widget.other.uid) {
      ChatWatcher.instance.activeChatUid = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    _tick?.cancel();
    _typingIdle?.cancel();
    _highlightTimer?.cancel();
    _showJump.dispose();
    _newCount.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeMarkRead();
    } else if (state == AppLifecycleState.paused) {
      _stopTyping();
    }
  }

  // ---- typing indicator ----------------------------------------------------

  void _onTextChanged() {
    setState(() {});
    if (_hasText) {
      final now = DateTime.now();
      if (_lastTypingSent == null || now.difference(_lastTypingSent!).inSeconds >= 4) {
        _lastTypingSent = now;
        _service.setTyping(widget.other.uid, true);
      }
      _typingIdle?.cancel();
      _typingIdle = Timer(const Duration(seconds: 3), _stopTyping);
    } else {
      _stopTyping();
    }
  }

  void _stopTyping() {
    _typingIdle?.cancel();
    if (_lastTypingSent != null) {
      _lastTypingSent = null;
      _service.setTyping(widget.other.uid, false);
    }
  }

  // ---- read receipts, scrolling -------------------------------------------

  void _maybeMarkRead() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (_latest.isEmpty) return;
    final newest = _latest.first;
    if (newest.senderId == _service.myUid) return;
    if (_markedId == newest.id) return;
    _markedId = newest.id;
    _service.markRead(widget.other.uid);
  }

  MsgStatus _statusFor(Message m, ChatInfo info) {
    final t = m.createdAt;
    if (t == null) return MsgStatus.pending;
    final read = info.otherLastReadAt, delivered = info.otherLastDeliveredAt;
    if (read != null && !t.isAfter(read)) return MsgStatus.read;
    if (delivered != null && !t.isAfter(delivered)) return MsgStatus.delivered;
    return MsgStatus.sent;
  }

  /// Item 0 is the newest message (the list is reversed). Show the jump button when it's off screen.
  void _onPositions() {
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty) return;
    final minIndex = pos.map((p) => p.index).reduce(math.min);
    final away = minIndex > 0;
    if (_showJump.value != away) _showJump.value = away;
    if (!away && _newCount.value != 0) _newCount.value = 0;
  }

  void _trackNew(List<Message> msgs) {
    if (msgs.isEmpty) return;
    final newest = msgs.first;
    if (_prevNewestId == null) {
      _prevNewestId = newest.id;
      return;
    }
    if (_prevNewestId != newest.id) {
      _prevNewestId = newest.id;
      if (_showJump.value && newest.senderId != _service.myUid) _newCount.value++;
    }
  }

  void _toBottom() {
    if (_scroll.isAttached) {
      _scroll.scrollTo(index: 0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  void _jumpTo(String messageId, List<Message> msgs) {
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx < 0) {
      _toast('That message is too far back.');
      return;
    }
    if (_scroll.isAttached) {
      _scroll.scrollTo(
        index: idx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _highlightId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  // ---- actions -------------------------------------------------------------

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  String _previewOf(Message m) => m.deleted
      ? 'Deleted message'
      : switch (m.type) {
          'image' => '📷 Photo',
          'file' => '📎 ${m.fileName ?? 'File'}',
          _ => m.text ?? '',
        };

  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final reply = _replying;
    _ctrl.clear();
    setState(() => _replying = null);
    _toBottom();
    await _service.send(
      otherUid: widget.other.uid,
      text: text,
      reply: reply == null
          ? null
          : ReplyRef(id: reply.id, senderId: reply.senderId, text: _previewOf(reply)),
    );
  }

  Future<void> _attach() async {
    final picked = await FilePicker.pickFile();
    if (picked == null || picked.path == null) return;

    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService.upload(File(picked.path!), name: picked.name);
      final ext = (picked.extension ?? '').toLowerCase();
      final isImage = const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      await _service.send(
        otherUid: widget.other.uid,
        type: isImage ? 'image' : 'file',
        url: url,
        fileName: picked.name,
        size: await picked.length(),
      );
      _toBottom();
    } catch (_) {
      if (mounted) _toast('Could not send the file. Check size limits and your Cloudinary settings.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openThemeSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      barrierColor: Colors.black26,
      builder: (_) => ChatThemeSheet(
        initial: _theme,
        otherUid: widget.other.uid,
        onChanged: (t, {required persist}) {
          setState(() => _theme = t);
          if (persist) ChatThemeStore.save(widget.other.uid, t);
        },
      ),
    );
  }

  void _showMenu(Message m, bool mine) {
    if (m.type == 'call') return;
    HapticFeedback.selectionClick();
    final myReaction = m.reactions[_service.myUid];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!m.deleted)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < _quickReactions.length; i++)
                      _ReactionButton(
                        emoji: _quickReactions[i],
                        selected: myReaction == _quickReactions[i],
                        index: i,
                        onTap: () {
                          Navigator.pop(ctx);
                          _service.react(
                            widget.other.uid,
                            m.id,
                            myReaction == _quickReactions[i] ? null : _quickReactions[i],
                          );
                        },
                      ),
                  ],
                ),
              ),
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replying = m);
                },
              ),
            if (!m.deleted && m.type == 'text')
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: m.text ?? ''));
                  _toast('Copied');
                },
              ),
            if (mine && !m.deleted)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
                title: const Text('Delete for everyone'),
                onTap: () {
                  Navigator.pop(ctx);
                  _service.deleteMessage(widget.other.uid, m.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---- UI ------------------------------------------------------------------

  Widget _title(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<AppUser?>(
      stream: _otherUser,
      builder: (context, userSnap) {
        final u = userSnap.data ?? widget.other;
        return StreamBuilder<ChatInfo>(
          stream: _info,
          builder: (context, infoSnap) {
            final info = infoSnap.data ?? ChatInfo.empty;
            final String? sub = info.isTyping
                ? 'typing…'
                : u.isOnline
                    ? 'online'
                    : (u.hidePresence || u.lastSeen == null ? null : lastSeenText(u.lastSeen!));
            final highlight = info.isTyping || u.isOnline;

            return Row(
              children: [
                UserAvatar(
                  uid: u.uid,
                  name: u.name,
                  photoUrl: u.photoUrl,
                  radius: 18,
                  online: u.isOnline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: sub == null
                              ? const SizedBox(key: ValueKey('none'), width: double.infinity)
                              : Text(
                                  sub,
                                  key: ValueKey(sub),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: highlight ? kOnlineGreen : cs.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    return StreamBuilder<ChatInfo>(
      stream: _info,
      builder: (context, infoSnap) {
        final info = infoSnap.data ?? ChatInfo.empty;
        return StreamBuilder<List<Message>>(
          stream: _messages,
          builder: (context, snap) {
            if (snap.hasError) return const Center(child: Text('Could not load messages.'));
            if (!snap.hasData) return const SkeletonChat();
            final msgs = snap.data!;
            _latest = msgs;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _maybeMarkRead();
              _trackNew(msgs);
            });

            if (msgs.isEmpty) {
              return Center(
                child: Text('Say hi 👋',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 18)),
              );
            }
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              itemPositionsListener: _positions,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                final showDate = m.createdAt != null &&
                    (older?.createdAt == null || !sameDay(m.createdAt!, older!.createdAt!));
                final mine = m.senderId == _service.myUid;
                return Column(
                  key: ValueKey(m.id),
                  children: [
                    if (showDate) _DateChip(label: dayLabel(m.createdAt!)),
                    SwipeToReply(
                      enabled: m.type != 'call' && !m.deleted,
                      onReply: () => setState(() => _replying = m),
                      child: MessageBubble(
                        message: m,
                        isMine: mine,
                        status: mine ? _statusFor(m, info) : null,
                        mineColor: _theme.mine,
                        otherColor: _theme.other,
                        highlight: _highlightId == m.id,
                        replyAuthor: m.reply == null
                            ? null
                            : (m.reply!.senderId == _service.myUid ? 'You' : widget.other.name),
                        onReplyTap: m.reply == null ? null : () => _jumpTo(m.reply!.id, msgs),
                        onLongPress: () => _showMenu(m, mine),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _title(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: () => startCall(context, widget.other, video: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () => startCall(context, widget.other, video: true),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'theme') _openThemeSheet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'theme', child: Text('Chat theme')),
            ],
          ),
        ],
      ),
      body: ChatBackground(
        theme: _theme,
        child: Column(
          children: [
            const ConnectionBanner(),
            Expanded(
              child: Stack(
                children: [
                  _list(context),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showJump,
                      builder: (_, show, __) => AnimatedScale(
                        scale: show ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: ValueListenableBuilder<int>(
                          valueListenable: _newCount,
                          builder: (_, n, __) => Badge(
                            isLabelVisible: n > 0,
                            label: Text('$n'),
                            child: FloatingActionButton.small(
                              heroTag: null,
                              onPressed: _toBottom,
                              child: const Icon(Icons.keyboard_arrow_down_rounded),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            StreamBuilder<ChatInfo>(
              stream: _info,
              builder: (context, snap) {
                final typing = snap.data?.isTyping ?? false;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: typing
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                            child: TypingBubble(),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              child: _uploading
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox(width: double.infinity),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _replying == null
                  ? const SizedBox(width: double.infinity)
                  : _ReplyBar(
                      author: _replying!.senderId == _service.myUid ? 'You' : widget.other.name,
                      text: _previewOf(_replying!),
                      onClose: () => setState(() => _replying = null),
                    ),
            ),
            Material(
              color: cs.surface.withValues(alpha: _theme.hasBackground ? .92 : 0),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file_rounded),
                        onPressed: _uploading ? null : _attach,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Message'),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: _hasText
                              ? Padding(
                                  key: const ValueKey('send'),
                                  padding: const EdgeInsets.only(left: 6),
                                  child: IconButton.filled(
                                    onPressed: _sendText,
                                    icon: const Icon(Icons.send_rounded),
                                  ),
                                )
                              : const SizedBox(key: ValueKey('none'), width: 4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.emoji,
    required this.selected,
    required this.index,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? cs.primaryContainer : Colors.transparent,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.author, required this.text, required this.onClose});
  final String author, text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author,
                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose),
        ],
      ),
    );
  }
}
