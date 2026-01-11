import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../widgets/unread_badge_widget.dart';
import '../messages/group_chat_page.dart';

class TeacherGroupsScreen extends StatefulWidget {
  const TeacherGroupsScreen({super.key});

  @override
  State<TeacherGroupsScreen> createState() => _TeacherGroupsScreenState();
}

class _TeacherGroupsScreenState extends State<TeacherGroupsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _teacherGroups = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _teacherId;

  @override
  void initState() {
    super.initState();
    _loadTeacherGroups();
  }

  Future<void> _loadTeacherGroups() async {
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

      _teacherId = currentUser.uid;


      // Query all classes where this teacher teaches any subject
      final classesSnapshot = await _firestore.collection('classes').get();

      List<Map<String, dynamic>> groups = [];

      for (var classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final subjectTeachers =
            classData['subjectTeachers'] as Map<String, dynamic>?;

        if (subjectTeachers == null) continue;

        // Find subjects where this teacher is assigned
        subjectTeachers.forEach((subject, teacherData) {
          if (teacherData is Map<String, dynamic>) {
            final assignedTeacherId = teacherData['teacherId'] as String?;

            if (assignedTeacherId == _teacherId) {
              groups.add({
                'classId': classDoc.id,
                'className': classData['className'] ?? 'Unknown Class',
                'section': classData['section'] ?? '',
                'subject': subject,
                'teacherName': teacherData['teacherName'] ?? 'Teacher',
                'schoolCode': classData['schoolCode'] ?? '',
              });
            }
          }
        });
      }

      // Sort groups by class name and subject
      groups.sort((a, b) {
        int classCompare = a['className'].compareTo(b['className']);
        if (classCompare != 0) return classCompare;
        int sectionCompare = a['section'].compareTo(b['section']);
        if (sectionCompare != 0) return sectionCompare;
        return a['subject'].compareTo(b['subject']);
      });


      setState(() {
        _teacherGroups = groups;
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
          'My Groups',
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
            onPressed: _loadTeacherGroups,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
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
                      onPressed: _loadTeacherGroups,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
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
    if (_teacherGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: isDark ? Colors.white24 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No groups assigned',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You haven\'t been assigned to any class subjects yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? Colors.white.withOpacity(0.4)
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTeacherGroups,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _teacherGroups.length,
        itemBuilder: (context, index) {
          final group = _teacherGroups[index];
          return _buildGroupCard(context, group, isDark);
        },
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    Map<String, dynamic> group,
    bool isDark,
  ) {
    final className = group['className'] as String;
    final section = group['section'] as String;
    final subject = group['subject'] as String;
    final classId = group['classId'] as String;
    final teacherName = group['teacherName'] as String? ?? 'Teacher';

    final icon = _getSubjectIcon(subject);

    // Extract grade number from className (e.g., "Grade 10" -> "10")
    final gradeMatch = RegExp(r'\d+').firstMatch(className);
    final grade = gradeMatch?.group(0) ?? className;

    // Get unread count
    final chatId = '$classId|${subject.toLowerCase().replaceAll(' ', '_')}';
    final unreadCountProvider = Provider.of<UnreadCountProvider>(context);
    final unreadCount = unreadCountProvider.getUnreadCount(chatId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200]!,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatPage(
                  classId: classId,
                  subjectId: subject.toLowerCase().replaceAll(' ', '_'),
                  subjectName: subject,
                  teacherName: teacherName,
                  icon: icon,
                  className: className,
                  section: section,
                ),
              ),
            );
          },
          child: Row(
            children: [
              // Violet left accent bar
              Container(
                width: 4,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Subject Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(width: 16),

              // Group Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subject,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (unreadCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: InlineUnreadBadge(count: unreadCount),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Class Group',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Teacher: $teacherName',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withOpacity(0.5)
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSubjectIcon(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return '📐';
    if (s.contains('science')) return '🔬';
    if (s.contains('social')) return '🌍';
    if (s.contains('english')) return '📚';
    if (s.contains('hindi')) return '📖';
    if (s.contains('chem')) return '🧪';
    if (s.contains('phy')) return '⚛️';
    if (s.contains('bio')) return '🧬';
    if (s.contains('computer')) return '💻';
    if (s.contains('history')) return '📜';
    if (s.contains('physical') || s.contains('education')) return '⚽';
    if (s.contains('art')) return '🎨';
    if (s.contains('music')) return '🎵';
    return '📕';
  }

  // Get subject gradient colors (violet theme)
  List<Color> _getSubjectGradient(String subjectName) {
    final subject = subjectName.toLowerCase();
    if (subject.contains('math')) {
      return [const Color(0xFF7C3AED), const Color(0xFF9B59B6)];
    }
    if (subject.contains('science')) {
      return [const Color(0xFF8B5CF6), const Color(0xFFA855F7)];
    }
    if (subject.contains('english') || subject.contains('hindi')) {
      return [const Color(0xFF6D28D9), const Color(0xFF7C3AED)];
    }
    if (subject.contains('history') || subject.contains('social')) {
      return [const Color(0xFF9333EA), const Color(0xFFA855F7)];
    }
    if (subject.contains('phy')) {
      return [const Color(0xFF6D28D9), const Color(0xFF8B5CF6)];
    }
    if (subject.contains('chem')) {
      return [const Color(0xFF9333EA), const Color(0xFFA855F7)];
    }
    if (subject.contains('bio')) {
      return [const Color(0xFF7C3AED), const Color(0xFF9B59B6)];
    }
    if (subject.contains('computer')) {
      return [const Color(0xFF8B5CF6), const Color(0xFF9333EA)];
    }
    if (subject.contains('art')) {
      return [const Color(0xFF9B59B6), const Color(0xFFA855F7)];
    }
    if (subject.contains('music')) {
      return [const Color(0xFF7C3AED), const Color(0xFF9333EA)];
    }
    if (subject.contains('physical') || subject.contains('education')) {
      return [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
    }
    return [const Color(0xFF7C3AED), const Color(0xFF9B59B6)];
  }
}
