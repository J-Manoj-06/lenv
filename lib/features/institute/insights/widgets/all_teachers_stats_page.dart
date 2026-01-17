import 'package:flutter/material.dart';
import '../../../../services/insights/insights_repository.dart';
import '../../../../models/insights/teacher_stats_model.dart';
import './teacher_insights_details_page.dart';

class AllTeachersStatsPage extends StatefulWidget {
  const AllTeachersStatsPage({
    super.key,
    required this.schoolCode,
    required this.range,
  });

  final String schoolCode;
  final String range;

  @override
  State<AllTeachersStatsPage> createState() => _AllTeachersStatsPageState();
}

class _AllTeachersStatsPageState extends State<AllTeachersStatsPage> {
  final InsightsRepository _repository = InsightsRepository();
  bool _isLoading = true;
  TeacherStatsSummary? _teacherStats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.getTeacherStatsSummary(
        schoolCode: widget.schoolCode,
        range: widget.range,
      );
      if (mounted) {
        setState(() {
          _teacherStats = data;
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
        title: const Text('Teacher Performance'),
        backgroundColor: cardColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _teacherStats == null || _teacherStats!.teachers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: subtitleColor),
                  const SizedBox(height: 16),
                  Text(
                    'No teacher data available',
                    style: TextStyle(color: subtitleColor, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _teacherStats!.teachers.length,
              itemBuilder: (context, index) {
                final teacher = _teacherStats!.teachers[index];
                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TeacherInsightsDetailsPage(
                            teacherId: teacher.teacherId,
                            teacherName: teacher.name,
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
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF146D7A).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFF146D7A),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  teacher.name,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${teacher.totalTests} tests',
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
