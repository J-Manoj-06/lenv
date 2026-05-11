import 'package:flutter/material.dart';

enum MainNavSwipeDirection { left, right }

class MainNavSwipeNotification extends Notification {
  final MainNavSwipeDirection direction;

  MainNavSwipeNotification(this.direction);
}
