import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/rewards/rewards_module.dart';

/// Wraps the Rewards catalog with local Riverpod + GoRouter support
/// This allows the rewards feature to use its own routing independently
/// from the main app router without conflicts
class RewardsTabWrapper extends StatelessWidget {
  const RewardsTabWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Create a local GoRouter for rewards feature routes
    final router = GoRouter(
      // Ensure we land on the catalog instead of '/'
      initialLocation: RewardsModule.catalogRoute,
      routes: RewardsModule.getRoutes(),
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Page not found'),
              const SizedBox(height: 16),
              Text(state.error.toString()),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go(RewardsModule.catalogRoute),
                child: const Text('Go to Rewards'),
              ),
            ],
          ),
        ),
      ),
    );

    // Wrap with ProviderScope for Riverpod + local GoRouter
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: Theme.of(context),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
