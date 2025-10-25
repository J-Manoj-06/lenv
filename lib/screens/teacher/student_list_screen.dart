import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
                _buildHeader(),
                _buildSearchBar(),
                Expanded(child: _buildStudentList()),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F8).withOpacity(0.85),
        border: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 24),
                onPressed: () => Navigator.pop(context),
                color: const Color(0xFF1F2937),
              ),
              Expanded(
                child: Text(
                  widget.className,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 40), // Spacer to balance the back button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search for a student',
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    final students = _filteredStudents;

    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
          child: _buildStudentCard(students[index]),
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

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Section: $_sectionForQuery',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_score(student)}%',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chevron icon
              Icon(Icons.chevron_right, color: Colors.grey[400]),
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
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, color: Colors.grey[600]),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case 'Top Performer':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        break;
      case 'On Track':
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        break;
      case 'Needs Attention':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        break;
      case 'Needs Help':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        break;
      default:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
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
