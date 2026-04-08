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
  final Set<String> _expandedGroupKeys = <String>{};

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

  List<_NotificationGroup> _groupNotifications(
    List<NotificationModel> notifications,
  ) {
    final grouped = <String, List<NotificationModel>>{};
    for (final n in notifications) {
      final key = _groupKeyFor(n);
      grouped.putIfAbsent(key, () => <NotificationModel>[]).add(n);
    }

    final result =
        grouped.entries.map((entry) {
            final items = [...entry.value]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return _NotificationGroup(key: entry.key, items: items);
          }).toList()
          ..sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));

    return result;
  }

  String _groupKeyFor(NotificationModel notification) {
    final metadata = notification.metadata ?? const <String, dynamic>{};

    String? metaValue(List<String> keys) {
      for (final key in keys) {
        final value = metadata[key]?.toString();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    if (notification.category == NotificationCategory.messaging) {
      final communityId = metaValue(['communityId']);
      if (communityId != null) return 'msg:community:$communityId';

      final sectionGroup = metaValue(['groupId', 'sectionGroupId']);
      if (sectionGroup != null) return 'msg:section:$sectionGroup';

      final classId = metaValue(['classId']);
      final subjectId = metaValue(['subjectId']);
      if (classId != null && subjectId != null) {
        return 'msg:class:$classId:subject:$subjectId';
      }

      final target = notification.targetId;
      if (target != null && target.isNotEmpty) return 'msg:target:$target';

      return 'msg:title:${notification.title.trim().toLowerCase()}';
    }

    if (notification.category == NotificationCategory.tests ||
        notification.category == NotificationCategory.academic) {
      final testId = metaValue([
        'testId',
        'scheduledTestId',
        'assignmentId',
        'resultId',
      ]);
      if (testId != null) return 'test:$testId';

      final target = notification.targetId;
      if (target != null && target.isNotEmpty) return 'test:target:$target';

      final dedupe = notification.dedupeKey;
      if (dedupe != null && dedupe.isNotEmpty) return 'test:dedupe:$dedupe';

      return 'test:title:${notification.title.trim().toLowerCase()}';
    }

    return 'single:${notification.notificationId}';
  }

  bool _isGroupable(NotificationModel notification) {
    return notification.category == NotificationCategory.messaging ||
        notification.category == NotificationCategory.tests ||
        notification.category == NotificationCategory.academic;
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
                final groups = _groupNotifications(notifications);

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
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final latest = group.latest;
                      final canGroup =
                          group.items.length > 1 && _isGroupable(latest);
                      final roleAccent = _roleAccent(
                        latest.role.isNotEmpty ? latest.role : currentRole,
                      );

                      if (!canGroup) {
                        return NotificationCard(
                          notification: latest,
                          roleAccent: roleAccent,
                          animationDelayMs: index * 30,
                          onTap: () => _handleNotificationTap(latest),
                          onMarkRead: () => _markRead(latest),
                          onDismiss: () =>
                              _deleteNotification(latest.notificationId),
                        );
                      }

                      final expanded = _expandedGroupKeys.contains(group.key);

                      return _GroupedNotificationCard(
                        key: ValueKey(group.key),
                        group: group,
                        roleAccent: roleAccent,
                        expanded: expanded,
                        animationDelayMs: index * 30,
                        onToggleExpand: () {
                          setState(() {
                            if (expanded) {
                              _expandedGroupKeys.remove(group.key);
                            } else {
                              _expandedGroupKeys.add(group.key);
                            }
                          });
                        },
                        onTapLatest: () => _handleNotificationTap(latest),
                        onTapChild: _handleNotificationTap,
                        onMarkReadLatest: () => _markRead(latest),
                        onMarkReadChild: _markRead,
                        onDeleteChild: (n) =>
                            _deleteNotification(n.notificationId),
                        onMarkAllRead: () => _markGroupAsRead(group.items),
                        onDeleteGroup: () => _deleteGroup(group.items),
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

  Future<void> _markReadSilent(NotificationModel notification) async {
    if (notification.isRead) return;
    try {
      await _notificationService.markAsRead(notification.notificationId);
    } catch (_) {}
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

  Future<void> _deleteNotificationSilent(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
    } catch (_) {}
  }

  Future<void> _markGroupAsRead(List<NotificationModel> items) async {
    for (final n in items.where((n) => !n.isRead)) {
      await _markReadSilent(n);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${items.length} notifications marked as read')),
    );
  }

  Future<void> _deleteGroup(List<NotificationModel> items) async {
    for (final n in items) {
      await _deleteNotificationSilent(n.notificationId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${items.length} notifications deleted')),
    );
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

class _NotificationGroup {
  final String key;
  final List<NotificationModel> items;

  const _NotificationGroup({required this.key, required this.items});

  NotificationModel get latest => items.first;
}

class _GroupedNotificationCard extends StatelessWidget {
  final _NotificationGroup group;
  final Color roleAccent;
  final bool expanded;
  final int animationDelayMs;
  final VoidCallback onToggleExpand;
  final VoidCallback onTapLatest;
  final ValueChanged<NotificationModel> onTapChild;
  final VoidCallback onMarkReadLatest;
  final ValueChanged<NotificationModel> onMarkReadChild;
  final ValueChanged<NotificationModel> onDeleteChild;
  final VoidCallback onMarkAllRead;
  final VoidCallback onDeleteGroup;

  const _GroupedNotificationCard({
    super.key,
    required this.group,
    required this.roleAccent,
    required this.expanded,
    this.animationDelayMs = 0,
    required this.onToggleExpand,
    required this.onTapLatest,
    required this.onTapChild,
    required this.onMarkReadLatest,
    required this.onMarkReadChild,
    required this.onDeleteChild,
    required this.onMarkAllRead,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final latest = group.latest;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 220 + animationDelayMs),
      tween: Tween<double>(begin: 0.94, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Opacity(
          opacity: scale,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: roleAccent.withOpacity(0.45), width: 1),
        ),
        color: isDark ? Colors.grey[850] : Colors.white,
        child: Column(
          children: [
            InkWell(
              onTap: onToggleExpand,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: roleAccent.withOpacity(0.2),
                      child: Icon(
                        _iconFor(latest.category),
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
                            latest.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            latest.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.collections_bookmark_outlined,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${group.items.length} updates',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
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
                                  _typeLabel(latest.category),
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
                            if (value == 'read_all') {
                              onMarkAllRead();
                            } else if (value == 'delete_all') {
                              onDeleteGroup();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'read_all',
                              child: Text('Mark all in group as read'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete_all',
                              child: Text('Delete all in group'),
                            ),
                          ],
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey[500],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    for (final n in group.items) _buildChildRow(context, n),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildRow(BuildContext context, NotificationModel n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      onTap: () => onTapChild(n),
      title: Text(
        n.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: isDark ? Colors.grey[300] : Colors.grey[800],
        ),
      ),
      subtitle: Text(
        _relativeTime(n.createdAt),
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      leading: Icon(Icons.subdirectory_arrow_right_rounded, color: roleAccent),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, color: Colors.grey[500], size: 18),
        onSelected: (value) {
          if (value == 'read') {
            onMarkReadChild(n);
          } else if (value == 'delete') {
            onDeleteChild(n);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem<String>(value: 'read', child: Text('Mark as read')),
          PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  IconData _iconFor(NotificationCategory type) {
    switch (type) {
      case NotificationCategory.messaging:
        return Icons.chat_bubble_outline_rounded;
      case NotificationCategory.tests:
      case NotificationCategory.academic:
        return Icons.description_outlined;
      case NotificationCategory.rewards:
        return Icons.card_giftcard_rounded;
      case NotificationCategory.announcements:
        return Icons.campaign_outlined;
      case NotificationCategory.alerts:
        return Icons.warning_amber_rounded;
      case NotificationCategory.general:
        return Icons.notifications;
    }
  }

  String _typeLabel(NotificationCategory type) {
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

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}
