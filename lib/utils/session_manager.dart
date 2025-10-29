import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionManager {
  /// Save user login session
  static Future<void> saveLoginSession({
    required String userId,
    required String userRole, // 'teacher' or 'student'
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userId', userId);
    await prefs.setString('userRole', userRole);
    print('✅ Session saved: $userRole ($userId)');
  }

  /// Check if user has an active session
  static Future<Map<String, dynamic>> getLoginSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userId = prefs.getString('userId');
    final userRole = prefs.getString('userRole');
    final user = FirebaseAuth.instance.currentUser;

    return {
      'isLoggedIn': isLoggedIn && user != null,
      'userId': userId,
      'userRole': userRole,
    };
  }

  /// Clear user session (logout)
  static Future<void> clearLoginSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('userRole');
    print('✅ Session cleared');
  }

  /// Get initial screen route based on session
  static Future<String> getInitialScreen() async {
    final session = await getLoginSession();
    if (session['isLoggedIn'] == true) {
      if (session['userRole'] == 'teacher') {
        return '/teacher-dashboard';
      } else if (session['userRole'] == 'student') {
        return '/student-dashboard';
      }
    }
    return '/login';
  }
}
