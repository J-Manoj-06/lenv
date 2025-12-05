import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../messages/group_chat_page.dart';

/// Aggregated teacher messages screen
/// Shows subjects taught by the teacher with the list of classes per subject.
/// Mirrors provided HTML Tailwind design adapted to Flutter.
class TeacherSubjectMessagesScreen extends StatefulWidget {
  const TeacherSubjectMessagesScreen({super.key});

  @override
  State<TeacherSubjectMessagesScreen> createState() =>
      _TeacherSubjectMessagesScreenState();
}

class _TeacherSubjectMessagesScreenState
    extends State<TeacherSubjectMessagesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  /// subject -> list of class maps {classId,className,section,schoolCode,teacherName}
  final Map<String, List<Map<String, dynamic>>> _subjectClasses = {};

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
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
      final teacherId = currentUser.uid;

      final classesSnapshot = await _firestore.collection('classes').get();
      final Map<String, List<Map<String, dynamic>>> subjectClasses = {};

      for (final classDoc in classesSnapshot.docs) {
        final data = classDoc.data();
        final subjectTeachers =
            data['subjectTeachers'] as Map<String, dynamic>?;
        if (subjectTeachers == null) continue;

        subjectTeachers.forEach((subject, teacherData) {
          if (teacherData is Map<String, dynamic>) {
            final tid = teacherData['teacherId'] as String?;
            if (tid == teacherId) {
              subjectClasses.putIfAbsent(subject, () => []);
              subjectClasses[subject]!.add({
                'classId': classDoc.id,
                'className': data['className'] ?? 'Unknown',
                'section': data['section'] ?? '',
                'schoolCode': data['schoolCode'] ?? '',
                'teacherName': teacherData['teacherName'] ?? currentUser.name,
              });
            }
          }
        });
      }

      // Sort classes inside each subject by className then section
      for (final entry in subjectClasses.entries) {
        entry.value.sort((a, b) {
          final c = (a['className'] as String).compareTo(
            b['className'] as String,
          );
          if (c != 0) return c;
          return (a['section'] as String).compareTo(b['section'] as String);
        });
      }

      setState(() {
        _subjectClasses.clear();
        _subjectClasses.addAll(subjectClasses);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load subjects: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF140F23)
          : const Color(0xFFF3F4F6),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: isDark
              ? Colors.white.withOpacity(0.02)
              : Colors.white,
          elevation: 1,
          titleSpacing: 0,
          centerTitle: true,
          title: Text(
            'Messages',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF7C4DFF)),
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
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
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadSubjects,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
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
      );
    }

    final subjects = _filteredSubjectEntries();
    if (subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_unread, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No subjects assigned yet.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.grey[700],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildFilterRow(isDark),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              final entry = subjects[index];
              return _buildSubjectCard(entry.subject, entry.classes, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F1B2E)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.search,
                    color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search subject',
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(
    String subject,
    List<Map<String, dynamic>> classes,
    bool isDark,
  ) {
    final icon = _getSubjectEmoji(subject);
    final primary = const Color(0xFF7C4DFF);
    final hasMultiple = classes.length > 1;

    String classesLabel;
    if (hasMultiple) {
      classesLabel =
          'Classes ' +
          classes
              .map(
                (c) =>
                    (c['className'] as String) +
                    (c['section'].toString().isNotEmpty ? c['section'] : ''),
              )
              .join(', ');
    } else {
      final c = classes.first;
      final sec = (c['section'] as String).trim();
      classesLabel =
          'Class ${(c['className'] as String)}${sec.isNotEmpty ? sec : ''}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onSubjectTap(subject, classes),
        child: Row(
          children: [
            // Left accent border
            Container(
              width: 4,
              height: 96,
              decoration: BoxDecoration(
                color: primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            classesLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF6B7280),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SubjectEntry> _filteredSubjectEntries() {
    final entries = _subjectClasses.entries
        .map((e) => _SubjectEntry(subject: e.key, classes: e.value))
        .toList();
    entries.sort(
      (a, b) => a.subject.toLowerCase().compareTo(b.subject.toLowerCase()),
    );
    if (_searchQuery.isEmpty) return entries;
    return entries.where((entry) {
      final subjMatch = entry.subject.toLowerCase().contains(_searchQuery);
      final classesText = entry.classes
          .map((c) => (c['className'] as String) + (c['section'] as String))
          .join(' ')
          .toLowerCase();
      return subjMatch || classesText.contains(_searchQuery);
    }).toList();
  }

  void _onSubjectTap(String subject, List<Map<String, dynamic>> classes) {
    if (classes.length == 1) {
      final c = classes.first;
      _openChat(
        c['classId'] as String,
        subject,
        c['className'] as String,
        c['section'] as String,
        c['teacherName'] as String,
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Class for $subject',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final c = classes[index];
                      return ListTile(
                        leading: const Icon(Icons.class_),
                        title: Text(
                          '${c['className']} - Section ${c['section']}',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _openChat(
                            c['classId'] as String,
                            subject,
                            c['className'] as String,
                            c['section'] as String,
                            c['teacherName'] as String,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _openChat(
    String classId,
    String subject,
    String className,
    String section,
    String teacherName,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          classId: classId,
          subjectId: subject.toLowerCase().replaceAll(' ', '_'),
          subjectName: subject,
          teacherName: teacherName,
          icon: _getSubjectEmoji(subject),
          className: className,
          section: section,
        ),
      ),
    );
  }

  String _getSubjectEmoji(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return '🔢';
    if (s.contains('history')) return '📜';
    if (s.contains('physics')) return '⚡';
    if (s.contains('chem')) return '🧪';
    if (s.contains('bio')) return '🧬';
    if (s.contains('science')) return '🔬';
    if (s.contains('english')) return '📖';
    if (s.contains('computer')) return '💻';
    if (s.contains('social')) return '🌍';
    if (s.contains('physical') || s.contains('education')) return '⚽';
    return '📕';
  }
}

class _SubjectEntry {
  final String subject;
  final List<Map<String, dynamic>> classes;
  _SubjectEntry({required this.subject, required this.classes});
}
