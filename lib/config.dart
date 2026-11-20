/// Change the app's in-app name here (see RENAME_AND_LOGO.md for the phone label and icon).
class AppInfo {
  static const name = 'Koko';
  static const version = '1.1';
}

/// Fill these in (see UPGRADE.md).
class Config {
  // Cloudinary (file + profile photo uploads)
  static const cloudinaryCloudName = 'YOUR_CLOUD_NAME';
  static const cloudinaryUploadPreset = 'YOUR_UNSIGNED_PRESET';

  // Metered TURN relay (makes calls work across different networks / emulators).
  // appName is the part before ".metered.live". Leave both empty to use STUN only.
  static const meteredAppName = '';
  static const meteredApiKey = '';
}
