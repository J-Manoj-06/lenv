import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../providers/auth_provider.dart';
import '../../../utils/session_manager.dart';
import '../../messages/teacher_group_chat_page.dart';
import '../../../services/group_messaging_service.dart';
import '../../messages/staff_room_group_chat_page.dart';
import '../../../services/offline_data_service.dart';
import '../../../widgets/group_avatar_widget.dart';
import '../../../widgets/staff_room_avatar_widget.dart';

/// Models
class TeachingContext {
  final String classId;
  final String className;
  final String section;
  final String subject;
  final String teacherId;
  final String teacherName;
  final String schoolCode;

  TeachingContext({
    required this.classId,
    required this.className,
    required this.section,
    required this.subject,
    required this.teacherId,
    required this.teacherName,
    required this.schoolCode,
  });

  String get groupId => '${classId}_$subject';
  String get displayName => '$subject • Class $className $section';
}

class MessageGroup {
  final String groupId;
  final String subjectId; // ✅ Added: Actual subject ID for Firestore queries
  final String subjectName;
  final String className;
  final String sectionName;
  final String teacherId;
  final int studentCount;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String classId;

  MessageGroup({
    required this.groupId,
    required this.subjectId, // ✅ Added
    required this.subjectName,
    required this.className,
    required this.sectionName,
    required this.teacherId,
    required this.studentCount,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.classId,
  });

  String get displayName => '$subjectName • Class $className $sectionName';
}

