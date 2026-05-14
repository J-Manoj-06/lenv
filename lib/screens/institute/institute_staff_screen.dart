import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../providers/auth_provider.dart' as app_auth;
import '../../models/user_model.dart';
import '../../widgets/principal_dashboard_header.dart';
import '../../services/offline_cache_manager.dart';
import '../../services/network_service.dart';
import 'staff_details_page.dart';

class InstituteStaffScreen extends StatefulWidget {
  const InstituteStaffScreen({super.key});

  @override
  State<InstituteStaffScreen> createState() => _InstituteStaffScreenState();
}

class _InstituteStaffScreenState extends State<InstituteStaffScreen> {
  List<_StaffMember> _staff = [];
  bool _isLoading = true;
  String _query = '';
  String _filter = 'all';
  final OfflineCacheManager _cacheManager = OfflineCacheManager();
  final NetworkService _networkService = NetworkService();
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _networkService.initialize();
    _connectivitySub = _networkService.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      final wasOnline = _isOnline;
      setState(() {
        _isOnline = online;
      });

      // Auto-switch back to live mode and fetch fresh staff when online again.
      if (!wasOnline && online) {
        _loadStaff();
      }
    });
    _loadStaff();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _networkService.dispose();
    super.dispose();
  }

  List<_StaffMember> _staffFromCachedList(dynamic cachedData) {
    if (cachedData is! List) return const <_StaffMember>[];

    final items = <_StaffMember>[];
    for (final item in cachedData) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(item);
      final subjectsRaw = map['subjects'];
      final classesRaw = map['classes'];

      items.add(
        _StaffMember(
          id: map['id']?.toString() ?? '',
          name: map['name']?.toString() ?? 'Unknown',
          email: map['email']?.toString() ?? '',
          phone: map['phone']?.toString() ?? '',
          status: map['status']?.toString() ?? 'Active',
          role: map['role']?.toString() ?? 'Teaching',
          roleKey: map['roleKey']?.toString() ?? 'teaching',
          imageUrl: map['imageUrl']?.toString() ?? '',
          subjects: subjectsRaw is List
              ? subjectsRaw.map((e) => e.toString()).toList()
              : const <String>['Not assigned'],
          classes: classesRaw is List
              ? classesRaw.map((e) => e.toString()).toList()
              : const <String>['Not assigned'],
          tests: const <_TestInfo>[],
          stats: const _StaffStats(
            totalTests: 0,
            avgScore: 0,
            studentsImpacted: 0,
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _loadFromCache(String schoolCode) async {
    final cached = _cacheManager.getCachedUserData(
      userId: schoolCode,
      dataType: 'principal_staff',
    );
    final cachedStaff = _staffFromCachedList(cached);

    if (!mounted) return;
    setState(() {
      _staff = cachedStaff;
      _isLoading = false;
    });
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  String _normalizeGradeLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase().startsWith('grade ')) return trimmed;
    return 'Grade $trimmed';
  }

  String _displayClassLabel(String className, String section) {
    final normalizedClass = _normalizeGradeLabel(className);
    final normalizedSection = section.trim();
    if (normalizedClass.isEmpty) return '';
    if (normalizedSection.isEmpty) return normalizedClass;
    return '$normalizedClass - $normalizedSection';
  }

  Map<String, List<String>> _extractAssignments(Map<String, dynamic> data) {
    final classAssignments = _stringList(data['classAssignments']);
    final classesHandled = _stringList(data['classesHandled']);
    final sections = _stringList(data['sections'] ?? data['section']);
    final subjectsHandled = _stringList(
      data['subjectsHandled'] ?? data['subject'] ?? data['subjects'],
    );

    final classLabels = <String>{};
    final subjectLabels = <String>{};

    for (final assignment in classAssignments) {
      final parts = assignment.split(':');
      if (parts.isEmpty) continue;

      final className = parts.first.trim();
      final rhs = parts.length > 1 ? parts[1] : '';
      final rhsParts = rhs.split(',').map((e) => e.trim()).toList();
      final section = rhsParts.isNotEmpty ? rhsParts.first : '';
      final subject = rhsParts.length > 1 ? rhsParts.sublist(1).join(', ') : '';

      final classLabel = _displayClassLabel(className, section);
      if (classLabel.isNotEmpty) {
        classLabels.add(classLabel);
      }
      if (subject.isNotEmpty) {
        subjectLabels.add(subject);
      }
    }

    if (classLabels.isEmpty && classesHandled.isNotEmpty) {
      if (sections.isNotEmpty) {
        for (final className in classesHandled) {
          for (final section in sections) {
            final label = _displayClassLabel(className, section);
            if (label.isNotEmpty) {
              classLabels.add(label);
            }
          }
        }
      } else {
        for (final className in classesHandled) {
          final label = _normalizeGradeLabel(className);
          if (label.isNotEmpty) {
            classLabels.add(label);
          }
        }
      }
    }

    for (final subject in subjectsHandled) {
      if (subject.isNotEmpty) {
        subjectLabels.add(subject);
      }
    }

    return {
      'classes': classLabels.isEmpty
          ? const <String>['Not assigned']
          : (classLabels.toList()..sort()),
      'subjects': subjectLabels.isEmpty
          ? const <String>['Not assigned']
          : (subjectLabels.toList()..sort()),
    };
  }

  String _staffKeyFor(Map<String, dynamic> data, String docId) {
    final uid = (data['uid'] ?? data['teacherId'] ?? data['userId'] ?? '')
        .toString()
        .trim();
    if (uid.isNotEmpty) return 'uid:$uid';

    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty) return 'email:$email';

    return 'doc:$docId';
  }

  bool _sameSchool(Map<String, dynamic> data, String schoolCode) {
    final normalizedSchool = schoolCode.trim().toLowerCase();
    if (normalizedSchool.isEmpty) return false;

    final values = <String>{
      (data['schoolCode'] ?? '').toString().trim().toLowerCase(),
      (data['instituteId'] ?? '').toString().trim().toLowerCase(),
      (data['schoolId'] ?? '').toString().trim().toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    return values.contains(normalizedSchool);
  }

  Map<String, dynamic> _mergeStaffData(
    Map<String, dynamic> base,
    Map<String, dynamic> incoming,
  ) {
    final merged = Map<String, dynamic>.from(base);

    for (final entry in incoming.entries) {
      final value = entry.value;
      if (value == null) continue;

      if (value is List) {
        final existing = _stringList(merged[entry.key]);
        final next = value.map((e) => e.toString().trim()).toList();
        final combined = <String>{...existing, ...next}
          ..removeWhere((e) => e.isEmpty);
        if (combined.isNotEmpty) {
          merged[entry.key] = combined.toList();
        }
        continue;
      }

      final stringValue = value.toString().trim();
      final existingValue = (merged[entry.key] ?? '').toString().trim();
      if (existingValue.isEmpty && stringValue.isNotEmpty) {
        merged[entry.key] = value;
      }
    }

    return merged;
  }

  _StaffMember? _staffFromData(String fallbackId, Map<String, dynamic> data) {
    final assignments = _extractAssignments(data);
    final nameCandidates = [
      data['name'],
      data['teacherName'],
    ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty);
    final name = nameCandidates.isEmpty ? '' : nameCandidates.first;

    if (name.isEmpty) return null;

    final email = (data['email'] ?? '').toString().trim();
    final phone = (data['phone'] ?? data['mobile'] ?? '').toString().trim();
    final imageUrl =
        (data['profileImageUrl'] ??
                data['profileImage'] ??
                data['photoUrl'] ??
                '')
            .toString()
            .trim();

    return _StaffMember(
      id: fallbackId,
      name: name,
      email: email,
      phone: phone,
      status: (data['status'] ?? 'Active').toString(),
      role: (data['designation'] ?? data['roleLabel'] ?? 'Teacher').toString(),
      roleKey: (data['role'] ?? 'teacher').toString(),
      imageUrl: imageUrl,
      subjects: assignments['subjects'] ?? const <String>['Not assigned'],
      classes: assignments['classes'] ?? const <String>['Not assigned'],
      tests: const <_TestInfo>[],
      stats: const _StaffStats(totalTests: 0, avgScore: 0, studentsImpacted: 0),
    );
  }

  Future<String?> _resolveSchoolCode({
    required app_auth.AuthProvider authProvider,
    required User? firebaseUser,
    required String? fallbackSchoolCode,
  }) async {
    final directCode = authProvider.currentUser?.instituteId?.trim();
    if (directCode != null && directCode.isNotEmpty) {
      return directCode;
    }

    if (firebaseUser != null) {
      try {
        final principalDoc = await FirebaseFirestore.instance
            .collection('principals')
            .doc(firebaseUser.uid)
            .get();
        final code = principalDoc.data()?['schoolCode']?.toString().trim();
        if (code != null && code.isNotEmpty) {
          return code;
        }
      } catch (_) {}

      if (firebaseUser.email != null && firebaseUser.email!.isNotEmpty) {
        try {
          final principalQuery = await FirebaseFirestore.instance
              .collection('principals')
              .where('email', isEqualTo: firebaseUser.email)
              .limit(1)
              .get();
          final code = principalQuery.docs.isNotEmpty
              ? principalQuery.docs.first
                    .data()['schoolCode']
                    ?.toString()
                    .trim()
              : null;
          if (code != null && code.isNotEmpty) {
            return code;
          }
        } catch (_) {}
      }

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get();
        final data = userDoc.data();
        final code = (data?['schoolCode'] ?? data?['instituteId'] ?? '')
            .toString()
            .trim();
        if (code.isNotEmpty) {
          return code;
        }
      } catch (_) {}
    }

    final fallback = fallbackSchoolCode?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return null;
  }

  Future<List<_StaffMember>> _fetchStaffForSchool(String schoolCode) async {
    final firestore = FirebaseFirestore.instance;
    final usersBySchoolCode = firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('schoolCode', isEqualTo: schoolCode)
        .get();
    final usersByInstituteId = firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('instituteId', isEqualTo: schoolCode)
        .get();
    final teachersBySchoolCode = firestore
        .collection('teachers')
        .where('schoolCode', isEqualTo: schoolCode)
        .get();
    final teachersByInstituteId = firestore
        .collection('teachers')
        .where('instituteId', isEqualTo: schoolCode)
        .get();

    final results = await Future.wait([
      usersBySchoolCode,
      usersByInstituteId,
      teachersBySchoolCode,
      teachersByInstituteId,
    ]);

    final merged = <String, Map<String, dynamic>>{};

    for (final result in results) {
      for (final doc in result.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        if (!_sameSchool(data, schoolCode)) continue;

        final key = _staffKeyFor(data, doc.id);
        final current = merged[key];
        data['uid'] = (data['uid'] ?? doc.id).toString();
        merged[key] = current == null ? data : _mergeStaffData(current, data);
      }
    }

    final staff = merged.entries
        .map(
          (entry) => _staffFromData(
            entry.value['uid']?.toString() ?? entry.key,
            entry.value,
          ),
        )
        .whereType<_StaffMember>()
        .toList();

    staff.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return staff;
  }

  Future<void> _loadStaff() async {
    await _cacheManager.initialize();
    _isOnline = await _networkService.isConnected();
    if (!mounted) return;

    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final currentUser = authProvider.currentUser;
    if (currentUser == null || currentUser.role != UserRole.institute) {
      if (!mounted) return;
      setState(() {
        _staff = [];
        _isLoading = false;
      });
      return;
    }

    // Get current Firebase Auth user
    final firebaseUser = FirebaseAuth.instance.currentUser;

    String? fallbackSchoolCode = _cacheManager.getLastPrincipalSchoolCode();

    if (firebaseUser == null) {
      if (fallbackSchoolCode != null && fallbackSchoolCode.isNotEmpty) {
        await _loadFromCache(fallbackSchoolCode);
      } else {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final schoolCode = await _resolveSchoolCode(
        authProvider: authProvider,
        firebaseUser: firebaseUser,
        fallbackSchoolCode: fallbackSchoolCode,
      );

      if (schoolCode == null || schoolCode.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final staffList = await _fetchStaffForSchool(schoolCode);

      await _cacheManager.cacheUserData(
        userId: schoolCode,
        dataType: 'principal_staff',
        data: staffList
            .map(
              (s) => {
                'id': s.id,
                'name': s.name,
                'email': s.email,
                'phone': s.phone,
                'status': s.status,
                'role': s.role,
                'roleKey': s.roleKey,
                'imageUrl': s.imageUrl,
                'subjects': s.subjects,
                'classes': s.classes,
              },
            )
            .toList(),
      );

      setState(() {
        _staff = staffList;
        _isLoading = false;
      });
    } catch (e) {
      if (fallbackSchoolCode != null && fallbackSchoolCode.isNotEmpty) {
        await _loadFromCache(fallbackSchoolCode);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final chipColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final primaryColor = const Color(0xFF146D7B);
    final slateColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    // Extract unique classes from staff
    final allClasses = <String>{};
    for (var staff in _staff) {
      for (var classInfo in staff.classes) {
        if (classInfo != 'Not assigned') {
          allClasses.add(classInfo.trim());
        }
      }
    }
    final availableClasses = ['All Classes', ...allClasses.toList()..sort()];

    final filtered = _staff.where((s) {
      final matchesQuery =
          _query.isEmpty ||
          s.name.toLowerCase().contains(_query) ||
          s.subjects.any((subj) => subj.toLowerCase().contains(_query)) ||
          s.classes.any((c) => c.toLowerCase().contains(_query));

      final matchesFilter =
          _filter == 'all' ||
          s.classes.any((c) => c.toLowerCase().contains(_filter.toLowerCase()));
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            PrincipalDashboardHeader(
              title: 'Staff Directory',
              subtitle: '${_staff.length} staff members',
              icon: Icons.people_alt_rounded,
            ),
            if (!_isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.orange.shade700,
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Offline Mode - Showing cached staff list',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            _SearchFilters(
              primary: primaryColor,
              chip: chipColor,
              slate: slateColor,
              onQueryChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              onFilterChanged: (value) => setState(() => _filter = value),
              activeFilter: _filter,
              availableClasses: availableClasses,
              isDark: isDark,
              textColor: textColor,
              cardColor: cardColor,
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    )
                  : _staff.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.manage_accounts_outlined,
                              size: 54,
                              color: subtitleColor.withOpacity(0.7),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No staff found for this school yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isOnline
                                  ? 'We could not find teacher records linked to this institute. Once staff profiles are available, they will appear here.'
                                  : 'You are offline and no cached staff list is available for this school yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          ...filtered.map(
                            (s) => _StaffCard(
                              staff: s,
                              panel: cardColor,
                              slate: slateColor,
                              onTap: () => _openDetails(s),
                              isDark: isDark,
                              textColor: textColor,
                              subtitleColor: subtitleColor,
                            ),
                          ),
                          if (filtered.isEmpty && !_isLoading)
                            Padding(
                              padding: const EdgeInsets.only(top: 56),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 40,
                                    color: subtitleColor.withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No staff match your search.',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Try a different name, subject, or class filter.',
                                    style: TextStyle(color: subtitleColor),
                                  ),
                                ],
                              ),
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

  void _openDetails(_StaffMember staff) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StaffDetailsPage(
          staff: StaffMember(
            id: staff.id,
            name: staff.name,
            email: staff.email,
            phone: staff.phone,
            status: staff.status,
            role: staff.role,
            roleKey: staff.roleKey,
            imageUrl: staff.imageUrl,
            subjects: staff.subjects,
            classes: staff.classes,
            stats: StaffStats(
              totalTests: staff.stats.totalTests,
              avgScore: staff.stats.avgScore,
              studentsImpacted: staff.stats.studentsImpacted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchFilters extends StatefulWidget {
  const _SearchFilters({
    required this.primary,
    required this.chip,
    required this.slate,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.activeFilter,
    required this.availableClasses,
    required this.isDark,
    required this.textColor,
    required this.cardColor,
  });

  final Color primary;
  final Color chip;
  final Color slate;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onFilterChanged;
  final String activeFilter;
  final List<String> availableClasses;
  final bool isDark;
  final Color textColor;
  final Color cardColor;

  @override
  State<_SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<_SearchFilters> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.isNotEmpty;
      });
    });
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showClassPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: widget.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.slate.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: widget.primary, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    'Filter by Class',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.availableClasses.length,
                itemBuilder: (context, index) {
                  final classItem = widget.availableClasses[index];
                  final value = classItem == 'All Classes' ? 'all' : classItem;
                  final isSelected = value == widget.activeFilter;

                  return InkWell(
                    onTap: () {
                      widget.onFilterChanged(value);
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? widget.primary.withOpacity(0.1)
                            : Colors.transparent,
                        border: Border(
                          left: BorderSide(
                            color: isSelected
                                ? widget.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              classItem,
                              style: TextStyle(
                                color: isSelected
                                    ? widget.primary
                                    : widget.textColor,
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: widget.primary,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchBorderRadius = BorderRadius.circular(18);
    final searchBaseColor = widget.isDark
        ? const Color.fromRGBO(30, 41, 59, 0.60)
        : const Color.fromRGBO(248, 250, 252, 0.95);
    final searchFocusedColor = widget.isDark
        ? const Color.fromRGBO(43, 58, 82, 0.72)
        : Colors.white;
    final searchBorderColor = _isFocused
        ? const Color(0xFF3B82F6)
        : const Color.fromRGBO(255, 255, 255, 0.08);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            scale: _isFocused ? 1.01 : 1.0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: ClipRRect(
              borderRadius: searchBorderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _isFocused ? searchFocusedColor : searchBaseColor,
                    borderRadius: searchBorderRadius,
                    border: Border.all(
                      color: searchBorderColor,
                      width: _isFocused ? 1.25 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isDark
                            ? Colors.black.withOpacity(0.26)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                      if (_isFocused)
                        const BoxShadow(
                          color: Color.fromRGBO(59, 130, 246, 0.28),
                          blurRadius: 24,
                          spreadRadius: 1,
                          offset: Offset(0, 0),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        Icons.search_rounded,
                        color: const Color(0xFF94A3B8),
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: widget.onQueryChanged,
                          cursorColor: const Color(0xFF93C5FD),
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                            height: 1.35,
                          ),
                          decoration: const InputDecoration(
                            hintText:
                                'Search staff by name, subject, or class...',
                            hintStyle: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _hasText
                            ? GestureDetector(
                                key: const ValueKey('clear-search'),
                                onTap: () {
                                  _controller.clear();
                                  widget.onQueryChanged('');
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(
                                      148,
                                      163,
                                      184,
                                      0.16,
                                    ),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF9CA3AF),
                                    size: 16,
                                  ),
                                ),
                              )
                            : const SizedBox(width: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Class Filter Dropdown
          GestureDetector(
            onTap: () => _showClassPicker(context),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: widget.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isDark
                      ? const Color(0xFF2E3C52)
                      : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: widget.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.activeFilter == 'all'
                          ? 'All Classes'
                          : widget.activeFilter,
                      style: TextStyle(
                        color: widget.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.slate,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.panel,
    required this.slate,
    required this.onTap,
    required this.isDark,
    required this.textColor,
    required this.subtitleColor,
  });

  final _StaffMember staff;
  final Color panel;
  final Color slate;
  final VoidCallback onTap;
  final bool isDark;
  final Color textColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF146D7A);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: staff.imageUrl.isNotEmpty
                    ? Image.network(
                        staff.imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 56,
                          height: 56,
                          color: const Color(0xFF1E3A5F),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        color: const Color(0xFF1E3A5F),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            staff.name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            staff.role,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      staff.subjects.first,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (staff.classes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: staff.classes.take(3).map((className) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              className,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (staff.email.isNotEmpty || staff.phone.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        staff.email.isNotEmpty ? staff.email : staff.phone,
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: slate,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffMember {
  const _StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.status,
    required this.role,
    required this.roleKey,
    required this.imageUrl,
    required this.subjects,
    required this.classes,
    required this.tests,
    required this.stats,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String status;
  final String role;
  final String roleKey; // all | teaching | non-teaching | on-leave
  final String imageUrl;
  final List<String> subjects;
  final List<String> classes;
  final List<_TestInfo> tests;
  final _StaffStats stats;

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'in class':
        return Colors.green;
      case 'free period':
        return Colors.grey;
      case 'absent':
        return Colors.red;
      case 'on leave':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}

class _TestInfo {
  const _TestInfo({required this.title, required this.date, required this.avg});

  final String title;
  final String date;
  final int avg;
}

class _StaffStats {
  const _StaffStats({
    required this.totalTests,
    required this.avgScore,
    required this.studentsImpacted,
  });

  final int totalTests;
  final int avgScore;
  final int studentsImpacted;
}
