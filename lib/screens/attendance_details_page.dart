import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/attendance_summary_model.dart';
import '../models/class_attendance_model.dart';
import '../services/attendance_service.dart';
import '../widgets/attendance_summary_card.dart';
import '../widgets/class_attendance_tile.dart';

class AttendanceDetailsPage extends StatefulWidget {
  final DateTime date;

  const AttendanceDetailsPage({super.key, required this.date});

  @override
  State<AttendanceDetailsPage> createState() => _AttendanceDetailsPageState();
}

class _AttendanceDetailsPageState extends State<AttendanceDetailsPage> {
  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();

  AttendanceSummaryModel? _summary;
  List<ClassAttendanceModel> _classList = [];
  List<ClassAttendanceModel> _filteredClassList = [];
  bool _isLoading = true;
  String? _error;
  String _filterOption = 'All Classes';

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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await _attendanceService.getAttendanceSummary(
        widget.date,
      );
      final classList = await _attendanceService.getClassWiseAttendance(
        widget.date,
      );

      setState(() {
        _summary = summary;
        _classList = classList;
        _filteredClassList = classList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load attendance data';
        _isLoading = false;
      });
    }
  }

  void _filterClasses() {
    setState(() {
      var filtered = List<ClassAttendanceModel>.from(_classList);

      // Apply search filter
      if (_searchController.text.isNotEmpty) {
        final searchLower = _searchController.text.toLowerCase();
        filtered = filtered.where((c) {
          final classNameMatch = c.className.toLowerCase().contains(
            searchLower,
          );
          final studentMatch = c.students.any(
            (s) => s.name.toLowerCase().contains(searchLower),
          );
          return classNameMatch || studentMatch;
        }).toList();
      }

      // Apply dropdown filter
      switch (_filterOption) {
        case 'Low Attendance (<75%)':
          filtered = filtered.where((c) => c.percentage < 75).toList();
          break;
        case 'Highest First':
          filtered.sort((a, b) => b.percentage.compareTo(a.percentage));
          break;
        case 'Lowest First':
          filtered.sort((a, b) => a.percentage.compareTo(b.percentage));
          break;
        default:
          // All Classes - no additional filter
          break;
      }

      _filteredClassList = filtered;
    });
  }

  String _getDateSubtitle() {
    final now = DateTime.now();
    final difference = now.difference(widget.date).inDays;

    String dateStr = DateFormat('dd MMM yyyy').format(widget.date);

    if (difference == 0) {
      return '$dateStr (Today)';
    } else if (difference == 1) {
      return '$dateStr (Yesterday)';
    } else {
      return dateStr;
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
              'Attendance Details',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _getDateSubtitle(),
              style: TextStyle(color: subtitleColor, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list, color: textColor),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(cardColor, subtitleColor)
          : _error != null
          ? _buildErrorState(textColor, subtitleColor)
          : _buildContent(cardColor, textColor, subtitleColor),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportReport,
        backgroundColor: const Color(0xFF146D7A),
        icon: const Icon(Icons.download, color: Colors.white),
        label: const Text(
          'Export Report',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildLoadingState(Color cardColor, Color subtitleColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildShimmerCard(cardColor, 120),
        const SizedBox(height: 16),
        ...List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildShimmerCard(cardColor, 100),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerCard(Color cardColor, double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF146D7A)),
        ),
      ),
    );
  }

  Widget _buildErrorState(Color textColor, Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: subtitleColor),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Something went wrong',
            style: TextStyle(color: textColor, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF146D7A),
            ),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color cardColor, Color textColor, Color subtitleColor) {
    return Column(
      children: [
        // Summary Section
        Padding(
          padding: const EdgeInsets.all(16),
          child: AttendanceSummaryCard(
            summary: _summary!,
            cardColor: cardColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _filterClasses(),
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'Search class or student name...',
              hintStyle: TextStyle(color: subtitleColor),
              prefixIcon: Icon(Icons.search, color: subtitleColor),
              filled: true,
              fillColor: cardColor,
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

        const SizedBox(height: 16),

        // Class List
        Expanded(
          child: _filteredClassList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: subtitleColor),
                      const SizedBox(height: 16),
                      Text(
                        'No classes found',
                        style: TextStyle(color: textColor, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: _filteredClassList.length,
                  itemBuilder: (context, index) {
                    return ClassAttendanceTile(
                      classData: _filteredClassList[index],
                      cardColor: cardColor,
                      textColor: textColor,
                      subtitleColor: subtitleColor,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('Filter Classes', style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                [
                  'All Classes',
                  'Low Attendance (<75%)',
                  'Highest First',
                  'Lowest First',
                ].map((option) {
                  return RadioListTile<String>(
                    title: Text(option, style: TextStyle(color: textColor)),
                    value: option,
                    groupValue: _filterOption,
                    activeColor: const Color(0xFF146D7A),
                    onChanged: (value) {
                      setState(() {
                        _filterOption = value!;
                        _filterClasses();
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  void _exportReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export feature coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
