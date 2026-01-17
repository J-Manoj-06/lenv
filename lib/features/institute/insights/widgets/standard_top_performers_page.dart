import 'package:flutter/material.dart';
import '../../../../services/insights/insights_repository.dart';
import '../../../../models/insights/top_performer_model.dart';

class StandardTopPerformersPage extends StatefulWidget {
  const StandardTopPerformersPage({
    super.key,
    required this.standard,
    required this.schoolCode,
    required this.range,
  });

  final String standard;
  final String schoolCode;
  final String range;

  @override
  State<StandardTopPerformersPage> createState() =>
      _StandardTopPerformersPageState();
}

class _StandardTopPerformersPageState extends State<StandardTopPerformersPage> {
  final InsightsRepository _repository = InsightsRepository();
  final TextEditingController _searchController = TextEditingController();

  StandardFullRanking? _ranking;
  List<TopPerformerStudent> _filteredStudents = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final ranking = await _repository.getStandardFullRanking(
        schoolCode: widget.schoolCode,
        range: widget.range,
        standard: widget.standard,
      );

      if (mounted) {
        setState(() {
          _ranking = ranking;
          _filteredStudents = ranking?.students ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading ranking: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterStudents(String query) {
    if (_ranking == null) return;

    setState(() {
      if (query.isEmpty) {
        _filteredStudents = _ranking!.students;
      } else {
        _filteredStudents = _ranking!.students
            .where(
              (s) =>
                  s.name.toLowerCase().contains(query.toLowerCase()) ||
                  s.section.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
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
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standard ${widget.standard} Rankings',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_filteredStudents.length} students',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: cardColor,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterStudents,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'Search by name or section...',
                hintStyle: TextStyle(color: subtitleColor),
                prefixIcon: Icon(Icons.search, color: subtitleColor),
                filled: true,
                fillColor: bgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Student List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF146D7A),
                    ),
                  )
                : _filteredStudents.isEmpty
                ? _buildEmptyState(subtitleColor)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredStudents.length,
                    itemBuilder: (context, index) {
                      final student = _filteredStudents[index];
                      return _buildStudentCard(
                        student,
                        cardColor,
                        textColor,
                        subtitleColor,
                        isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(
    TopPerformerStudent student,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final medals = ['🥇', '🥈', '🥉'];
    final rankDisplay = student.rank <= 3
        ? medals[student.rank - 1]
        : '#${student.rank}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF146D7A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              rankDisplay,
              style: TextStyle(
                fontSize: student.rank <= 3 ? 20 : 16,
                fontWeight: FontWeight.w700,
                color: student.rank <= 3 ? textColor : const Color(0xFF146D7A),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Student Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Section ${student.section}',
                  style: TextStyle(color: subtitleColor, fontSize: 13),
                ),
              ],
            ),
          ),

          // Score Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF146D7A), Color(0xFF0E5A66)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${student.avgScore.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: subtitleColor),
          const SizedBox(height: 16),
          Text(
            'No students found',
            style: TextStyle(color: subtitleColor, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
