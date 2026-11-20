import 'package:audioplayers/audioplayers.dart';

/// Ringtone for incoming calls and ringback tone for the caller. Both are bundled
/// in assets/sounds (replace the files to change them).
class CallSounds {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playRingtone() => _play('sounds/ringtone.wav');
  static Future<void> playRingback() => _play('sounds/ringback.wav');

  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  static Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }
}
