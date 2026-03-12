import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../models/student_dashboard_data.dart';
import '../services/api_service.dart';
import '../services/network_service.dart';
import '../repositories/dashboard_repository.dart';
import '../providers/dashboard_provider.dart';

/// Initialize all services and dependencies for the network-aware dashboard
class DashboardSetup {
  static Future<void> initialize() async {
    // Initialize Hive for offline storage
    await _initializeHive();
  }

  /// Initialize Hive and register adapters
  static Future<void> _initializeHive() async {
    await Hive.initFlutter();

    // Register Hive Type Adapters
    // Note: After creating the models, run: flutter pub run build_runner build
    // This will generate the .g.dart files with adapters

    // Register adapters only if not already registered
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(StudentDashboardDataAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MessageItemAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(AssignmentItemAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(AnnouncementItemAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(AttendanceSummaryAdapter());
    }

  }

  /// Create provider instances with proper dependency injection
  static List<ChangeNotifierProvider> getProviders() {
    // Create service instances
    final apiService = ApiService();
    final networkService = NetworkService();
    final repository = DashboardRepository(
      apiService: apiService,
      networkService: networkService,
    );

    return [
      ChangeNotifierProvider<DashboardProvider>(
        create: (_) => DashboardProvider(
          repository: repository,
          networkService: networkService,
        ),
      ),
    ];
  }

  /// Widget wrapper to provide all necessary dependencies
  static Widget wrapWithProviders({required Widget child}) {
    // Create service instances
    final apiService = ApiService();
    final networkService = NetworkService();
    final repository = DashboardRepository(
      apiService: apiService,
      networkService: networkService,
    );

    return ChangeNotifierProvider<DashboardProvider>(
      create: (_) => DashboardProvider(
        repository: repository,
        networkService: networkService,
      ),
      child: child,
    );
  }
}
