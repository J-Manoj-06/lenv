import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../widgets/notification_card.dart';
import '../../providers/auth_provider.dart' as auth;

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

  int _selectedIndex = 1; // Unread default

  List<NotificationModel> _applyLocalFilter(
    List<NotificationModel> unreadNotifications,
    _FilterTab tab,
  ) {
    if (tab.category != null) {
      return unreadNotifications
          .where((n) => n.category == tab.category)
          .toList();
    }
    return unreadNotifications;
  }

  Color _roleAccent(String role) {
    final r = role.toLowerCase();
    if (r.contains('teacher')) return const Color(0xFF5B4BDB); // Indigo
    if (r.contains('parent')) return const Color(0xFF2EAD62); // Green
    if (r.contains('principal') || r.contains('institute')) {
      return const Color(0xFFE59D2F); // Gold
    }
    return const Color(0xFF1E9BFF); // Student blue/cyan
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_selectedIndex];
    final authProvider = Provider.of<auth.AuthProvider>(context);
    final currentRole = authProvider.currentUser?.role.name ?? 'student';
    final accent = _roleAccent(currentRole);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldBg = isDark
        ? const Color(0xFF121316)
        : const Color(0xFFF5F7FB);
    final appBarBg = isDark
        ? Color.lerp(const Color(0xFF1B1D22), accent, 0.18)!
        : Color.lerp(Colors.white, accent, 0.14)!;
    final appBarFg = isDark ? Colors.white : const Color(0xFF101418);
    final chipBg = isDark ? const Color(0xFF151821) : Colors.white;
    final chipBorder = isDark
        ? Colors.white.withOpacity(0.18)
        : const Color(0xFFD7DCE7);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
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
                  label: Text(
                    item.label,
                    style: TextStyle(
                      color: _selectedIndex == index
                          ? (isDark ? Colors.white : accent)
                          : (isDark
                                ? Colors.white.withOpacity(0.85)
                                : const Color(0xFF2B3140)),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: chipBg,
                  selected: _selectedIndex == index,
                  selectedColor: accent.withOpacity(isDark ? 0.22 : 0.14),
                  side: BorderSide(
                    color: _selectedIndex == index ? accent : chipBorder,
                    width: _selectedIndex == index ? 1.4 : 1,
                  ),
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
              stream: _notificationService.unreadNotificationsStream(limit: 50),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildSkeletonList();
                }

                final unreadNotifications =
                    snapshot.data ?? const <NotificationModel>[];
                final notifications = _applyLocalFilter(
                  unreadNotifications,
                  tab,
                );

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
                    await Future.delayed(const Duration(milliseconds: 350));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return NotificationCard(
                        notification: notification,
                        roleAccent: _roleAccent(
                          notification.role.isNotEmpty
                              ? notification.role
                              : currentRole,
                        ),
                        animationDelayMs: index * 30,
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

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      itemBuilder: (_, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.22),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.withOpacity(0.2),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 180,
                      color: Colors.grey.withOpacity(0.18),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 120,
                      color: Colors.grey.withOpacity(0.16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    await _markRead(notification);

    if (!mounted) return;

    final navArgs = {
      ...(notification.metadata ?? <String, dynamic>{}),
      'targetId': notification.targetId,
      'notificationId': notification.notificationId,
    };

    if (notification.deepLinkRoute != null &&
        notification.deepLinkRoute!.isNotEmpty) {
      try {
        Navigator.pushNamed(
          context,
          notification.deepLinkRoute!,
          arguments: navArgs,
        );
        return;
      } catch (_) {}
    }

    try {
      switch (notification.category) {
        case NotificationCategory.messaging:
          if ((notification.metadata ?? const {})['communityId'] != null) {
            Navigator.pushNamed(
              context,
              '/community-group-chat',
              arguments: navArgs,
            );
            return;
          }
          if ((notification.metadata ?? const {})['classId'] != null &&
              (notification.metadata ?? const {})['subjectId'] != null) {
            Navigator.pushNamed(
              context,
              '/teacher/student-group-chat',
              arguments: navArgs,
            );
            return;
          }
          if ((notification.deepLinkRoute ?? '').contains('section-group') ||
              (notification.metadata ?? const {})['groupId'] != null) {
            Navigator.pushNamed(
              context,
              '/parent/section-group-chat',
              arguments: navArgs,
            );
            return;
          }
          Navigator.pushNamed(context, '/messages', arguments: navArgs);
          return;
        case NotificationCategory.tests:
        case NotificationCategory.academic:
          Navigator.pushNamed(context, '/student-tests', arguments: navArgs);
          return;
        case NotificationCategory.rewards:
          Navigator.pushNamed(context, '/student-rewards', arguments: navArgs);
          return;
        case NotificationCategory.announcements:
        case NotificationCategory.alerts:
        case NotificationCategory.general:
          Navigator.pushNamed(context, '/notifications');
          return;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Target unavailable. Opening notifications.'),
        ),
      );
      Navigator.pushNamed(context, '/notifications');
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
