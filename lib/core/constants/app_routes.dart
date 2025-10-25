class AppRoutes {
  // Auth Routes
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String roleSelection = '/role-selection';
  
  // Common Routes
  static const String profile = '/profile';
  
  // Institute Routes
  static const String instituteDashboard = '/institute/dashboard';
  static const String manageTeachers = '/institute/teachers';
  static const String manageStudents = '/institute/students';
  static const String announcements = '/institute/announcements';
  
  // Teacher Routes
  static const String teacherDashboard = '/teacher/dashboard';
  static const String createTest = '/teacher/create-test';
  static const String evaluateTest = '/teacher/evaluate-test';
  static const String teacherAnalytics = '/teacher/analytics';
  
  // Student Routes
  static const String studentDashboard = '/student/dashboard';
  static const String takeTest = '/student/take-test';
  static const String studentResults = '/student/results';
  static const String studentRewards = '/student/rewards';
  
  // Parent Routes
  static const String parentDashboard = '/parent/dashboard';
  static const String childProgress = '/parent/child-progress';
  static const String sendReward = '/parent/send-reward';
}
