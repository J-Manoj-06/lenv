import 'package:flutter/material.dart';

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

  final List<_StaffMember> _staff = _sampleStaff;
  String _query = '';
  String _filter = 'all';

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
              child: SingleChildScrollView(
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
                    if (filtered.isEmpty)
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: _primary,
        onPressed: () {},
        child: const Icon(Icons.person_add, color: Colors.white, size: 28),
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
  });

  final Color primary;
  final Color accent;
  final Color bg;
  final Color slate;

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
              child: Text(
                'L',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Institute — Staff Directory',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Principal view — read-only',
                  style: TextStyle(color: slate, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Settings',
              style: TextStyle(color: Colors.white, fontSize: 13),
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
                child: Image.network(
                  staff.imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
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
                        Expanded(
                          child: Text(
                            '${staff.status} • ${staff.subjects.join(', ')}',
                            style: TextStyle(color: slate, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    staff.classes.join(', '),
                    style: TextStyle(color: slate, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tests: ${staff.stats.totalTests}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                child: Image.network(
                  staff.imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
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
                    const SizedBox(height: 4),
                    Text(
                      '${staff.role} • ${staff.status}',
                      style: TextStyle(color: slate, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
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
        return Colors.blueGrey;
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

const List<_StaffMember> _sampleStaff = [
  _StaffMember(
    id: 't1',
    name: 'Dr. Evelyn Reed',
    status: 'In Class',
    role: 'Teaching',
    roleKey: 'teaching',
    imageUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuCnpmTw_w7LHywfRsGObzxL1E8SgXBJZOex7whDPocViAOVh8b_05d3p0bq68MJLwERXOph5U8l48-F2VSwAf9wsI8_qFrGfWNzQbHlhBtIgjoTp1l3wFWmOMgzFtTxrRsxTD2J_S5eTduwDWLNdwYe-d6T0Tz68CXfZrI55-bKNCmoVMM_IwTfN__3Nj9vVC7VD_-sd_lxeZhlhDoif8DsakW18AFGU81o-770Ntzm_upN5aW0a0M9DlkRvzrqtdjFk6kFxsWvS43g',
    subjects: ['Mathematics', 'Physics'],
    classes: ['10-A', '11-B'],
    tests: [
      _TestInfo(title: 'Algebra Unit Test', date: '2025-11-01', avg: 78),
      _TestInfo(title: 'Newton Laws Quiz', date: '2025-10-10', avg: 74),
    ],
    stats: _StaffStats(totalTests: 12, avgScore: 76, studentsImpacted: 120),
  ),
  _StaffMember(
    id: 't2',
    name: 'Mr. Samuel Chen',
    status: 'Free Period',
    role: 'Teaching',
    roleKey: 'teaching',
    imageUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuCB-QAXoWBzwUeP6UXdYjm9_H_ZiA0aZuZNgoHsKQdr2P14uH2Buh-cozvqsF0irNPBfDz2zJCShKLFvl_Nbeb3vxTU97A7tIi9M5GaHZ3nlzx79HJUiy0KqxGFBj_lFPGvUVBKVvauomkVAYaTRRiC9e6ZMCO0byMaINXNlHBIoygDjoKDSPAoySV664yqtmoddekjpnSej3CPksg-f7X53DiD8TTLaZ4S2-aPJcxICbLiFmWWJOMJ2i-bPlShp2jVGnS6PfaQhWZU',
    subjects: ['English', 'Computer Science'],
    classes: ['9-C'],
    tests: [
      _TestInfo(title: 'Comprehension Quiz', date: '2025-10-25', avg: 81),
    ],
    stats: _StaffStats(totalTests: 5, avgScore: 80, studentsImpacted: 30),
  ),
  _StaffMember(
    id: 't3',
    name: 'Ms. Anika Patel',
    status: 'Absent',
    role: 'Teaching',
    roleKey: 'on-leave',
    imageUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuCo47qOnpla-Qmgvn_hYN1TPZNL9gB5Ugq5-Ji9KFSnyB1eIQtNG56CztBhBOGhsyARlsDA6m1-cM6cjYw4Tsp9xk7LRktqXqyKC0WP6zAR5SXQozpA1C2GoPXq7yOLLcKILu70RxFdS2paipTd15PMAe0Ebw89sj-FH5mNwSTPODnqQTtRP-SDXvGT4_QorUEPCl8ChiPNRxGsynyYuvf-IiN6vlAkkMJbGPNgSAldDBGyKNwIuwtVf-_cGqcwVqMBItciPUVt-u3J',
    subjects: ['Biology'],
    classes: ['10-A'],
    tests: const [],
    stats: _StaffStats(totalTests: 0, avgScore: 0, studentsImpacted: 0),
  ),
  _StaffMember(
    id: 't4',
    name: 'Mr. David Lee',
    status: 'In Class',
    role: 'Non-Teaching',
    roleKey: 'non-teaching',
    imageUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuAJVobfsfvRPh1HKbUTe-ntjPG-X5mOj6WiRvu4tn3xi6FW96RxBgzoKJWetALHp4DsVQZ8RznlCunugAObFWh7lRrJJfHPDSroZeme7Kg4D1dMtnUl46gQpyA1iYbbH6Li1V-a7HHA9XdHtadNK36CdSATGRw6G9_4E5plNmCm3zZ0hXvSdrBHc_gAnCvirWs0P5EuDL62xZYgoXs-Hnxs-ADxKHMdnSvf6Xkd9mxDBx1oO8P7kE2ZxUomA-PrSeZ4vJKkOFHOo9CG',
    subjects: const [],
    classes: ['Support'],
    tests: const [],
    stats: _StaffStats(totalTests: 0, avgScore: 0, studentsImpacted: 0),
  ),
];
