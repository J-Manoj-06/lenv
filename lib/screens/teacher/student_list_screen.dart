import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';
import '../../widgets/teacher_bottom_nav.dart';

class StudentListScreen extends StatefulWidget {
  final String className;

  const StudentListScreen({Key? key, required this.className})
    : super(key: key);

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _searchController = TextEditingController();

  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _students = [];

  // Parsed from widget.className (e.g., "Grade 4 - A")
  late final String _classNameForQuery; // e.g., "Grade 4"
  late final String _sectionForQuery; // e.g., "A"

  @override
  void initState() {
    super.initState();
    _parseArgs();
    _loadStudents();
  }

  void _parseArgs() {
    // Expect formats like: "Grade 4 - A" or "Grade 4-A"
    final raw = widget.className.trim();
    final parts = raw.split(' - ');
    if (parts.length == 2) {
      _classNameForQuery = parts[0].trim(); // keep "Grade 4" exactly
      _sectionForQuery = parts[1].trim();
    } else {
      // Fallback: try removing leading "Grade " and take last token as section
      _sectionForQuery = raw.split('-').last.trim();
      final gradePart = raw.split('-').first.trim();
      _classNameForQuery = gradePart.startsWith('Grade')
          ? gradePart
          : 'Grade ${gradePart}';
    }
  }

  Future<void> _loadStudents() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'No user logged in';
          _isLoading = false;
        });
        return;
      }

      // We only need school id and to pass a single class (e.g., ["Grade 4"]) and a single section (e.g., "A")
      final schoolId = currentUser.instituteId ?? '';
      final students = await _teacherService.getStudentsByTeacher(schoolId, [
        _classNameForQuery,
      ], _sectionForQuery);

      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load students: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _students;

    return _students.where((s) {
      final name = _displayName(s).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadStudents,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildHeader(theme),
                // Center the content area on wide screens
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: [
                          _buildSearchBar(theme),
                          Expanded(child: _buildStudentList(theme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const TeacherBottomNav(selectedIndex: 1),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.95),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 24),
                    onPressed: () => Navigator.pop(context),
                    color: theme.iconTheme.color,
                  ),
                  Expanded(
                    child: Text(
                      widget.className,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 40,
                  ), // Spacer to balance the back button
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search for a student',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          filled: true,
          fillColor: theme.cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList(ThemeData theme) {
    final students = _filteredStudents;

    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.iconTheme.color?.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildStudentCard(theme, students[index]),
        );
      },
    );
  }

  String _displayName(Map<String, dynamic> s) {
    final first = (s['firstName'] ?? '').toString().trim();
    final last = (s['lastName'] ?? '').toString().trim();
    final fallback = [first, last].where((e) => e.isNotEmpty).join(' ').trim();
    return (s['name'] ?? s['studentName'] ?? s['fullName'] ?? fallback)
        .toString()
        .trim();
  }

  int _score(Map<String, dynamic> s) {
    final v = s['score'] ?? s['averageScore'] ?? 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  String? _avatar(Map<String, dynamic> s) {
    return (s['imageUrl'] ?? s['photoUrl'] ?? s['avatar'])?.toString();
  }

  Widget _buildStudentCard(ThemeData theme, Map<String, dynamic> student) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          _viewStudentDetails(student);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Student avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child:
                    (_avatar(student) != null && _avatar(student)!.isNotEmpty)
                    ? Image.network(
                        _avatar(student)!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _avatarPlaceholder();
                        },
                      )
                    : _avatarPlaceholder(),
              ),
              const SizedBox(width: 16),
              // Student info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(student),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Section: $_sectionForQuery',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_score(student)}%',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chevron icon
              Icon(
                Icons.chevron_right,
                color: theme.iconTheme.color?.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
      ),
    );
  }

  void _viewStudentDetails(Map<String, dynamic> student) {
    Navigator.pushNamed(
      context,
      '/student-performance',
      arguments: {
        'name': _displayName(student),
        'class': widget.className,
        'imageUrl': _avatar(student) ?? '',
        'score': _score(student),
        'studentId': (student['id'] ?? '').toString(),
      },
    );
  }
}
