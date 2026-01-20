import 'package:connectivity_plus/connectivity_plus.dart';

/// Service to track network connectivity state globally
/// Provides a stream of connectivity changes and synchronous checks
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  bool _initialized = false;

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  /// Initialize connectivity monitoring
  /// Call once in main() before using the service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Check initial connectivity state with timeout
      final result = await _connectivity.checkConnectivity().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () =>
            ConnectivityResult.wifi, // Assume online if check times out
      );
      _isOnline = result != ConnectivityResult.none;
      _initialized = true;

      // Listen for connectivity changes
      _connectivity.onConnectivityChanged.listen((result) {
        _isOnline = result != ConnectivityResult.none;
      });
    } catch (e) {
      // If we can't determine state, assume online (safer default)
      _isOnline = true;
      _initialized = true;
    }
  }

  /// Check if device is currently online
  bool get isOnline => _isOnline;

  /// Check if device is currently offline
  bool get isOffline => !_isOnline;

  /// Get stream of connectivity changes
  /// Useful for listening to network state changes in UI/providers
  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged
      .map((result) => result != ConnectivityResult.none);
}
