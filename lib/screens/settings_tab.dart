import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../theme/theme_controller.dart';
import '../widgets/animated_route.dart';
import '../widgets/avatar.dart';
import 'profile_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeController>();
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
      ),
      body: StreamBuilder<AppUser?>(
        stream: UserService.instance.watch(uid),
        builder: (context, snap) {
          final me = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // ---- profile ----
              Card(
                elevation: 0,
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: UserAvatar(
                    uid: uid,
                    name: me?.name ?? '',
                    photoUrl: me?.photoUrl,
                    radius: 30,
                    hero: false,
                  ),
                  title: Text(me?.name ?? '…',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  subtitle: Text(
                    (me?.about.isNotEmpty ?? false) ? me!.about : (me?.email ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(fadeSlideRoute(const ProfileScreen())),
                ),
              ),

              // ---- appearance ----
              const _Section('Appearance'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
                    ButtonSegment(
                        value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                    ButtonSegment(
                        value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ],
                  selected: {tc.mode},
                  onSelectionChanged: (s) => tc.setMode(s.first),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in ThemeController.accentChoices)
                    GestureDetector(
                      onTap: () => tc.setAccent(c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tc.seed.toARGB32() == c.toARGB32() ? cs.onSurface : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: AnimatedScale(
                          scale: tc.seed.toARGB32() == c.toARGB32() ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('Font', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ThemeController.fonts)
                    ChoiceChip(
                      label: Text(f, style: _previewFont(f)),
                      selected: tc.font == f,
                      onSelected: (_) => tc.setFont(f),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Text('Text size', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${(tc.textScale * 100).round()}%', style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
              Slider(
                value: tc.textScale,
                min: 0.85,
                max: 1.4,
                divisions: 11,
                onChanged: tc.previewTextScale,
                onChangeEnd: (_) => tc.saveTextScale(),
              ),
              const _PreviewBubbles(),

              // ---- privacy ----
              const _Section('Privacy'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show online status and last seen'),
                subtitle: const Text('Turn off to hide them from other people.'),
                value: !(me?.hidePresence ?? false),
                onChanged: (v) => UserService.instance.setHidePresence(!v),
              ),

              // ---- account ----
              const _Section('Account'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_rounded, color: cs.error),
                title: Text('Log out', style: TextStyle(color: cs.error)),
                onTap: () => AuthService.signOut(),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('${AppInfo.name} · v${AppInfo.version}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  static TextStyle? _previewFont(String f) {
    if (f == 'System default') return null;
    try {
      return GoogleFonts.getFont(f);
    } catch (_) {
      return null;
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Two sample bubbles so the font and size changes are visible right away.
class _PreviewBubbles extends StatelessWidget {
  const _PreviewBubbles();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bubble(String text, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(text,
                style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface, fontSize: 16)),
          ),
        );

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: Column(
        children: [
          bubble('Hey! How does this look?', false),
          bubble('Looks great to me 👌', true),
        ],
      ),
    );
  }
}
