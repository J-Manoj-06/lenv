import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1113),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, controller) {
            return _StaffDetailsSheet(
              staff: staff,
              controller: controller,
              primary: _primary,
              panel: _panel,
              slate: _slate400,
            );
          },
        );
      },
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

class _StaffDetailsSheet extends StatelessWidget {
  const _StaffDetailsSheet({
    required this.staff,
    required this.controller,
    required this.primary,
    required this.panel,
    required this.slate,
  });

  final _StaffMember staff;
  final ScrollController controller;
  final Color primary;
  final Color panel;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        controller: controller,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                          color: primary.withOpacity(0.2),
                          child: Icon(Icons.person, color: primary, size: 32),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        color: primary.withOpacity(0.2),
                        child: Icon(Icons.person, color: primary, size: 32),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      staff.role,
                      style: TextStyle(color: slate, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: staff.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                staff.status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Contact Information
          if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact Information',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (staff.email.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.email, color: slate, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            staff.email,
                            style: TextStyle(color: slate, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (staff.phone.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.phone, color: slate, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          staff.phone,
                          style: TextStyle(color: slate, fontSize: 13),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
            const SizedBox(height: 16),
          Row(
            children: [
              _StatTile(
                title: 'Total Tests',
                value: staff.stats.totalTests.toString(),
                panel: panel,
                slate: slate,
              ),
              const SizedBox(width: 10),
              _StatTile(
                title: 'Avg Score',
                value: '${staff.stats.avgScore}%',
                panel: panel,
                slate: slate,
              ),
              const SizedBox(width: 10),
              _StatTile(
                title: 'Students',
                value: staff.stats.studentsImpacted.toString(),
                panel: panel,
                slate: slate,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TagPanel(
                  title: 'Subjects Handled',
                  tags: staff.subjects,
                  panel: panel,
                  slate: slate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TagPanel(
                  title: 'Classes',
                  tags: staff.classes,
                  panel: panel,
                  slate: slate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TestsPanel(
            tests: staff.tests,
            panel: panel,
            slate: slate,
            primary: primary,
          ),
          const SizedBox(height: 16),
          _NotesPanel(panel: panel, slate: slate),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.panel,
    required this.slate,
  });

  final String title;
  final String value;
  final Color panel;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: slate, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPanel extends StatelessWidget {
  const _TagPanel({
    required this.title,
    required this.tags,
    required this.panel,
    required this.slate,
  });

  final String title;
  final List<String> tags;
  final Color panel;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: slate, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.isEmpty
                ? [
                    Text(
                      'No data',
                      style: TextStyle(color: slate, fontSize: 13),
                    ),
                  ]
                : tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                      .toList(),
          ),
        ],
      ),
    );
  }
}

class _TestsPanel extends StatelessWidget {
  const _TestsPanel({
    required this.tests,
    required this.panel,
    required this.slate,
    required this.primary,
  });

  final List<_TestInfo> tests;
  final Color panel;
  final Color slate;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Tests',
                style: TextStyle(color: slate, fontSize: 13),
              ),
              Text(
                'Most recent first',
                style: TextStyle(color: slate, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (tests.isEmpty)
            Text(
              'No recent tests',
              style: TextStyle(color: slate, fontSize: 13),
            )
          else
            Column(
              children: tests
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.date,
                            style: TextStyle(color: slate, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${t.avg}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _NotesPanel extends StatelessWidget {
  const _NotesPanel({required this.panel, required this.slate});

  final Color panel;
  final Color slate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes (read-only)',
            style: TextStyle(color: slate, fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text(
            'No notes available.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
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
