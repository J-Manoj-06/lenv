import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/parent_provider.dart';
import 'parent_chat_screen.dart';

class ParentMessagesScreen extends StatefulWidget {
  const ParentMessagesScreen({super.key});

  @override
  State<ParentMessagesScreen> createState() => _ParentMessagesScreenState();
}

class _ParentMessagesScreenState extends State<ParentMessagesScreen> {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filteredTeachers = [];
  bool _isLoading = true;
  bool _queuedReload = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTeachers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTeachers = _teachers;
      } else {
        _filteredTeachers = _teachers.where((teacher) {
          final name = (teacher['name'] as String? ?? '').toLowerCase();
          final subject = (teacher['subject'] as String? ?? '').toLowerCase();
          return name.contains(query) || subject.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadTeachers() async {
    setState(() => _isLoading = true);

    try {
      final parentProvider = Provider.of<ParentProvider>(
        context,
        listen: false,
      );

      if (!parentProvider.hasChildren) {
        setState(() {
          _isLoading = false;
          _teachers = [];
          _filteredTeachers = [];
        });
        return;
      }

      final Set<String> teacherIds = {};
      final List<Map<String, dynamic>> teachersList = [];

      // Get all children's class info
      for (final child in parentProvider.children) {
        if (child.className != null && child.schoolCode != null) {
          final studentClass = child.className!;
          final studentSection = child.section ?? '';

          print(
            '🔍 Looking for teachers for: $studentClass, Section: $studentSection, School: ${child.schoolCode}',
          );

          // Fetch teachers for this school
          final teachersSnapshot = await FirebaseFirestore.instance
              .collection('teachers')
              .where('schoolCode', isEqualTo: child.schoolCode)
              .get();

          // If no docs in teachers collection, try legacy users collection
          final docsToScan = teachersSnapshot.docs.isNotEmpty
              ? teachersSnapshot.docs
              : (await FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'teacher')
                        .where('schoolCode', isEqualTo: child.schoolCode)
                        .get())
                    .docs;

          print('📚 Scanning ${docsToScan.length} teacher docs');

          for (final doc in docsToScan) {
            final data = doc.data();
            final teacherId = doc.id;

            // Check if teacher teaches this child's class
            final classAssignments =
                (data['classAssignments'] as List?) ??
                (data['classes'] as List?);

            if (classAssignments != null) {
              // classAssignments format: ["Grade 10: A, math", "Grade 9: B, science"]
              bool teachesThisClass = false;
              String? teacherSubject;

              for (final assignment in classAssignments) {
                final assignmentStr = assignment.toString();
                // Parse "Grade 10: A, math"
                if (assignmentStr.contains(':')) {
                  final parts = assignmentStr.split(':');
                  final className = parts[0].trim();

                  if (parts.length > 1) {
                    final secondPart = parts[1].trim();
                    final subParts = secondPart.split(',');
                    final section = subParts.length > 0
                        ? subParts[0].trim()
                        : '';
                    final subject = subParts.length > 1
                        ? subParts[1].trim()
                        : '';

                    // Check if matches student's class and section
                    if (className == studentClass &&
                        (studentSection.isEmpty || section == studentSection)) {
                      teachesThisClass = true;
                      teacherSubject = subject;
                      break;
                    }
                  }
                }
              }

              if (teachesThisClass && !teacherIds.contains(teacherId)) {
                teacherIds.add(teacherId);
                final teacherName =
                    data['teacherName'] ?? data['name'] ?? 'Unknown Teacher';
                print('✅ Added teacher: $teacherName - $teacherSubject');

                teachersList.add({
                  'id': teacherId,
                  'name': teacherName,
                  'email': data['email'] ?? '',
                  'subject': teacherSubject ?? 'General',
                  'className': studentClass,
                  'profileImage': data['profileImage'],
                });
              }
            }
          }
        }
      }

      print('📋 Total unique teachers found: ${teachersList.length}');

      // Sort by name
      teachersList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      setState(() {
        _teachers = teachersList;
        _filteredTeachers = teachersList;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading teachers: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: isDark ? backgroundDark : Colors.white,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0.5,
      ),
      body: Consumer<ParentProvider>(
        builder: (context, parentProvider, child) {
          // If children just finished loading, auto-load teachers once
          if (parentProvider.hasChildren &&
              _teachers.isEmpty &&
              !_isLoading &&
              !_queuedReload) {
            _queuedReload = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _queuedReload = false;
              _loadTeachers();
            });
          }

          if (!parentProvider.hasChildren) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No children found',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Search Bar
              _buildSearchBar(isDark),

              // Teachers List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            parentGreen,
                          ),
                        ),
                      )
                    : _filteredTeachers.isEmpty
                    ? _buildEmptyState(isDark)
                    : RefreshIndicator(
                        onRefresh: _loadTeachers,
                        color: parentGreen,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _filteredTeachers.length,
                          itemBuilder: (context, index) {
                            final teacher = _filteredTeachers[index];
                            return _buildTeacherCard(isDark, teacher);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? backgroundDark : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : textPrimary),
        decoration: InputDecoration(
          hintText: 'Search teachers...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1A2F) : backgroundLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherCard(bool isDark, Map<String, dynamic> teacher) {
    final name = teacher['name'] as String;
    final subject = teacher['subject'] as String;
    final className = teacher['className'] as String?;
    final profileImage = teacher['profileImage'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentChatScreen(
                teacherId: teacher['id'] as String,
                teacherName: name,
                teacherSubject: subject,
                teacherAvatarUrl: teacher['profileImage'] as String?,
                className: className ?? '',
                section: Provider.of<ParentProvider>(
                  context,
                  listen: false,
                ).selectedChild?.section,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Profile Picture
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      parentGreen.withOpacity(0.8),
                      parentGreen.withOpacity(0.4),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: parentGreen.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: profileImage != null
                    ? ClipOval(
                        child: Image.network(
                          profileImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.person, color: Colors.white, size: 28),
                        ),
                      )
                    : const Icon(Icons.person, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),

              // Teacher Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: parentGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subject,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: parentGreen,
                            ),
                          ),
                        ),
                        if (className != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            className,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Message Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: parentGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.message_outlined,
                  color: parentGreen,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: parentGreen.withOpacity(0.1),
            ),
            child: Icon(
              Icons.search_off,
              size: 60,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty
                ? 'No teachers found'
                : 'No teachers match your search',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _searchController.text.isEmpty
                  ? 'Teachers will appear here when your children are assigned to classes'
                  : 'Try searching with a different keyword',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
