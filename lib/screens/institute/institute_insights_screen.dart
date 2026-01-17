import 'package:flutter/material.dart';

const Color _bgDark = Color(0xFF0F1416);
const Color _cardDark = Color(0xFF15171B);
const Color _primary = Color(0xFF146D7A); // institute teal
const Color _accent = Color(0xFFFFA726);
const Color _positive = Color(0xFF34D399);
const Color _negative = Color(0xFFFB7185);

class InstituteInsightsScreen extends StatefulWidget {
  const InstituteInsightsScreen({super.key});

  @override
  State<InstituteInsightsScreen> createState() =>
      _InstituteInsightsScreenState();
}

class _InstituteInsightsScreenState extends State<InstituteInsightsScreen> {
  String _selectedRange = '7d';

  @override
  Widget build(BuildContext context) {
    // Theme detection
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? _bgDark : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              selectedRange: _selectedRange,
              onRangeChanged: (val) => setState(() => _selectedRange = val),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChartsRow(),
                    const SizedBox(height: 24),
                    _RecentTests(),
                    const SizedBox(height: 24),
                    _StandardsList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.selectedRange, required this.onRangeChanged});

  final String selectedRange;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgDark.withOpacity(0.95),
        border: const Border(
          bottom: BorderSide(color: Colors.white12, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [_primary, _accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Text(
                'L',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'School Insights',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RangeToggle(selected: selectedRange, onTap: onRangeChanged),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.download, color: Colors.white70),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.selected, required this.onTap});

  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: ['7d', '30d', 'monthly']
            .map(
              (r) => GestureDetector(
                onTap: () => onTap(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected == r
                        ? _primary.withOpacity(0.8)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    r,
                    style: TextStyle(
                      color: selected == r ? Colors.white : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _KPIGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: const [
        _KPICard(
          label: 'Total Students',
          value: '1,234',
          change: '+4%',
          isPositive: true,
        ),
        _KPICard(
          label: 'Total Teachers',
          value: '68',
          change: 'Stable',
          isPositive: null,
        ),
        _KPICard(
          label: "Today's Attendance",
          value: '91%',
          change: '+2%',
          isPositive: true,
        ),
        _KPICard(
          label: 'Avg Test Score',
          value: '78%',
          change: '-1%',
          isPositive: false,
        ),
      ],
    );
  }
}

class _KPICard extends StatelessWidget {
  const _KPICard({
    required this.label,
    required this.value,
    required this.change,
    this.isPositive,
  });

  final String label;
  final String value;
  final String change;
  final bool? isPositive;

  @override
  Widget build(BuildContext context) {
    final color = isPositive == null
        ? Colors.white54
        : (isPositive! ? _positive : _negative);
    final icon = isPositive == null
        ? Icons.minimize
        : (isPositive! ? Icons.arrow_upward : Icons.arrow_downward);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Text(change, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Class Average — Last 30 days',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Weighted average across all classes',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primary.withOpacity(0.3),
                      _primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Chart Placeholder',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  Text(
                    'Min: 56%',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    'Max: 92%',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    'Avg: 78%',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Subject Performance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Share of average scores by subject',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _SubjectTag(color: _primary, label: 'Math', value: '25%'),
                  const SizedBox(width: 12),
                  _SubjectTag(color: _accent, label: 'Science', value: '22%'),
                  const SizedBox(width: 12),
                  _SubjectTag(color: _positive, label: 'English', value: '18%'),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Average by class (sample)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _ClassBar(className: '10-A', value: 82),
              const SizedBox(height: 8),
              _ClassBar(className: '10-B', value: 75),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectTag extends StatelessWidget {
  const _SubjectTag({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

class _ClassBar extends StatelessWidget {
  const _ClassBar({required this.className, required this.value});

  final String className;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            className,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(999),
            ),
            child: FractionallySizedBox(
              widthFactor: value / 100,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primary, _accent.withOpacity(0.8)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(
            '$value%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _RecentTests extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Tests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _TestCard(
          icon: Icons.science,
          iconColor: _primary,
          title: 'Math Weekly Test — Std 10',
          subtitle: 'Nov 18, 2025 — Algebra & Geometry',
          avgScore: '78%',
        ),
        const SizedBox(height: 10),
        _TestCard(
          icon: Icons.menu_book,
          iconColor: _accent,
          title: 'Science Quiz — Std 9',
          subtitle: 'Nov 16, 2025 — Physics',
          avgScore: '84%',
        ),
      ],
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.avgScore,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String avgScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avgScore,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Avg Score',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StandardsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Standards & Sections',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap a standard to expand sections and view quick KPIs per section',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _StandardCard(
          standardNum: '10',
          title: 'Standard 10',
          subjects: 'Math, Science, English',
          avgScore: 81,
          sections: _sampleSections10,
        ),
        const SizedBox(height: 12),
        _StandardCard(
          standardNum: '9',
          title: 'Standard 9',
          subjects: 'Math, Science, Social',
          avgScore: 76,
          sections: _sampleSections9,
        ),
      ],
    );
  }
}

class _StandardCard extends StatefulWidget {
  const _StandardCard({
    required this.standardNum,
    required this.title,
    required this.subjects,
    required this.avgScore,
    required this.sections,
  });

  final String standardNum;
  final String title;
  final String subjects;
  final int avgScore;
  final List<_SectionData> sections;

  @override
  State<_StandardCard> createState() => _StandardCardState();
}

class _StandardCardState extends State<_StandardCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [_primary, _accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.standardNum,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
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
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subjects,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Avg Score',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.avgScore}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.chevron_right,
                  color: Colors.white70,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            ...widget.sections.map((s) => _SectionRow(section: s)),
          ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});

  final _SectionData section;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SectionDetailScreen(section: section),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1113),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Teacher: ${section.teacher}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Avg: ${section.avg}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Attendance: ${section.attendance}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SectionDetailScreen extends StatefulWidget {
  const _SectionDetailScreen({required this.section});

  final _SectionData section;

  @override
  State<_SectionDetailScreen> createState() => _SectionDetailScreenState();
}

class _SectionDetailScreenState extends State<_SectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardDark,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.section.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Teacher: ${widget.section.teacher}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Average Score',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.section.avg}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Attendance',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.section.attendance}%',
                            style: const TextStyle(
                              color: _positive,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Subject Performance',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.section.subjects.map(
              (s) => _SubjectPerformanceRow(subject: s),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectPerformanceRow extends StatelessWidget {
  const _SubjectPerformanceRow({required this.subject});

  final _SubjectPerformance subject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                subject.name,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                '${subject.score}%',
                style: TextStyle(
                  color: _primary.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(999),
            ),
            child: FractionallySizedBox(
              widthFactor: subject.score / 100,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_primary, _accent]),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionData {
  const _SectionData({
    required this.name,
    required this.teacher,
    required this.avg,
    required this.attendance,
    required this.subjects,
  });

  final String name;
  final String teacher;
  final int avg;
  final int attendance;
  final List<_SubjectPerformance> subjects;
}

class _SubjectPerformance {
  const _SubjectPerformance({required this.name, required this.score});

  final String name;
  final int score;
}

const List<_SectionData> _sampleSections10 = [
  _SectionData(
    name: 'Section A',
    teacher: 'Ms. Anika',
    avg: 83,
    attendance: 92,
    subjects: [
      _SubjectPerformance(name: 'Math', score: 82),
      _SubjectPerformance(name: 'Science', score: 76),
      _SubjectPerformance(name: 'English', score: 88),
    ],
  ),
  _SectionData(
    name: 'Section B',
    teacher: 'Mr. David',
    avg: 79,
    attendance: 89,
    subjects: [
      _SubjectPerformance(name: 'Math', score: 74),
      _SubjectPerformance(name: 'Science', score: 80),
      _SubjectPerformance(name: 'English', score: 90),
    ],
  ),
  _SectionData(
    name: 'Section C',
    teacher: 'Ms. Priya',
    avg: 80,
    attendance: 90,
    subjects: [
      _SubjectPerformance(name: 'Math', score: 78),
      _SubjectPerformance(name: 'Science', score: 82),
      _SubjectPerformance(name: 'English', score: 85),
    ],
  ),
];

const List<_SectionData> _sampleSections9 = [
  _SectionData(
    name: 'Section A',
    teacher: 'Mr. Karthik',
    avg: 78,
    attendance: 90,
    subjects: [
      _SubjectPerformance(name: 'Math', score: 80),
      _SubjectPerformance(name: 'Science', score: 75),
      _SubjectPerformance(name: 'Social', score: 79),
    ],
  ),
  _SectionData(
    name: 'Section B',
    teacher: 'Ms. Radha',
    avg: 74,
    attendance: 88,
    subjects: [
      _SubjectPerformance(name: 'Math', score: 72),
      _SubjectPerformance(name: 'Science', score: 76),
      _SubjectPerformance(name: 'Social', score: 74),
    ],
  ),
];
