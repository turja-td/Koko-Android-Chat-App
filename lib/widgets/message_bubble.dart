import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../utils.dart';
import 'animated_route.dart';
import 'image_viewer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.status,
    this.replyAuthor,
    this.onLongPress,
    this.onReplyTap,
    this.mineColor,
    this.otherColor,
    this.highlight = false,
  });

  final Message message;
  final bool isMine;
  final MsgStatus? status; // only for my own messages
  final String? replyAuthor;
  final VoidCallback? onLongPress, onReplyTap;
  final Color? mineColor, otherColor; // from the chat theme, null = app colours
  final bool highlight; // brief flash after "jump to message"

  @override
  Widget build(BuildContext context) {
    if (message.type == 'call') return _callLog(context);

    final cs = Theme.of(context).colorScheme;
    final custom = isMine ? mineColor : otherColor;
    final bg = custom ?? (isMine ? cs.primary : cs.surfaceContainerHighest);
    final fg = custom == null
        ? (isMine ? cs.onPrimary : cs.onSurface)
        : (ThemeData.estimateBrightnessForColor(custom) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1B1B1F));
    final deleted = message.deleted;
    final isImage = message.type == 'image' && !deleted;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    final Widget content = deleted
        ? _deleted(fg)
        : switch (message.type) {
            'image' => _image(context),
            'file' => _file(fg),
            _ => Text(message.text ?? '', style: TextStyle(color: fg, fontSize: 16, height: 1.3)),
          };

    final time = message.createdAt == null ? '' : time12(message.createdAt!);

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: isImage ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.reply != null && !deleted) _quote(fg),
            content,
            const SizedBox(height: 4),
            Padding(
              padding: isImage ? const EdgeInsets.only(right: 8, bottom: 2) : EdgeInsets.zero,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 11)),
                    if (status != null) ...[
                      const SizedBox(width: 4),
                      _ticks(status!, fg),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final row = Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            bubble,
            if (message.reactions.isNotEmpty && !deleted)
              Transform.translate(
                offset: const Offset(0, -6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _reactions(context),
                ),
              ),
          ],
        ),
      ),
    );

    final highlighted = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: highlight ? cs.primary.withValues(alpha: .22) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: row,
    );

    // Only animate messages that just arrived, not old ones scrolling into view.
    final fresh = message.createdAt == null || DateTime.now().difference(message.createdAt!).inSeconds < 3;
    if (!fresh) return highlighted;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset((isMine ? 30 : -30) * (1 - v), 12 * (1 - v)),
          child: child,
        ),
      ),
      child: highlighted,
    );
  }

  Widget _reactions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final e in message.reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final signature = counts.entries.map((e) => '${e.key}${e.value}').join();

    return TweenAnimationBuilder<double>(
      key: ValueKey(signature), // pops again whenever the reactions change
      tween: Tween(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in counts.entries) ...[
              Text(e.key, style: const TextStyle(fontSize: 14)),
              if (e.value > 1)
                Text(' ${e.value}', style: TextStyle(fontSize: 12, color: cs.onSurface)),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ticks(MsgStatus s, Color fg) {
    final soft = fg.withValues(alpha: .7);
    return switch (s) {
      MsgStatus.pending => Icon(Icons.access_time_rounded, size: 13, color: soft),
      MsgStatus.sent => Icon(Icons.done_rounded, size: 16, color: soft),
      MsgStatus.delivered => Icon(Icons.done_all_rounded, size: 16, color: soft),
      MsgStatus.read => const Icon(Icons.done_all_rounded, size: 16, color: Color(0xFF4FC3F7)),
    };
  }

  Widget _deleted(Color fg) {
    final soft = fg.withValues(alpha: .7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block_rounded, size: 16, color: soft),
        const SizedBox(width: 6),
        Text('This message was deleted', style: TextStyle(color: soft, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _quote(Color fg) {
    final r = message.reply!;
    return GestureDetector(
      onTap: onReplyTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: fg.withValues(alpha: .6)),
                Flexible(
                  child: Container(
                    color: fg.withValues(alpha: .12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(replyAuthor ?? '',
                            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
                        Text(r.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final url = message.url!;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        fadeSlideRoute(ImageViewer(url: url, heroTag: 'img_${message.id}')),
      ),
      child: Hero(
        tag: 'img_${message.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            width: 240,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              return SizedBox(
                width: 240,
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(
                    value: total == null ? null : progress.cumulativeBytesLoaded / total,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => const SizedBox(
              width: 240,
              height: 120,
              child: Icon(Icons.broken_image_rounded),
            ),
          ),
        ),
      ),
    );
  }

  Widget _file(Color fg) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => launchUrl(Uri.parse(message.url!), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insert_drive_file_rounded, color: fg),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'File',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
                Text(
                  formatBytes(message.size),
                  style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Centered "call" row, e.g. "Voice call · 02:13" or "Missed video call".
  Widget _callLog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = message.callVideo ? 'video' : 'voice';
    final outcome = message.callOutcome ?? 'failed';
    final missedForMe = outcome == 'missed' && !isMine;

    final text = switch (outcome) {
      'completed' =>
        '${kind[0].toUpperCase()}${kind.substring(1)} call · ${formatDuration(message.callSeconds ?? 0)}',
      'missed' => isMine ? 'No answer' : 'Missed $kind call',
      'declined' => 'Call declined',
      'busy' => 'Busy',
      _ => 'Call failed',
    };
    final time = message.createdAt == null ? '' : time12(message.createdAt!);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              message.callVideo
                  ? Icons.videocam_rounded
                  : (missedForMe ? Icons.call_missed_rounded : Icons.call_rounded),
              size: 18,
              color: missedForMe ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  style: TextStyle(color: missedForMe ? cs.error : cs.onSurface, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            Text(time, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
