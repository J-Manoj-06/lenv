import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static SharedPreferences? _prefsCache;

  /// Get SharedPreferences instance (cached for performance)
  static Future<SharedPreferences> _getPrefs() async {
    _prefsCache ??= await SharedPreferences.getInstance();
    return _prefsCache!;
  }

  /// Save user login session
  static Future<void> saveLoginSession({
    required String userId,
    required String userRole, // 'teacher' or 'student'
    String? schoolId, // instituteId
  }) async {
    final prefs = await _getPrefs();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userId', userId);
    await prefs.setString('userRole', userRole);
    if (schoolId != null && schoolId.isNotEmpty) {
      await prefs.setString('schoolId', schoolId);
    }
  }

  /// Check if user has an active session
  static Future<Map<String, dynamic>> getLoginSession() async {
    final prefs = await _getPrefs();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userId = prefs.getString('userId');
    final userRole = prefs.getString('userRole');
    final schoolId = prefs.getString('schoolId');

    // Do not require FirebaseAuth.currentUser here.
    // On cold start (especially offline), Firebase user restoration can be delayed
    // and would incorrectly force navigation to login.
    final hasLocalSession =
        isLoggedIn && userId != null && userId.isNotEmpty && userRole != null;

    return {
      'isLoggedIn': hasLocalSession,
      'userId': userId,
      'userRole': userRole,
      'schoolId': schoolId,
    };
  }

  /// Clear user session (logout)
  static Future<void> clearLoginSession() async {
    final prefs = await _getPrefs();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('userRole');
    await prefs.remove('schoolId');
    _prefsCache = null; // Clear cache on logout
  }

  /// Get initial screen route based on session
  static Future<String> getInitialScreen() async {
    final session = await getLoginSession();
    // ignore: avoid_print
    if (session['isLoggedIn'] == true) {
      final userRole = session['userRole'] as String?;
      if (userRole == 'teacher') {
        return '/teacher-dashboard';
      } else if (userRole == 'student') {
        return '/student-dashboard';
      } else if (userRole == 'parent') {
        return '/parent-dashboard';
      } else if (userRole == 'institute') {
        return '/institute-dashboard';
      }
    }
    // When not logged in, send to role selection (we don't have a '/login' route)
    return '/role-selection';
  }
}
