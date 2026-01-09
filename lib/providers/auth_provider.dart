import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _initialized = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _initialized;

  /// Ensure auth is initialized (idempotent)
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await initializeAuth();
    }
  }

  /// Initialize auth state from Firebase Auth
  Future<void> initializeAuth() async {
    if (_initialized) return;

    _isLoading = true;
    notifyListeners();

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        // User is already logged in, load their data
        _currentUser = await _authService.getUserData(firebaseUser.uid);
        print(
          '✅ Auth initialized: ${_currentUser?.name} (${_currentUser?.role})',
        );
      }
    } catch (e) {
      print('⚠️ Error initializing auth: $e');
      _errorMessage = e.toString();
    } finally {
      _initialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  // Sign in
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signInWithEmailPassword(
        email,
        password,
      );
      _isLoading = false;
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Register
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? instituteId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.registerWithEmailPassword(
        email: email,
        password: password,
        name: name,
        role: role,
        phone: phone,
        instituteId: instituteId,
      );
      _isLoading = false;
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Clear all SharedPreferences data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      print('✅ All local data cleared from SharedPreferences');

      // Sign out from Firebase
      await _authService.signOut();

      // Clear current user
      _currentUser = null;

      // Reset initialization flag
      _initialized = false;

      notifyListeners();

      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error during sign out: $e');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Callback to notify other providers when user changes
  void Function()? onUserChanged;

  // Reset password
  Future<bool> resetPassword(String email) async {
    try {
      await _authService.resetPassword(email);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Update user profile
  void updateUserProfile(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
