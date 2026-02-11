import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service for monitoring network connectivity status
class NetworkService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  // Stream controller to broadcast connectivity changes
  final _connectivityController = StreamController<bool>.broadcast();

  /// Stream that emits true when connected, false when disconnected
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  /// Initialize network monitoring
  void initialize() {
    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _checkConnectivity([result]);
    });

    // Check initial connectivity
    _checkInitialConnectivity();
  }

  /// Check initial connectivity status
  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _checkConnectivity([result]);
    } catch (e) {
      _connectivityController.add(false);
    }
  }

  /// Process connectivity results
  void _checkConnectivity(List<ConnectivityResult> results) {
    // Check if any connection is available
    final isConnected = results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );

    _connectivityController.add(isConnected);
  }

  /// Check if device is currently connected to internet
  Future<bool> isConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet;
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
