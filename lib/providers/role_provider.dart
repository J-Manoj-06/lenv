import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class RoleProvider with ChangeNotifier {
  UserRole? _selectedRole;

  UserRole? get selectedRole => _selectedRole;

  void setRole(UserRole role) {
    _selectedRole = role;
    notifyListeners();
  }

  void clearRole() {
    _selectedRole = null;
    notifyListeners();
  }

  String getRoleName() {
    switch (_selectedRole) {
      case UserRole.institute:
        return 'Institute';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.student:
        return 'Student';
      case UserRole.parent:
        return 'Parent';
      default:
        return 'Unknown';
    }
  }

  String getRoleRoute() {
    switch (_selectedRole) {
      case UserRole.institute:
        return '/institute/dashboard';
      case UserRole.teacher:
        return '/teacher/dashboard';
      case UserRole.student:
        return '/student/dashboard';
      case UserRole.parent:
        return '/parent/dashboard';
      default:
        return '/';
    }
  }
}
