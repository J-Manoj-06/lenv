import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
    // Don't notify during initialization to avoid setState during build
    // notifyListeners() will be called once at the end

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        // User is already logged in, load their data
        try {
          _currentUser = await _authService.getUserData(firebaseUser.uid);

          // Cache user data for offline access
          if (_currentUser != null) {
            await _cacheUserData(_currentUser!);
          }
        } catch (e) {
          // Firestore fetch failed (likely offline), try loading from cache
          debugPrint('⚠️ Failed to fetch user data from Firestore: $e');
          debugPrint('🔄 Attempting to load from cache...');
          _currentUser = await _loadCachedUserData();

          if (_currentUser != null) {
            debugPrint('✅ Loaded user from cache: ${_currentUser!.name}');
          } else {
            debugPrint('❌ No cached user data found');
          }
        }
      } else {
        // Firebase auth state may not be restored yet (or device is offline).
        // Try cached user data so app can continue in offline mode.
        _currentUser = await _loadCachedUserData();

        if (_currentUser != null) {
          debugPrint(
            '✅ Loaded cached user while Firebase user is unavailable: ${_currentUser!.name}',
          );
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('❌ Error initializing auth: $e');
    } finally {
      _initialized = true;
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Safely notify listeners, deferring if called during build
  void _safeNotifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // We're in the build phase, defer notification
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      // Safe to notify immediately
      notifyListeners();
    }
  }

  /// Cache user data to SharedPreferences for offline access
  Future<void> _cacheUserData(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = {
        'uid': user.uid,
        'email': user.email,
        'name': user.name,
        'role': user.role.toString(),
        'phone': user.phone,
        'profileImage': user.profileImage,
        'instituteId': user.instituteId,
        'createdAt': user.createdAt.toIso8601String(),
        'isActive': user.isActive,
      };
      await prefs.setString('cached_user_data', jsonEncode(userData));
    } catch (e) {
      debugPrint('⚠️ Failed to cache user data: $e');
    }
  }

  /// Load cached user data from SharedPreferences
  Future<UserModel?> _loadCachedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_user_data');

      if (cachedData == null || cachedData.isEmpty) {
        return null;
      }

      final Map<String, dynamic> userData = jsonDecode(cachedData);

      // Parse role enum
      UserRole role;
      final roleStr = userData['role'].toString();
      if (roleStr.contains('teacher')) {
        role = UserRole.teacher;
      } else if (roleStr.contains('student')) {
        role = UserRole.student;
      } else if (roleStr.contains('parent')) {
        role = UserRole.parent;
      } else if (roleStr.contains('institute')) {
        role = UserRole.institute;
      } else {
        role = UserRole.student; // Default fallback
      }

      return UserModel(
        uid: userData['uid'],
        email: userData['email'],
        name: userData['name'],
        role: role,
        phone: userData['phone'],
        profileImage: userData['profileImage'],
        instituteId: userData['instituteId'],
        createdAt: DateTime.parse(userData['createdAt']),
        isActive: userData['isActive'] ?? true,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load cached user data: $e');
      return null;
    }
  }

  /// Force re-fetch the current user, bypassing the _initialized guard.
  /// Useful when the user object is null despite a valid Firebase session.
  Future<void> forceRefreshUser() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          _currentUser = await _authService.getUserData(firebaseUser.uid);
          if (_currentUser != null) await _cacheUserData(_currentUser!);
        } catch (_) {
          _currentUser ??= await _loadCachedUserData();
        }
      } else {
        _currentUser ??= await _loadCachedUserData();
      }
      _initialized = true;
      _safeNotifyListeners();
    } catch (_) {}
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

      // Cache user data for offline access
      if (_currentUser != null) {
        await _cacheUserData(_currentUser!);
      }

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
      // Pause Firestore network to avoid transient permission-denied noise
      // from listeners while auth token is being revoked.
      try {
        await FirebaseFirestore.instance.disableNetwork();
      } catch (_) {}

      // Clear only auth/session-related keys.
      // Keep school selection keys so the last selected school is preserved.
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove('isLoggedIn'),
        prefs.remove('userId'),
        prefs.remove('userRole'),
        prefs.remove('schoolId'),
        prefs.remove('cached_user_data'),
      ]);

      // Sign out from Firebase
      await _authService.signOut();

      // Clear current user
      _currentUser = null;

      // Reset initialization flag
      _initialized = false;

      notifyListeners();

      // Re-enable network after a short delay so the logged-out UI can mount
      // and stale listeners from the previous route are fully disposed.
      Future<void>.delayed(const Duration(milliseconds: 900), () async {
        try {
          await FirebaseFirestore.instance.enableNetwork();
        } catch (_) {}
      });
    } catch (e) {
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
