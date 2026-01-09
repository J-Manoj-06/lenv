import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'models/product_model.dart';
import 'models/reward_request_model.dart';
import 'ui/screens/rewards_catalog_screen.dart';
import 'ui/screens/product_detail_screen.dart';
import 'ui/screens/student_requests_screen.dart';
import 'ui/screens/parent_dashboard_screen.dart';
import 'ui/screens/request_detail_screen.dart';

/// RewardsModule provides routing configuration for the rewards feature
class RewardsModule {
  static const String catalogRoute = '/rewards/catalog';
  static const String productDetailRoute = '/rewards/product/:productId';
  static const String studentRequestsRoute =
      '/rewards/requests/student/:studentId';
  static const String parentDashboardRoute =
      '/rewards/requests/parent/:parentId';
  static const String requestDetailRoute = '/rewards/request/:requestId';

  /// Feature flag for enabling/disabling rewards feature
  static bool isEnabled = true;

  /// Get all routes for rewards feature
  static List<RouteBase> getRoutes() {
    if (!isEnabled) return [];

    return [
      // Root redirect so any accidental '/' goes to catalog
      GoRoute(path: '/', redirect: (context, state) => catalogRoute),
      // Rewards Catalog Screen
      GoRoute(
        path: '/rewards/catalog',
        name: 'rewards-catalog',
        builder: (context, state) => const RewardsCatalogScreen(),
      ),
      // Product Detail Screen
      GoRoute(
        path: '/rewards/product/:productId',
        name: 'product-detail',
        builder: (context, state) {
          final productId = state.pathParameters['productId']!;
          final product = state.extra as ProductModel?;
          return ProductDetailScreen(
            productId: productId,
            initialProduct: product,
          );
        },
      ),
      // Student Requests Screen
      GoRoute(
        path: '/rewards/requests/student/:studentId',
        name: 'student-requests',
        builder: (context, state) {
          final studentId = state.pathParameters['studentId']!;
          return StudentRequestsScreen(studentId: studentId);
        },
      ),
      // Parent Dashboard Screen
      GoRoute(
        path: '/rewards/requests/parent/:parentId',
        name: 'parent-dashboard',
        builder: (context, state) {
          final parentId = state.pathParameters['parentId']!;
          return ParentDashboardScreen(parentId: parentId);
        },
      ),
      // Request Detail Screen
      GoRoute(
        path: '/rewards/request/:requestId',
        name: 'request-detail',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;
          final request = state.extra as RewardRequestModel?;
          return RequestDetailScreen(
            requestId: requestId,
            initialRequest: request,
          );
        },
      ),
    ];
  }

  /// Navigate to rewards catalog
  static void navigateToCatalog(BuildContext context) {
    context.go(catalogRoute);
  }

  /// Navigate to product detail
  static void navigateToProduct(
    BuildContext context, {
    required String productId,
    ProductModel? product,
  }) {
    context.go(
      productDetailRoute.replaceAll(':productId', productId),
      extra: product,
    );
  }

  /// Navigate to student requests
  static void navigateToStudentRequests(
    BuildContext context, {
    required String studentId,
  }) {
    context.go(studentRequestsRoute.replaceAll(':studentId', studentId));
  }

  /// Navigate to parent dashboard
  static void navigateToParentDashboard(
    BuildContext context, {
    required String parentId,
  }) {
    context.go(parentDashboardRoute.replaceAll(':parentId', parentId));
  }

  /// Navigate to request detail
  static void navigateToRequestDetail(
    BuildContext context, {
    required String requestId,
    RewardRequestModel? request,
  }) {
    context.push(
      requestDetailRoute.replaceAll(':requestId', requestId),
      extra: request,
    );
  }

  /// Initialize the rewards module (if needed for any setup)
  static Future<void> initialize() async {
    // TODO: Add any initialization logic
    // - Check if feature flag is enabled
    // - Pre-load dummy data if offline
    // - Initialize Firestore listeners
  }
}
