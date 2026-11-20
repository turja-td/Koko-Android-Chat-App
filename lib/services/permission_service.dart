import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  /// First launch only: explain, then ask for everything the app uses.
  static Future<void> requestAllOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('perms_asked') == true) return;
    if (!context.mounted) return;

    final go = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => const _PermissionSheet(),
    );
    await prefs.setBool('perms_asked', true);
    if (go != true) return;

    await [
      Permission.notification,
      Permission.microphone,
      Permission.camera,
      Permission.bluetoothConnect,
    ].request();
  }

  /// Before starting or answering a call. Returns true when calling can go ahead.
  static Future<bool> ensureForCall(BuildContext context, {required bool video}) async {
    final statuses = await [Permission.microphone, if (video) Permission.camera].request();
    // Optional: lets audio route to Bluetooth headsets. Result is ignored.
    await Permission.bluetoothConnect.request();

    if (statuses.values.every((s) => s.isGranted)) return true;
    if (!context.mounted) return false;

    final permanent = statuses.values.any((s) => s.isPermanentlyDenied);
    final what = video ? 'the microphone and camera' : 'the microphone';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission needed'),
        content: Text(
          permanent
              ? 'Calls need access to $what. Open Settings > Permissions and turn it on.'
              : 'Calls need access to $what. Please allow it and try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (permanent)
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
    return false;
  }
}

class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet();

  static const _items = [
    (Icons.notifications_rounded, 'Notifications', 'Get alerted about new messages and missed calls.'),
    (Icons.mic_rounded, 'Microphone', 'Talk during voice and video calls.'),
    (Icons.videocam_rounded, 'Camera', 'Show your video in video calls.'),
    (Icons.bluetooth_audio_rounded, 'Nearby devices', 'Use Bluetooth headsets during calls.'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Allow permissions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Koko needs a few permissions to work properly.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (var i = 0; i < _items.length; i++)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 350 + i * 90),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(_items[i].$1, color: cs.onPrimaryContainer),
                  ),
                  title: Text(_items[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_items[i].$3),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Center(child: Text('Not now')),
            ),
          ],
        ),
      ),
    );
  }
}
