import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../theme/chat_theme.dart';

/// Paints the chat's gradient or photo behind [child], cross-fading when it changes.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key, required this.theme, required this.child});
  final ChatTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _layer(),
          ),
        ),
        child,
      ],
    );
  }

  Widget _layer() {
    if (theme.imagePath != null) {
      return Stack(
        key: ValueKey('img_${theme.imagePath}'),
        fit: StackFit.expand,
        children: [
          Image.file(File(theme.imagePath!), fit: BoxFit.cover),
          ColoredBox(color: Colors.black.withValues(alpha: theme.dim)),
        ],
      );
    }
    if (theme.colors.isNotEmpty) {
      return DecoratedBox(
        key: ValueKey(theme.id),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: theme.colors,
          ),
        ),
      );
    }
    return const SizedBox.expand(key: ValueKey('none'));
  }
}
