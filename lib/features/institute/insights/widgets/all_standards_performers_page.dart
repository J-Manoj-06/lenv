import 'package:flutter/material.dart';
import '../../../../services/insights/insights_repository.dart';
import '../../../../models/insights/top_performer_model.dart';
import './standard_top_performers_page.dart';

class AllStandardsPerformersPage extends StatefulWidget {
  const AllStandardsPerformersPage({
    super.key,
    required this.schoolCode,
    required this.range,
  });

  final String schoolCode;
  final String range;

  @override
  State<AllStandardsPerformersPage> createState() =>
      _AllStandardsPerformersPageState();
}

class _AllStandardsPerformersPageState
    extends State<AllStandardsPerformersPage> {
  final InsightsRepository _repository = InsightsRepository();
  bool _isLoading = true;
  TopPerformersSummary? _topPerformers;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.getTopPerformersSummary(
        schoolCode: widget.schoolCode,
        range: widget.range,
      );
      if (mounted) {
        setState(() {
          _topPerformers = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Top Performers'),
        backgroundColor: cardColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _topPerformers == null || _topPerformers!.standards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: subtitleColor),
                  const SizedBox(height: 16),
                  Text(
                    'No performance data available',
                    style: TextStyle(color: subtitleColor, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _topPerformers!.standards.length,
              itemBuilder: (context, index) {
                final standard = _topPerformers!.standards[index];
                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StandardTopPerformersPage(
                            standard: standard.standard,
                            schoolCode: widget.schoolCode,
                            range: widget.range,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Standard ${standard.standard}',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${standard.top3.length} top performers',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: subtitleColor),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
