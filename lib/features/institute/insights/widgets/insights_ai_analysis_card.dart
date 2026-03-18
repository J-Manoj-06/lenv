import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/insights/ai_report_model.dart';
import '../../../../services/insights/ai_insights_report_service.dart';

class InsightsAIAnalysisCard extends StatefulWidget {
  const InsightsAIAnalysisCard({
    super.key,
    required this.schoolCode,
    required this.range,
  });

  final String schoolCode;
  final String range;

  @override
  State<InsightsAIAnalysisCard> createState() => _InsightsAIAnalysisCardState();
}

class _InsightsAIAnalysisCardState extends State<InsightsAIAnalysisCard> {
  final AIInsightsReportService _aiService = AIInsightsReportService();
  final PageController _pageController = PageController();

  String _selectedScope = 'Whole School';
  String? _selectedStandard;
  String? _selectedSection;
  String _selectedMetric = 'Performance';

  bool _isGenerating = false;
  bool _isLoadingOptions = true;
  AIInsightsReport? _report;
  int _currentCardIndex = 0;

  final List<String> _scopes = ['Whole School', 'Standard', 'Section'];
  List<String> _standards = ['Select'];
  List<String> _sections = ['Select'];
  final List<String> _metrics = ['Performance', 'Attendance'];

  @override
  void initState() {
    super.initState();
    _loadAvailableOptions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InsightsAIAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload options if school code changed
    if (oldWidget.schoolCode != widget.schoolCode &&
        widget.schoolCode.isNotEmpty) {
      _loadAvailableOptions();
    }
  }

