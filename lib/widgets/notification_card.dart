import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';

class NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onMarkRead;
  final Color roleAccent;
  final int animationDelayMs;

  const NotificationCard({
    super.key,
    required this.notification,
    required this.onTap,
    this.onDismiss,
    this.onMarkRead,
    required this.roleAccent,
    this.animationDelayMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 220 + animationDelayMs),
      tween: Tween<double>(begin: 0.92, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Opacity(
          opacity: scale,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Dismissible(
        key: Key(notification.notificationId),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onMarkRead?.call();
            return true;
          }
          onDismiss?.call();
          return true;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          color: roleAccent.withOpacity(0.85),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done_all_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Mark Read',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dismiss',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.delete_outline, color: Colors.white),
            ],
          ),
        ),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: notification.isRead ? 0.5 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: notification.isRead
                ? BorderSide.none
                : BorderSide(color: roleAccent.withOpacity(0.45), width: 1),
          ),
          color: notification.isRead
              ? (isDark ? Colors.grey[900] : Colors.grey[50])
              : (isDark ? Colors.grey[850] : Colors.white),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: roleAccent.withOpacity(0.2),
                    child: Icon(
                      _getIconForType(
                        notification.category,
                        notification.iconType,
                      ),
                      color: roleAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.body,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[700],
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimestamp(notification.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: roleAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getTypeLabel(notification.category),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: roleAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Column(
                    children: [
                      if (!notification.isRead)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(left: 8, top: 4),
                          decoration: BoxDecoration(
                            color: roleAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey[500],
                          size: 18,
                        ),
                        onSelected: (value) {
                          if (value == 'read') {
                            onMarkRead?.call();
                          } else if (value == 'delete') {
                            onDismiss?.call();
                          }
                        },
                        itemBuilder: (context) => [
                          if (!notification.isRead)
                            const PopupMenuItem<String>(
                              value: 'read',
                              child: Text('Mark as read'),
                            ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(NotificationCategory type, String iconType) {
    final iconLabel = iconType.toLowerCase();
    if (iconLabel.contains('principal') || iconLabel.contains('shield')) {
      return Icons.shield_outlined;
    }
    switch (type) {
      case NotificationCategory.messaging:
        return Icons.chat_bubble_outline_rounded;
      case NotificationCategory.tests:
        return Icons.description_outlined;
      case NotificationCategory.rewards:
        return Icons.card_giftcard_rounded;
      case NotificationCategory.announcements:
        return Icons.campaign_outlined;
      case NotificationCategory.academic:
        return Icons.auto_graph_outlined;
      case NotificationCategory.alerts:
        return iconLabel.contains('principal')
            ? Icons.shield_outlined
            : Icons.warning_amber_rounded;
      case NotificationCategory.general:
        return Icons.notifications;
    }
  }

  String _getTypeLabel(NotificationCategory type) {
    switch (type) {
      case NotificationCategory.messaging:
        return 'MESSAGING';
      case NotificationCategory.tests:
        return 'TESTS';
      case NotificationCategory.rewards:
        return 'REWARDS';
      case NotificationCategory.announcements:
        return 'ANNOUNCEMENT';
      case NotificationCategory.academic:
        return 'ACADEMIC';
      case NotificationCategory.alerts:
        return 'ALERT';
      case NotificationCategory.general:
        return 'GENERAL';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(timestamp);
    }
  }
}