/// Service for fetching message groups
class MessageGroupsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _toMillis(dynamic raw) {
    if (raw is int) return raw;
    if (raw is Timestamp) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return 0;
  }

  int _compareMessageGroups(MessageGroup a, MessageGroup b) {
    if (a.lastMessageTime == null && b.lastMessageTime == null) {
      final subjectCmp = a.subjectName.toLowerCase().compareTo(
        b.subjectName.toLowerCase(),
      );
      if (subjectCmp != 0) return subjectCmp;

      final classCmp = a.className.toLowerCase().compareTo(
        b.className.toLowerCase(),
      );
      if (classCmp != 0) return classCmp;

      final sectionCmp = a.sectionName.toLowerCase().compareTo(
        b.sectionName.toLowerCase(),
      );
      if (sectionCmp != 0) return sectionCmp;

      return a.groupId.compareTo(b.groupId);
    }

    if (a.lastMessageTime == null) return 1;
    if (b.lastMessageTime == null) return -1;

    final timeComparison = b.lastMessageTime!.compareTo(a.lastMessageTime!);
    if (timeComparison != 0) return timeComparison;

    final subjectCmp = a.subjectName.toLowerCase().compareTo(
      b.subjectName.toLowerCase(),
    );
    if (subjectCmp != 0) return subjectCmp;

    final classCmp = a.className.toLowerCase().compareTo(
      b.className.toLowerCase(),
    );
    if (classCmp != 0) return classCmp;

    final sectionCmp = a.sectionName.toLowerCase().compareTo(
      b.sectionName.toLowerCase(),
    );
    if (sectionCmp != 0) return sectionCmp;

    return a.groupId.compareTo(b.groupId);
  }

  // ✅ NEW: Cache for message groups (5 minute TTL)
  final Map<String, MessageGroup> _groupCache = {};

  // ✅ NEW: Clear cache on demand (when teacher sends message)
  void clearCache() {
    _groupCache.clear();
  }

  // ✅ NEW: Mark specific group as read (clear unread badge)
  void markGroupAsRead(String groupId) {
    final group = _groupCache[groupId];
    if (group != null) {
      // Update cache with zero unread count
      _groupCache[groupId] = MessageGroup(
        groupId: group.groupId,
        subjectId: group.subjectId,
        subjectName: group.subjectName,
        className: group.className,
        sectionName: group.sectionName,
        teacherId: group.teacherId,
        studentCount: group.studentCount,
        unreadCount: 0, // ✅ Clear badge
        lastMessage: group.lastMessage,
        lastMessageTime: group.lastMessageTime,
        classId: group.classId,
      );
    }
  }

  /// ✅ OPTIMIZED: Use teacher_groups collection (1 read instead of 50+)
  Future<List<TeachingContext>> getTeacherTeachingContexts(
    String teacherId,
  ) async {
    try {
      // ✅ OPTIMIZATION: Read from teacher_groups index (1 Firestore read)
      final teacherGroupsDoc = await _firestore
          .collection('teacher_groups')
          .doc(teacherId)
          .get();

      if (!teacherGroupsDoc.exists || teacherGroupsDoc.data() == null) {
        return _getTeachingContextsFallback(teacherId);
      }

      final data = teacherGroupsDoc.data()!;

      // ✅ NEW: Handle both data structures (array or map-based)
      List<dynamic> classesData = [];

      if (data['classes'] is List) {
        // New structure: classes as array
        classesData = data['classes'] as List<dynamic>;
      } else if (data['groups'] is Map) {
        // Alternative structure: groups as map
        final groupsMap = data['groups'] as Map<String, dynamic>;
        classesData = groupsMap.values.toList();
      }

      List<TeachingContext> contexts = [];

      // Convert each class/group to TeachingContext
      for (final classItem in classesData) {
        if (classItem is Map<String, dynamic>) {
          contexts.add(
            TeachingContext(
              classId: classItem['classId'] ?? '',
              className: classItem['className'] ?? 'Unknown',
              section: classItem['section'] ?? '',
              subject: classItem['subject'] ?? '',
              teacherId: teacherId,
              teacherName: data['teacherName'] ?? 'Teacher',
              schoolCode: data['schoolCode'] ?? '',
            ),
          );
        }
      }

      return contexts;
    } catch (e) {
      return _getTeachingContextsFallback(teacherId);
    }
  }

  /// Fallback: Scan all classes (legacy method)
  Future<List<TeachingContext>> _getTeachingContextsFallback(
    String teacherId,
  ) async {
    final classesSnapshot = await _firestore.collection('classes').get();
    List<TeachingContext> contexts = [];

    for (var classDoc in classesSnapshot.docs) {
      final classData = classDoc.data();
      final subjectTeachers =
          classData['subjectTeachers'] as Map<String, dynamic>?;

      if (subjectTeachers == null) continue;

      subjectTeachers.forEach((subject, teacherData) {
        if (teacherData is Map<String, dynamic>) {
          final assignedTeacherId = teacherData['teacherId'] as String?;

          if (assignedTeacherId == teacherId) {
            contexts.add(
              TeachingContext(
                classId: classDoc.id,
                className: classData['className'] ?? 'Unknown',
                section: classData['section'] ?? '',
                subject: subject,
                teacherId: teacherId,
                teacherName: teacherData['teacherName'] ?? 'Teacher',
                schoolCode: classData['schoolCode'] ?? '',
              ),
            );
          }
        }
      });
    }

    return contexts;
  }

  Future<MessageGroup> convertToMessageGroup(TeachingContext context) async {
    // ✅ OPTIMIZATION: Skip expensive student count query (can be done async later)
    // This alone saves 1 second per group!
    int studentCount = 0;

    // ✅ FIXED: Create proper subject ID (standardized format)
    final subjectId = context.subject.toLowerCase().replaceAll(' ', '_');

    // Get last message from group chat - ✅ FIXED: Use correct Firestore path
    String? lastMessage;
    DateTime? lastMessageTime;
    int unreadCount = 0;

    try {
      // ✅ Get last message
      final messagesSnapshot = await _firestore
          .collection('classes')
          .doc(context.classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1) // Only need the last message
          .get();

      if (messagesSnapshot.docs.isNotEmpty) {
        // Get last message (always first doc due to descending order)
        final lastMsg = messagesSnapshot.docs.first.data();
        lastMessage =
            lastMsg['message'] as String?; // ✅ Fixed: Use 'message' field name
        final timestampMs = _toMillis(lastMsg['timestamp']);
        if (timestampMs > 0) {
          lastMessageTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
        }
      }

      // ✅ NEW: Use persistent unread count from GroupMessagingService
      final messagingService = GroupMessagingService();
      unreadCount = await messagingService.getUnreadCount(
        context.classId,
        subjectId,
        context.teacherId,
      );
    } catch (e) {
      // Group chat may not exist yet
    }

    return MessageGroup(
      groupId: context.groupId,
      subjectId: subjectId, // ✅ Added: Store actual subjectId
      subjectName: context.subject,
      className: context.className,
      sectionName: context.section,
      teacherId: context.teacherId,
      studentCount: studentCount, // Can fetch this later without blocking
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      classId: context.classId,
    );
  }

  Future<List<MessageGroup>> getTeacherMessageGroups(String teacherId) async {
    // Always fetch fresh data (cache disabled to prevent stale groups)
    final contexts = await getTeacherTeachingContexts(teacherId);
    final groups = <MessageGroup>[];

    // Load groups in parallel where possible
    for (var context in contexts) {
      final group = await convertToMessageGroup(context);
      groups.add(group);
    }

    // Sort by latest activity descending, with deterministic tie-breakers.
    groups.sort(_compareMessageGroups);

    return groups;
  }
}

