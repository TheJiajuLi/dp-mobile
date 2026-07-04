import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotifSettings {
  final bool likes;
  final bool comments;
  final bool follows;
  final bool system;

  const NotifSettings({
    this.likes = true,
    this.comments = true,
    this.follows = true,
    this.system = true,
  });

  NotifSettings copyWith({
    bool? likes,
    bool? comments,
    bool? follows,
    bool? system,
  }) => NotifSettings(
    likes: likes ?? this.likes,
    comments: comments ?? this.comments,
    follows: follows ?? this.follows,
    system: system ?? this.system,
  );
}

final notifProvider = StateNotifierProvider<NotifNotifier, NotifSettings>(
  (ref) => NotifNotifier(),
);

class NotifNotifier extends StateNotifier<NotifSettings> {
  NotifNotifier() : super(const NotifSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotifSettings(
      likes: prefs.getBool('notif_likes') ?? true,
      comments: prefs.getBool('notif_comments') ?? true,
      follows: prefs.getBool('notif_follows') ?? true,
      system: prefs.getBool('notif_system') ?? true,
    );
  }

  Future<void> toggle(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_$key', value);
    state = switch (key) {
      'likes' => state.copyWith(likes: value),
      'comments' => state.copyWith(comments: value),
      'follows' => state.copyWith(follows: value),
      'system' => state.copyWith(system: value),
      _ => state,
    };
  }
}
