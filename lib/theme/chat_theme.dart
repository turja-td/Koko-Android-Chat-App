import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-chat look: a gradient or your own photo as the background plus bubble colours.
/// Saved on this device only (the other person doesn't see your choice).
class ChatTheme {
  const ChatTheme({
    required this.id,
    required this.name,
    this.colors = const [],
    this.mine,
    this.other,
    this.imagePath,
    this.dim = 0.3,
  });

  final String id, name;
  final List<Color> colors; // background gradient, empty = normal app background
  final Color? mine, other; // bubble colours, null = app theme colours
  final String? imagePath; // custom photo background
  final double dim; // darkening over a photo, 0..1

  bool get hasBackground => colors.isNotEmpty || imagePath != null;

  ChatTheme copyWith({String? imagePath, double? dim, Color? mine, bool clearMine = false}) => ChatTheme(
        id: id,
        name: name,
        colors: colors,
        mine: clearMine ? null : (mine ?? this.mine),
        other: other,
        imagePath: imagePath ?? this.imagePath,
        dim: dim ?? this.dim,
      );
}

const kDefaultChatTheme = ChatTheme(id: 'default', name: 'Default');

const kChatThemes = <ChatTheme>[
  kDefaultChatTheme,
  ChatTheme(
    id: 'sunset',
    name: 'Sunset',
    colors: [Color(0xFFFFD1A9), Color(0xFFFF8E7A)],
    mine: Color(0xFFD84A5F),
    other: Color(0xE6FFFFFF),
  ),
  ChatTheme(
    id: 'ocean',
    name: 'Ocean',
    colors: [Color(0xFFA1C4FD), Color(0xFFC2E9FB)],
    mine: Color(0xFF2B6CB0),
    other: Color(0xE6FFFFFF),
  ),
  ChatTheme(
    id: 'forest',
    name: 'Forest',
    colors: [Color(0xFFD4FC79), Color(0xFF96E6A1)],
    mine: Color(0xFF2F855A),
    other: Color(0xE6FFFFFF),
  ),
  ChatTheme(
    id: 'rose',
    name: 'Rose',
    colors: [Color(0xFFFBC2EB), Color(0xFFA6C1EE)],
    mine: Color(0xFFB83280),
    other: Color(0xE6FFFFFF),
  ),
  ChatTheme(
    id: 'lavender',
    name: 'Lavender',
    colors: [Color(0xFFE0C3FC), Color(0xFF8EC5FC)],
    mine: Color(0xFF6B46C1),
    other: Color(0xE6FFFFFF),
  ),
  ChatTheme(
    id: 'midnight',
    name: 'Midnight',
    colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
    mine: Color(0xFF3B82F6),
    other: Color(0xFF2A3441),
  ),
  ChatTheme(
    id: 'noir',
    name: 'Noir',
    colors: [Color(0xFF000000), Color(0xFF1C1C1E)],
    mine: Color(0xFF6C5CE7),
    other: Color(0xFF2B2B2E),
  ),
];

class ChatThemeStore {
  static String _key(String uid) => 'chat_theme_$uid';

  static Future<ChatTheme> load(String otherUid) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(otherUid));
    if (raw == null) return kDefaultChatTheme;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = m['id'] as String;
      if (id == 'custom') {
        final path = m['imagePath'] as String?;
        if (path == null || !File(path).existsSync()) return kDefaultChatTheme;
        return ChatTheme(
          id: 'custom',
          name: 'Custom photo',
          imagePath: path,
          dim: (m['dim'] as num?)?.toDouble() ?? 0.3,
          mine: m['mine'] == null ? null : Color(m['mine'] as int),
        );
      }
      return kChatThemes.firstWhere((t) => t.id == id, orElse: () => kDefaultChatTheme);
    } catch (_) {
      return kDefaultChatTheme;
    }
  }

  static Future<void> save(String otherUid, ChatTheme t) async {
    final p = await SharedPreferences.getInstance();
    if (t.id == 'default') {
      await p.remove(_key(otherUid));
      return;
    }
    await p.setString(
      _key(otherUid),
      jsonEncode({
        'id': t.id,
        if (t.id == 'custom') ...{
          'imagePath': t.imagePath,
          'dim': t.dim,
          'mine': t.mine?.toARGB32(),
        },
      }),
    );
  }

  /// Copies the picked photo into app storage so it survives cache cleanup.
  static Future<String> importImage(String otherUid, String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final dest = '${dir.path}/chat_bg_${otherUid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> deleteImage(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
