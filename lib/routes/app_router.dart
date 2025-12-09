import 'package:flutter/material.dart';
import 'package:new_reward/screens/test_media_upload_screen.dart';
import '../screens/common/splash_screen.dart';
import '../screens/common/role_selection_screen.dart';
import '../screens/teacher/teacher_login_screen.dart';
import '../screens/teacher/create_test_screen.dart';
import '../screens/teacher/create_test_entry_screen.dart';
import '../screens/teacher/create_ai_test_screen.dart';
import '../screens/teacher/student_list_screen.dart';
import '../screens/teacher/student_performance_screen.dart';
import '../screens/teacher/test_result_screen.dart';
import '../screens/teacher/my_highlights_screen.dart';
import '../screens/student/student_login_screen.dart';
import '../screens/parent/parent_login_screen.dart';
import '../screens/parent/child_profile_screen.dart';
import '../widgets/parent_main_navigation.dart';
import '../screens/parent/parent_dashboard_screen.dart';
import '../screens/institute/institute_login_screen.dart';
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
import '../screens/ai/ai_chat_page.dart';
import '../screens/student/student_profile_screen.dart';
import '../screens/student/student_groups_screen.dart';
import '../screens/teacher/teacher_groups_screen.dart';
import '../screens/teacher/profile_screen.dart';
import '../screens/parent/parent_section_group_chat_screen.dart';

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

      case '/parent-login':
        return MaterialPageRoute(builder: (_) => const ParentLoginScreen());

      case '/institute-login':
        return MaterialPageRoute(builder: (_) => const InstituteLoginScreen());

      case '/parent-dashboard':
        return MaterialPageRoute(
          builder: (_) => const ParentMainNavigation(initialIndex: 0),
        );

      case '/parent/child-profile':
        return MaterialPageRoute(builder: (_) => const ChildProfileScreen());

      case '/institute-dashboard':
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Institute Dashboard - Coming Soon')),
          ),
        );

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
          builder: (_) => const StudentMainNavigation(initialIndex: 3),
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
          builder: (_) => const StudentMainNavigation(initialIndex: 4),
        );

      case '/student-profile':
        return MaterialPageRoute(builder: (_) => const StudentProfileScreen());

      case '/student-groups':
        return MaterialPageRoute(builder: (_) => const StudentGroupsScreen());

      case '/teacher-dashboard':
        return MaterialPageRoute(
          builder: (_) => const TeacherMainNavigation(initialIndex: 0),
        );

      case '/create-test':
        return MaterialPageRoute(builder: (_) => const CreateTestScreen());

      case '/create-test-entry':
        return MaterialPageRoute(builder: (_) => const CreateTestEntryScreen());

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

      case '/test-media-upload':
        return MaterialPageRoute(builder: (_) => const TestMediaUploadScreen());

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
        return MaterialPageRoute(builder: (_) => const ProfileScreen());

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

      case '/parent/section-group-chat':
        final args = settings.arguments as Map<String, dynamic>?;
        final groupId = args?['groupId'] as String?;
        final groupName = args?['groupName'] as String?;
        if (groupId == null || groupName == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing section group data')),
            ),
          );
        }

        return MaterialPageRoute(
          builder: (_) => ParentSectionGroupChatScreen(
            groupId: groupId,
            groupName: groupName,
            className: args?['className'] as String?,
            section: args?['section'] as String?,
            childName: (args?['childName'] as String?) ?? '',
            childId: (args?['childId'] as String?) ?? '',
            schoolCode: args?['schoolCode'] as String?,
            senderRole: (args?['senderRole'] as String?) ?? 'parent',
          ),
        );

      case '/ai-chat':
        return MaterialPageRoute(builder: (_) => const AiChatPage());

      case '/teacher-groups':
        return MaterialPageRoute(builder: (_) => const TeacherGroupsScreen());

      case '/test-media-upload':
        return MaterialPageRoute(builder: (_) => const TestMediaUploadScreen());

      // YouTube feature removed

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
