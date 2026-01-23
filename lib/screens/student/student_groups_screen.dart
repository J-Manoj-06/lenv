import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/unread_badge_widget.dart';
import '../messages/group_chat_page.dart';

class StudentGroupsScreen extends StatefulWidget {
  const StudentGroupsScreen({super.key});

  @override
  State<StudentGroupsScreen> createState() => _StudentGroupsScreenState();
}

class _StudentGroupsScreenState extends State<StudentGroupsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _classData;
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<DocumentSnapshot>? _classStreamSubscription;

  @override
  void initState() {
    super.initState();
    // ✅ NEW: Ensure auth is initialized before loading data
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _classStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload unread counts when returning from chat
    if (_classData != null) {
      _prefetchUnreadCountsForSubjects(
        classId: _classData!['id'] as String,
        subjects: _classData!['subjects'] as List<dynamic>?,
      );
    }
  }

  /// Initialize auth and set up class data stream listener
  Future<void> _initializeAndLoad() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // ✅ CRITICAL: Wait for auth to initialize on app start
      await authProvider.ensureInitialized();

      // Now load class data after auth is ready
      await _setupClassStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Set up real-time listener for class data updates
  Future<void> _setupClassStream() async {
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

      // First load - get student info to find class doc ID
      final studentDoc = await _firestore
          .collection('students')
          .doc(currentUser.uid)
          .get();

      if (!studentDoc.exists) {
        setState(() {
          _errorMessage = 'Student data not found';
          _isLoading = false;
        });
        return;
      }

      final studentData = studentDoc.data()!;
      final className = studentData['className'] as String?;
      final section = studentData['section'] as String?;
      final schoolCode = studentData['schoolCode'] as String?;

      if (className == null || section == null || schoolCode == null) {
        setState(() {
          _errorMessage = 'Class information not available';
          _isLoading = false;
        });
        return;
      }

      // Find class document ID
      final classQuery = await _firestore
          .collection('classes')
          .where('className', isEqualTo: className)
          .where('section', isEqualTo: section)
          .where('schoolCode', isEqualTo: schoolCode)
          .limit(1)
          .get();

      if (classQuery.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Class not found in database';
          _isLoading = false;
        });
        return;
      }

      final classDocId = classQuery.docs.first.id;

      // 🔥 NEW: Set up real-time listener on class document
      _classStreamSubscription?.cancel();
      _classStreamSubscription = _firestore
          .collection('classes')
          .doc(classDocId)
          .snapshots()
          .listen(
            (snapshot) async {
              if (!snapshot.exists) {
                if (mounted) {
                  setState(() {
                    _errorMessage = 'Class data not found';
                    _isLoading = false;
                  });
                }
                return;
              }

              final classData = snapshot.data()!;
              classData['id'] = snapshot.id;

              // Prime unread badges for all subjects
              await _prefetchUnreadCountsForSubjects(
                classId: snapshot.id,
                subjects: classData['subjects'] as List<dynamic>?,
              );

              if (mounted) {
                setState(() {
                  _classData = classData;
                  _isLoading = false;
                });
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Error loading class: $error';
                  _isLoading = false;
                });
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error setting up stream: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadClassData() async {
    if (!mounted) return;

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

      // Ensure unread provider is ready for this user so badges work
      Provider.of<UnreadCountProvider>(
        context,
        listen: false,
      ).initialize(currentUser.uid);

      // Get student data to find their class and section
      final studentDoc = await _firestore
          .collection('students')
          .doc(currentUser.uid)
          .get();

      if (!studentDoc.exists) {
        setState(() {
          _errorMessage = 'Student data not found';
          _isLoading = false;
        });
        return;
      }

      final studentData = studentDoc.data()!;
      final className = studentData['className'] as String?;
      final section = studentData['section'] as String?;
      final schoolCode = studentData['schoolCode'] as String?;

      if (className == null || section == null || schoolCode == null) {
        setState(() {
          _errorMessage = 'Class information not available';
          _isLoading = false;
        });
        return;
      }

      // Query the classes collection to find the matching class
      final classQuery = await _firestore
          .collection('classes')
          .where('className', isEqualTo: className)
          .where('section', isEqualTo: section)
          .where('schoolCode', isEqualTo: schoolCode)
          .limit(1)
          .get();

      if (classQuery.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Class not found in database';
          _isLoading = false;
        });
        return;
      }

      final classDoc = classQuery.docs.first;
      final classData = classDoc.data();
      classData['id'] = classDoc.id; // Add document ID

      // Prime unread badges for all subjects in one batch so list shows counts
      await _prefetchUnreadCountsForSubjects(
        classId: classDoc.id,
        subjects: classData['subjects'] as List<dynamic>?,
      );

      setState(() {
        _classData = classData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading class data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Subject Groups',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            onPressed: _loadClassData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8800)),
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.orange[700],
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
                      onPressed: _loadClassData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8800),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _buildGroupsList(isDark),
    );
  }

  Widget _buildGroupsList(bool isDark) {
    if (_classData == null) {
      return const Center(child: Text('No class data available'));
    }

    var subjects = _classData!['subjects'] as List<dynamic>?;
    final subjectTeachers =
        _classData!['subjectTeachers'] as Map<String, dynamic>?;
    final classId = _classData!['id'] as String;
    final className = _classData!['className'] as String;
    final section = _classData!['section'] as String;

    if (subjects == null || subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 64,
              color: isDark ? Colors.white24 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No subjects available',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Sort subjects by last message time (most recent first)
    final sortedSubjects = List<dynamic>.from(subjects);
    final subjectLastMessageTime =
        _classData!['subjectLastMessageTime'] as Map<String, dynamic>?;
    if (subjectLastMessageTime != null && subjectLastMessageTime.isNotEmpty) {
      sortedSubjects.sort((a, b) {
        final timeA = subjectLastMessageTime[a] as dynamic;
        final timeB = subjectLastMessageTime[b] as dynamic;

        // Handle null timestamps (subjects with no messages)
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // Subjects without messages go to bottom
        if (timeB == null) return -1;

        // Both are timestamps - sort descending (most recent first)
        try {
          final dateA = (timeA as Timestamp).toDate();
          final dateB = (timeB as Timestamp).toDate();
          return dateB.compareTo(dateA); // Descending
        } catch (e) {
          return 0;
        }
      });
    }

    final finalSubjects = sortedSubjects;

    return RefreshIndicator(
      onRefresh: _loadClassData,
      child: Column(
        children: [
          // Class Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8800), Color(0xFFFF9E2A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8800).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.groups,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$className - Section $section',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${subjects.length} Subject${subjects.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Subjects List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: finalSubjects.length,
              itemBuilder: (context, index) {
                final subject = finalSubjects[index] as String;
                final teacherData =
                    subjectTeachers?[subject.toLowerCase()]
                        as Map<String, dynamic>?;
                final teacherName =
                    teacherData?['teacherName'] as String? ?? 'Teacher';
                return _buildSubjectCard(
                  context,
                  subject,
                  teacherName,
                  classId,
                  isDark,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _prefetchUnreadCountsForSubjects({
    required String classId,
    required List<dynamic>? subjects,
  }) async {
    if (subjects == null || subjects.isEmpty) {
      return;
    }

    final unread = Provider.of<UnreadCountProvider>(context, listen: false);

    // Build chatIds and types for batch loader
    final chatIds = <String>[];
    final chatTypes = <String, String>{};

    for (final subject in subjects) {
      if (subject is! String || subject.isEmpty) continue;
      final subjectId = subject.toLowerCase().replaceAll(' ', '_');
      final chatId = '$classId|$subjectId';
      chatIds.add(chatId);
      chatTypes[chatId] = ChatTypeConfig.groupChat;
    }

    await unread.loadUnreadCountsBatch(chatIds: chatIds, chatTypes: chatTypes);
  }

  Widget _buildSubjectCard(
    BuildContext context,
    String subject,
    String teacherName,
    String classId,
    bool isDark,
  ) {
    final unread = Provider.of<UnreadCountProvider>(context);
    final subjectId = subject.toLowerCase().replaceAll(' ', '_');
    final chatId = '$classId|$subjectId';
    final unreadCount = unread.getUnreadCount(chatId);

    final icon = _getSubjectIcon(subject);
    final color = _getSubjectColor(subject);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            // Navigate to chat and wait for return
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatPage(
                  classId: classId,
                  subjectId: subject.toLowerCase().replaceAll(' ', '_'),
                  subjectName: subject,
                  teacherName: teacherName,
                  icon: icon,
                ),
              ),
            );

            // Force refresh unread counts when returning from chat
            if (mounted) {
              final unreadProvider = Provider.of<UnreadCountProvider>(
                context,
                listen: false,
              );
              final refreshChatId =
                  '$classId|${subject.toLowerCase().replaceAll(' ', '_')}';
              await unreadProvider.loadUnreadCount(
                chatId: refreshChatId,
                chatType: ChatTypeConfig.groupChat,
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Subject Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(icon, style: const TextStyle(fontSize: 28)),
                  ),
                ),
                const SizedBox(width: 16),

                // Subject Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              teacherName,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[700],
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            InlineUnreadBadge(count: unreadCount),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow Icon
                Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSubjectIcon(String subject) {
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
    if (s.contains('physical') || s.contains('education')) return '⚽';
    return '📕';
  }

  Color _getSubjectColor(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return const Color(0xFF4A90E2);
    if (s.contains('science')) return const Color(0xFF50C878);
    if (s.contains('social')) return const Color(0xFFE67E22);
    if (s.contains('english')) return const Color(0xFF9B59B6);
    if (s.contains('hindi')) return const Color(0xFFE74C3C);
    if (s.contains('computer')) return const Color(0xFF3498DB);
    if (s.contains('physical') || s.contains('education')) {
      return const Color(0xFF2ECC71);
    }
    return const Color(0xFFFF8800);
  }
}
