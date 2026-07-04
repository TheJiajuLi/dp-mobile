import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/locale_provider.dart';
import '../../core/network/api_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/tutorial_model.dart';
import '../auth/auth_service.dart';

class CommunityState {
  final List<TutorialModel> tutorials;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final int totalPages;
  final String selectedTag;
  final String searchQuery;

  const CommunityState({
    this.tutorials = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.selectedTag = '全部',
    this.searchQuery = '',
  });

  bool get hasMore => currentPage < totalPages;

  List<TutorialModel> get filtered {
    var list = tutorials;
    if (selectedTag != '全部') {
      list = list.where((t) => t.tags.contains(selectedTag)).toList();
    }
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((t) =>
              t.title.toLowerCase().contains(q) || t.username.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  CommunityState copyWith({
    List<TutorialModel>? tutorials,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    int? currentPage,
    int? totalPages,
    String? selectedTag,
    String? searchQuery,
  }) {
    return CommunityState(
      tutorials: tutorials ?? this.tutorials,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      selectedTag: selectedTag ?? this.selectedTag,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class CommunityNotifier extends StateNotifier<CommunityState> {
  final ApiClient _api;
  final String? _userId;
  final Ref _ref;

  CommunityNotifier(this._api, this._userId, this._ref) : super(const CommunityState()) {
    fetchFirstPage();
  }

  // community_screen.dart 显示 error 时会用 l10n.loadFailedWithReason(...)
  // 套一层本地化的"加载失败："前缀——这里存的必须是纯粹的原因文本，不能
  // 自己再嵌一遍中文前缀，不然中文模式下会重复，英文模式下会中英文夹杂
  Future<void> fetchFirstPage() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.get(
        '/auth/tutorials',
        queryParameters: {'status': 'published', 'page': 1, 'limit': 20},
      );
      if (!res.success || res.data == null) {
        state = state.copyWith(isLoading: false, error: res.message ?? _currentL10n().requestFailed);
        return;
      }
      final data = res.data as Map;
      final rawList = data['tutorials'] as List;
      final list =
          rawList.map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
      await _cachePage(1, rawList);
      state = state.copyWith(
        tutorials: list,
        isLoading: false,
        currentPage: (data['page'] as num?)?.toInt() ?? 1,
        totalPages: (data['pages'] as num?)?.toInt() ?? 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<void> refresh() => fetchFirstPage();

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.currentPage + 1;
    try {
      final res = await _api.get(
        '/auth/tutorials',
        queryParameters: {'status': 'published', 'page': nextPage, 'limit': 20},
      );
      if (!res.success || res.data == null) {
        state = state.copyWith(isLoadingMore: false, error: res.message ?? _currentL10n().requestFailed);
        return;
      }
      final data = res.data as Map;
      final rawList = data['tutorials'] as List;
      final list =
          rawList.map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
      await _cachePage(nextPage, rawList);
      state = state.copyWith(
        tutorials: [...state.tutorials, ...list],
        isLoadingMore: false,
        currentPage: (data['page'] as num?)?.toInt() ?? nextPage,
        totalPages: (data['pages'] as num?)?.toInt() ?? state.totalPages,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: '$e');
    }
  }

  void setTag(String tag) => state = state.copyWith(selectedTag: tag);

  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);

  Future<void> _cachePage(int page, List rawList) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${userId}_community_p$page', jsonEncode(rawList));
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  AppLocalizations _currentL10n() {
    final pref = _ref.read(localeProvider);
    final locale = localeFor(pref) ?? PlatformDispatcher.instance.locale;
    if (AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode)) {
      return lookupAppLocalizations(locale);
    }
    return lookupAppLocalizations(const Locale('zh'));
  }
}

final communityProvider = StateNotifierProvider<CommunityNotifier, CommunityState>((ref) {
  final api = ref.watch(apiClientProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  return CommunityNotifier(api, userId, ref);
});
