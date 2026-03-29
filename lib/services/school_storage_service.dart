import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage school-related data in local storage
class SchoolStorageService {
  static const String _keySchoolId = 'school_id';
  static const String _keySchoolName = 'school_name';
  static const String _keySchoolLogo = 'school_logo';
  static const String _keyThemeColor = 'theme_color';
  static const String _keyHasSeenOnboarding = 'has_seen_onboarding';

  late SharedPreferences _prefs;

  /// Initialize SharedPreferences
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Check if app has been launched for the first time
  bool get hasSeenOnboarding {
    return _prefs.getBool(_keyHasSeenOnboarding) ?? false;
  }

  /// Mark onboarding as seen
  Future<void> setOnboardingSeen() async {
    await _prefs.setBool(_keyHasSeenOnboarding, true);
  }

  /// Get stored school ID
  String? get schoolId {
    return _prefs.getString(_keySchoolId);
  }

  /// Get stored school name
  String? get schoolName {
    return _prefs.getString(_keySchoolName);
  }

  /// Get stored school logo URL
  String? get schoolLogo {
    return _prefs.getString(_keySchoolLogo);
  }

  /// Get stored theme color (as hex string)
  String? get themeColor {
    return _prefs.getString(_keyThemeColor);
  }

  /// Save school data
  Future<void> saveSchoolData({
    required String schoolId,
    required String schoolName,
    required String schoolLogo,
    String? themeColor,
  }) async {
    await Future.wait([
      _prefs.setString(_keySchoolId, schoolId),
      _prefs.setString(_keySchoolName, schoolName),
      _prefs.setString(_keySchoolLogo, schoolLogo),
      if (themeColor != null) _prefs.setString(_keyThemeColor, themeColor),
    ]);
  }

  /// Update school logo
  Future<void> updateSchoolLogo(String logoUrl) async {
    await _prefs.setString(_keySchoolLogo, logoUrl);
  }

  /// Check if school is selected
  bool get isSchoolSelected {
    return schoolId != null && schoolId!.isNotEmpty;
  }

  /// Clear all school data (for logout)
  Future<void> clearSchoolData() async {
    await Future.wait([
      _prefs.remove(_keySchoolId),
      _prefs.remove(_keySchoolName),
      _prefs.remove(_keySchoolLogo),
      _prefs.remove(_keyThemeColor),
    ]);
  }
}

// Singleton instance
final schoolStorageService = SchoolStorageService();
