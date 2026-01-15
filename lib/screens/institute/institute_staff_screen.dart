import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'staff_details_page.dart';

class InstituteStaffScreen extends StatefulWidget {
  const InstituteStaffScreen({super.key});

  @override
  State<InstituteStaffScreen> createState() => _InstituteStaffScreenState();
}

class _InstituteStaffScreenState extends State<InstituteStaffScreen> {
  static const Color _bg = Color(0xFF0F1416);
  static const Color _panel = Color(0xFF1E293B);
  static const Color _chip = Color(0xFF334155);
  static const Color _primary = Color(0xFF146D7B);
  static const Color _accent = Color(0xFF6A5AE0);
  static const Color _slate400 = Color(0xFF94A3B8);

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
    final filtered = _staff.where((s) {
      final matchesQuery =
          _query.isEmpty ||
          s.name.toLowerCase().contains(_query) ||
          s.subjects.any((subj) => subj.toLowerCase().contains(_query)) ||
          s.classes.any((c) => c.toLowerCase().contains(_query));
      final matchesFilter = _filter == 'all' || s.roleKey == _filter;
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              primary: _primary,
              accent: _accent,
              bg: _bg,
              slate: _slate400,
              totalStaff: _staff.length,
            ),
            _SearchFilters(
              primary: _primary,
              chip: _chip,
              slate: _slate400,
              onQueryChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              onFilterChanged: (value) => setState(() => _filter = value),
              activeFilter: _filter,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary),
                    )
                  : _staff.isEmpty
                  ? Center(
                      child: Text(
                        'No staff found in this school',
                        style: TextStyle(color: Colors.grey[400]),
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
                              panel: _panel,
                              slate: _slate400,
                              onTap: () => _openDetails(s),
                            ),
                          ),
                          if (filtered.isEmpty && !_isLoading)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Text(
                                'No staff match your search.',
                                style: TextStyle(color: Colors.grey[400]),
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
  });

  final Color primary;
  final Color accent;
  final Color bg;
  final Color slate;
  final int totalStaff;

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
                const Text(
                  'Staff Directory',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalStaff staff members',
                  style: TextStyle(color: slate, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFilters extends StatelessWidget {
  const _SearchFilters({
    required this.primary,
    required this.chip,
    required this.slate,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.activeFilter,
  });

  final Color primary;
  final Color chip;
  final Color slate;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onFilterChanged;
  final String activeFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: slate, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: onQueryChanged,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by name, subject or class...',
                      hintStyle: TextStyle(color: slate),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: [
                _FilterChip(
                  label: 'All',
                  value: 'all',
                  active: activeFilter == 'all',
                  primary: primary,
                  chip: chip,
                  slate: slate,
                  onTap: () => onFilterChanged('all'),
                ),
                _FilterChip(
                  label: 'Teaching',
                  value: 'teaching',
                  active: activeFilter == 'teaching',
                  primary: primary,
                  chip: chip,
                  slate: slate,
                  onTap: () => onFilterChanged('teaching'),
                ),
                _FilterChip(
                  label: 'Non-Teaching',
                  value: 'non-teaching',
                  active: activeFilter == 'non-teaching',
                  primary: primary,
                  chip: chip,
                  slate: slate,
                  onTap: () => onFilterChanged('non-teaching'),
                ),
                _FilterChip(
                  label: 'On Leave',
                  value: 'on-leave',
                  active: activeFilter == 'on-leave',
                  primary: primary,
                  chip: chip,
                  slate: slate,
                  onTap: () => onFilterChanged('on-leave'),
                ),
              ],
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
  });

  final _StaffMember staff;
  final Color panel;
  final Color slate;
  final VoidCallback onTap;

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
                        errorBuilder: (_, __, ___) => Container(
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
                      style: const TextStyle(
                        color: Colors.white,
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
                            style: TextStyle(color: slate, fontSize: 13),
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
