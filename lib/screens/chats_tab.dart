import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../models.dart';
import '../services/chat_service.dart';
import '../utils.dart';
import '../widgets/animated_route.dart';
import '../widgets/avatar.dart';
import '../widgets/connection_banner.dart';
import '../widgets/shimmer.dart';
import '../widgets/theme_toggle.dart';
import 'chat_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<List<AppUser>> _users = ChatService.instance.users();
  late final Stream<Map<String, ChatMeta>> _metas = ChatService.instance.chatMetas();
  Timer? _tick;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Re-evaluate "online" / "typing" as time passes, even when nothing new arrives.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppInfo.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
        actions: const [ThemeToggleButton()],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    return StreamBuilder<List<AppUser>>(
      stream: _users,
      builder: (context, usersSnap) {
        if (!usersSnap.hasData) return const SkeletonList();
        return StreamBuilder<Map<String, ChatMeta>>(
          stream: _metas,
          builder: (context, metaSnap) {
            final metas = metaSnap.data ?? {};
            final users = usersSnap.data!
                .where((u) => _query.isEmpty || u.name.toLowerCase().contains(_query))
                .toList()
              ..sort((a, b) {
                final ta = metas[a.uid]?.lastTime, tb = metas[b.uid]?.lastTime;
                if (ta != null && tb != null) return tb.compareTo(ta);
                if (ta != null) return -1;
                if (tb != null) return 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

            if (users.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _query.isEmpty
                        ? 'No one else is here yet.\nAsk a friend to create an account.'
                        : 'No matches.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: users.length,
              itemBuilder: (context, i) => _tile(context, users[i], metas[users[i].uid], i),
            );
          },
        );
      },
    );
  }

  Widget _tile(BuildContext context, AppUser u, ChatMeta? meta, int index) {
    final cs = Theme.of(context).colorScheme;
    final mine = meta?.lastSenderId == ChatService.instance.myUid;
    final unread = (meta?.unread ?? 0) > 0 && !mine;
    final typing = meta?.isTyping ?? false;

    final String subtitle = meta == null
        ? (u.about.isNotEmpty ? u.about : u.email)
        : '${mine ? 'You: ' : ''}${meta.lastMessage}';

    return TweenAnimationBuilder<double>(
      key: ValueKey(u.uid),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + math.min(index, 8) * 70),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 28 * (1 - v)), child: child),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: UserAvatar(
          uid: u.uid,
          name: u.name,
          photoUrl: u.photoUrl,
          radius: 26,
          online: u.isOnline,
        ),
        title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: typing
              ? const Text('typing…',
                  key: ValueKey('typing'),
                  style: TextStyle(color: kOnlineGreen, fontStyle: FontStyle.italic))
              : Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unread ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
        ),
        trailing: meta == null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    shortTime(meta.lastTime),
                    style: TextStyle(color: unread ? cs.primary : cs.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  AnimatedScale(
                    scale: unread ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        '${meta.unread}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
        onTap: () => Navigator.of(context).push(fadeSlideRoute(ChatScreen(other: u))),
      ),
    );
  }
}
