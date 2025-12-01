import 'package:flutter/material.dart';
import '../../models/group_subject.dart';
import '../../services/group_messaging_service.dart';
import 'group_chat_page.dart';

class GroupsListPage extends StatefulWidget {
  final String studentId;

  const GroupsListPage({super.key, required this.studentId});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage> {
  final GroupMessagingService _messagingService = GroupMessagingService();
  List<GroupSubject> _subjects = [];
  bool _isLoading = true;
  String? _classId;

  @override
  void initState() {
    super.initState();
    _loadClassSubjects();
  }

  Future<void> _loadClassSubjects() async {
    setState(() => _isLoading = true);

    try {
      // Get student's class ID from their profile
      final classId = await _messagingService.getStudentClassId(
        widget.studentId,
      );

      if (classId == null) {
        setState(() {
          _subjects = [];
          _isLoading = false;
          _classId = null;
        });
        return;
      }

      _classId = classId;

      // Fetch subjects from classes/{classId}/subjects collection
      final subjects = await _messagingService.getClassSubjects(classId);

      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8800)),
      );
    }

    if (_classId == null) {
      return const Center(
        child: Text(
          'Unable to determine your class.\nPlease contact your administrator.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (_subjects.isEmpty) {
      return const Center(
        child: Text(
          'No subject groups available yet.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _subjects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final subject = _subjects[index];
        return _SubjectGroupCard(
          subject: subject,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatPage(
                  classId: _classId!,
                  subjectId: subject.id,
                  subjectName: subject.name,
                  teacherName: subject.teacherName,
                  icon: subject.icon,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SubjectGroupCard extends StatelessWidget {
  final GroupSubject subject;
  final VoidCallback onTap;

  const _SubjectGroupCard({required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Subject Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
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
                children: [
                  Text(
                    subject.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Class Group',
                    style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Teacher: ${subject.teacherName}',
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow Icon
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white30,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
