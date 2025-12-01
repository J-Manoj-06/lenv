import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
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

      print('🔍 Looking for classes where teacher $_teacherId is assigned');

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
              print(
                '✅ Found group: ${classData['className']} - ${classData['section']} - $subject',
              );
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

      print('📊 Total groups found: ${groups.length}');

      setState(() {
        _teacherGroups = groups;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading teacher groups: $e');
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
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
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
                            const Text(
                              'Subject Groups',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_teacherGroups.length} Group${_teacherGroups.length != 1 ? 's' : ''}',
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

          // Groups List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _teacherGroups.length,
              itemBuilder: (context, index) {
                final group = _teacherGroups[index];
                return _buildGroupCard(context, group, isDark);
              },
            ),
          ),
        ],
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatPage(
                  classId: classId,
                  subjectId: subject.toLowerCase().replaceAll(' ', '_'),
                  subjectName: subject,
                  teacherName: 'You (Teacher)',
                  icon: icon,
                  className: className,
                  section: section,
                ),
              ),
            );
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

                // Group Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.class_,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$className - Section $section',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[700],
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.arrow_forward_ios, size: 16, color: color),
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
    if (s.contains('physical') || s.contains('education'))
      return const Color(0xFF2ECC71);
    return const Color(0xFF6366F1);
  }
}
