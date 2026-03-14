import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';

class NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onMarkRead;

  const NotificationCard({
    super.key,
    required this.notification,
    required this.onTap,
    this.onDismiss,
    this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(notification.notificationId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: notification.isRead ? 0.5 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: notification.isRead
              ? BorderSide.none
              : BorderSide(
                  color: theme.primaryColor.withOpacity(0.3),
                  width: 1,
                ),
        ),
        color: notification.isRead
            ? (isDark ? Colors.grey[900] : Colors.grey[50])
            : (isDark ? Colors.grey[850] : Colors.white),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Icon Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _getColorForType(notification.category),
                  child: Icon(
                    _getIconForType(notification.category),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Center: Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
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

                      // Body
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

                      // Timestamp
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
                          // Type badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getColorForType(
                                notification.category,
                              ).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getTypeLabel(notification.category),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _getColorForType(notification.category),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right: Unread indicator
                Column(
                  children: [
                    if (!notification.isRead)
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(left: 8, top: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
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
    );
  }

  Color _getColorForType(NotificationCategory type) {
    switch (type) {
      case NotificationCategory.messaging:
        return Colors.blue;
      case NotificationCategory.tests:
        return Colors.orange;
      case NotificationCategory.rewards:
        return Colors.green;
      case NotificationCategory.announcements:
        return Colors.indigo;
      case NotificationCategory.academic:
        return Colors.teal;
      case NotificationCategory.alerts:
        return Colors.red;
      case NotificationCategory.general:
        return Colors.grey;
    }
  }

  IconData _getIconForType(NotificationCategory type) {
    switch (type) {
      case NotificationCategory.messaging:
        return Icons.chat_bubble;
      case NotificationCategory.tests:
        return Icons.quiz;
      case NotificationCategory.rewards:
        return Icons.workspace_premium;
      case NotificationCategory.announcements:
        return Icons.campaign;
      case NotificationCategory.academic:
        return Icons.school;
      case NotificationCategory.alerts:
        return Icons.warning_amber;
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
