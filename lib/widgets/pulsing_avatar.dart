import 'package:flutter/material.dart';

import 'avatar.dart';

/// Avatar with two expanding rings, used while a call is ringing/connecting.
class PulsingAvatar extends StatelessWidget {
  const PulsingAvatar({
    super.key,
    required this.animation,
    required this.name,
    this.active = true,
  });

  final Animation<double> animation;
  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 230,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              for (final offset in const [0.0, 0.5])
                Builder(builder: (_) {
                  final t = (animation.value + offset) % 1.0;
                  final size = 110 + 120 * t;
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: (1 - t) * .45),
                        width: 2,
                      ),
                    ),
                  );
                }),
            UserAvatar(uid: name, name: name, radius: 52, hero: false),
          ],
        ),
      ),
    );
  }
}
