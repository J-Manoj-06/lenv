import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

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
    debugPrint(
      '🔐 [SessionManager] saveLoginSession -> userId=$userId, userRole=$userRole, schoolId=$schoolId',
    );
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userId', userId);
    await prefs.setString('userRole', userRole);
    if (schoolId != null && schoolId.isNotEmpty) {
      await prefs.setString('schoolId', schoolId);
    }

    debugPrint(
      '✅ [SessionManager] saved -> isLoggedIn=${prefs.getBool('isLoggedIn')}, userId=${prefs.getString('userId')}, userRole=${prefs.getString('userRole')}, schoolId=${prefs.getString('schoolId')}',
    );
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

    debugPrint(
      '📦 [SessionManager] getLoginSession -> raw(isLoggedIn=$isLoggedIn, userId=$userId, userRole=$userRole, schoolId=$schoolId) => hasLocalSession=$hasLocalSession',
    );

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
    debugPrint(
      '🧹 [SessionManager] clearLoginSession -> clearing persisted keys',
    );
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('userRole');
    await prefs.remove('schoolId');
    _prefsCache = null; // Clear cache on logout
    debugPrint('✅ [SessionManager] clearLoginSession -> done');
  }

  /// Get initial screen route based on session
  static Future<String> getInitialScreen() async {
    final session = await getLoginSession();
    debugPrint('🧭 [SessionManager] getInitialScreen -> session=$session');
    if (session['isLoggedIn'] == true) {
      final userRole = session['userRole'] as String?;
      if (userRole == 'teacher') {
        debugPrint('🧭 [SessionManager] route=/teacher-dashboard');
        return '/teacher-dashboard';
      } else if (userRole == 'student') {
        debugPrint('🧭 [SessionManager] route=/student-dashboard');
        return '/student-dashboard';
      } else if (userRole == 'parent') {
        debugPrint('🧭 [SessionManager] route=/parent-dashboard');
        return '/parent-dashboard';
      } else if (userRole == 'institute') {
        debugPrint('🧭 [SessionManager] route=/institute-dashboard');
        return '/institute-dashboard';
      }
    }
    // When not logged in, send to role selection (we don't have a '/login' route)
    debugPrint('🧭 [SessionManager] route=/role-selection (fallback)');
    return '/role-selection';
  }
}
