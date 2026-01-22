import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../providers/auth_provider.dart';
import '../../messages/group_chat_page.dart';
import '../../../services/group_messaging_service.dart';
import '../../messages/staff_room_chat_page.dart';

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

  // ✅ NEW: Cache for message groups (5 minute TTL)
  final Map<String, MessageGroup> _groupCache = {};
  DateTime? _cacheTimestamp;

  // ✅ NEW: Cache check method
  bool _isCacheValid() {
    if (_cacheTimestamp == null || _groupCache.isEmpty) return false;
    return DateTime.now().difference(_cacheTimestamp!).inMinutes < 5;
  }

  // ✅ NEW: Clear cache on demand (when teacher sends message)
  void clearCache() {
    _groupCache.clear();
    _cacheTimestamp = null;
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
        final timestamp = lastMsg['timestamp'] as int?;
        if (timestamp != null) {
          lastMessageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
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
    // ✅ NEW: Return cached results if valid (no Firestore queries!)
    if (_isCacheValid()) {
      return _groupCache.values.toList();
    }

    final contexts = await getTeacherTeachingContexts(teacherId);
    final groups = <MessageGroup>[];

    // ✅ OPTIMIZATION: Load groups in parallel where possible
    for (var context in contexts) {
      final group = await convertToMessageGroup(context);
      groups.add(group);
      _groupCache[group.groupId] = group; // ✅ NEW: Cache as we go
    }

    // ✅ NEW: Update cache timestamp
    _cacheTimestamp = DateTime.now();

    // Sort by last message time (most recent first), then by subject name
    groups.sort((a, b) {
      // First sort by last message time (most recent first)
      if (a.lastMessageTime == null && b.lastMessageTime == null) {
        // If both have no messages, sort by subject name
        return a.subjectName.compareTo(b.subjectName);
      }
      if (a.lastMessageTime == null) return 1;
      if (b.lastMessageTime == null) return -1;
      final timeComparison = b.lastMessageTime!.compareTo(a.lastMessageTime!);

      // If same time, sort by subject name
      if (timeComparison == 0) {
        return a.subjectName.compareTo(b.subjectName);
      }
      return timeComparison;
    });

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
  List<MessageGroup> _groups = [];
  List<MessageGroup> _filteredGroups = [];
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  StreamSubscription<DocumentSnapshot>? _groupsStreamSubscription;

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
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        _setupTeacherGroupsStream(currentUser.uid);
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

    _groupsStreamSubscription = FirebaseFirestore.instance
        .collection('teacher_groups')
        .doc(teacherId)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            // Load groups fresh from the updated teacher_groups doc
            try {
              final groups = await _service.getTeacherMessageGroups(teacherId);

              if (mounted) {
                setState(() {
                  _groups = groups;
                  // Reapply search filter if active
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
                  _isLoading = false;
                });
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Error loading groups: $e';
                });
              }
            }
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
  }

  Future<void> _loadGroups({bool forceRefresh = false}) async {
    // ✅ REMOVED: _loadGroups now obsolete (handled by stream listener)
    // Kept for backward compatibility if called elsewhere
    if (forceRefresh) {
      _service.clearCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
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
          fillColor: isDark ? const Color(0xFF1E1A2F) : Colors.white,
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
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6A4FF7)),
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
                backgroundColor: const Color(0xFF6A4FF7),
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
      color: const Color(0xFF6A4FF7),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: displayGroups.length + 1, // +1 for Staff Room card
        itemBuilder: (context, index) {
          // Show Staff Room card as first item
          if (index == 0) {
            return _buildStaffRoomCard(isDark);
          }

          // Show regular groups after Staff Room
          return MessageGroupTile(
            group: displayGroups[index - 1],
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
                color: const Color(0xFF6A4FF7).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_rounded,
                size: 80,
                color: const Color(0xFF6A4FF7).withOpacity(0.6),
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
                backgroundColor: const Color(0xFF6A4FF7),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              final instituteId = authProvider.currentUser?.instituteId ?? '';
              final instituteName = 'Institute'; // Generic name for teachers

              if (instituteId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StaffRoomChatPage(
                      instituteId: instituteId,
                      instituteName: instituteName,
                      isTeacher: true, // Different color for teachers
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(16),
            splashColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.withOpacity(0.05),
            highlightColor: isDark
                ? Colors.white.withOpacity(0.03)
                : Colors.grey.withOpacity(0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  // Orange left accent bar (teacher theme)
                  Container(
                    width: 4,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF97316), // Orange for teachers
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Icon with letter
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.business,
                        size: 28,
                        color: Color(0xFFF97316),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

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
                                'Teacher Group Chat',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chat with all teachers',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
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

  void _openGroupChat(MessageGroup group) async {
    // ✅ Mark group as read in cache
    _service.markGroupAsRead(group.groupId);

    // ✅ Mark group as read in Firestore for persistence
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      final messagingService = GroupMessagingService();
      await messagingService.markGroupAsRead(
        group.classId,
        group.subjectId,
        currentUser.uid,
      );
    }

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

    // ✅ OPTIMIZATION: Mark group as read in teacher_groups index
    _markGroupAsReadInFirestore(group);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatPage(
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
    // Refresh group list so new message pushes this group to the top
    // without waiting for cache expiry.
    await _loadGroups(forceRefresh: true);
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
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF222222) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.grey[200]!,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                splashColor: widget.isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.05),
                highlightColor: widget.isDark
                    ? Colors.white.withOpacity(0.03)
                    : Colors.grey.withOpacity(0.03),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      // Violet left accent bar
                      Container(
                        width: 4,
                        height: 70,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7C3AED),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Subject Icon with letter
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A4FF7).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            widget.group.subjectName
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6A4FF7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

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
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: widget.isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.group.unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red[600],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${widget.group.unreadCount}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Builder(
                              builder: (context) {
                                // Extract grade number from className
                                final gradeMatch = RegExp(
                                  r'\d+',
                                ).firstMatch(widget.group.className);
                                final grade =
                                    gradeMatch?.group(0) ??
                                    widget.group.className;
                                return Text(
                                  'Grade $grade • Section ${widget.group.sectionName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
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
        ),
      ),
    );
  }
}
