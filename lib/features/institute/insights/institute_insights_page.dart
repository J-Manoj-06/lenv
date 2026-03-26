import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/insights/insights_repository.dart';
import './widgets/insights_top_performers_card.dart';
import './widgets/insights_teacher_performance_card.dart';
import './widgets/insights_ai_analysis_card.dart';

class InstituteInsightsPage extends StatefulWidget {
  const InstituteInsightsPage({super.key});

  @override
  State<InstituteInsightsPage> createState() => _InstituteInsightsPageState();
}

class _InstituteInsightsPageState extends State<InstituteInsightsPage> {
  final InsightsRepository _repository = InsightsRepository();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF8FAFC);
    final authProvider = Provider.of<AuthProvider>(context);
    final schoolCode = authProvider.currentUser?.instituteId ?? '';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card 1: Top Performers
                    InsightsTopPerformersCard(schoolCode: schoolCode),
                    const SizedBox(height: 16),

                    // Card 2: Teacher Performance
                    InsightsTeacherPerformanceCard(schoolCode: schoolCode),
                    const SizedBox(height: 16),

                    // Card 3: AI Analysis
                    InsightsAIAnalysisCard(
                      schoolCode: schoolCode,
                      range:
                          '30d', // Keep for AI analysis backward compatibility
                    ),
                    const SizedBox(height: 24),
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
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'School Insights',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregationProgressDialog extends StatelessWidget {
  const _AggregationProgressDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF146D7A)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aggregating Data...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Processing test results and calculating insights.\nThis may take 5-10 seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
