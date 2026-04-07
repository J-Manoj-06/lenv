import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/insights/ai_report_model.dart';
import '../../../../models/insights/insights_metrics_model.dart';
import '../../../../services/insights/ai_insights_report_service.dart';
import '../../../../services/insights/insights_repository.dart';

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
  final InsightsRepository _repository = InsightsRepository();

  String _selectedScope = 'Whole School';
  String? _selectedStandard;
  String? _selectedSection;

  bool _isGenerating = false;
  bool _isLoadingOptions = true;
  AIInsightsReport? _report;
  InsightsMetrics? _latestMetrics;
  String? _statusMessage;

  final List<String> _scopes = ['Whole School', 'Standard', 'Section'];
  List<String> _standards = ['Select'];
  List<String> _sections = ['Select'];

  @override
  void initState() {
    super.initState();
    _loadAvailableOptions();
  }

  @override
  void didUpdateWidget(InsightsAIAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolCode != widget.schoolCode &&
        widget.schoolCode.isNotEmpty) {
      _loadAvailableOptions();
    }
  }

  Future<void> _loadAvailableOptions() async {
    if (widget.schoolCode.isEmpty) {
      setState(() => _isLoadingOptions = false);
      return;
    }

    setState(() => _isLoadingOptions = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      final Set<String> uniqueStandards = {};
      final Set<String> uniqueSections = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final className = data['className'] as String?;
        if (className != null && className.isNotEmpty) {
          String grade = className;
          grade = grade.replaceAll('Grade ', '').replaceAll('grade ', '');
          if (grade.contains('-')) {
            grade = grade.split('-')[0].trim();
          }
          grade = grade.trim();
          if (grade.isNotEmpty && RegExp(r'^\d+$').hasMatch(grade)) {
            uniqueStandards.add(grade);
          }
        }

        final section = data['section'] as String?;
        if (section != null && section.isNotEmpty) {
          uniqueSections.add(section.trim().toUpperCase());
        }
      }

      final sortedStandards = uniqueStandards.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      final sortedSections = uniqueSections.toList()..sort();

      if (!mounted) return;
      setState(() {
        _standards = ['Select', ...sortedStandards];
        _sections = ['Select', ...sortedSections];
        _isLoadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOptions = false);
    }
  }

  String _getScopeKey() {
    if (_selectedScope == 'Whole School') {
      return 'school';
    }

    if (_selectedScope == 'Standard' &&
        _selectedStandard != null &&
        _selectedStandard != 'Select') {
      return 'STD$_selectedStandard';
    }

    if (_selectedScope == 'Section' &&
        _selectedStandard != null &&
        _selectedStandard != 'Select' &&
        _selectedSection != null &&
        _selectedSection != 'Select') {
      return 'STD${_selectedStandard}_$_selectedSection';
    }

    return 'school';
  }

  bool get _canGenerate {
    if (_isLoadingOptions || widget.schoolCode.isEmpty) return false;
    if (_selectedScope == 'Standard') {
      return _selectedStandard != null && _selectedStandard != 'Select';
    }
    if (_selectedScope == 'Section') {
      return _selectedStandard != null &&
          _selectedStandard != 'Select' &&
          _selectedSection != null &&
          _selectedSection != 'Select';
    }
    return true;
  }

  Future<void> _generateReport() async {
    if (!_canGenerate) return;

    setState(() {
      _isGenerating = true;
      _statusMessage = null;
      _report = null;
    });

    try {
      final scopeKey = _getScopeKey();

      final metrics = await _repository.getInsightsMetrics(
        schoolCode: widget.schoolCode,
        range: widget.range,
        scopeKey: scopeKey,
        forceRefresh: true,
      );

      if (metrics == null) {
        if (!mounted) return;
        setState(() {
          _latestMetrics = null;
          _report = null;
          _statusMessage =
              'No completed test data found for this selection. Run tests and try again.';
          _isGenerating = false;
        });
        return;
      }

      final report = await _aiService.generateReport(
        schoolCode: widget.schoolCode,
        range: widget.range,
        scopeKey: scopeKey,
        metric: 'Performance',
      );

      if (!mounted) return;
      setState(() {
        _latestMetrics = metrics;
        _report = report;
        _statusMessage = report == null
            ? 'Unable to generate report right now. Please try again.'
            : null;
        _isGenerating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _statusMessage =
            'Unable to generate report right now. Please try again.';
      });
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        'Real performance insights from current test data',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildFilterRow(
              'Scope',
              _selectedScope,
              _scopes,
              (val) => setState(() {
                _selectedScope = val;
                _statusMessage = null;
                _report = null;
                if (val == 'Whole School') {
                  _selectedStandard = null;
                  _selectedSection = null;
                } else if (val == 'Standard') {
                  _selectedSection = null;
                }
              }),
              textColor,
              subtitleColor,
              isDark,
            ),
            const SizedBox(height: 12),

            if (_selectedScope != 'Whole School') ...[
              _buildFilterRow(
                'Standard',
                _selectedStandard ?? 'Select',
                _standards,
                (val) => setState(() {
                  _selectedStandard = val;
                  _statusMessage = null;
                  _report = null;
                  if (_selectedScope == 'Section') {
                    _selectedSection = null;
                  }
                }),
                textColor,
                subtitleColor,
                isDark,
              ),
              const SizedBox(height: 12),
            ],

            if (_selectedScope == 'Section') ...[
              _buildFilterRow(
                'Section',
                _selectedSection ?? 'Select',
                _sections,
                (val) => setState(() {
                  _selectedSection = val;
                  _statusMessage = null;
                  _report = null;
                }),
                textColor,
                subtitleColor,
                isDark,
              ),
              const SizedBox(height: 12),
            ],

            _buildReadOnlyMetric(textColor, subtitleColor, isDark),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isGenerating || !_canGenerate)
                    ? null
                    : _generateReport,
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

            if (_statusMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _statusMessage!,
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
            ],

            if (_report != null) ...[
              const SizedBox(height: 18),
              _buildSimpleReport(_report!, textColor, subtitleColor, isDark),
            ],
          ],
        ),
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
            items: options
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyMetric(
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Metric',
          style: TextStyle(
            color: subtitleColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: subtitleColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                size: 18,
                color: Color(0xFF146D7A),
              ),
              const SizedBox(width: 8),
              Text(
                'Performance',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleReport(
    AIInsightsReport report,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final scopeLabel = _selectedScope == 'Whole School'
        ? 'Whole School'
        : _selectedScope == 'Standard'
        ? 'Standard ${_selectedStandard ?? '-'}'
        : 'Standard ${_selectedStandard ?? '-'} • Section ${_selectedSection ?? '-'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF146D7A).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Report',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scope: $scopeLabel',
            style: TextStyle(color: subtitleColor, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Updated: ${report.generatedAt.toLocal()}',
            style: TextStyle(color: subtitleColor, fontSize: 12),
          ),
          const SizedBox(height: 14),

          if (_latestMetrics != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetricChip(
                  'Avg Score ${_latestMetrics!.avgScore.toStringAsFixed(1)}%',
                  isDark,
                  subtitleColor,
                ),
                _buildMetricChip(
                  '${_latestMetrics!.testCount} tests',
                  isDark,
                  subtitleColor,
                ),
                _buildMetricChip(
                  '${_latestMetrics!.weakStudentsCount} weak students',
                  isDark,
                  subtitleColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          _buildSection('Summary', [report.summary], textColor, subtitleColor),
          const SizedBox(height: 12),
          _buildSection(
            'What is going well',
            report.strengths,
            textColor,
            subtitleColor,
          ),
          const SizedBox(height: 12),
          _buildSection(
            'Needs attention',
            report.weakAreas,
            textColor,
            subtitleColor,
          ),
          const SizedBox(height: 12),
          _buildSection(
            'Action plan',
            report.suggestedActions,
            textColor,
            subtitleColor,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, bool isDark, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: subtitleColor.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: subtitleColor,
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<String> lines,
    Color textColor,
    Color subtitleColor,
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
        const SizedBox(height: 6),
        ...lines
            .take(4)
            .map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: Color(0xFF146D7A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
