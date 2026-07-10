import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/aria/screens/aria_screen.dart';
import '../../features/aurora/screens/aurora_progress_screen.dart';
import '../../features/auth/auth_service.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/switch_account_screen.dart';
import '../../features/community/screens/community_screen.dart';
import '../../features/column/screens/column_detail_screen.dart';
import '../../features/community/screens/tutorial_detail_screen.dart';
import '../../features/creator/screens/aurora_screen.dart';
import '../../features/creator/screens/columns_screen.dart';
import '../../features/creator/screens/creator_center_screen.dart';
import '../../features/creator/screens/works_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/jisuo/screens/answer_question_screen.dart';
import '../../features/jisuo/screens/jisuo_screen.dart';
import '../../features/jisuo/screens/question_detail_screen.dart';
import '../../features/messages/models/conversation_model.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/conversation_list_screen.dart';
import '../../features/messages/screens/friend_list_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/messages/screens/invite_list_screen.dart';
import '../../features/messages/screens/notifications_screen.dart';
import '../../features/notebook/screens/notebook_editor_screen.dart';
import '../../features/notebook/screens/notebook_home_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/follow_list_screen.dart';
import '../../features/profile/screens/user_profile_screen.dart';
import '../../features/publish/screens/publish_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/settings/screens/about_screen.dart';
import '../../features/settings/screens/faq_list_screen.dart';
import '../../features/settings/screens/help_feedback_screen.dart';
import '../../features/settings/screens/account_security_screen.dart';
import '../../features/settings/screens/login_history_screen.dart';
import '../../features/settings/screens/payment_screen.dart';
import '../../features/settings/screens/privacy_policy_screen.dart';
import '../../features/settings/screens/privacy_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/storage_screen.dart';
import '../../features/settings/screens/terms_of_service_screen.dart';
import '../../features/settings/screens/subscription_screen.dart';
import '../../shared/widgets/main_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    // token 通过 main.dart 的 jimeng://reset-password?token=xxx deep link
    // 解析出来后带着它 push 到这里；理论上也可以直接手动导航到这个路径
    // 本身自带 query 参数，两条路都从 state.uri 读，逻辑统一
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => ResetPasswordScreen(
        token: state.uri.queryParameters['token'] ?? '',
      ),
    ),
    GoRoute(
      path: '/switch-account',
      builder: (context, state) => const SwitchAccountScreen(),
    ),
    // 发现页不再是底部Tab（内容已经搬到首页顶部），但页面本身留着——
    // 挪出 shell 之外，作为可以直接 push 到的独立路由，之后要挪作他用
    // 再改
    GoRoute(
      path: '/community',
      builder: (context, state) => const CommunityScreen(),
    ),
    GoRoute(
      path: '/publish',
      builder: (context, state) => const PublishScreen(),
    ),
    GoRoute(
      path: '/publish/:id',
      builder: (context, state) =>
          PublishScreen(tutorialId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/friends',
      builder: (context, state) => const FriendListScreen(),
    ),
    GoRoute(
      path: '/creator',
      builder: (context, state) => const CreatorCenterScreen(),
    ),
    GoRoute(
      path: '/creator/works',
      // 从创作者中心"草稿箱"行跳过来时带 extra:1，直接定位到草稿 tab
      builder: (context, state) =>
          WorksScreen(initialTab: state.extra as int? ?? 0),
    ),
    GoRoute(
      path: '/creator/columns',
      builder: (context, state) => const ColumnsScreen(),
    ),
    GoRoute(
      path: '/creator/aurora',
      builder: (context, state) => const AuroraScreen(),
    ),
    // 已经是极光创作者之后查看"本月续期进度"用这个——跟上面 /creator/
    // aurora（还没入选时的申请门槛/宣传页）是两个不同阶段的页面，不要
    // 合并成一个，语义不一样
    GoRoute(
      path: '/aurora/progress',
      builder: (context, state) => const AuroraProgressScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) =>
          SearchScreen(initialQuery: state.uri.queryParameters['q']),
    ),
    GoRoute(
      path: '/notebook',
      builder: (context, state) => const NotebookHomeScreen(),
    ),
    GoRoute(
      path: '/notebook/:id',
      builder: (context, state) =>
          NotebookEditorScreen(nbId: state.pathParameters['id']!),
    ),
    // ARIA 不再是底部导航的一个 tab，改由首页九宫格 push 进来
    GoRoute(path: '/aria', builder: (context, state) => const AriaScreen()),
    GoRoute(
      path: '/answer-question',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AnswerQuestionScreen(
          questionId: extra['questionId']?.toString() ?? '',
          questionText: extra['questionText']?.toString() ?? '',
          domain: extra['domain']?.toString() ?? '',
        );
      },
    ),
    GoRoute(
      path: '/questions/:id',
      builder: (context, state) => QuestionDetailScreen(
        questionId: state.pathParameters['id']!,
        initialQuestion: state.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(
      path: '/edit-profile',
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/security',
      builder: (context, state) => const AccountSecurityScreen(),
    ),
    GoRoute(
      path: '/settings/security/history',
      builder: (context, state) => const LoginHistoryScreen(),
    ),
    GoRoute(
      path: '/settings/payment',
      builder: (context, state) => const PaymentScreen(),
    ),
    GoRoute(
      path: '/settings/subscription',
      builder: (context, state) => const SubscriptionScreen(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: '/settings/storage',
      builder: (context, state) => const StorageScreen(),
    ),
    GoRoute(
      path: '/settings/about',
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: '/settings/terms',
      builder: (context, state) => const TermsOfServiceScreen(),
    ),
    GoRoute(
      path: '/settings/privacy-policy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/settings/help',
      builder: (context, state) => const HelpFeedbackScreen(),
    ),
    GoRoute(
      path: '/settings/faq',
      builder: (context, state) =>
          FaqListScreen(initialQuery: state.extra as String?),
    ),
    GoRoute(
      path: '/messages/chat/:conversationId',
      builder: (context, state) => ChatScreen(
        conversationId: state.pathParameters['conversationId']!,
        conversation: state.extra as Conversation?,
      ),
    ),
    GoRoute(
      path: '/messages/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/invite-list',
      builder: (context, state) => const InviteListScreen(),
    ),
    GoRoute(
      path: '/messages/conversations',
      builder: (context, state) => const ConversationListScreen(),
    ),
    GoRoute(
      path: '/tutorial/:id',
      builder: (context, state) =>
          TutorialDetailScreen(tutorialId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/columns/:id',
      builder: (context, state) =>
          ColumnDetailScreen(columnId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/users/:identifier',
      builder: (context, state) =>
          UserProfileScreen(identifier: state.pathParameters['identifier']!),
    ),
    GoRoute(
      path: '/users/:userId/followers',
      builder: (context, state) => FollowListScreen(
        userId: state.pathParameters['userId']!,
        type: 'followers',
      ),
    ),
    GoRoute(
      path: '/users/:userId/following',
      builder: (context, state) => FollowListScreen(
        userId: state.pathParameters['userId']!,
        type: 'following',
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/jisuo',
              builder: (context, state) => const JisuoScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/messages',
              builder: (context, state) => const MessagesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              // "我的" 是根级 tab，不是 push 进来的，复用 UserProfileScreen
              // 展示当前登录用户自己（不带返回按钮）
              builder: (context, state) => Consumer(
                builder: (context, ref, _) {
                  final user = ref.watch(currentUserProvider);
                  if (user == null) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return UserProfileScreen(
                    identifier: user.username,
                    showBackButton: false,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
