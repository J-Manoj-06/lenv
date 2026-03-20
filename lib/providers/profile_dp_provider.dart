import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/profile_dp_service.dart';

/// State management for profile display pictures.
///
/// Provides:
/// - Current user's DP URL (reactive)
/// - Upload / remove operations with progress tracking
/// - Cache of other users' DP URLs (to avoid repeated fetches)
class ProfileDPProvider extends ChangeNotifier {
  final ProfileDPService _dpService = ProfileDPService();
  final Set<String> _loggedPermissionErrors = <String>{};

  bool _isPermissionDeniedError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('permission-denied') ||
        msg.contains('permission denied') ||
        msg.contains('insufficient permissions');
  }

  void _logPermissionErrorOnce(String key, Object error) {
    if (_loggedPermissionErrors.add(key)) {
      debugPrint('ProfileDPProvider permission denied [$key]: $error');
    }
  }

  static String _friendlyErrorMessage(Object error, String fallback) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('permission-denied') ||
        lower.contains('permission denied') ||
        lower.contains('insufficient permissions')) {
      return 'Permission denied. Check Firestore access for this photo.';
    }

    if (lower.contains('network') ||
        lower.contains('socketexception') ||
        lower.contains('unavailable')) {
      return 'Network error. Check your internet connection and try again.';
    }

    return fallback;
  }

  // ── Current user state ────────────────────────────────────────────────────
  String? _currentUserId;
  String? _currentUserDP;
  bool _hasProfileImage = false;

  // Upload state
  bool _isUploading = false;
  int _uploadProgress = 0;
  String? _uploadError;

  // Real-time listener
  StreamSubscription<Map<String, dynamic>?>? _dpSubscription;

  // ── Other users' DP cache ─────────────────────────────────────────────────
  final Map<String, String?> _userDPCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, String> _userDPUpdatedAt = {}; // userId → updatedAt string
  static const Duration _cacheTTL = Duration(hours: 24);

  // ── Group DP cache ────────────────────────────────────────────────────────
  final Map<String, String?> _groupDPCache = {};
  final Map<String, String> _groupDPUpdatedAt =
      {}; // groupId → updatedAt string
  final Map<String, StreamSubscription<Map<String, dynamic>?>>
  _groupDPSubscriptions = {};

  // ── Staff room DP cache ──────────────────────────────────────────────────
  final Map<String, String?> _staffRoomDPCache = {};
  final Map<String, String> _staffRoomDPUpdatedAt = {};
  final Map<String, StreamSubscription<Map<String, dynamic>?>>
  _staffRoomDPSubscriptions = {};

  // ── Getters ───────────────────────────────────────────────────────────────
  String? get currentUserDP => _currentUserDP;
  bool get hasProfileImage => _hasProfileImage;
  bool get isUploading => _isUploading;
  int get uploadProgress => _uploadProgress;
  String? get uploadError => _uploadError;

  /// Cache key for current user's DP — unique per upload.
  String get currentUserCacheKey =>
      _buildUserCacheKey(_currentUserId ?? '', _currentUserDP);

  /// Cache key for any user's DP for use in CachedNetworkImage.
  String getUserCacheKey(String userId) =>
      _buildUserCacheKey(userId, _userDPCache[userId]);

  /// Cache key for a group DP.
  String getGroupCacheKey(String groupId) =>
      'gp_${groupId}_${_groupDPUpdatedAt[groupId] ?? _groupDPCache[groupId] ?? groupId}';

  /// Cache key for a staff-room DP.
  String getStaffRoomCacheKey(String roomId) =>
      'sr_${roomId}_${_staffRoomDPUpdatedAt[roomId] ?? _staffRoomDPCache[roomId] ?? roomId}';

  static String _buildUserCacheKey(String userId, String? url) {
    // Use URL as key component since it already embeds an upload timestamp.
    // Fallback to userId so the key is never empty.
    return 'dp_${userId}_${url?.hashCode ?? 0}';
  }

  // ── Initialization ────────────────────────────────────────────────────────

  /// Start listening to the current user's DP in real-time.
  void initForUser(String userId, {String? userName}) {
    if (_currentUserId == userId) return; // already listening
    _currentUserId = userId;
    _dpSubscription?.cancel();
    _dpSubscription = _dpService
        .watchUserDP(userId)
        .listen(
          (data) {
            _currentUserDP = data?['profileImageUrl'] as String?;
            _hasProfileImage = data?['hasProfileImage'] as bool? ?? false;

            // Store updatedAt for cache-key building
            final ts = data?['profileImageUpdatedAt'];
            if (ts != null) _userDPUpdatedAt[userId] = ts.toString();

            // Also update cache entry for this user
            _userDPCache[userId] = _currentUserDP;
            _cacheTimestamps[userId] = DateTime.now();

            notifyListeners();
          },
          onError: (error) {
            if (_isPermissionDeniedError(error)) {
              _logPermissionErrorOnce('user:$userId', error);
              _currentUserDP = null;
              _hasProfileImage = false;
              _dpSubscription?.cancel();
              _dpSubscription = null;
              notifyListeners();
              return;
            }
            debugPrint('ProfileDPProvider user dp stream error: $error');
          },
        );
  }

  /// Clear all active listeners and transient session state on logout.
  void clearSession() {
    _dpSubscription?.cancel();
    _dpSubscription = null;

    for (final sub in _groupDPSubscriptions.values) {
      sub.cancel();
    }
    _groupDPSubscriptions.clear();

    for (final sub in _staffRoomDPSubscriptions.values) {
      sub.cancel();
    }
    _staffRoomDPSubscriptions.clear();

    _currentUserId = null;
    _currentUserDP = null;
    _hasProfileImage = false;
    _isUploading = false;
    _uploadProgress = 0;
    _uploadError = null;

    _userDPCache.clear();
    _cacheTimestamps.clear();
    _userDPUpdatedAt.clear();
    _groupDPCache.clear();
    _groupDPUpdatedAt.clear();
    _staffRoomDPCache.clear();
    _staffRoomDPUpdatedAt.clear();

    notifyListeners();
  }

  @override
  void dispose() {
    _dpSubscription?.cancel();
    for (final sub in _groupDPSubscriptions.values) {
      sub.cancel();
    }
    for (final sub in _staffRoomDPSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  // ── Upload operations ─────────────────────────────────────────────────────

  /// Upload or change profile picture.
  ///
  /// [userId] must be the current authenticated user's UID.
  Future<bool> uploadProfileImage({
    required String userId,
    required File imageFile,
  }) async {
    // Validate
    final validationError = ProfileDPService.validateImageFile(imageFile);
    if (validationError != null) {
      _uploadError = validationError;
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _uploadProgress = 0;
    _uploadError = null;
    notifyListeners();

    try {
      final url = await _dpService.uploadProfileImage(
        userId: userId,
        imageFile: imageFile,
        onProgress: (p) {
          _uploadProgress = p;
          notifyListeners();
        },
      );

      _currentUserDP = url;
      _hasProfileImage = true;
      _userDPCache[userId] = url;
      _cacheTimestamps[userId] = DateTime.now();
      _isUploading = false;
      _uploadProgress = 100;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(
        e,
        'Upload failed. Please try again.',
      );
      _isUploading = false;
      debugPrint('ProfileDPProvider: upload error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove the current user's profile picture.
  Future<bool> removeProfileImage({required String userId}) async {
    _isUploading = true;
    _uploadError = null;
    notifyListeners();

    try {
      await _dpService.removeProfileImage(userId: userId);
      _currentUserDP = null;
      _hasProfileImage = false;
      _userDPCache[userId] = null;
      _isUploading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(
        e,
        'Failed to remove photo. Please try again.',
      );
      _isUploading = false;
      debugPrint('ProfileDPProvider: remove error: $e');
      notifyListeners();
      return false;
    }
  }

  // ── Other user DP lookup ──────────────────────────────────────────────────

  /// Get a user's DP URL. Uses cache; fetches from Firestore if expired.
  Future<String?> getUserDP(String userId) async {
    // Check cache freshness
    final lastFetch = _cacheTimestamps[userId];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _cacheTTL &&
        _userDPCache.containsKey(userId)) {
      return _userDPCache[userId];
    }

    try {
      final data = await _dpService.getUserDPData(userId);
      final url = data?['url'] as String?;
      final updatedAt = data?['updatedAt'] as String?;
      _userDPCache[userId] = url;
      _cacheTimestamps[userId] = DateTime.now();
      if (updatedAt != null) _userDPUpdatedAt[userId] = updatedAt;
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Get a cached DP URL synchronously (may be null if not yet loaded).
  String? getCachedUserDP(String userId) => _userDPCache[userId];

  // ── Group DP ──────────────────────────────────────────────────────────────

  /// Start listening to a group's DP in real-time.
  void watchGroupDP(String groupId) {
    if (_groupDPSubscriptions.containsKey(groupId)) return;
    _groupDPSubscriptions[groupId] = _dpService
        .watchGroupDP(groupId)
        .listen(
          (data) {
            _groupDPCache[groupId] = data?['groupImageUrl'] as String?;
            // Store updatedAt for cache-key building
            final ts = data?['groupImageUpdatedAt'];
            if (ts != null) _groupDPUpdatedAt[groupId] = ts.toString();
            notifyListeners();
          },
          onError: (error) {
            if (_isPermissionDeniedError(error)) {
              _logPermissionErrorOnce('group:$groupId', error);
              _groupDPSubscriptions[groupId]?.cancel();
              _groupDPSubscriptions.remove(groupId);
              return;
            }
            debugPrint('ProfileDPProvider group dp stream error: $error');
          },
        );
  }

  /// Get group DP from cache.
  String? getGroupDP(String groupId) => _groupDPCache[groupId];

  /// Upload group DP (teachers only).
  Future<bool> uploadGroupImage({
    required String groupId,
    required File imageFile,
  }) async {
    final validationError = ProfileDPService.validateImageFile(imageFile);
    if (validationError != null) {
      _uploadError = validationError;
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _uploadProgress = 0;
    _uploadError = null;
    notifyListeners();

    try {
      final url = await _dpService.uploadGroupImage(
        groupId: groupId,
        imageFile: imageFile,
        onProgress: (p) {
          _uploadProgress = p;
          notifyListeners();
        },
      );

      _groupDPCache[groupId] = url;
      _isUploading = false;
      _uploadProgress = 100;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(
        e,
        'Group photo upload failed. Please try again.',
      );
      _isUploading = false;
      debugPrint('ProfileDPProvider: group upload error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove group DP.
  Future<bool> removeGroupImage({required String groupId}) async {
    _isUploading = true;
    _uploadError = null;
    notifyListeners();

    try {
      await _dpService.removeGroupImage(groupId: groupId);
      _groupDPCache[groupId] = null;
      _isUploading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(e, 'Failed to remove group photo.');
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear upload error.
  void clearError() {
    _uploadError = null;
    notifyListeners();
  }

  // ── Staff room DP ────────────────────────────────────────────────────────

  /// Start listening to a staff-room DP in real-time.
  void watchStaffRoomDP(String roomId) {
    if (_staffRoomDPSubscriptions.containsKey(roomId)) return;
    _staffRoomDPSubscriptions[roomId] = _dpService
        .watchStaffRoomDP(roomId)
        .listen(
          (data) {
            _staffRoomDPCache[roomId] = data?['staffRoomImageUrl'] as String?;
            final ts = data?['staffRoomImageUpdatedAt'];
            if (ts != null) _staffRoomDPUpdatedAt[roomId] = ts.toString();
            notifyListeners();
          },
          onError: (error) {
            if (_isPermissionDeniedError(error)) {
              _logPermissionErrorOnce('staffRoom:$roomId', error);
              _staffRoomDPSubscriptions[roomId]?.cancel();
              _staffRoomDPSubscriptions.remove(roomId);
              return;
            }
            debugPrint('ProfileDPProvider staff room dp stream error: $error');
          },
        );
  }

  /// Get staff-room DP from cache.
  String? getStaffRoomDP(String roomId) => _staffRoomDPCache[roomId];

  /// Upload staff-room DP (principal / institute only).
  Future<bool> uploadStaffRoomImage({
    required String roomId,
    required File imageFile,
  }) async {
    final validationError = ProfileDPService.validateImageFile(imageFile);
    if (validationError != null) {
      _uploadError = validationError;
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _uploadProgress = 0;
    _uploadError = null;
    notifyListeners();

    try {
      final url = await _dpService.uploadStaffRoomImage(
        roomId: roomId,
        imageFile: imageFile,
        onProgress: (p) {
          _uploadProgress = p;
          notifyListeners();
        },
      );

      _staffRoomDPCache[roomId] = url;
      _isUploading = false;
      _uploadProgress = 100;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(
        e,
        'Staff room photo upload failed. Please try again.',
      );
      _isUploading = false;
      debugPrint('ProfileDPProvider: staff room upload error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove staff-room DP.
  Future<bool> removeStaffRoomImage({required String roomId}) async {
    _isUploading = true;
    _uploadError = null;
    notifyListeners();

    try {
      await _dpService.removeStaffRoomImage(roomId: roomId);
      _staffRoomDPCache[roomId] = null;
      _isUploading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _uploadError = _friendlyErrorMessage(
        e,
        'Failed to remove staff room photo.',
      );
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }
}
