import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/call_launcher.dart';
import '../services/chat_service.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/connection_banner.dart';
import '../widgets/shimmer.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  late final Stream<List<CallLog>> _logs = ChatService.instance.callLogs();
  late final Stream<List<AppUser>> _users = ChatService.instance.users();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: _users,
              builder: (context, usersSnap) {
                if (!usersSnap.hasData) return const SkeletonList(count: 6);
                final byId = {for (final u in usersSnap.data!) u.uid: u};
                return StreamBuilder<List<CallLog>>(
                  stream: _logs,
                  builder: (context, snap) {
                    if (snap.hasError) return const Center(child: Text('Could not load calls.'));
                    if (!snap.hasData) return const SkeletonList(count: 6);
                    final logs = snap.data!.where((l) {
                      final other = l.callerId == ChatService.instance.myUid ? l.calleeId : l.callerId;
                      return byId.containsKey(other);
                    }).toList();

                    if (logs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.call_rounded,
                                  size: 56, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 12),
                              const Text('No calls yet.\nStart one from a chat.',
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final l = logs[i];
                        final me = ChatService.instance.myUid;
                        final other = byId[l.callerId == me ? l.calleeId : l.callerId]!;
                        return _CallTile(log: l, other: other, incoming: l.calleeId == me, index: i);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.log, required this.other, required this.incoming, required this.index});
  final CallLog log;
  final AppUser other;
  final bool incoming;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final missed = log.outcome == 'missed' && incoming;

    final icon = incoming
        ? (missed ? Icons.call_missed_rounded : Icons.call_received_rounded)
        : Icons.call_made_rounded;

    final outcome = switch (log.outcome) {
      'completed' => formatDuration(log.seconds),
      'missed' => incoming ? 'Missed' : 'No answer',
      'declined' => 'Declined',
      'busy' => 'Busy',
      _ => 'Failed',
    };
    final when = log.createdAt == null ? '' : '${shortTime(log.createdAt!)} · ';

    return TweenAnimationBuilder<double>(
      key: ValueKey(log.id),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + math.min(index, 8) * 60),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: UserAvatar(
          uid: other.uid,
          name: other.name,
          photoUrl: other.photoUrl,
          radius: 24,
          hero: false,
        ),
        title: Text(
          other.name,
          style: TextStyle(fontWeight: FontWeight.w600, color: missed ? cs.error : null),
        ),
        subtitle: Row(
          children: [
            Icon(icon, size: 15, color: missed ? cs.error : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$when$outcome',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: missed ? cs.error : cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(log.video ? Icons.videocam_rounded : Icons.call_rounded, color: cs.primary),
          onPressed: () => startCall(context, other, video: log.video),
        ),
      ),
    );
  }
}
