import 'package:flutter/material.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../widgets/notification_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();

  final List<_FilterTab> _tabs = const [
    _FilterTab(label: 'All'),
    _FilterTab(label: 'Unread', unreadOnly: true),
    _FilterTab(label: 'Messaging', category: NotificationCategory.messaging),
    _FilterTab(label: 'Tests', category: NotificationCategory.tests),
    _FilterTab(label: 'Rewards', category: NotificationCategory.rewards),
    _FilterTab(
      label: 'Announcements',
      category: NotificationCategory.announcements,
    ),
    _FilterTab(label: 'Academic', category: NotificationCategory.academic),
    _FilterTab(label: 'Alerts', category: NotificationCategory.alerts),
  ];

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<int>(
            stream: _notificationService.unreadCountStream(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return const SizedBox.shrink();

              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unreadCount unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_read') {
                _markAllAsRead();
              } else if (value == 'clear_all') {
                _showClearAllDialog();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'mark_all_read',
                child: Text('Mark all as read'),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Text('Clear all notifications'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final item = _tabs[index];
                return ChoiceChip(
                  label: Text(item.label),
                  selected: _selectedIndex == index,
                  onSelected: (_) {
                    setState(() => _selectedIndex = index);
                  },
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: _tabs.length,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<NotificationModel>>(
              stream: _notificationService.notificationsStream(
                category: tab.category,
                unreadOnly: tab.unreadOnly,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final notifications =
                    snapshot.data ?? const <NotificationModel>[];

                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No notifications yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ll see role-based updates for messages, tests, rewards and alerts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return NotificationCard(
                        notification: notification,
                        onTap: () => _handleNotificationTap(notification),
                        onMarkRead: () => _markRead(notification),
                        onDismiss: () =>
                            _deleteNotification(notification.notificationId),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    await _markRead(notification);

    if (!mounted) return;

    if (notification.deepLinkRoute != null &&
        notification.deepLinkRoute!.isNotEmpty) {
      try {
        Navigator.pushNamed(
          context,
          notification.deepLinkRoute!,
          arguments: notification.metadata,
        );
        return;
      } catch (_) {
        // Fall through to category fallback.
      }
    }

    switch (notification.category) {
      case NotificationCategory.messaging:
        Navigator.pushNamed(
          context,
          '/messages',
          arguments: notification.metadata,
        );
        break;
      case NotificationCategory.tests:
      case NotificationCategory.academic:
        Navigator.pushNamed(context, '/student-tests');
        break;
      case NotificationCategory.rewards:
        Navigator.pushNamed(context, '/student-rewards');
        break;
      case NotificationCategory.announcements:
      case NotificationCategory.alerts:
      case NotificationCategory.general:
        // Already on notification center; keep user on this screen.
        break;
    }
  }

  Future<void> _markRead(NotificationModel notification) async {
    if (notification.isRead) return;
    await _notificationService.markAsRead(notification.notificationId);
  }

  Future<void> _markAllAsRead() async {
    try {
      await _notificationService.markAllAsRead();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text(
          'Are you sure you want to delete all notifications? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllNotifications();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllNotifications() async {
    try {
      await _notificationService.clearAllNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Notification deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _FilterTab {
  final String label;
  final NotificationCategory? category;
  final bool unreadOnly;

  const _FilterTab({
    required this.label,
    this.category,
    this.unreadOnly = false,
  });
}
