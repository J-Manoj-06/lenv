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

  String _selectedScope = 'Whole School';
  String? _selectedStandard;
  String? _selectedSection;
  String _selectedMetric = 'Performance';

  bool _isGenerating = false;
  bool _isLoadingOptions = true;
  AIInsightsReport? _report;

  final List<String> _scopes = ['Whole School', 'Standard', 'Section'];
  List<String> _standards = ['Select'];
  List<String> _sections = ['Select'];
  final List<String> _metrics = [
    'Performance',
    'Attendance',
    'Participation',
    'Weak Subjects',
    'Improvement',
  ];

  @override
  void initState() {
    super.initState();
    _loadAvailableOptions();
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
      print('⚠️ Skipping load: School code is empty');
      setState(() => _isLoadingOptions = false);
      return;
    }

    setState(() => _isLoadingOptions = true);

    try {
      print(
        '🔍 Loading standards and sections for school: ${widget.schoolCode}',
      );

      // Fetch students from the school
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      print('📋 Found ${snapshot.docs.length} students');

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

      print('✅ Found standards: $sortedStandards');
      print('✅ Found sections: $sortedSections');

      setState(() {
        _standards = ['Select', ...sortedStandards];
        _sections = ['Select', ...sortedSections];
        _isLoadingOptions = false;
      });
    } catch (e) {
      print('❌ Error loading options: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School code not available')),
      );
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
      print('❌ Error generating report: $e');
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate report')),
        );
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

                // Report Display
                if (_report != null) ...[
                  const SizedBox(height: 24),
                  _buildReportDisplay(
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
