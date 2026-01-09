import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'models/product_model.dart';
import 'models/reward_request_model.dart';
import 'ui/screens/rewards_catalog_screen.dart';
import 'ui/screens/product_detail_screen.dart';
import 'ui/screens/student_requests_screen.dart';
import 'ui/screens/parent_request_approval_screen.dart';
import 'ui/screens/request_detail_screen.dart';

/// Wrapper that provides local ProviderScope + GoRouter for Rewards feature
/// This allows the Rewards catalog and detail screens to work independently
/// without conflicting with the app's main Provider/routing setup
class RewardsScreenWrapper extends StatelessWidget {
  final String? userId;

  const RewardsScreenWrapper({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    // Create a local GoRouter for rewards navigation
    // Routes must match what RewardsCatalogScreen.onTap calls (e.g., /rewards/product/:productId)
    final rewardsRouter = GoRouter(
      initialLocation: '/rewards/catalog',
      routes: [
        GoRoute(
          path: '/rewards/catalog',
          name: 'rewards-catalog',
          builder: (context, state) => RewardsCatalogScreen(studentId: userId),
        ),
        GoRoute(
          path: '/rewards/product/:productId',
          name: 'product-detail',
          builder: (context, state) {
            final productId = state.pathParameters['productId']!;
            final product = state.extra as ProductModel?;
            return ProductDetailScreen(
              productId: productId,
              initialProduct: product,
              studentId: userId,
            );
          },
        ),
        GoRoute(
          path: '/rewards/requests/student/:studentId',
          name: 'student-requests',
          builder: (context, state) {
            final studentId = state.pathParameters['studentId']!;
            return StudentRequestsScreen(studentId: studentId);
          },
        ),
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
        GoRoute(
          path: '/rewards/parent-approvals/:parentId',
          name: 'parent-approvals',
          builder: (context, state) {
            final parentId = state.pathParameters['parentId']!;
            return ParentRequestApprovalScreen(parentId: parentId);
          },
        ),
      ],
    );

    // Wrap with ProviderScope so Riverpod providers work
    // Wrap with MaterialApp so GoRouter can provide navigation context
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: rewardsRouter,
        theme: Theme.of(context),
        darkTheme: Theme.of(context),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
