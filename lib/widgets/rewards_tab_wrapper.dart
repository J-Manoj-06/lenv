import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/rewards/rewards_module.dart';

/// Wraps the Rewards catalog with local Riverpod + GoRouter support
/// This allows the rewards feature to use its own routing independently
/// from the main app router without conflicts
class RewardsTabWrapper extends StatefulWidget {
  const RewardsTabWrapper({super.key});

  @override
  State<RewardsTabWrapper> createState() => _RewardsTabWrapperState();
}

class _RewardsTabWrapperState extends State<RewardsTabWrapper> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
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
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: _router,
        theme: Theme.of(context),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
