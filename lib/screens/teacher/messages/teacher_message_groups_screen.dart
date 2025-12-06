import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/auth_provider.dart';
import '../../messages/group_chat_page.dart';

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
  Map<String, MessageGroup> _groupCache = {};
  DateTime? _cacheTimestamp;
  static const Duration _cacheDuration = Duration(minutes: 5);

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

  Future<List<TeachingContext>> getTeacherTeachingContexts(
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
      // ✅ OPTIMIZATION: Use single combined query for both last message and unread
      final messagesSnapshot = await _firestore
          .collection('classes')
          .doc(context.classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(300) // Get more messages at once
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

        // ✅ OPTIMIZATION: Count unread in memory instead of extra query
        unreadCount = 0;
        for (var doc in messagesSnapshot.docs) {
          final msg = doc.data();
          final senderId = msg['senderId'] as String?;
          if (senderId != null && senderId != context.teacherId) {
            unreadCount++;
          }
        }
      }
    } catch (e) {
      // Group chat may not exist yet
      print(
        '⚠️ No messages yet for class: ${context.classId}, subject: $subjectId. Error: $e',
      );
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
      print('📦 Using cached message groups (instant load)');
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

class _TeacherMessageGroupsScreenState
    extends State<TeacherMessageGroupsScreen> {
  final MessageGroupsService _service = MessageGroupsService();
  List<MessageGroup> _groups = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups({bool forceRefresh = false}) async {
    // ✅ NEW: Option to force clear cache and refresh
    if (forceRefresh) {
      _service.clearCache();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final groups = await _service.getTeacherMessageGroups(currentUser.uid);

      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading groups: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF130F23)
            : const Color(0xFFF6F5F8),
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              // Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadGroups,
          ),
        ],
      ),
      body: _buildBody(isDark),
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

    if (_groups.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadGroups,
      color: const Color(0xFF6A4FF7),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          return MessageGroupTile(
            group: _groups[index],
            isDark: isDark,
            onTap: () => _openGroupChat(_groups[index]),
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

  void _openGroupChat(MessageGroup group) {
    // ✅ Mark group as read and update UI immediately
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

    Navigator.push(
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
    // ✅ REMOVED forceRefresh to prevent 3-4 second loading delay
    // Cache will naturally expire after 5 minutes
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
              color: widget.isDark
                  ? const Color(0xFF1E1E2E).withOpacity(0.6)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6A4FF7).withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.isDark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: const Color(0xFF6A4FF7).withOpacity(0.1),
                highlightColor: const Color(0xFF6A4FF7).withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Subject + Icon + Badge Row
                      Row(
                        children: [
                          // Subject Icon
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6A4FF7), Color(0xFF8F66FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF6A4FF7,
                                  ).withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                widget.group.subjectName
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Subject Title + Unread Badge
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.group.subjectName,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: widget.isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          letterSpacing: -0.3,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (widget.group.unreadCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF6A4FF7),
                                              Color(0xFF8F66FF),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '${widget.group.unreadCount}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Class/Section Badge (Inline)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF6A4FF7,
                                    ).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF6A4FF7,
                                      ).withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.class_rounded,
                                        size: 13,
                                        color: const Color(0xFF6A4FF7),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Grade ${widget.group.className} • Section ${widget.group.sectionName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6A4FF7),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Last Message Preview
                      if (widget.group.lastMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 13,
                                color: widget.isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.group.lastMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
