import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';
import '../theme/theme_controller.dart';

/// Bottom sheet to pick this chat's theme. The chat behind it updates live.
class ChatThemeSheet extends StatefulWidget {
  const ChatThemeSheet({
    super.key,
    required this.initial,
    required this.otherUid,
    required this.onChanged,
  });

  final ChatTheme initial;
  final String otherUid;

  /// [persist] is false while dragging a slider (live preview only).
  final void Function(ChatTheme theme, {required bool persist}) onChanged;

  @override
  State<ChatThemeSheet> createState() => _ChatThemeSheetState();
}

class _ChatThemeSheetState extends State<ChatThemeSheet> {
  late ChatTheme _theme = widget.initial;
  bool _importing = false;

  void _set(ChatTheme t, {bool persist = true}) {
    setState(() => _theme = t);
    widget.onChanged(t, persist: persist);
  }

  Future<void> _pickPhoto() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || picked.path == null) return;
    setState(() => _importing = true);
    try {
      final old = _theme.imagePath;
      final path = await ChatThemeStore.importImage(widget.otherUid, picked.path!);
      _set(ChatTheme(
        id: 'custom',
        name: 'Custom photo',
        imagePath: path,
        dim: _theme.id == 'custom' ? _theme.dim : 0.3,
        mine: _theme.mine,
      ));
      await ChatThemeStore.deleteImage(old);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat theme',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('Only you see this background.', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            SizedBox(
              height: 118,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in kChatThemes)
                    _Swatch(
                      label: t.name,
                      selected: _theme.id == t.id,
                      theme: t,
                      onTap: () => _set(t),
                    ),
                  _Swatch(
                    label: _importing ? 'Loading…' : 'My photo',
                    selected: _theme.id == 'custom',
                    photoPath: _theme.id == 'custom' ? _theme.imagePath : null,
                    icon: Icons.add_photo_alternate_rounded,
                    onTap: _importing ? () {} : _pickPhoto,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: _theme.id != 'custom'
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.brightness_6_rounded, size: 20),
                            const SizedBox(width: 8),
                            const Text('Darken photo'),
                            Expanded(
                              child: Slider(
                                value: _theme.dim.clamp(0.0, 0.7),
                                min: 0,
                                max: 0.7,
                                onChanged: (v) => _set(_theme.copyWith(dim: v), persist: false),
                                onChangeEnd: (v) => _set(_theme.copyWith(dim: v)),
                              ),
                            ),
                          ],
                        ),
                        const Text('Your bubble colour'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          children: [
                            for (final c in ThemeController.accentChoices)
                              GestureDetector(
                                onTap: () => _set(_theme.copyWith(mine: c)),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _theme.mine?.toARGB32() == c.toARGB32()
                                          ? cs.onSurface
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    this.theme,
    this.photoPath,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ChatTheme? theme;
  final String? photoPath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = theme?.colors ?? const <Color>[];
    final mine = theme?.mine ?? cs.primary;
    final other = theme?.other ?? cs.surfaceContainerHighest;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 74,
              height: 92,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: colors.isEmpty ? cs.surfaceContainerHigh : null,
                gradient: colors.isEmpty ? null : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
                image: photoPath == null
                    ? null
                    : DecorationImage(image: FileImage(File(photoPath!)), fit: BoxFit.cover),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: icon != null && photoPath == null
                  ? Center(child: Icon(icon, color: cs.onSurfaceVariant))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 34,
                            height: 12,
                            decoration: BoxDecoration(color: other, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 40,
                            height: 12,
                            decoration: BoxDecoration(color: mine, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}
