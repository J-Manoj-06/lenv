import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
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

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    // Get current Firebase Auth user
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Get the principal's schoolCode from principals collection using Firebase UID
      String? schoolCode;

      final principalDoc = await FirebaseFirestore.instance
          .collection('principals')
          .doc(firebaseUser.uid)
          .get();

      if (principalDoc.exists) {
        schoolCode = principalDoc.data()?['schoolCode']?.toString();
      }

      // If not found by UID, try by email
      if ((schoolCode == null || schoolCode.isEmpty) &&
          firebaseUser.email != null) {
        final principalQuery = await FirebaseFirestore.instance
            .collection('principals')
            .where('email', isEqualTo: firebaseUser.email)
            .limit(1)
            .get();

        if (principalQuery.docs.isNotEmpty) {
          schoolCode = principalQuery.docs.first
              .data()['schoolCode']
              ?.toString();
        }
      }

      if (schoolCode == null || schoolCode.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Now query the users collection for teachers with matching schoolCode
      final teachersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('schoolCode', isEqualTo: schoolCode)
          .get();

      final staffList = <_StaffMember>[];

      for (final doc in teachersSnap.docs) {
        final data = doc.data();
        final name =
            data['name']?.toString() ??
            data['teacherName']?.toString() ??
            'Unknown';
        final email = data['email']?.toString() ?? '';
        final phone = data['phone']?.toString() ?? '';
        final photoUrl =
            data['photoUrl']?.toString() ??
            data['profileImage']?.toString() ??
            '';

        // Get class assignments from the users collection format
        final classAssignments =
            (data['classAssignments'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        staffList.add(
          _StaffMember(
            id: doc.id,
            name: name,
            email: email,
            phone: phone,
            status: 'Active',
            role: 'Teaching',
            roleKey: 'teaching',
            imageUrl: photoUrl,
            subjects: classAssignments.isNotEmpty
                ? classAssignments
                : ['Not assigned'],
            classes: classAssignments.isNotEmpty
                ? classAssignments
                : ['Not assigned'],
            tests: [],
            stats: const _StaffStats(
              totalTests: 0,
              avgScore: 0,
              studentsImpacted: 0,
            ),
          ),
        );
      }

      setState(() {
        _staff = staffList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
    final accentColor = const Color(0xFF6A5AE0);
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
          // Extract just the grade part (e.g., "Grade 10" from "Grade 10: A, Math")
          final parts = classInfo.split(':');
          if (parts.isNotEmpty) {
            allClasses.add(parts[0].trim());
          }
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
            _Header(
              primary: primaryColor,
              accent: accentColor,
              bg: bgColor,
              slate: slateColor,
              totalStaff: _staff.length,
              isDark: isDark,
              textColor: textColor,
              subtitleColor: subtitleColor,
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
                      child: Text(
                        'No staff found in this school',
                        style: TextStyle(color: subtitleColor),
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
                              padding: const EdgeInsets.only(top: 40),
                              child: Text(
                                'No staff match your search.',
                                style: TextStyle(color: subtitleColor),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.primary,
    required this.accent,
    required this.bg,
    required this.slate,
    required this.totalStaff,
    required this.isDark,
    required this.textColor,
    required this.subtitleColor,
  });

  final Color primary;
  final Color accent;
  final Color bg;
  final Color slate;
  final int totalStaff;
  final bool isDark;
  final Color textColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.92),
        border: const Border(
          bottom: BorderSide(color: Colors.white24, width: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [accent, primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.people, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff Directory',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalStaff staff members',
                  style: TextStyle(color: subtitleColor, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.active,
    required this.primary,
    required this.chip,
    required this.slate,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final Color primary;
  final Color chip;
  final Color slate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? primary : chip,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : slate,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
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
    final statusColor = staff.statusColor;

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
          ),
          child: Row(
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
                    Text(
                      staff.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${staff.status} • ${staff.subjects.join(', ')}',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
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
