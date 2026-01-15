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
    return Scaffold(
      backgroundColor: _bgDark,
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
                    // 3 KPI Cards only
                    _KPIGrid(),
                    const SizedBox(height: 32),

                    // One Main Chart
                    _MainChart(),
                    const SizedBox(height: 32),

                    // Subject Performance (simplified chips)
                    _SubjectPerformanceSection(),
                    const SizedBox(height: 32),

                    // Recent Tests (only 2)
                    _RecentTests(),
                    const SizedBox(height: 32),

                    // Standards (collapsible)
                    _StandardsList(),
                    const SizedBox(height: 16),
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

// ============================================
// HEADER / TOP BAR (Simplified)
// ============================================
class _TopBar extends StatelessWidget {
  const _TopBar({required this.selectedRange, required this.onRangeChanged});

  final String selectedRange;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _bgDark,
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Institute Insights',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'School overview & trends',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.download_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
                style: IconButton.styleFrom(backgroundColor: _cardDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RangeToggle(selected: selectedRange, onTap: onRangeChanged),
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['7d', '30d', 'Monthly']
            .map(
              (r) => GestureDetector(
                onTap: () => onTap(r.toLowerCase()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected == r.toLowerCase()
                        ? _primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    r,
                    style: TextStyle(
                      color: selected == r.toLowerCase()
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 13,
                      fontWeight: selected == r.toLowerCase()
                          ? FontWeight.w600
                          : FontWeight.w400,
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

// ============================================
// KPI GRID (3 cards only, bigger spacing)
// ============================================
class _KPIGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: const [
        _KPICard(
          label: 'Total Students',
          value: '1,234',
          change: '+4%',
          isPositive: true,
        ),
        _KPICard(
          label: 'Attendance',
          value: '91%',
          change: '+2%',
          isPositive: true,
        ),
        _KPICard(
          label: 'Avg Score',
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
      padding: const EdgeInsets.all(16),
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Text(
                change,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// MAIN CHART (One clean chart with mini stats)
// ============================================
class _MainChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Class Average Trend',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Last 30 days performance',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 20),
          // Chart placeholder (shorter)
          Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary.withOpacity(0.2), _primary.withOpacity(0.05)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Chart Placeholder',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          // Mini stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniStat(label: 'Min', value: '56%'),
              Container(width: 1, height: 24, color: Colors.white10),
              _MiniStat(label: 'Max', value: '92%'),
              Container(width: 1, height: 24, color: Colors.white10),
              _MiniStat(label: 'Avg', value: '78%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================
// SUBJECT PERFORMANCE (Horizontal chips)
// ============================================
class _SubjectPerformanceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Score distribution by subject',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _SubjectChip(label: 'Math', percentage: '25%', color: _primary),
              _SubjectChip(label: 'Science', percentage: '22%', color: _accent),
              _SubjectChip(
                label: 'English',
                percentage: '18%',
                color: _positive,
              ),
              _SubjectChip(
                label: 'Social',
                percentage: '15%',
                color: Color(0xFF8B5CF6),
              ),
              _SubjectChip(
                label: 'Hindi',
                percentage: '12%',
                color: Color(0xFFEC4899),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.label,
    required this.percentage,
    required this.color,
  });

  final String label;
  final String percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text('•', style: TextStyle(color: color.withOpacity(0.5))),
          const SizedBox(width: 6),
          Text(
            percentage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// RECENT TESTS (Only 2 tests + View All button)
// ============================================
class _RecentTests extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Tests',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: Row(
                children: const [
                  Text(
                    'View all',
                    style: TextStyle(
                      color: _primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, color: _primary, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TestCard(
          icon: Icons.calculate_outlined,
          iconColor: _primary,
          title: 'Math Weekly Test',
          subtitle: 'Standard 10 • Nov 18, 2025',
          avgScore: '78%',
        ),
        const SizedBox(height: 12),
        _TestCard(
          icon: Icons.science_outlined,
          iconColor: _accent,
          title: 'Science Quiz',
          subtitle: 'Standard 9 • Nov 16, 2025',
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
      padding: const EdgeInsets.all(16),
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
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avgScore,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Avg',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// STANDARDS LIST (Collapsible/Expandable)
// ============================================
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
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap to view sections and performance',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subjects,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.avgScore}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Avg',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                  size: 24,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white10),
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
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
                  const SizedBox(height: 3),
                  Text(
                    'Teacher: ${section.teacher}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${section.avg}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Att: ${section.attendance}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
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

// ============================================
// SECTION DETAIL SCREEN (unchanged backend)
// ============================================
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

// ============================================
// DATA MODELS (unchanged)
// ============================================
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
