import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLocale { system, zh, en }

final localeProvider =
    StateNotifierProvider<LocaleNotifier, AppLocale>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<AppLocale> {
  LocaleNotifier() : super(AppLocale.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('app_locale') ?? 'system';
    state = AppLocale.values.firstWhere(
      (l) => l.name == val,
      orElse: () => AppLocale.system,
    );
  }

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', locale.name);
  }
}

// 跟主题的 ThemePreference 不一样：Locale? 需要在 build() 里当 MaterialApp
// 的 locale 参数用，null 代表"跟随系统"，所以拆成一个纯函数而不是塞进
// LocaleNotifier 的字段——避免每次 state 变化都要额外 notify 一次派生值
Locale? localeFor(AppLocale pref) => switch (pref) {
  AppLocale.zh => const Locale('zh'),
  AppLocale.en => const Locale('en'),
  AppLocale.system => null,
};
