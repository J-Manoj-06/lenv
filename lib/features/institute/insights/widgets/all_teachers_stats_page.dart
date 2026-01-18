import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './teacher_insights_details_page.dart';

class AllTeachersStatsPage extends StatefulWidget {
  const AllTeachersStatsPage({
    super.key,
    required this.schoolCode,
    required this.range,
  });

  final String schoolCode;
  final String range;

  @override
  State<AllTeachersStatsPage> createState() => _AllTeachersStatsPageState();
}

class _AllTeachersStatsPageState extends State<AllTeachersStatsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filteredTeachers = [];
  final TextEditingController _searchController = TextEditingController();
  String? _selectedStandard;
  List<String> _availableStandards = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Get all teachers in the school from users collection
      final teacherSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();

      final List<Map<String, dynamic>> teachers = [];

      for (var doc in teacherSnapshot.docs) {
        final teacherData = doc.data();

        // Fetch name from teacherName field (primary), then name, then displayName
        String teacherName = '';
        if (teacherData['teacherName'] != null &&
            (teacherData['teacherName'] as String).isNotEmpty) {
          teacherName = teacherData['teacherName'];
        } else if (teacherData['name'] != null &&
            (teacherData['name'] as String).isNotEmpty) {
          teacherName = teacherData['name'];
        } else if (teacherData['displayName'] != null &&
            (teacherData['displayName'] as String).isNotEmpty) {
          teacherName = teacherData['displayName'];
        } else if (teacherData['email'] != null &&
            (teacherData['email'] as String).isNotEmpty) {
          teacherName = teacherData['email'].split('@')[0]; // Use email prefix
        } else {
          teacherName = 'Teacher'; // Last resort
        }

        // IMPORTANT: Use the 'uid' field from the document if it exists (Firebase Auth UID)
        // Otherwise fall back to the document ID
        final authUid = teacherData['uid'] as String?;
        final firestoreDocId = doc.id;

        teachers.add({
          'uid': authUid ?? firestoreDocId, // Use Auth UID if available
          'docId': firestoreDocId, // Keep doc ID as backup
          'name': teacherName,
          'email': teacherData['email'] ?? '',
          'totalTests': 0, // Default to 0
          'classesHandled': [],
          'section': '',
        });
      }

      // Debug: Print first few teachers with their UIDs
      print('DEBUG: First 3 teachers with UIDs:');
      for (var teacher in teachers.take(3)) {
        print('  - Name: "${teacher['name']}", UID: "${teacher['uid']}", Email: "${teacher['email']}"');
      }

      // Fetch unique classes from students collection
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      print('DEBUG: Found ${studentsSnapshot.docs.length} students');

      // Extract unique class names and map teachers to classes via students
      final Set<String> classNamesSet = {};
      final Map<String, Set<String>> teacherToClassesMap = {};

      for (var student in studentsSnapshot.docs) {
        final className = student.data()['className'] as String?;
        final classTeacher = student.data()['classTeacher'] as String?;
        final section = student.data()['section'] as String?;

        if (className != null && className.isNotEmpty) {
          classNamesSet.add(className);
        }

        // Map teacher to class via classTeacher field
        if (classTeacher != null &&
            classTeacher.isNotEmpty &&
            className != null &&
            className.isNotEmpty) {
          // Find teacher ID that matches this name
          for (var teacher in teachers) {
            if ((teacher['name'] as String).toLowerCase().contains(
                  classTeacher.toLowerCase(),
                ) ||
                classTeacher.toLowerCase().contains(
                  (teacher['name'] as String).toLowerCase(),
                )) {
              teacherToClassesMap.putIfAbsent(
                teacher['uid'] as String,
                () => {},
              );
              teacherToClassesMap[teacher['uid'] as String]!.add(className);
            }
          }
        }
      }

      // Update teachers with their classes
      for (var teacher in teachers) {
        final classes = teacherToClassesMap[teacher['uid']] ?? <String>{};
        teacher['classesHandled'] = classes.toList()..sort();
      }

      // Get test data from testResults collection (where actual test data is stored)
      // Query testResults by schoolCode to get all tests conducted
      final testResultsSnapshot = await FirebaseFirestore.instance
          .collection('testResults')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .where('status', isEqualTo: 'completed')
          .get();

      print(
        'DEBUG: Found ${testResultsSnapshot.docs.length} completed test results for schoolCode: ${widget.schoolCode}',
      );

      // Track unique tests per teacher
      final Map<String, Set<String>> teacherTestsMap = {};
      final Set<String> uniqueTeacherIds = {};

      // Debug: Print sample test result structure
      if (testResultsSnapshot.docs.isNotEmpty) {
        final sampleData = testResultsSnapshot.docs.first.data();
        print('DEBUG: Sample testResult fields: ${sampleData.keys.toList()}');
        print('DEBUG: Sample teacherId value: "${sampleData['teacherId']}"');
        print('DEBUG: Sample teacherEmail value: "${sampleData['teacherEmail']}"');
        print('DEBUG: Sample teacherName value: "${sampleData['teacherName']}"');
      }

      // Debug: Print teacher UIDs we're looking for
      print('DEBUG: Teacher UIDs from users collection:');
      for (var teacher in teachers.take(5)) {
        print('  - UID: "${teacher['uid']}", Name: "${teacher['name']}"');
      }

      for (var result in testResultsSnapshot.docs) {
        final resultData = result.data();
        final teacherId = resultData['teacherId'] as String?;
        final teacherEmail = resultData['teacherEmail'] as String?;
        final className = resultData['className'] as String?;
        final testId = resultData['testId'] as String?;

        if (teacherId != null) {
          uniqueTeacherIds.add(teacherId);
        }

        if (className != null && className.isNotEmpty) {
          classNamesSet.add(className);
        }

        // Map teacher to unique tests and classes
        if (teacherId != null && testId != null) {
          // Track unique test IDs for each teacher
          teacherTestsMap.putIfAbsent(teacherId, () => {});
          teacherTestsMap[teacherId]!.add(testId);
        }
      }

      print('DEBUG: Unique teacherIds in testResults: ${uniqueTeacherIds.toList()}');

      // Update teacher test counts based on unique test IDs
      // Try multiple matching strategies: UID, docId, email
      int matchedCount = 0;
      for (var teacher in teachers) {
        final teacherUid = teacher['uid'] as String;
        final teacherDocId = teacher['docId'] as String?;
        final teacherEmail = teacher['email'] as String?;
        
        int uniqueTests = 0;
        
        // Strategy 1: Match by UID (Firebase Auth UID)
        uniqueTests = teacherTestsMap[teacherUid]?.length ?? 0;
        
        // Strategy 2: If no match, try by document ID
        if (uniqueTests == 0 && teacherDocId != null && teacherDocId != teacherUid) {
          uniqueTests = teacherTestsMap[teacherDocId]?.length ?? 0;
          if (uniqueTests > 0) {
            print('DEBUG: Matched teacher "${teacher['name']}" by docId: $teacherDocId');
          }
        }
        
        // Strategy 3: If still no match, try by email
        if (uniqueTests == 0 && teacherEmail != null) {
          for (var entry in teacherTestsMap.entries) {
            // Check if this teacherId matches the email
            if (entry.key == teacherEmail) {
              uniqueTests = entry.value.length;
              print('DEBUG: Matched teacher "${teacher['name']}" by email: $teacherEmail');
              break;
            }
          }
        }
        
        teacher['totalTests'] = uniqueTests;
        if (uniqueTests > 0) matchedCount++;
      }
      
      print('DEBUG: Matched $matchedCount teachers with tests');
      print('DEBUG: Teacher test count summary:');
      for (var teacher in teachers.where((t) => (t['totalTests'] as int) > 0)) {
        print('  - ${teacher['name']}: ${teacher['totalTests']} tests');
      }

      // Also get class info from scheduledTests for additional metadata
      try {
        final scheduledTestsSnapshot = await FirebaseFirestore.instance
            .collection('scheduledTests')
            .where('schoolCode', isEqualTo: widget.schoolCode)
            .get();

        print(
          'DEBUG: Found ${scheduledTestsSnapshot.docs.length} scheduled tests',
        );

        for (var test in scheduledTestsSnapshot.docs) {
          final testData = test.data();
          final className = testData['className'] as String?;
          final teacherId = testData['teacherId'] as String?;

          if (className != null && className.isNotEmpty) {
            classNamesSet.add(className);
          }

          // Map teacher to classes they handle
          if (teacherId != null) {
            for (var teacher in teachers) {
              if (teacher['uid'] == teacherId) {
                final classes = teacher['classesHandled'] as List<dynamic>;
                if (className != null &&
                    className.isNotEmpty &&
                    !classes.contains(className)) {
                  classes.add(className);
                }
                break;
              }
            }
          }
        }
      } catch (e) {
        print('DEBUG: Error fetching scheduledTests: $e');
      }

      // Filter out teachers with no tests conducted
      final teachersWithTests = teachers.where((teacher) {
        final totalTests = teacher['totalTests'] as int;
        return totalTests > 0;
      }).toList();

      print('DEBUG: ${teachersWithTests.length} out of ${teachers.length} teachers have conducted tests');

      final standards = classNamesSet.toList()..sort();
      print('DEBUG: Found ${standards.length} unique standards: $standards');

      if (mounted) {
        setState(() {
          _teachers = teachersWithTests;
          _availableStandards = standards;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading teachers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = _teachers;

    // Note: The class filter is for UI organization only, all teachers are shown regardless
    // since all teachers can teach in any class

    // Filter by search query only
    if (_searchController.text.isNotEmpty) {
      result = result
          .where(
            (teacher) => (teacher['name'] as String).toLowerCase().contains(
              _searchController.text.toLowerCase(),
            ),
          )
          .toList();
      print(
        'DEBUG: After search filter "${_searchController.text}": ${result.length} teachers',
      );
    }

    setState(() {
      _filteredTeachers = result;
    });
  }

  void _filterTeachers(String query) {
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Teacher Performance'),
        backgroundColor: cardColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Standard Filter Chips
          if (_availableStandards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // All Standards chip
                    FilterChip(
                      label: Text(
                        'All',
                        style: TextStyle(
                          color: _selectedStandard == null
                              ? Colors.white
                              : textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: _selectedStandard == null
                          ? const Color(0xFF146D7A)
                          : cardColor,
                      side: BorderSide(
                        color: _selectedStandard == null
                            ? const Color(0xFF146D7A)
                            : subtitleColor.withOpacity(0.3),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedStandard = null;
                        });
                        _applyFilters();
                      },
                    ),
                    const SizedBox(width: 8),
                    // Individual standard chips
                    ..._availableStandards.map(
                      (standard) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            standard,
                            style: TextStyle(
                              color: _selectedStandard == standard
                                  ? Colors.white
                                  : textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: _selectedStandard == standard
                              ? const Color(0xFF146D7A)
                              : cardColor,
                          side: BorderSide(
                            color: _selectedStandard == standard
                                ? const Color(0xFF146D7A)
                                : subtitleColor.withOpacity(0.3),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedStandard = standard;
                            });
                            _applyFilters();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'No class standards available',
                style: TextStyle(color: subtitleColor, fontSize: 14),
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterTeachers,
              decoration: InputDecoration(
                hintText: 'Search teachers...',
                hintStyle: TextStyle(color: subtitleColor),
                prefixIcon: Icon(Icons.search, color: subtitleColor),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: subtitleColor),
                        onPressed: () {
                          _searchController.clear();
                          _filterTeachers('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: subtitleColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: subtitleColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF146D7A),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFF1F5F9),
              ),
              style: TextStyle(color: textColor),
            ),
          ),
          // Teachers list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _teachers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: subtitleColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No teachers found',
                          style: TextStyle(color: subtitleColor, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : _filteredTeachers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: subtitleColor),
                        const SizedBox(height: 16),
                        Text(
                          'No teachers match your search',
                          style: TextStyle(color: subtitleColor, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredTeachers.length,
                    itemBuilder: (context, index) {
                      final teacher = _filteredTeachers[index];
                      return Card(
                        color: cardColor,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    TeacherInsightsDetailsPage(
                                      teacherId: teacher['uid'],
                                      teacherName: teacher['name'],
                                      schoolCode: widget.schoolCode,
                                      range: widget.range,
                                    ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF146D7A,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Color(0xFF146D7A),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        teacher['name'],
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${teacher['totalTests']} tests',
                                        style: TextStyle(
                                          color: subtitleColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: subtitleColor,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
