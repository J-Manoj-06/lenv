import 'package:flutter/material.dart';
import '../screens/common/splash_screen.dart';
import '../screens/common/role_selection_screen.dart';
import '../screens/teacher/teacher_login_screen.dart';
import '../screens/teacher/teacher_dashboard.dart';
import '../screens/teacher/create_test_screen.dart';
import '../screens/teacher/ai_test_generator_screen.dart';
import '../screens/teacher/classes_screen.dart';
import '../screens/teacher/student_list_screen.dart';
import '../screens/teacher/student_performance_screen.dart';
import '../screens/teacher/tests_screen.dart';
import '../screens/teacher/test_result_screen.dart';
import '../screens/teacher/leaderboard_screen.dart';
import '../screens/teacher/profile_screen.dart';
import '../screens/student/student_login_screen.dart';
import '../screens/student/student_dashboard_screen.dart';
import '../screens/dev/dev_tools_screen.dart';
import '../screens/student/student_test_result_screen.dart';

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
          builder: (_) => const StudentDashboardScreen(),
        );

      case '/teacher-dashboard':
        return MaterialPageRoute(
          builder: (_) => const TeacherDashboardScreen(),
        );

      case '/create-test':
        return MaterialPageRoute(builder: (_) => const CreateTestScreen());

      case '/ai-test-generator':
        return MaterialPageRoute(builder: (_) => const AITestGeneratorScreen());

      case '/classes':
        return MaterialPageRoute(builder: (_) => const ClassesScreen());

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
        return MaterialPageRoute(builder: (_) => const TestsScreen());

      case '/test-result':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder: (_) => TestResultScreen(
            testName: args['name'] ?? 'Test',
            className: args['class'] ?? 'Grade',
            status: args['status'] ?? 'Past',
            endTime: args['endTime'] ?? '',
          ),
        );

      case '/leaderboard':
        return MaterialPageRoute(builder: (_) => const LeaderboardScreen());

      case '/profile':
        return MaterialPageRoute(builder: (_) => const ProfileScreen());

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
