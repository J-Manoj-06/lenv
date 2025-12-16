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

class _GroupsListPageState extends State<GroupsListPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final GroupMessagingService _messagingService = GroupMessagingService();
  List<GroupSubject> _subjects = [];
  bool _isLoading = true;
  String? _classId;
  bool _hasAttemptedLoad = false;

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

  Future<void> _loadClassSubjects() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    _hasAttemptedLoad = true;

    try {
      // Use studentId directly (already authenticated from AuthProvider)
      final studentUid = widget.studentId;

      if (studentUid.isEmpty) {
        print('❌ GroupsListPage: studentId is empty');
        if (!mounted) return;
        setState(() {
          _subjects = [];
          _isLoading = false;
          _classId = null;
        });
        return;
      }

      print(
        '📱 GroupsListPage: Loading class subjects for student: $studentUid',
      );

      // Get student's class ID from their profile (checks students collection first)
      final classId = await _messagingService.getStudentClassId(studentUid);

      if (!mounted) return;

      if (classId == null) {
        print('❌ GroupsListPage: No class ID found for student: $studentUid');
        setState(() {
          _subjects = [];
          _isLoading = false;
          _classId = null;
        });
        return;
      }

      _classId = classId;
      print('✅ GroupsListPage: Found classId: $classId');

      // Fetch subjects from classes/{classId}/subjects collection
      final subjects = await _messagingService.getClassSubjects(classId);

      if (!mounted) return;

      print('✅ GroupsListPage: Loaded ${subjects.length} subjects');
      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('❌ GroupsListPage error: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const orange = Color(0xFFF97316);

    if (_isLoading) {
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

    if (_classId == null) {
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
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
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
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Teacher: ${subject.teacherName}',
                    style: TextStyle(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow Icon
            Icon(
              Icons.arrow_forward_ios,
              color: theme.iconTheme.color?.withOpacity(0.35),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
