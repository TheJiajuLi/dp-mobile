import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/aria/screens/aria_screen.dart';
import '../../features/auth/auth_service.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/community/screens/community_screen.dart';
import '../../features/community/screens/tutorial_detail_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/messages/models/conversation_model.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/notebook/screens/notebook_editor_screen.dart';
import '../../features/notebook/screens/notebook_home_screen.dart';
import '../../features/profile/screens/follow_list_screen.dart';
import '../../features/profile/screens/user_profile_screen.dart';
import '../../features/publish/screens/publish_screen.dart';
import '../../shared/widgets/main_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/publish', builder: (context, state) => const PublishScreen()),
    GoRoute(
      path: '/notebook',
      builder: (context, state) => const NotebookHomeScreen(),
    ),
    GoRoute(
      path: '/notebook/:id',
      builder: (context, state) => NotebookEditorScreen(
        nbId: state.pathParameters['id']!,
      ),
    ),
    // ARIA 不再是底部导航的一个 tab，改由首页九宫格 push 进来
    GoRoute(path: '/aria', builder: (context, state) => const AriaScreen()),
    GoRoute(
      path: '/messages/chat/:conversationId',
      builder: (context, state) => ChatScreen(
        conversationId: state.pathParameters['conversationId']!,
        conversation: state.extra as Conversation?,
      ),
    ),
    GoRoute(
      path: '/tutorial/:id',
      builder: (context, state) => TutorialDetailScreen(
        tutorialId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/users/:identifier',
      builder: (context, state) => UserProfileScreen(
        identifier: state.pathParameters['identifier']!,
      ),
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
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/community',
              builder: (context, state) => const CommunityScreen(),
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
