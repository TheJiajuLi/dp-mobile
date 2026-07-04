import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 叫 ThemePreference 而不是 AppTheme——core/theme/app_theme.dart 里已经有一个
// 装 ThemeData 的 AppTheme 类，两个都导入到 main.dart 时会撞名
enum ThemePreference { system, light, dark }

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemePreference>(
  (ref) => ThemeNotifier(),
);

class ThemeNotifier extends StateNotifier<ThemePreference> {
  ThemeNotifier() : super(ThemePreference.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('app_theme') ?? 'system';
    state = ThemePreference.values.firstWhere(
      (t) => t.name == val,
      orElse: () => ThemePreference.system,
    );
  }

  Future<void> setTheme(ThemePreference theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', theme.name);
  }
}