  Future<void> _loadAvailableOptions() async {
    // Skip if school code is empty
    if (widget.schoolCode.isEmpty) {
      setState(() => _isLoadingOptions = false);
      return;
    }

    setState(() => _isLoadingOptions = true);

    try {
      // Fetch students from the school
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      final Set<String> uniqueStandards = {};
      final Set<String> uniqueSections = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Extract standard from className
        // Handles formats: "Grade 10", "10", "10 - A - Math"
        final className = data['className'] as String?;
        if (className != null && className.isNotEmpty) {
          String grade = className;

          // Remove "Grade" prefix if present
          grade = grade.replaceAll('Grade ', '').replaceAll('grade ', '');

          // If contains dash, take first part (e.g., "10 - A - Math" -> "10")
          if (grade.contains('-')) {
            grade = grade.split('-')[0].trim();
          }

          grade = grade.trim();

          // Only add if it's a valid number
          if (grade.isNotEmpty && RegExp(r'^\d+$').hasMatch(grade)) {
            uniqueStandards.add(grade);
          }
        }

        // Extract section
        final section = data['section'] as String?;
        if (section != null && section.isNotEmpty) {
          uniqueSections.add(section.trim().toUpperCase());
        }
      }

      // Sort and update lists
      final sortedStandards = uniqueStandards.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      final sortedSections = uniqueSections.toList()..sort();

      setState(() {
        _standards = ['Select', ...sortedStandards];
        _sections = ['Select', ...sortedSections];
        _isLoadingOptions = false;
      });
    } catch (e) {
      setState(() => _isLoadingOptions = false);
    }
  }

  String _getScopeKey() {
    if (_selectedScope == 'Whole School') {
      return 'school';
    } else if (_selectedScope == 'Standard' && _selectedStandard != null) {
      return 'STD$_selectedStandard';
    } else if (_selectedScope == 'Section' &&
        _selectedStandard != null &&
        _selectedSection != null) {
      return 'STD${_selectedStandard}_$_selectedSection';
    }
    return 'school';
  }

  Future<void> _generateReport() async {
    if (widget.schoolCode.isEmpty) {
      // School code not available
      return;
    }

    setState(() {
      _isGenerating = true;
      _report = null;
    });

    try {
      final scopeKey = _getScopeKey();
      final report = await _aiService.generateReport(
        schoolCode: widget.schoolCode,
        range: widget.range,
        scopeKey: scopeKey,
        metric: _selectedMetric,
      );

      if (mounted) {
        setState(() {
          _report = report;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF146D7A), Color(0xFF0E5A66)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Analysis',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Custom insights powered by AI',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filters
                _buildFilterRow(
                  'Scope',
                  _selectedScope,
                  _scopes,
                  (val) => setState(() {
                    _selectedScope = val;
                    if (val == 'Whole School') {
                      _selectedStandard = null;
                      _selectedSection = null;
                    }
                  }),
                  textColor,
                  subtitleColor,
                  isDark,
                ),
                const SizedBox(height: 12),

                // Standard Dropdown (conditionally enabled)
                if (_selectedScope != 'Whole School')
                  _buildFilterRow(
                    'Standard',
                    _selectedStandard ?? 'Select',
                    _standards,
                    (val) => setState(() => _selectedStandard = val),
                    textColor,
                    subtitleColor,
                    isDark,
                  ),
                if (_selectedScope != 'Whole School')
                  const SizedBox(height: 12),

                // Section Dropdown (conditionally enabled)
                if (_selectedScope == 'Section' || _selectedScope == 'Class')
                  _buildFilterRow(
                    'Section',
                    _selectedSection ?? 'Select',
                    _sections,
                    (val) => setState(() => _selectedSection = val),
                    textColor,
                    subtitleColor,
                    isDark,
                  ),
                if (_selectedScope == 'Section' || _selectedScope == 'Class')
                  const SizedBox(height: 12),

                // Metric Dropdown
                _buildFilterRow(
                  'Metric',
                  _selectedMetric,
                  _metrics,
                  (val) => setState(() => _selectedMetric = val),
                  textColor,
                  subtitleColor,
                  isDark,
                ),
                const SizedBox(height: 20),

                // Generate Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isGenerating ? null : _generateReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF146D7A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isGenerating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Generate AI Report',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                // Report Display with Carousel
                if (_report != null) ...[
                  const SizedBox(height: 24),
                  _buildCarouselReport(
                    _report!,
                    textColor,
                    subtitleColor,
                    isDark,
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(
    String label,
    String selected,
    List<String> options,
    ValueChanged<String> onChanged,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: subtitleColor.withOpacity(0.2)),
          ),
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            icon: Icon(Icons.arrow_drop_down, color: subtitleColor),
            items: options.map((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCarouselReport(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Column(
      children: [
        // Carousel
        SizedBox(
          height: 420,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentCardIndex = index);
            },
            children: [
              _buildOverviewCard(report, textColor, subtitleColor, isDark),
              _buildStrengthsCard(report, textColor, subtitleColor, isDark),
              _buildWeakAreasCard(report, textColor, subtitleColor, isDark),
              _buildActionPlanCard(report, textColor, subtitleColor, isDark),
              _buildTrendCard(report, textColor, subtitleColor, isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Dot Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentCardIndex == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentCardIndex == index
                    ? const Color(0xFF146D7A)
                    : subtitleColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Swipe Hint
        if (_currentCardIndex < 4)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.swipe,
                color: subtitleColor.withOpacity(0.6),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Swipe to see more insights →',
                style: TextStyle(
                  color: subtitleColor.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // Card 1: Overview with AI Score
  Widget _buildOverviewCard(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final aiScore = _calculateAIScore(report);
    final status = _getPerformanceStatus(aiScore);
    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.white, const Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF146D7A).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF146D7A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: Color(0xFF146D7A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AI Overview',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // AI Score Display
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: aiScore / 100,
                        strokeWidth: 12,
                        backgroundColor: subtitleColor.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          aiScore.toStringAsFixed(0),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'AI Score',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(status),
                        color: statusColor,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Summary (2 lines max)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _truncateSummary(report.summary, 2),
              style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.6),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Card 2: Strengths
  Widget _buildStrengthsCard(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF064E3B), const Color(0xFF022C22)]
              : [const Color(0xFFECFDF5), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Key Strengths',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Strengths List
          Expanded(
            child: ListView.builder(
              itemCount: report.strengths.take(5).length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          report.strengths[index],
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontSize: 13,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Card 3: Weak Areas
  Widget _buildWeakAreasCard(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF7C2D12), const Color(0xFF431407)]
              : [const Color(0xFFFEF3C7), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Areas to Improve',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Weak Areas List
          Expanded(
            child: ListView.builder(
              itemCount: report.weakAreas.take(5).length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.priority_high_rounded,
                          color: Color(0xFFF59E0B),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          report.weakAreas[index],
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontSize: 13,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Card 4: Action Plan
  Widget _buildActionPlanCard(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final priorities = ['High', 'High', 'Medium'];
    final priorityColors = {
      'High': const Color(0xFFEF4444),
      'Medium': const Color(0xFFF59E0B),
      'Low': const Color(0xFF10B981),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E40AF), const Color(0xFF1E3A8A)]
              : [const Color(0xFFDCFCE7), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF146D7A).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF146D7A).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.playlist_add_check_rounded,
                  color: Color(0xFF146D7A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Action Plan',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Action Items
          Expanded(
            child: ListView.builder(
              itemCount: report.suggestedActions.take(3).length,
              itemBuilder: (context, index) {
                final priority = index < priorities.length
                    ? priorities[index]
                    : 'Low';
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: priorityColors[priority]!.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: priorityColors[priority]!.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              priority,
                              style: TextStyle(
                                color: priorityColors[priority],
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Step ${index + 1}',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        report.suggestedActions[index],
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Card 5: Trend
  Widget _buildTrendCard(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    // Mock data - replace with actual metrics
    final metrics = [
      {
        'label': 'Average Score',
        'value': 0.72,
        'color': const Color(0xFF10B981),
      },
      {'label': 'Attendance', 'value': 0.85, 'color': const Color(0xFF3B82F6)},
      {'label': 'Engagement', 'value': 0.68, 'color': const Color(0xFF8B5CF6)},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF581C87), const Color(0xFF3B0764)]
              : [const Color(0xFFFAF5FF), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.show_chart_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Performance Trends',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Progress Bars
          ...metrics.map((metric) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        metric['label'] as String,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${((metric['value'] as double) * 100).toInt()}%',
                        style: TextStyle(
                          color: metric['color'] as Color,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: metric['value'] as double,
                      backgroundColor: subtitleColor.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        metric['color'] as Color,
                      ),
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          // Improvement Suggestion
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Focus on improving engagement through interactive activities',
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  double _calculateAIScore(AIInsightsReport report) {
    // Calculate based on strengths vs weak areas
    final strengthCount = report.strengths.length;
    final weakCount = report.weakAreas.length;
    final total = strengthCount + weakCount;

    if (total == 0) return 50.0;

    final ratio = strengthCount / total;
    return (ratio * 100).clamp(0, 100);
  }

  String _getPerformanceStatus(double score) {
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Moderate';
    return 'Critical';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Good':
        return const Color(0xFF10B981);
      case 'Moderate':
        return const Color(0xFFF59E0B);
      case 'Critical':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Good':
        return Icons.check_circle_rounded;
      case 'Moderate':
        return Icons.warning_rounded;
      case 'Critical':
        return Icons.error_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  String _truncateSummary(String text, int maxLines) {
    final words = text.split(' ');
    if (words.length <= 20) return text;
    return '${words.take(20).join(' ')}...';
  }

  Widget _buildReportDisplay(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF146D7A).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Text(
            'Summary',
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            report.summary,
            style: TextStyle(color: subtitleColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Strengths
          _buildBulletSection(
            '💪 Strengths',
            report.strengths,
            textColor,
            subtitleColor,
            const Color(0xFF10B981),
          ),
          const SizedBox(height: 16),

          // Weak Areas
          _buildBulletSection(
            '⚠️ Weak Areas',
            report.weakAreas,
            textColor,
            subtitleColor,
            const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 16),

          // Suggested Actions
          _buildBulletSection(
            '🎯 Recommended Actions',
            report.suggestedActions,
            textColor,
            subtitleColor,
            const Color(0xFF146D7A),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletSection(
    String title,
    List<String> items,
    Color textColor,
    Color subtitleColor,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
