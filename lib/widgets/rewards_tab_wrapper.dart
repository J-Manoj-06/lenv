import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/rewards/rewards_module.dart';
import '../features/rewards/ui/screens/rewards_catalog_screen.dart';

/// Wraps the Rewards catalog with local Riverpod + GoRouter support
/// This allows the rewards feature to use its own routing independently
/// from the main app router without conflicts
class RewardsTabWrapper extends StatelessWidget {
  const RewardsTabWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Create a local GoRouter for rewards feature routes
    final router = GoRouter(
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
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
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
