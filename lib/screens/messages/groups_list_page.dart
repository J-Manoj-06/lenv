import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
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
  final Map<String, int> _lastMessageTs =
      {}; // chatId -> last message timestamp
  final Map<String, dynamic> _messageListeners =
      {}; // Store listeners for cleanup
  final Set<String> _messageErrorLogged = <String>{};
  final Set<String> _openingChats = <String>{};

  String _chatIdForSubject(String subjectId) {
    return '$_classId|$subjectId';
  }

  int _toMillis(dynamic ts) {
    if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    if (ts is num) return ts.toInt();
    return 0;
  }

  int _compareSubjectsByRecent(GroupSubject a, GroupSubject b) {
    final at = _lastMessageTs[_chatIdForSubject(a.id)] ?? 0;
    final bt = _lastMessageTs[_chatIdForSubject(b.id)] ?? 0;
    final recentCmp = bt.compareTo(at);
    if (recentCmp != 0) return recentCmp;

    final nameCmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCmp != 0) return nameCmp;

    return a.id.compareTo(b.id);
  }

  void _sortSubjectsByRecent() {
    _subjects.sort(_compareSubjectsByRecent);
  }

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
    // Listen to message updates for sorting by newest message and unread badge refreshes.
    final query = FirebaseFirestore.instance
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subject.id)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1);

    // Store the listener so we can cancel it on dispose
    _messageListeners[chatId] = query.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        try {
          // Update message timestamp for sorting
          if (snapshot.docs.isNotEmpty) {
            final lastMsg = snapshot.docs.first.data();
            final msgTs = _toMillis(lastMsg['timestamp']);
            if (msgTs > 0) {
              final previousTs = _lastMessageTs[chatId] ?? 0;
              if (msgTs != previousTs) {
                _lastMessageTs[chatId] = msgTs;
                _resortGroups();
              }
            }
          }
          final unread = Provider.of<UnreadCountProvider>(
            context,
            listen: false,
          );
          unread.loadUnreadCount(
            chatId: chatId,
            chatType: ChatTypeConfig.groupChat,
          );
        } catch (_) {}
      },
      onError: (e) {
        final msg = e.toString().toLowerCase();
        final isSignedOut = fb_auth.FirebaseAuth.instance.currentUser == null;
        if (msg.contains('permission-denied') ||
            msg.contains('permission denied') ||
            msg.contains('insufficient permissions')) {
          if (!isSignedOut && _messageErrorLogged.add(chatId)) {
            debugPrint('Permission denied listening messages for $chatId');
          }
          _messageListeners[chatId]?.cancel?.call();
          _messageListeners.remove(chatId);
          return;
        }
        if (_messageErrorLogged.add('other:$chatId')) {
          debugPrint('Error listening to messages for $chatId: $e');
        }
      },
    );
  }

  void _resortGroups() {
    if (mounted) {
      setState(() {
        _sortSubjectsByRecent();
      });
    }
  }

  Future<String?> _resolveClassIdForOpen() async {
    if (_classId != null && _classId!.isNotEmpty) {
      return _classId;
    }

    final cachedClassId = _offlineService.getCachedStudentClassId(
      widget.studentId,
    );
    if (cachedClassId != null && cachedClassId.isNotEmpty) {
      _classId = cachedClassId;
      return _classId;
    }

    try {
      final fetchedClassId = await _messagingService
          .getStudentClassId(widget.studentId)
          .timeout(const Duration(seconds: 6));
      if (fetchedClassId != null && fetchedClassId.isNotEmpty) {
        _classId = fetchedClassId;
        await _offlineService.cacheStudentClassId(
          studentId: widget.studentId,
          classId: fetchedClassId,
        );
        return _classId;
      }
    } catch (_) {}

    return null;
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

        // ✅ Message listeners will load timestamps and trigger sort
        for (final s in cachedSubjects) {
          if (_classId != null) {
            _listenForMessageUpdates(_classId!, s);
          }
        }
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

      // ✅ Message listeners will load timestamps and trigger sort
      for (final s in subjects) {
        _listenForMessageUpdates(_classId!, s);
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

            // Start listeners to load message timestamps
            if (_classId != null) {
              for (final s in cachedData) {
                _listenForMessageUpdates(_classId!, s);
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
              final chatId = '${_classId ?? ''}|${subject.id}';

              return _SubjectGroupCard(
                subject: subject,
                chatId: chatId,
                onTap: () async {
                  if (_openingChats.contains(chatId)) return;

                  if (mounted) {
                    setState(() {
                      _openingChats.add(chatId);
                    });
                  }

                  // Capture context before any async operations
                  final navContext = context;

                  final resolvedClassId = await _resolveClassIdForOpen();
                  if (resolvedClassId == null || resolvedClassId.isEmpty) {
                    if (mounted) {
                      setState(() {
                        _openingChats.remove(chatId);
                      });
                      ScaffoldMessenger.of(navContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Still connecting. Please try again in a moment.',
                          ),
                        ),
                      );
                    }
                    return;
                  }

                  try {
                    final resolvedChatId = '$resolvedClassId|${subject.id}';

                    // Navigate and wait for return
                    await Navigator.push(
                      navContext,
                      MaterialPageRoute(
                        builder: (context) => TeacherGroupChatPage(
                          classId: resolvedClassId,
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
                        unreadProvider.refreshChat(resolvedChatId);
                        unreadProvider.loadUnreadCount(
                          chatId: resolvedChatId,
                          chatType: ChatTypeConfig.groupChat,
                        );
                      } catch (e) {}
                    }
                  } finally {
                    if (mounted) {
                      setState(() {
                        _openingChats.remove(chatId);
                      });
                    }
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
