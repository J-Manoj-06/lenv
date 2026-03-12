import 'dart:async';
import 'package:flutter/material.dart';
import '../models/student_dashboard_data.dart';
import '../repositories/dashboard_repository.dart';
import '../services/network_service.dart';

/// Provider for managing student dashboard state
class DashboardProvider extends ChangeNotifier {
  final DashboardRepository _repository;
  final NetworkService _networkService;

  // State variables
  StudentDashboardData? _dashboardData;
  bool _isLoading = false;
  bool _isConnected = true;
  bool _hasError = false;
  String? _errorMessage;
  StreamSubscription<bool>? _connectivitySubscription;

  DashboardProvider({
    required DashboardRepository repository,
    required NetworkService networkService,
  }) : _repository = repository,
       _networkService = networkService {
    _initializeConnectivityListener();
  }

  // Getters
  StudentDashboardData? get dashboardData => _dashboardData;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get hasData => _dashboardData != null;
  bool get shouldShowAnimation => !_isConnected || (_isLoading && !hasData);

  /// Initialize connectivity listener
  void _initializeConnectivityListener() {
    _networkService.initialize();
    _connectivitySubscription = _networkService.onConnectivityChanged.listen((
      isConnected,
    ) {
      final wasDisconnected = !_isConnected;
      _isConnected = isConnected;
      notifyListeners();

      // Auto-refresh when connectivity is restored
      if (wasDisconnected && isConnected && _dashboardData != null) {
        refreshDashboard(_dashboardData!.studentId);
      }
    });
  }

  /// Load dashboard data for a student
  Future<void> loadDashboard(String studentId) async {
    if (_isLoading) return;

    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _repository.fetchDashboardData(studentId);

      if (data != null) {
        _dashboardData = data;
        _hasError = false;
      } else {
        // No data from API or cache
        _hasError = true;
        _errorMessage = 'Unable to load dashboard data';
        _dashboardData = null;
      }
    } catch (e) {
      _hasError = true;
      _errorMessage = 'Error loading dashboard: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh dashboard data
  Future<void> refreshDashboard(String studentId) async {
    await loadDashboard(studentId);
  }

  /// Clear cached data
  Future<void> clearCache(String studentId) async {
    await _repository.clearCache(studentId);
    _dashboardData = null;
    notifyListeners();
  }

  /// Check if cache exists
  Future<bool> hasCachedData(String studentId) async {
    return await _repository.hasCachedData(studentId);
  }

  /// Get cache age in hours
  Future<int?> getCacheAge(String studentId) async {
    return await _repository.getCacheAge(studentId);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _networkService.dispose();
    super.dispose();
  }
}