/// Main Message Groups Screen
class TeacherMessageGroupsScreen extends StatefulWidget {
  const TeacherMessageGroupsScreen({super.key});

  @override
  State<TeacherMessageGroupsScreen> createState() =>
      _TeacherMessageGroupsScreenState();
}

class _TeacherMessageGroupsScreenState extends State<TeacherMessageGroupsScreen>
    with AutomaticKeepAliveClientMixin {
  final MessageGroupsService _service = MessageGroupsService();
  final OfflineDataService _offlineService = OfflineDataService();
  List<MessageGroup> _groups = [];
  List<MessageGroup> _filteredGroups = [];
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  StreamSubscription<DocumentSnapshot>? _groupsStreamSubscription;
  Timer? _refreshTimer;
  String _instituteId = ''; // ✅ Cached offline: used by Staff Room card onTap
  final Set<String> _openingGroupIds = <String>{};

  @override
  bool get wantKeepAlive => true; // ✅ Preserve state when switching tabs

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // ✅ NEW: Ensure auth is initialized before loading groups
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupsStreamSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredGroups = _groups;
        _isSearching = false;
      } else {
        _isSearching = true;
        _filteredGroups = _groups.where((group) {
          return group.subjectName.toLowerCase().contains(query) ||
              group.className.toLowerCase().contains(query) ||
              group.sectionName.toLowerCase().contains(query) ||
              group.displayName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  /// Initialize auth and set up real-time group listener
  Future<void> _initializeAndLoad() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // ✅ CRITICAL: Wait for auth to initialize on app start
      await authProvider.ensureInitialized();

      // Now set up stream listener after auth is ready
      String? userId = authProvider.currentUser?.uid;

      // ✅ OFFLINE FALLBACK: Get userId from SharedPreferences if auth user is null
      if (userId == null || userId.isEmpty) {
        final session = await SessionManager.getLoginSession();
        userId = session['userId'] as String?;
        debugPrint('🔄 Groups: using cached userId from session: $userId');
      }

      // ✅ Cache instituteId for Staff Room card (works offline)
      final authInstituteId = authProvider.currentUser?.instituteId ?? '';
      if (authInstituteId.isNotEmpty) {
        setState(() => _instituteId = authInstituteId);
      } else {
        final session = await SessionManager.getLoginSession();
        final sessionSchoolId = session['schoolId'] as String? ?? '';
        if (sessionSchoolId.isNotEmpty && mounted) {
          setState(() => _instituteId = sessionSchoolId);
          debugPrint(
            '🔄 Groups: using cached schoolId for staff room: $sessionSchoolId',
          );
        }
      }

      if (userId != null && userId.isNotEmpty) {
        _setupTeacherGroupsStream(userId);
      } else {
        // No userId available at all - stop loading
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Unable to load groups. Please reconnect.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Set up real-time listener on teacher_groups Firestore document
  /// This ensures groups reorder immediately when new messages arrive
  void _setupTeacherGroupsStream(String teacherId) {
    // Cancel previous subscription if exists
    _groupsStreamSubscription?.cancel();

    // Load groups initially
    _loadGroupsFromFirestore(teacherId);

    // Listen to teacher_groups document for structural changes
    _groupsStreamSubscription = FirebaseFirestore.instance
        .collection('teacher_groups')
        .doc(teacherId)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            // Always force refresh to get latest message timestamps
            _service.clearCache();

            // Load groups fresh from the updated teacher_groups doc
            await _loadGroupsFromFirestore(teacherId);
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = 'Error listening to groups: $error';
                _isLoading = false;
              });
            }
          },
        );

    // Set up periodic refresh every 10 seconds to catch new messages
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _service.clearCache();
      _loadGroupsFromFirestore(teacherId);
    });
  }

  Future<void> _loadGroupsFromFirestore(String teacherId) async {
    // ✅ Ensure offline service is initialized
    try {
      await _offlineService.initialize();
    } catch (e) {
      debugPrint('⚠️ Failed to initialize offline service: $e');
    }

    // ✅ Try loading from cache first for instant display
    debugPrint('🔍 Attempting to load cached teacher groups for: $teacherId');
    final cachedGroups = _offlineService.getCachedTeacherGroups(teacherId);
    debugPrint('🔍 Got cached groups: ${cachedGroups?.length ?? 0} groups');

    if (cachedGroups != null && cachedGroups.isNotEmpty) {
      debugPrint('✅ Loading ${cachedGroups.length} groups from cache');
      try {
        if (mounted) {
          setState(() {
            _groups = cachedGroups.map((data) {
              try {
                return MessageGroup(
                  groupId: data['groupId'] ?? '',
                  subjectId: data['subjectId'] ?? '',
                  subjectName: data['subjectName'] ?? '',
                  className: data['className'] ?? '',
                  sectionName: data['sectionName'] ?? '',
                  teacherId: data['teacherId'] ?? '',
                  studentCount: data['studentCount'] ?? 0,
                  lastMessage: data['lastMessage'] as String?,
                  lastMessageTime: data['lastMessageTime'] != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          data['lastMessageTime'] as int,
                        )
                      : null,
                  unreadCount: data['unreadCount'] ?? 0,
                  classId: data['classId'] ?? '',
                );
              } catch (e) {
                debugPrint('❌ Error creating MessageGroup from cache: $e');
                debugPrint('   Data: $data');
                rethrow;
              }
            }).toList();
            _filteredGroups = _groups;
            _isLoading = false;
            debugPrint(
              '✅ UI updated with ${_groups.length} groups, _isLoading=$_isLoading',
            );
          });
        }
      } catch (e) {
        debugPrint('❌ Fatal error loading cached groups: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Error loading cached groups: $e';
          });
        }
      }
    } else {
      debugPrint('⚠️ No cached groups found for teacherId: $teacherId');
    }

    // ✅ Now fetch fresh data from network
    try {
      final groups = await _service
          .getTeacherMessageGroups(teacherId)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('⏱️ Network timeout loading teacher message groups');
              return <MessageGroup>[];
            },
          );

      // ✅ Cache the groups for offline access
      if (groups.isNotEmpty) {
        final groupsData = groups
            .map(
              (g) => {
                'groupId': g.groupId,
                'subjectId': g.subjectId,
                'subjectName': g.subjectName,
                'className': g.className,
                'sectionName': g.sectionName,
                'teacherId': g.teacherId,
                'studentCount': g.studentCount,
                'lastMessage': g.lastMessage,
                'lastMessageTime': g.lastMessageTime?.millisecondsSinceEpoch,
                'unreadCount': g.unreadCount,
                'classId': g.classId,
              },
            )
            .toList();

        await _offlineService.cacheTeacherGroups(
          teacherId: teacherId,
          groups: groupsData,
        );
      }

      if (mounted) {
        setState(() {
          if (groups.isNotEmpty) {
            _groups = groups;
            if (_isSearching) {
              final query = _searchController.text.toLowerCase();
              _filteredGroups = groups.where((group) {
                return group.subjectName.toLowerCase().contains(query) ||
                    group.className.toLowerCase().contains(query) ||
                    group.sectionName.toLowerCase().contains(query) ||
                    group.displayName.toLowerCase().contains(query);
              }).toList();
            } else {
              _filteredGroups = groups;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      // ✅ If network fails but we have cached data, keep showing it
      if (mounted) {
        setState(() {
          if (_groups.isEmpty) {
            _errorMessage = 'Error loading groups: $e';
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadGroups({bool forceRefresh = false}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String? userId = authProvider.currentUser?.uid;

    if (userId == null || userId.isEmpty) {
      final session = await SessionManager.getLoginSession();
      userId = session['userId'] as String?;
    }

    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load groups. Please reconnect.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (forceRefresh) {
      _service.clearCache();
    }

    await _loadGroupsFromFirestore(userId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildSearchBar(isDark),
          Expanded(child: _buildBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: 'Search groups by subject, class, or section...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF355872)),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your message groups...',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadGroups,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF355872),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final displayGroups = _isSearching ? _filteredGroups : _groups;

    if (_groups.isEmpty) {
      return _buildEmptyState(isDark);
    }

    if (_isSearching && _filteredGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'No groups found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGroups,
      color: const Color(0xFF355872),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: displayGroups.length + 1, // +1 for Staff Room card
        itemBuilder: (context, index) {
          // Show Staff Room card as first item
          if (index == 0) {
            return _buildStaffRoomCard(isDark);
          }

          // Show regular groups after Staff Room
          final group = displayGroups[index - 1];
          // Remove lastMessage and lastMessageTime to hide message preview
          final groupWithoutPreview = MessageGroup(
            groupId: group.groupId,
            subjectId: group.subjectId,
            subjectName: group.subjectName,
            className: group.className,
            sectionName: group.sectionName,
            teacherId: group.teacherId,
            studentCount: group.studentCount,
            unreadCount: group.unreadCount,
            lastMessage: null, // Remove message preview
            lastMessageTime: null, // Remove timestamp
            classId: group.classId,
          );
          return MessageGroupTile(
            group: groupWithoutPreview,
            isDark: isDark,
            onTap: () => _openGroupChat(displayGroups[index - 1]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF355872).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_rounded,
                size: 80,
                color: const Color(0xFF355872).withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No Message Groups',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You don\'t have any classes assigned yet. Once you\'re assigned to teach subjects, your message groups will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadGroups,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF355872),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffRoomCard(bool isDark) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final roomId = _instituteId.isNotEmpty
        ? _instituteId
        : (authProvider.currentUser?.instituteId ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFF5F0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFF97316).withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // ✅ Use cached _instituteId so this works offline too
              final instituteId =
                  authProvider.currentUser?.instituteId ?? _instituteId;
              final instituteName = 'Institute'; // Generic name for teachers

              if (instituteId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StaffRoomGroupChatPage(
                      instituteId: instituteId,
                      instituteName: instituteName,
                      isTeacher: true, // Different color for teachers
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(16),
            splashColor: const Color(0xFFF97316).withOpacity(0.1),
            highlightColor: const Color(0xFFF97316).withOpacity(0.05),
            child: Row(
              children: [
                // Orange left accent bar (teacher theme)
                Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),

                StaffRoomAvatarWidget(
                  roomId: roomId,
                  roomName: 'Staff Room',
                  size: 56,
                  canEdit: false,
                ),
                const SizedBox(width: 14),

                // Group Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Staff Room',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chat with all teachers',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openGroupChat(MessageGroup group) async {
    if (_openingGroupIds.contains(group.groupId)) return;

    setState(() {
      _openingGroupIds.add(group.groupId);
    });

    // ✅ Mark group as read in cache immediately
    _service.markGroupAsRead(group.groupId);

    // ✅ Update UI immediately to clear badge
    setState(() {
      final index = _groups.indexWhere((g) => g.groupId == group.groupId);
      if (index != -1) {
        _groups[index] = MessageGroup(
          groupId: group.groupId,
          subjectId: group.subjectId,
          subjectName: group.subjectName,
          className: group.className,
          sectionName: group.sectionName,
          teacherId: group.teacherId,
          studentCount: group.studentCount,
          unreadCount: 0, // Clear badge in UI
          lastMessage: group.lastMessage,
          lastMessageTime: group.lastMessageTime,
          classId: group.classId,
        );
      }
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      final messagingService = GroupMessagingService();
      unawaited(
        messagingService.markGroupAsRead(
          group.classId,
          group.subjectId,
          currentUser.uid,
        ),
      );
    }

    // ✅ OPTIMIZATION: Mark group as read in teacher_groups index (non-blocking)
    unawaited(_markGroupAsReadInFirestore(group));

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TeacherGroupChatPage(
            classId: group.classId,
            subjectId: group
                .subjectId, // ✅ FIXED: Use actual subjectId instead of groupId
            subjectName: group.subjectName,
            teacherName: 'Teacher',
            icon: _getIconForSubject(group.subjectName),
            className: group.className,
            section: group.sectionName,
          ),
        ),
      );
      // Refresh group list so new message pushes this group to the top.
      await _loadGroups(forceRefresh: true);
    } finally {
      if (mounted) {
        setState(() {
          _openingGroupIds.remove(group.groupId);
        });
      }
    }
  }

  /// ✅ OPTIMIZATION: Mark group as read in teacher_groups Firestore collection
  Future<void> _markGroupAsReadInFirestore(MessageGroup group) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      final groupId = group.groupId;
      await FirebaseFirestore.instance
          .collection('teacher_groups')
          .doc(currentUser.uid)
          .set({
            'groups': {
              groupId: {
                'unreadCount': 0,
                'lastReadAt': FieldValue.serverTimestamp(),
              },
            },
          }, SetOptions(merge: true));
    } catch (e) {}
  }

  // ✅ Helper method to get subject icon
  String _getIconForSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return '🔢';
    if (s.contains('science')) return '🔬';
    if (s.contains('social')) return '🌍';
    if (s.contains('english')) return '📖';
    if (s.contains('hindi')) return '📚';
    if (s.contains('chem')) return '🧪';
    if (s.contains('phy')) return '⚡';
    if (s.contains('bio')) return '🧬';
    if (s.contains('computer')) return '💻';
    if (s.contains('history')) return '📜';
    return '📕';
  }
}

/// Message Group Tile Widget
class MessageGroupTile extends StatefulWidget {
  final MessageGroup group;
  final bool isDark;
  final VoidCallback onTap;

  const MessageGroupTile({
    super.key,
    required this.group,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<MessageGroupTile> createState() => _MessageGroupTileState();
}

class _MessageGroupTileState extends State<MessageGroupTile>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Blue accent bar
                  Container(
                    width: 4,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF355872), Color(0xFF4A7A99)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 14),

                  GroupAvatarWidget(
                    groupId: widget.group.groupId,
                    groupName: widget.group.subjectName,
                    size: 56,
                    isTeacher: false,
                  ),
                  const SizedBox(width: 14),

                  // Group Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.group.subjectName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: widget.isDark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (widget.group.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE53E3E),
                                      Color(0xFFC53030),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${widget.group.unreadCount}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            // Extract grade number from className
                            final gradeMatch = RegExp(
                              r'\d+',
                            ).firstMatch(widget.group.className);
                            final grade =
                                gradeMatch?.group(0) ?? widget.group.className;
                            return Text(
                              'Grade $grade • Section ${widget.group.sectionName}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: widget.isDark
                                    ? Colors.white.withOpacity(0.5)
                                    : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
