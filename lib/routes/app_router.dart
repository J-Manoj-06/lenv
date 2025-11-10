import 'package:flutter/material.dart';
import '../screens/common/splash_screen.dart';
import '../screens/common/role_selection_screen.dart';
import '../screens/teacher/teacher_login_screen.dart';
import '../screens/teacher/create_test_screen.dart';
import '../screens/teacher/create_ai_test_screen.dart';
import '../screens/teacher/student_list_screen.dart';
import '../screens/teacher/student_performance_screen.dart';
import '../screens/teacher/test_result_screen.dart';
import '../screens/teacher/my_highlights_screen.dart';
import '../screens/student/student_login_screen.dart';
import '../screens/dev/dev_tools_screen.dart';
import '../screens/student/student_test_result_screen.dart';
import '../screens/rewards/search_rewards_screen.dart';
import '../screens/rewards/product_detail_screen.dart';
import '../models/product_model.dart';
import '../screens/rewards/my_requests_screen.dart';
import '../widgets/student_main_navigation.dart';
import '../widgets/teacher_main_navigation.dart';
import '../screens/teacher/messages/messages_screen.dart';
import '../screens/teacher/messages/chat_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case '/role-selection':
        return MaterialPageRoute(builder: (_) => const RoleSelectionScreen());

      case '/teacher-login':
        return MaterialPageRoute(builder: (_) => const TeacherLoginScreen());

      case '/student-login':
        return MaterialPageRoute(builder: (_) => const StudentLoginScreen());

      case '/student-dashboard':
        return MaterialPageRoute(
          builder: (_) => const StudentMainNavigation(initialIndex: 0),
        );

      case '/student-tests':
        return MaterialPageRoute(
          builder: (_) => const StudentMainNavigation(initialIndex: 1),
        );

      case '/student-rewards':
        return MaterialPageRoute(
          builder: (_) => const StudentMainNavigation(initialIndex: 2),
        );

      case '/search-rewards':
        return MaterialPageRoute(builder: (_) => const SearchRewardsScreen());

      case '/product-detail':
        final product = settings.arguments as ProductModel?;
        if (product == null) {
          return MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('Missing product'))),
          );
        }
        return MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        );

      case '/my-reward-requests':
        return MaterialPageRoute(
          builder: (_) => const MyRewardRequestsScreen(),
        );

      case '/student-leaderboard':
        return MaterialPageRoute(
          builder: (_) => const StudentMainNavigation(initialIndex: 3),
        );

      case '/student-profile':
        return MaterialPageRoute(
          builder: (_) => const StudentMainNavigation(initialIndex: 4),
        );

      case '/teacher-dashboard':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 0),
        );

      case '/create-test':
        return MaterialPageRoute(builder: (_) => const CreateTestScreen());

      case '/ai-test-generator':
        return MaterialPageRoute(builder: (_) => const CreateAITestScreen());

      case '/classes':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 1),
        );

      case '/student-list':
        final className = settings.arguments as String? ?? 'Class';
        return MaterialPageRoute(
          builder: (_) => StudentListScreen(className: className),
        );

      case '/student-performance':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder: (_) => StudentPerformanceScreen(
            studentId: args['studentId'] ?? '',
            studentName: args['name'] ?? 'Student',
            studentClass: args['class'] ?? 'Grade 8 - Science',
            imageUrl: args['imageUrl'] ?? '',
            averageScore: args['score'] ?? 0,
          ),
        );

      case '/tests':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 2),
        );

      case '/test-result':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder: (_) => TestResultScreen(
            testId: args['testId'] ?? args['id'] ?? '',
            testName: args['name'] ?? 'Test',
            className: args['class'] ?? 'Grade',
            status: args['status'] ?? 'Past',
            endTime: args['endTime'] ?? '',
          ),
        );

      case '/leaderboard':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 3),
        );

      case '/profile':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 4),
        );

      case '/my-highlights':
        return MaterialPageRoute(builder: (_) => const MyHighlightsScreen());

      case '/dev-tools':
        return MaterialPageRoute(builder: (_) => const DevToolsScreen());

      case '/student-test-result':
        final args = settings.arguments as Map<String, dynamic>?;
        final resultId = args?['resultId'] as String?;
        if (resultId == null || resultId.isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(
                child: Text('Missing resultId for student-test-result'),
              ),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => StudentTestResultScreen(resultId: resultId),
        );

      case '/messages':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => MessagesScreen(
            studentId: args?['studentId'] as String?,
            studentName: args?['studentName'] as String?,
          ),
        );

      case '/chat':
        final args = settings.arguments as Map<String, dynamic>?;
        if (args == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing conversation data')),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: args['conversationId'] as String,
            parentName: args['parentName'] as String,
            parentPhotoUrl: args['parentPhotoUrl'] as String?,
            studentName: args['studentName'] as String,
          ),
        );

      // Add more routes here as screens are created
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
