import 'package:flutter/material.dart';

import '../../widgets/page_swipe_back_wrapper.dart';

class MessagesSwipeToPopWrapper extends StatelessWidget {
  final Widget child;

  const MessagesSwipeToPopWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PageSwipeBackWrapper(child: child);
  }
}
