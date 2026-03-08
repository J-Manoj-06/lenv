import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';
import '../../services/messaging_service.dart';
import '../../utils/session_manager.dart';
import 'package:intl/intl.dart';
import '../../services/whatsapp_chat_service.dart';

enum AttendanceStatus { present, absent }

class AttendanceScreen extends StatefulWidget {
  final String? initialClass;
  const AttendanceScreen({super.key, this.initialClass});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final TeacherService _teacherService = TeacherService();
  DateTime _selectedDate = DateTime.now();
  String? _selectedClass; // Combined "Standard - Section" format
  List<String> _classes = []; // List of "Standard - Section"
  List<Map<String, dynamic>> _students = [];
  Map<String, AttendanceStatus> _attendanceMap = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSubmitted = false;
  bool _isEditing = false;
  bool _isOfflineMode = false; // true when showing cached data offline
  String _offlineUserId = ''; // cached when in offline mode

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  // ── Prefs cache helpers ────────────────────────────────────────────────────
  static String _classesKey(String userId) => 'attendance_classes_$userId';
  static String _studentsKey(String userId, String cls) =>
      'attendance_students_${userId}_${cls.replaceAll(' ', '_')}';

  Future<void> _saveClasses(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_classesKey(userId), jsonEncode(_classes));
    } catch (_) {}
  }

  Future<List<String>?> _loadCachedClasses(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_classesKey(userId));
      if (raw == null) return null;
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveStudents(String userId, String cls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_studentsKey(userId, cls), jsonEncode(_students));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _loadCachedStudents(
    String userId,
    String cls,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_studentsKey(userId, cls));
      if (raw == null) return null;
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadTeacherData() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        // ✅ OFFLINE FALLBACK: load cached class list from prefs
        final session = await SessionManager.getLoginSession();
        final userId = session['userId'] as String? ?? '';
        if (userId.isNotEmpty) {
          final cachedClasses = await _loadCachedClasses(userId);
          if (cachedClasses != null && cachedClasses.isNotEmpty) {
            if (mounted) {
              setState(() {
                _classes = cachedClasses..sort();
                _selectedClass =
                    (widget.initialClass != null &&
                        cachedClasses.contains(widget.initialClass))
                    ? widget.initialClass
                    : (_classes.isNotEmpty ? _classes[0] : null);
                _isLoading = false;
                _isEditing = false;
                _isOfflineMode = true;
                _offlineUserId = userId;
              });
            }
            if (_selectedClass != null)
              await _loadStudents(offlineUserId: userId);
            return;
          }
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final teacherData = await _teacherService.getTeacherByEmail(
        currentUser.email,
      );

      if (teacherData == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Extract classes in "Standard - Section" format
      final classes = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        teacherData['sections'] ?? teacherData['section'],
        classAssignments: teacherData['classAssignments'],
      );

      setState(() {
        _classes = classes..sort();
        _selectedClass =
            (widget.initialClass != null &&
                classes.contains(widget.initialClass))
            ? widget.initialClass
            : (_classes.isNotEmpty ? _classes[0] : null);
        _isLoading = false;
        _isEditing = false;
        _isOfflineMode = false;
      });

      // ✅ Save classes to prefs for offline access
      await _saveClasses(currentUser.uid);

      if (_selectedClass != null) {
        await _loadStudents();
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStudents({String? offlineUserId}) async {
    if (_selectedClass == null) return;

    setState(() => _isLoading = true);

    try {
      // Parse standard and section from combined format "Standard - Section"
      final parts = _selectedClass!.split(' - ');
      if (parts.length < 2) {
        setState(() => _isLoading = false);
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      final schoolCode = currentUser?.instituteId ?? '';
      final userId = currentUser?.uid ?? offlineUserId ?? '';

      if (schoolCode.isEmpty) {
        // ✅ OFFLINE FALLBACK: load cached students from prefs
        if (userId.isNotEmpty) {
          final cachedStudents = await _loadCachedStudents(
            userId,
            _selectedClass!,
          );
          if (cachedStudents != null && cachedStudents.isNotEmpty) {
            final attendanceMap = <String, AttendanceStatus>{};
            for (final s in cachedStudents) {
              attendanceMap[s['id']] = AttendanceStatus.present;
            }
            if (mounted) {
              setState(() {
                _students = cachedStudents;
                _attendanceMap = attendanceMap;
                _isLoading = false;
                _isOfflineMode = true;
              });
            }
            return;
          }
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Fetch students from 'students' collection
      final selectedStandard = parts[0].trim();
      final selectedSection = parts[1].trim();

      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: 'Grade $selectedStandard')
          .where('section', isEqualTo: selectedSection)
          .get();

      final List<Map<String, dynamic>> students = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Use uid field directly from students collection (auth UID)
        final authUid =
            data['uid'] as String? ?? doc.id; // fallback to doc id if missing

        // Extract parent phone from multiple possible field names
        final parentPhone =
            (data['parentPhone'] ??
                    data['parent_contact'] ??
                    data['phoneNumber'] ??
                    '')
                .toString();

        students.add({
          'id': authUid, // canonical key (auth UID)
          'legacyId': doc.id, // for reading old attendance docs
          'name': data['studentName'] ?? data['name'] ?? 'Unknown',
          'rollNo': data['rollNo'] ?? data['studentId'] ?? '—',
          'email': data['email'] ?? '',
          'parentPhone': parentPhone,
        });
      }

      // Sort by roll number or name
      students.sort((a, b) {
        final rollA = a['rollNo'].toString();
        final rollB = b['rollNo'].toString();
        return rollA.compareTo(rollB);
      });

      // Initialize attendance map with default "present" for all
      final attendanceMap = <String, AttendanceStatus>{};
      for (var student in students) {
        attendanceMap[student['id']] =
            AttendanceStatus.present; // keyed by auth UID
      }

      setState(() {
        _students = students;
        _attendanceMap = attendanceMap;
        _isLoading = false;
        _isSubmitted = false; // reset lock before checking existing
        _isEditing = false;
        _isOfflineMode = false;
      });

      // ✅ Save students to prefs cache for offline access
      if (userId.isNotEmpty) {
        await _saveStudents(userId, _selectedClass!);
      }

      // After loading students, hydrate any existing attendance and lock if already submitted
      await _fetchExistingAttendance();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchExistingAttendance() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      final schoolCode = currentUser?.instituteId ?? '';
      if (schoolCode.isEmpty || _selectedClass == null) {
        return;
      }

      // Parse standard and section
      final parts = _selectedClass!.split(' - ');
      if (parts.length < 2) return;

      final selectedStandard = parts[0].trim();
      final selectedSection = parts[1].trim();

      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final docId =
          '${schoolCode}_${dateKey}_${selectedStandard}_$selectedSection';

      // Check if attendance document exists
      final docSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .doc(docId)
          .get();

      if (!docSnap.exists) {
        setState(() {
          _isSubmitted = false;
          _isEditing = false;
        });
        return;
      }

      // Prefill statuses; support legacy docId keys and new auth UID keys
      final data = docSnap.data();
      final studentsData = data?['students'] as Map<String, dynamic>?;
      if (studentsData != null) {
        final updatedMap = Map<String, AttendanceStatus>.from(_attendanceMap);
        for (final entry in studentsData.entries) {
          final key = entry
              .key; // could be auth UID (new) or legacy student doc id (old)
          final info = entry.value as Map<String, dynamic>;
          final status = info['status']?.toString() ?? 'present';
          AttendanceStatus mapped = switch (status) {
            'present' => AttendanceStatus.present,
            'absent' => AttendanceStatus.absent,
            _ => AttendanceStatus.present,
          };
          // Resolve auth UID: if key matches a student's canonical id use directly; else try match via legacyId
          String resolvedKey = key;
          if (!updatedMap.containsKey(key)) {
            // attempt legacy match
            final match = _students.firstWhere(
              (s) => s['legacyId'] == key,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              resolvedKey = match['id']; // use auth UID
            }
          }
          updatedMap[resolvedKey] = mapped;
        }
        setState(() {
          _attendanceMap = updatedMap;
          _isSubmitted = true;
          _isEditing = false;
        });
      }
    } catch (e) {}
  }

  Future<void> _saveAttendance() async {
    if (_isSubmitted) return;
    setState(() => _isSaving = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final teacherId = authProvider.currentUser?.uid;
      final schoolCode = authProvider.currentUser?.instituteId ?? '';

      if (teacherId == null || schoolCode.isEmpty || _selectedClass == null) {
        throw Exception('Missing teacher, school, or class information');
      }

      // Parse standard and section
      final parts = _selectedClass!.split(' - ');
      if (parts.length < 2) {
        throw Exception('Invalid class format');
      }

      final selectedStandard = parts[0].trim();
      final selectedSection = parts[1].trim();

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final docId =
          '${schoolCode}_${dateStr}_${selectedStandard}_$selectedSection';

      // Build students map keyed ONLY by auth UID (canonical)
      final studentsMap = <String, Map<String, dynamic>>{};
      for (final student in _students) {
        final authUid = student['id'] as String; // canonical key
        final status = _attendanceMap[authUid]?.name ?? 'present';
        studentsMap[authUid] = {
          'name': student['name'] ?? '',
          'rollNo': student['rollNo'] ?? '',
          'status': status,
        };
      }

      // Save as a single document
      await FirebaseFirestore.instance.collection('attendance').doc(docId).set({
        'schoolCode': schoolCode,
        'standard': selectedStandard,
        'section': selectedSection,
        'date': dateStr,
        'teacherId': teacherId,
        'timestamp': FieldValue.serverTimestamp(),
        'students':
            studentsMap, // schema: { authUid: { name, rollNo, status } }
      });

      // ✅ Update attendance percentage in each student's document
      await _updateStudentAttendancePercentages(
        schoolCode,
        selectedStandard,
        selectedSection,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance Saved Successfully ✅'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isSubmitted = true;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  /// ✅ OPTIMIZED: Calculate and update attendance percentage for all students in the class
  /// Reuses TeacherService method to reduce code duplication
  Future<void> _updateStudentAttendancePercentages(
    String schoolCode,
    String grade,
    String section,
  ) async {
    try {
      // ✅ Use shared service method to fetch attendance records once
      final attendanceDocs = await TeacherService()
          .getAttendanceRecordsForClass(schoolCode, grade, section);

      if (attendanceDocs.isEmpty) return;

      // Calculate attendance for each student
      final Map<String, Map<String, int>> studentAttendance = {};

      for (final doc in attendanceDocs) {
        final students = doc['students'] as Map<String, dynamic>?;
        if (students == null) continue;

        for (final entry in students.entries) {
          final studentId = entry.key;
          final info = entry.value as Map<String, dynamic>;
          final status = info['status']?.toString().toLowerCase() ?? 'present';

          if (!studentAttendance.containsKey(studentId)) {
            studentAttendance[studentId] = {'total': 0, 'present': 0};
          }

          studentAttendance[studentId]!['total'] =
              (studentAttendance[studentId]!['total'] ?? 0) + 1;

          if (status == 'present') {
            studentAttendance[studentId]!['present'] =
                (studentAttendance[studentId]!['present'] ?? 0) + 1;
          }
        }
      }

      // Update each student document with calculated percentage
      final batch = FirebaseFirestore.instance.batch();
      int updateCount = 0;

      for (final entry in studentAttendance.entries) {
        final studentId = entry.key;
        final total = entry.value['total'] ?? 0;
        final present = entry.value['present'] ?? 0;

        if (total > 0) {
          final percentage = ((present / total) * 100).round().clamp(0, 100);

          // Update student document
          final studentRef = FirebaseFirestore.instance
              .collection('students')
              .doc(studentId);

          batch.update(studentRef, {
            'attendance': percentage,
            'attendancePercentage': percentage,
            'attendanceLastUpdated': FieldValue.serverTimestamp(),
          });

          updateCount++;
        }
      }

      if (updateCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      // Don't throw - this is a background update, shouldn't block main flow
    }
  }

  void _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isEditing = false;
      });
      // Reload students and attendance for the new date
      await _loadStudents(
        offlineUserId: _isOfflineMode ? _offlineUserId : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A1A1A), const Color(0xFF2A2A2A)]
                : [const Color(0xFF355872), const Color(0xFF4A7A99)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              if (_isOfflineMode)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Text(
                    '📶 Offline — showing cached student list',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _buildDateSelector(),
              _buildFilters(),
              Expanded(child: _buildStudentList()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildSaveButton(),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Attendance',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    // Always display formatted date as dd MMM yyyy
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: InkWell(
        onTap: _showDatePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.expand_more, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.3),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedClass,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            icon: const Icon(Icons.expand_more, color: Colors.white),
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            hint: Text('Select Class', style: TextStyle(color: Colors.white70)),
            selectedItemBuilder: (BuildContext context) {
              return _classes.map((className) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    className,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList();
            },
            items: _classes.map((className) {
              return DropdownMenuItem<String>(
                value: className,
                child: Text(
                  className,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F0C1D),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) async {
              if (value != null && value != _selectedClass) {
                setState(() {
                  _selectedClass = value;
                  _isEditing = false;
                });
                await _loadStudents(
                  offlineUserId: _isOfflineMode ? _offlineUserId : null,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F5F8);

    if (_isLoading) {
      return Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF355872)),
        ),
      );
    }

    if (_students.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Center(
          child: Text(
            'No students found',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final student = _students[index];
          return _buildStudentCard(student);
        },
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final studentId = student['id'];
    final status = _attendanceMap[studentId] ?? AttendanceStatus.present;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(color: Colors.white.withOpacity(0.1))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${student['name']} — Roll No. ${student['rollNo']}',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F0C1D),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Message',
                onPressed: () => _openChat(student),
                icon: const Icon(Icons.chat_bubble_outline),
                color: const Color(0xFF355872),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatusButton(
                  label: 'Present',
                  isSelected: status == AttendanceStatus.present,
                  color: Colors.green,
                  onTap: (_isSubmitted && !_isEditing) || _isSaving
                      ? null
                      : () {
                          setState(() {
                            _attendanceMap[studentId] =
                                AttendanceStatus.present;
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusButton(
                  label: 'Absent',
                  isSelected: status == AttendanceStatus.absent,
                  color: Colors.red,
                  onTap: (_isSubmitted && !_isEditing) || _isSaving
                      ? null
                      : () {
                          setState(() {
                            _attendanceMap[studentId] = AttendanceStatus.absent;
                          });
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Disable save entirely when offline
    if (_isOfflineMode) {
      return Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F5F8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Offline — Cannot Save Attendance',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F5F8),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          // Show Cancel button in edit mode
          if (_isSubmitted && _isEditing)
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _isEditing = false;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_isSubmitted && _isEditing) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (_isSaving) return;
                if (_isSubmitted) {
                  if (_isEditing) {
                    _updateAttendance();
                  } else {
                    setState(() => _isEditing = true);
                  }
                } else {
                  _saveAttendance();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF355872), Color(0xFF4A7A99)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isSubmitted
                              ? (_isEditing
                                    ? 'Save Changes'
                                    : 'Edit Attendance')
                              : 'Save Attendance',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAttendance() async {
    setState(() => _isSaving = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final teacherId = authProvider.currentUser?.uid;
      final schoolCode = authProvider.currentUser?.instituteId ?? '';

      if (teacherId == null || schoolCode.isEmpty || _selectedClass == null) {
        throw Exception('Missing teacher, school, or class information');
      }

      // Parse standard and section
      final parts = _selectedClass!.split(' - ');
      if (parts.length < 2) {
        throw Exception('Invalid class format');
      }

      final selectedStandard = parts[0].trim();
      final selectedSection = parts[1].trim();

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final docId =
          '${schoolCode}_${dateStr}_${selectedStandard}_$selectedSection';

      // Build updated students map
      final studentsMap = <String, Map<String, dynamic>>{};
      for (final student in _students) {
        final studentId = student['id'] as String;
        final status = _attendanceMap[studentId]?.name ?? 'present';

        studentsMap[studentId] = {
          'name': student['name'] ?? '',
          'rollNo': student['rollNo'] ?? '',
          'status': status,
        };
      }

      final docRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(docId);

      // Use update to ensure we don't create a new doc
      await docRef.update({
        'students': studentsMap,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': teacherId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance Updated Successfully ✏️'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isEditing = false;
          _isSaving = false;
          _isSubmitted = true;
        });
      }
    } on FirebaseException catch (e) {
      // If the doc somehow doesn't exist, surface a friendly message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openChat(Map<String, dynamic> student) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final teacherId = authProvider.currentUser?.uid;

    if (teacherId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Teacher not logged in')));
      return;
    }

    // Show loading dialog (use rootNavigator: false to preserve local context)
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                const Expanded(child: Text('Finding parent contact...')),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final messagingService = MessagingService();

      // Extract all possible parent contact info from student data
      final studentId = (student['id'] ?? '').toString();
      final parentPhone =
          (student['parentPhone'] ??
                  student['parent_contact'] ??
                  student['phoneNumber'] ??
                  '')
              .toString()
              .trim();
      final studentEmail = (student['email'] ?? '').toString().trim();

      print('🔍 Fetching parent for student: $studentId');

      // Fetch parent for this student (with all available hints)
      final parentData = await messagingService.fetchParentForStudent(
        studentId,
        parentPhone: parentPhone.isEmpty ? null : parentPhone,
        studentEmail: studentEmail.isEmpty ? null : studentEmail,
      );

      print(
        '📦 Parent data received: ${parentData != null ? "Found" : "Not found"}',
      );

      if (!mounted) return;

      // Dismiss loading dialog and navigate on next frame
      Navigator.of(context).pop();

      if (!mounted) return;

      if (parentData == null) {
        print('❌ No parent found for student: ${student['name']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No parent found for ${student['name']}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Details',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Parent Not Found'),
                    content: Text(
                      'Could not locate parent for:\n\n'
                      'Student: ${student['name']}\n'
                      'Roll No: ${student['rollNo']}\n'
                      'ID: $studentId\n\n'
                      'Please ensure the parent account is created and linked to this student in Firebase.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        return;
      }

      // Build required chat params
      final authProvider2 = Provider.of<AuthProvider>(context, listen: false);
      final schoolCode = authProvider2.currentUser?.instituteId ?? '';
      String className = (student['className'] ?? '').toString();
      String? section = student['section']?.toString();
      if (className.isEmpty && _selectedClass != null) {
        final parts = _selectedClass!.split(' - ');
        if (parts.length >= 2) {
          className = 'Grade ${parts[0].trim()}';
          section = parts[1].trim();
        }
      }

      print(
        '📋 Chat params - schoolCode: $schoolCode, className: $className, section: $section',
      );

      if (schoolCode.isEmpty) {
        print('❌ School code is empty!');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('School code not available')),
        );
        return;
      }

      // Get parent phone number
      final parentPhoneNumber = parentData['phoneNumber'] as String?;
      final studentName = (student['name'] ?? 'Student').toString();

      if (parentPhoneNumber == null || parentPhoneNumber.isEmpty) {
        print('❌ Parent phone number not available');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parent phone number not available'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Directly open WhatsApp
      print('📱 Opening WhatsApp for: $studentName');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening WhatsApp...'),
          duration: Duration(seconds: 1),
        ),
      );

      final whatsappService = WhatsAppChatService();
      final success = await whatsappService.startParentWhatsAppChat(
        studentName: studentName,
        parentPhoneNumber: parentPhoneNumber,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open WhatsApp. Please make sure WhatsApp is installed.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        print('✅ WhatsApp opened successfully');
      }
    } catch (e, stackTrace) {
      print('❌ Error in _openChat: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading dialog
      }
      print('📜 Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening chat: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
