import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/locale_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';

// 首页顶部的话题横滑筛选是一套更"日常"的粗分类（科学/经济/时事/生活/
// 数据/编程），跟卡片右上角那个更细的六色 CONTEXT.md 分类（数据科学/
// 生命科学/宇宙天文...见 shared/utils/topic_badge.dart）是两套不同粒度
// 的分类体系，各管各的，不要混用同一份关键词表
const homeFeedCategories = ['全部', '科学', '经济', '时事', '生活', '数据', '编程'];

const _categoryKeywords = {
  '科学': ['科学', '宇宙', '天文', '物理', '生命', '生物', '数学'],
  '经济': ['经济', '金融'],
  '时事': ['时事', '新闻', '政策', '社会'],
  '生活': ['生活'],
  '数据': ['数据'],
  '编程': ['编程', '代码', 'python', 'javascript', '开发'],
};

bool tutorialMatchesCategory(TutorialModel t, String category) {
  if (category == '全部') return true;
  final keywords = _categoryKeywords[category] ?? [category];
  final haystack = ('${t.title} ${t.tags.join(' ')}').toLowerCase();
  return keywords.any((k) => haystack.contains(k.toLowerCase()));
}

class HomeFeedState {
  final List<TutorialModel> tutorials;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final int totalPages;
  final String selectedCategory;

  const HomeFeedState({
    this.tutorials = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.selectedCategory = '全部',
  });

  bool get hasMore => currentPage < totalPages;

  List<TutorialModel> get filtered => selectedCategory == '全部'
      ? tutorials
      : tutorials
            .where((t) => tutorialMatchesCategory(t, selectedCategory))
            .toList();

  HomeFeedState copyWith({
    List<TutorialModel>? tutorials,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    int? currentPage,
    int? totalPages,
    String? selectedCategory,
  }) {
    return HomeFeedState(
      tutorials: tutorials ?? this.tutorials,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      selectedCategory: selectedCategory ?? this.selectedCategory,
    );
  }
}

// 跟 CommunityNotifier（community_provider.dart）同一套分页/缓存写法——
// 首页 Feed 和社区页都是拉 GET /auth/tutorials?status=published 分页列表，
// 只是缓存 key 前缀和筛选维度（粗分类 vs 具体 tag+搜索）不一样
class HomeFeedNotifier extends StateNotifier<HomeFeedState> {
  final ApiClient _api;
  final String? _userId;
  final Ref _ref;

  HomeFeedNotifier(this._api, this._userId, this._ref)
    : super(const HomeFeedState()) {
    fetchFirstPage();
  }

  Future<void> fetchFirstPage() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.get(
        '/auth/tutorials',
        queryParameters: {'status': 'published', 'page': 1, 'limit': 20},
      );
      if (!res.success || res.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: res.message ?? _currentL10n().requestFailed,
        );
        return;
      }
      final data = res.data as Map;
      final rawList = data['tutorials'] as List;
      final list = rawList
          .map((e) => TutorialModel.fromJson(e as Map<String, dynamic>))
          .toList();
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
        state = state.copyWith(
          isLoadingMore: false,
          error: res.message ?? _currentL10n().requestFailed,
        );
        return;
      }
      final data = res.data as Map;
      final rawList = data['tutorials'] as List;
      final list = rawList
          .map((e) => TutorialModel.fromJson(e as Map<String, dynamic>))
          .toList();
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

  void setCategory(String category) =>
      state = state.copyWith(selectedCategory: category);

  Future<void> _cachePage(int page, List rawList) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${userId}_home_feed_p$page', jsonEncode(rawList));
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  AppLocalizations _currentL10n() {
    final pref = _ref.read(localeProvider);
    final locale = localeFor(pref) ?? PlatformDispatcher.instance.locale;
    if (AppLocalizations.supportedLocales.any(
      (l) => l.languageCode == locale.languageCode,
    )) {
      return lookupAppLocalizations(locale);
    }
    return lookupAppLocalizations(const Locale('zh'));
  }
}

final homeFeedProvider = StateNotifierProvider<HomeFeedNotifier, HomeFeedState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    return HomeFeedNotifier(api, userId, ref);
  },
);
