import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/unread_count_mixins.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/unread_badge_widget.dart';
import '../../models/group_subject.dart';
import '../../services/group_messaging_service.dart';
import '../../services/offline_data_service.dart';
import 'teacher_group_chat_page.dart';
import '../../providers/auth_provider.dart';

class GroupsListPage extends StatefulWidget {
  final String studentId;

  const GroupsListPage({super.key, required this.studentId});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage>
    with
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver,
        UnreadCountMixin<GroupsListPage> {
  final GroupMessagingService _messagingService = GroupMessagingService();
  final OfflineDataService _offlineService = OfflineDataService();
  List<GroupSubject> _subjects = [];
  bool _isLoading = true;
  bool _isLoadingFromCache = false;
  String? _classId;
  bool _hasAttemptedLoad = false;
  final Map<String, int> _lastMessageTs = {}; // chatId -> latest timestamp
  final Map<String, dynamic> _messageListeners =
      {}; // Store listeners for cleanup
  final Map<String, dynamic> _subjectListeners =
      {}; // Track subject doc listeners for lastActivity updates

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay initial load to ensure StudentProvider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadClassSubjects();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel all message listeners
    for (final listener in _messageListeners.values) {
      listener?.cancel?.call();
    }
    _messageListeners.clear();

    // Cancel subject listeners
    for (final listener in _subjectListeners.values) {
      listener?.cancel?.call();
    }
    _subjectListeners.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasAttemptedLoad) {
      // Reload when app comes to foreground
      _loadClassSubjects();
    }
  }

  @override
  void didUpdateWidget(GroupsListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if studentId changes
    if (oldWidget.studentId != widget.studentId) {
      _loadClassSubjects();
    }
  }

  void _listenForMessageUpdates(String classId, GroupSubject subject) {
    final chatId = '$classId|${subject.id}';
    // Listen to all messages, not just the latest one, to ensure we catch every update
    final query = FirebaseFirestore.instance
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subject.id)
        .collection('messages')
        .orderBy('timestamp', descending: true);

    // Store the listener so we can cancel it on dispose
    _messageListeners[chatId] = query.snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty && mounted) {
        final rawTs = snapshot.docs.first.data()['timestamp'];
        final newTs = rawTs is int
            ? rawTs
            : (rawTs is Timestamp ? rawTs.millisecondsSinceEpoch : 0);

        // Update timestamp and resort immediately
        _lastMessageTs[chatId] = newTs;
        _resortGroups();

        // Refresh unread count for this chat
        try {
          final unread = Provider.of<UnreadCountProvider>(
            context,
            listen: false,
          );
          unread.loadUnreadCount(
            chatId: chatId,
            chatType: ChatTypeConfig.groupChat,
          );
        } catch (_) {}
      }
    }, onError: (e) => print('Error listening to messages for $chatId: $e'));
  }

  void _listenForSubjectActivity(String classId, GroupSubject subject) {
    final chatId = '$classId|${subject.id}';
    final docRef = FirebaseFirestore.instance
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subject.id);

    _subjectListeners[chatId] = docRef.snapshots().listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data();
      final activityTs = (data?['lastActivity'] as int?) ?? 0;
      if (activityTs == 0) return;

      final previous = _lastMessageTs[chatId] ?? 0;
      if (activityTs > previous) {
        _lastMessageTs[chatId] = activityTs;
        _resortGroups();
      }
    }, onError: (e) => debugPrint('Error listening to subject $chatId: $e'));
  }

  void _resortGroups() {
    if (mounted) {
      setState(() {
        _subjects.sort((a, b) {
          final at = _lastMessageTs['$_classId|${a.id}'] ?? 0;
          final bt = _lastMessageTs['$_classId|${b.id}'] ?? 0;
          return bt.compareTo(at);
        });
      });
    }
  }

  Future<void> _loadClassSubjects() async {
    if (!mounted) return;

    // If we already have a classId, don't refetch it unnecessarily
    final shouldRefetchClassId = _classId == null;

    // ✅ Load cached classId first if we don't have it
    if (_classId == null) {
      final cachedClassId = _offlineService.getCachedStudentClassId(
        widget.studentId,
      );
      if (cachedClassId != null) {
        _classId = cachedClassId;
      }
    }

    // ✅ Try loading from cache first for instant display
    final cachedSubjects = _offlineService.getCachedGroupSubjects(
      widget.studentId,
    );
    if (cachedSubjects != null && cachedSubjects.isNotEmpty) {
      if (mounted) {
        setState(() {
          _subjects = cachedSubjects;
          _isLoadingFromCache = true;
          _isLoading =
              false; // ✅ Don't show loading spinner if we have cached data
        });

        // Load cached timestamps for sorting
        for (final s in cachedSubjects) {
          if (_classId != null) {
            final chatId = '$_classId|${s.id}';
            final cachedTs = _offlineService.getCachedLastMessageTimestamp(
              chatId,
            );
            if (cachedTs != null) {
              _lastMessageTs[chatId] = cachedTs;
            }
          }
        }

        // Sort by cached timestamps
        _subjects.sort((a, b) {
          if (_classId == null) return 0;
          final at = _lastMessageTs['$_classId|${a.id}'] ?? 0;
          final bt = _lastMessageTs['$_classId|${b.id}'] ?? 0;
          return bt.compareTo(at);
        });
      }
      debugPrint('✅ Loaded ${cachedSubjects.length} groups from cache');
    } else {
      // Only show loading if we don't have cached data
      setState(() => _isLoading = true);
    }

    _hasAttemptedLoad = true;

    try {
      // Ensure unread provider has user (fallback to studentId if Auth not ready)
      try {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final uid = auth.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          unread.initialize(uid);
        } else if (widget.studentId.isNotEmpty) {
          unread.initialize(widget.studentId);
        }
      } catch (_) {}

      // Use studentId directly (already authenticated from AuthProvider)
      final studentUid = widget.studentId;

      if (studentUid.isEmpty) {
        if (!mounted) return;
        setState(() {
          _subjects = cachedSubjects ?? [];
          _isLoading = false;
          _classId = null;
        });
        return;
      }

      // Get student's class ID (use cached value if already loaded)
      String? classId = _classId;

      if (shouldRefetchClassId || classId == null) {
        // Try cached classId first
        classId = _offlineService.getCachedStudentClassId(studentUid);

        // If not in cache, fetch from network
        if (classId == null) {
          classId = await _messagingService.getStudentClassId(studentUid);
          // Cache it for offline use
          if (classId != null) {
            await _offlineService.cacheStudentClassId(
              studentId: studentUid,
              classId: classId,
            );
          }
        }
      }

      if (!mounted) return;

      if (classId == null) {
        setState(() {
          _subjects = cachedSubjects ?? [];
          _isLoading = false;
          // Don't reset _classId to null if we already had one
          // This preserves it across navigation
        });
        return;
      }

      _classId = classId;

      // Fetch subjects from classes/{classId}/subjects collection
      final subjects = await _messagingService.getClassSubjects(classId);

      if (!mounted) return;

      // ✅ Only cache if we actually got subjects from the network
      // Don't overwrite good cached data with empty results
      if (subjects.isNotEmpty) {
        await _offlineService.cacheGroupSubjects(
          studentId: widget.studentId,
          subjects: subjects,
        );

        // Only update UI if we got valid data from network
        setState(() {
          _subjects = subjects;
          _isLoading = false;
          _isLoadingFromCache = false;
        });
      } else if (_subjects.isEmpty) {
        // No network data AND no cached data - show empty state
        setState(() {
          _subjects = [];
          _isLoading = false;
          _isLoadingFromCache = false;
        });
      } else {
        // Network returned empty but we have cached data - keep showing it
        setState(() {
          _isLoading = false;
          _isLoadingFromCache = false;
        });
      }

      // Load unread counts for these subjects
      final chatIds = subjects.map((s) => '$_classId|${s.id}').toList();
      final chatTypes = {
        for (final s in subjects) '$_classId|${s.id}': ChatTypeConfig.groupChat,
      };
      await loadUnreadCountsForChats(chatIds: chatIds, chatTypes: chatTypes);

      // Fetch latest message timestamp for sorting like WhatsApp
      for (final s in subjects) {
        final chatId = '$_classId|${s.id}';
        try {
          final snap = await FirebaseFirestore.instance
              .collection('classes')
              .doc(_classId!)
              .collection('subjects')
              .doc(s.id)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final ts = (snap.docs.first.data()['timestamp'] as int?) ?? 0;
            _lastMessageTs[chatId] = ts;
            // ✅ Cache timestamp for offline sorting
            await _offlineService.cacheLastMessageTimestamp(
              chatId: chatId,
              timestamp: ts,
            );
          } else {
            _lastMessageTs[chatId] = 0;
          }
        } catch (_) {
          _lastMessageTs[chatId] = 0;
        }
      }
      if (mounted) {
        setState(() {
          _subjects.sort((a, b) {
            final at = _lastMessageTs['$_classId|${a.id}'] ?? 0;
            final bt = _lastMessageTs['$_classId|${b.id}'] ?? 0;
            return bt.compareTo(at);
          });
        });
      }

      // Cancel old listeners before setting up new ones
      for (final listener in _messageListeners.values) {
        listener?.cancel?.call();
      }
      _messageListeners.clear();

      for (final listener in _subjectListeners.values) {
        listener?.cancel?.call();
      }
      _subjectListeners.clear();

      // Set up real-time listeners for all subjects to resort on new messages
      for (final s in subjects) {
        _listenForMessageUpdates(_classId!, s);
        _listenForSubjectActivity(_classId!, s);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error loading groups from network: $e');

      // ✅ If network fails but we have cached data, keep showing it
      // If _subjects is already populated from cache, keep it as is
      // Otherwise, try to load from cache now
      setState(() {
        if (_subjects.isEmpty) {
          final cachedData = _offlineService.getCachedGroupSubjects(
            widget.studentId,
          );
          if (cachedData != null && cachedData.isNotEmpty) {
            _subjects = cachedData;

            // Load cached timestamps
            if (_classId != null) {
              for (final s in cachedData) {
                final chatId = '$_classId|${s.id}';
                final cachedTs = _offlineService.getCachedLastMessageTimestamp(
                  chatId,
                );
                if (cachedTs != null) {
                  _lastMessageTs[chatId] = cachedTs;
                }
              }
            }
          }
        }
        _isLoading = false;
        _isLoadingFromCache = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    const orange = Color(0xFFF97316);

    // ✅ Don't show loading if we have cached data
    if (_isLoading && !_isLoadingFromCache) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: orange),
            const SizedBox(height: 16),
            Text(
              'Loading your groups...',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_classId == null && _subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to determine your class.\nPlease contact your administrator.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadClassSubjects,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No subject groups available yet.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadClassSubjects,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _subjects.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final subject = _subjects[index];
              final chatId = '$_classId|${subject.id}';

              return _SubjectGroupCard(
                subject: subject,
                chatId: chatId,
                onTap: () async {
                  // Capture context before any async operations
                  final navContext = context;

                  // Navigate and wait for return
                  await Navigator.push(
                    navContext,
                    MaterialPageRoute(
                      builder: (context) => TeacherGroupChatPage(
                        classId: _classId!,
                        subjectId: subject.id,
                        subjectName: subject.name,
                        teacherName: subject.teacherName,
                        icon: subject.icon,
                      ),
                    ),
                  );

                  // Refresh unread count after returning - only if widget still mounted
                  if (mounted) {
                    try {
                      final unreadProvider = Provider.of<UnreadCountProvider>(
                        navContext,
                        listen: false,
                      );
                      unreadProvider.refreshChat(chatId);
                      unreadProvider.loadUnreadCount(
                        chatId: chatId,
                        chatType: ChatTypeConfig.groupChat,
                      );
                    } catch (e) {}
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubjectGroupCard extends StatelessWidget {
  final GroupSubject subject;
  final String chatId;
  final VoidCallback onTap;

  const _SubjectGroupCard({
    required this.subject,
    required this.chatId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const orange = Color(0xFFF97316);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Accent strip
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: orange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // Subject Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                  0.6,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(subject.icon, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),

            // Subject Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    subject.name,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Class Group',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.7,
                      ),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Teacher: ${subject.teacherName}',
                    style: TextStyle(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Fixed width container for badge to prevent layout shift
            SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Consumer<UnreadCountProvider>(
                  builder: (_, provider, _) {
                    final count = provider.getUnreadCount(chatId);
                    return UnreadBadge(count: count);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
