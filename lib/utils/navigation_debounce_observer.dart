import 'package:flutter/material.dart';

/// Global navigator observer that prevents rapid double-pushes of the same route.
/// When the same named route is pushed twice within [debounceDuration], the
/// second push is immediately popped so users don't get duplicate pages.
class NavigationDebounceObserver extends NavigatorObserver {
  NavigationDebounceObserver({
    this.debounceDuration = const Duration(milliseconds: 700),
  });

  final Duration debounceDuration;
  Route<dynamic>? _lastPushed;
  DateTime? _lastPushAt;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    final routeName = route.settings.name;
    final lastName = _lastPushed?.settings.name;
    final now = DateTime.now();

    final sameNamedRoute =
        routeName != null && lastName != null && routeName == lastName;
    final sameTypeRoute =
        routeName == null &&
        lastName == null &&
        _lastPushed != null &&
        route.runtimeType == _lastPushed!.runtimeType;

    final isDuplicate =
        (sameNamedRoute || sameTypeRoute) &&
        _lastPushAt != null &&
        now.difference(_lastPushAt!) < debounceDuration;

    if (isDuplicate) {
      // Drop the duplicate by popping it as soon as it's pushed
      Future.microtask(() {
        if (navigator?.canPop() ?? false) {
          navigator?.pop();
        }
      });
      return;
    }

    _lastPushed = route;
    _lastPushAt = now;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // Reset last pushed to previous route so future duplicate checks stay sane
    _lastPushed = previousRoute;
    _lastPushAt = DateTime.now();
  }
}
