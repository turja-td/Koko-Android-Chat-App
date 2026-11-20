import 'package:material_ui/material_ui.dart';

const kOnlineGreen = Color(0xFF25D366);

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.photoUrl,
    this.radius = 24,
    this.hero = true,
    this.online = false,
  });

  final String uid, name;
  final String? photoUrl;
  final double radius;
  final bool hero, online;

  static const _colors = [
    Color(0xFF6C5CE7),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF0984E3),
    Color(0xFFE84393),
    Color(0xFFD99A00),
  ];

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: _colors[uid.hashCode.abs() % _colors.length],
      foregroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: radius * .85, fontWeight: FontWeight.w600),
      ),
    );

    final dotSize = radius * .55;
    final withDot = Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: AnimatedScale(
            scale: online ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: kOnlineGreen,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: radius > 20 ? 2.5 : 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (!hero) return withDot;
    return Hero(
      tag: 'avatar_$uid',
      child: Material(type: MaterialType.transparency, child: withDot),
    );
  }
}
