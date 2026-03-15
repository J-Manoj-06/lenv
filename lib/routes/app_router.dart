import 'package:flutter/material.dart';
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
import '../screens/institute/institute_login_screen.dart';
import '../widgets/institute_main_navigation.dart';
import '../screens/student/student_test_result_screen.dart';
import '../screens/rewards/search_rewards_screen.dart';
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
import '../screens/teacher/theme_settings_screen.dart';
import '../screens/parent/parent_group_chat_page.dart';
import '../screens/notifications/notifications_screen.dart';
import '../share/share_target_screen.dart';
import '../share/incoming_share_data.dart';
import '../screens/messages/community_chat_page.dart';
import '../screens/messages/teacher_group_chat_page.dart';
import '../screens/messages/staff_room_group_chat_page.dart';

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
          builder: (_) => const InstituteMainNavigation(),
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

      case '/teacher/theme-settings':
        return MaterialPageRoute(builder: (_) => const ThemeSettingsScreen());

      case '/my-highlights':
        return MaterialPageRoute(builder: (_) => const MyHighlightsScreen());

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
          builder: (_) => ParentGroupChatPage(
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

      case '/notifications':
        return MaterialPageRoute(builder: (_) => const NotificationsScreen());

      case '/community-group-chat':
        final args = settings.arguments as Map<String, dynamic>?;
        final communityId =
            (args?['communityId'] ?? args?['targetId'] ?? '') as String;
        final communityName =
            (args?['groupName'] ?? args?['communityName'] ?? communityId)
                as String;
        final communityIcon = (args?['communityIcon'] ?? '🌐') as String;
        if (communityId.isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing community ID')),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => CommunityChatPage(
            communityId: communityId,
            communityName: communityName,
            icon: communityIcon,
          ),
        );

      case '/teacher/student-group-chat':
        final args = settings.arguments as Map<String, dynamic>?;
        final fallbackTargetId = (args?['targetId'] ?? '').toString();
        final targetParts = fallbackTargetId.split('|');
        final classId =
            (args?['classId'] ??
                    (targetParts.isNotEmpty ? targetParts.first : ''))
                .toString();
        final subjectId =
            (args?['subjectId'] ??
                    (targetParts.length > 1 ? targetParts[1] : ''))
                .toString();
        final subjectName =
            (args?['subjectName'] ?? subjectId.replaceAll('_', ' ')).toString();
        final teacherName = (args?['teacherName'] ?? 'Teacher').toString();
        final icon = (args?['icon'] ?? '📕').toString();
        final className = args?['className']?.toString();
        final section = args?['section']?.toString();

        if (classId.isEmpty || subjectId.isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing teacher-student group data')),
            ),
          );
        }

        return MaterialPageRoute(
          builder: (_) => TeacherGroupChatPage(
            classId: classId,
            subjectId: subjectId,
            subjectName: subjectName,
            teacherName: teacherName,
            icon: icon,
            className: className,
            section: section,
          ),
        );

      case '/staff-room-chat':
        final args = settings.arguments as Map<String, dynamic>?;
        final instituteId =
            (args?['instituteId'] ??
                    args?['groupId'] ??
                    args?['targetId'] ??
                    '')
                .toString();
        final instituteName =
            (args?['instituteName'] ?? args?['groupName'] ?? 'Staff Room')
                .toString();
        if (instituteId.isEmpty) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing staff room data')),
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => StaffRoomGroupChatPage(
            instituteId: instituteId,
            instituteName: instituteName,
          ),
        );

      case '/share-target':
        final shareData = settings.arguments as IncomingShareData?;
        if (shareData == null) {
          return MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('Missing share data'))),
          );
        }
        return MaterialPageRoute(
          builder: (_) => ShareTargetScreen(shareData: shareData),
        );

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
