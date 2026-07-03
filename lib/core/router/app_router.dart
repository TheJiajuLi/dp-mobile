import 'package:go_router/go_router.dart';
import '../../features/aria/screens/aria_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/community/screens/community_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/messages/models/conversation_model.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/notebook/screens/notebook_editor_screen.dart';
import '../../features/notebook/screens/notebook_home_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/publish/screens/publish_screen.dart';
import '../../shared/widgets/main_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
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
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
