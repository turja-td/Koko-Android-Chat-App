import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Drag a message to the right to reply, with a small buzz at the threshold.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const _threshold = 56.0;
  double _dx = 0;
  bool _dragging = false, _fired = false;

  void _update(DragUpdateDetails d) {
    if (!widget.enabled) return;
    setState(() {
      _dragging = true;
      _dx = (_dx + d.delta.dx).clamp(0.0, 72.0);
      if (!_fired && _dx >= _threshold) {
        _fired = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  void _end(DragEndDetails _) {
    if (!widget.enabled) return;
    if (_fired) widget.onReply();
    setState(() {
      _dragging = false;
      _dx = 0;
      _fired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _end(DragEndDetails()),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _dx),
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: 8,
              child: Opacity(
                opacity: (v / _threshold).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * (v / _threshold).clamp(0.0, 1.0),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.reply_rounded, size: 18, color: cs.onPrimaryContainer),
                  ),
                ),
              ),
            ),
            Transform.translate(offset: Offset(v, 0), child: child),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
