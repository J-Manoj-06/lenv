import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../screens/notifications/notifications_screen.dart';

class NotificationBellButton extends StatelessWidget {
  final Color? iconColor;
  final Color? badgeColor;
  final double iconSize;

  const NotificationBellButton({
    super.key,
    this.iconColor,
    this.badgeColor,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();

    return StreamBuilder<int>(
      stream: service.unreadCountStream(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_none_rounded,
                color: iconColor,
                size: iconSize,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor ?? const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
