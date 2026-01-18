import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
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

  bool _isAggregating = false;

  @override
  void initState() {
    super.initState();
    // Don't load data here - cards will load their own data when tapped
  }

  Future<void> _triggerAggregation() async {
    setState(() => _isAggregating = true);

    try {
      // Show progress dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _AggregationProgressDialog(),
      );

      // Trigger aggregations
      final baseUrl = 'https://insights-aggregator.giridharannj.workers.dev';

      // Run aggregations in sequence
      await http.get(Uri.parse('$baseUrl/aggregate-top-performers'));
      await http.get(Uri.parse('$baseUrl/aggregate-teacher-stats'));

      // Wait a moment for Firestore to propagate
      await Future.delayed(const Duration(seconds: 2));

      // Close dialog
      if (mounted) Navigator.of(context).pop();

      // Clear cache
      _repository.clearCaches();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Insights refreshed successfully!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error triggering aggregation: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAggregating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final authProvider = Provider.of<AuthProvider>(context);
    final schoolCode = authProvider.currentUser?.instituteId ?? '';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onRefresh: _triggerAggregation,
              isAggregating: _isAggregating,
            ),
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
  const _TopBar({required this.onRefresh, required this.isAggregating});

  final VoidCallback onRefresh;
  final bool isAggregating;

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
          const Spacer(),
          IconButton(
            onPressed: isAggregating ? null : onRefresh,
            icon: isAggregating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF146D7A),
                      ),
                    ),
                  )
                : const Icon(Icons.refresh, size: 22),
            tooltip: 'Refresh Insights (Runs Aggregation)',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF146D7A).withOpacity(0.1),
              foregroundColor: const Color(0xFF146D7A),
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
