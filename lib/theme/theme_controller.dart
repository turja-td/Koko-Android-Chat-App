import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide look: light/dark, accent colour, font and text size. All saved on the device.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._mode, this._seed, this._font, this._scale);

  static const accentChoices = <Color>[
    Color(0xFF6C5CE7),
    Color(0xFF0984E3),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFFE84393),
    Color(0xFFD99A00),
    Color(0xFF2D3436),
  ];

  /// Names must match Google Fonts family names exactly.
  static const fonts = <String>[
    'System default',
    'Inter',
    'Poppins',
    'Nunito',
    'Lato',
    'Lora',
    'Quicksand',
    'Raleway',
    'Caveat',
  ];

  ThemeMode _mode;
  Color _seed;
  String _font;
  double _scale;

  ThemeMode get mode => _mode;
  Color get seed => _seed;
  String get font => _font;
  double get textScale => _scale;

  static Future<ThemeController> load() async {
    final p = await SharedPreferences.getInstance();
    final mode = switch (p.getString('theme')) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final seed = Color(p.getInt('accent') ?? accentChoices.first.toARGB32());
    final savedFont = p.getString('font') ?? 'System default';
    final font = fonts.contains(savedFont) ? savedFont : 'System default';
    final scale = (p.getDouble('textScale') ?? 1.0).clamp(0.85, 1.4).toDouble();
    return ThemeController._(mode, seed, font, scale);
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });
  }

  /// Used by the quick toggle button in the app bar.
  Future<void> setDark(bool dark) => setMode(dark ? ThemeMode.dark : ThemeMode.light);

  Future<void> setAccent(Color color) async {
    _seed = color;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt('accent', color.toARGB32());
  }

  Future<void> setFont(String font) async {
    _font = font;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('font', font);
  }

  /// Live update while dragging the slider (not saved yet).
  void previewTextScale(double scale) {
    _scale = scale;
    notifyListeners();
  }

  Future<void> saveTextScale() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('textScale', _scale);
  }
}
