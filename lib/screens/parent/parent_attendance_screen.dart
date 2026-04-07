import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/parent_provider.dart';
import '../../models/attendance_record.dart';
import '../../services/parent_service.dart';
import '../../widgets/student_selection/student_avatar_row.dart';
import 'parent_profile_screen.dart';

class ParentAttendanceScreen extends StatefulWidget {
  const ParentAttendanceScreen({super.key});

  @override
  State<ParentAttendanceScreen> createState() => _ParentAttendanceScreenState();
}

class _ParentAttendanceScreenState extends State<ParentAttendanceScreen> {
  static const Color parentGreen = Color(0xFF1FA463);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  DateTime _selectedMonth = DateTime(
    2026,
    1,
  ); // Start from January 2026 where data exists
  List<AttendanceRecord> _attendanceRecords = [];
  bool _isLoading = false;
  String? _currentChildUid; // Track current child to reload when it changes

  final ParentService _parentService = ParentService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get the current selected child
    final parentProvider = Provider.of<ParentProvider>(context);
    final selectedChild = parentProvider.selectedChild;

    // If child is selected and different from current, load attendance
    if (selectedChild != null && selectedChild.uid != _currentChildUid) {
      _currentChildUid = selectedChild.uid;
      _attendanceRecords = []; // Clear old records
      _loadAttendance();
    }
  }

  @override
  void initState() {
    super.initState();
    // Don't load here - will load in didChangeDependencies when child is available
  }

  Future<void> _loadAttendance() async {
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
    final selectedChild = parentProvider.selectedChild;

    if (selectedChild == null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final records = await _parentService.getStudentAttendanceForMonth(
        selectedChild.uid,
        _selectedMonth,
      );
      setState(() {
        _attendanceRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadAttendance();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadAttendance();
  }

  int get _totalPresent =>
      _attendanceRecords.where((r) => r.status == 'present').length;

  int get _totalAbsent =>
      _attendanceRecords.where((r) => r.status == 'absent').length;

  double get _attendancePercentage {
    final workingDays = _attendanceRecords
        .where((r) => r.status != 'holiday')
        .length;
    if (workingDays == 0) return 0.0;
    return (_totalPresent / workingDays) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? backgroundDark : Colors.white,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ParentProfileScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ParentProvider>(
        builder: (context, parentProvider, child) {
          if (!parentProvider.hasChildren) {
            return _buildEmptyState(isDark, 'No children found');
          }

          return Column(
            children: [
              // Student Selection Row
              const StudentAvatarRow(),

              // Main Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            parentGreen,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAttendance,
                        color: parentGreen,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Summary Cards
                                _buildSummaryCards(isDark),
                                const SizedBox(height: 24),

                                // Calendar Section
                                _buildCalendarSection(isDark),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            isDark: isDark,
            label: 'Present',
            value: _totalPresent.toString(),
            icon: Icons.check_circle,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            isDark: isDark,
            label: 'Absent',
            value: _totalAbsent.toString(),
            icon: Icons.cancel,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildPercentageCard(isDark)),
      ],
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPercentageCard(bool isDark) {
    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: _attendancePercentage / 100,
                        strokeWidth: 6,
                        backgroundColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          parentGreen,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${_attendancePercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Attendance',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month Navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: isDark ? Colors.white : textPrimary,
              ),
              onPressed: _previousMonth,
            ),
            Text(
              DateFormat('MMMM yyyy').format(_selectedMonth),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_forward_ios,
                color: isDark ? Colors.white : textPrimary,
              ),
              onPressed: _nextMonth,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Calendar Grid
        Card(
          elevation: 2,
          color: isDark ? const Color(0xFF1E1A2F) : cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildCalendarGrid(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final firstDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final startWeekday = firstDayOfMonth.weekday; // 1 = Monday
    final daysInMonth = lastDayOfMonth.day;

    // Weekday headers
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      children: [
        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdays
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),

        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: startWeekday - 1 + daysInMonth,
          itemBuilder: (context, index) {
            // Empty cells before first day
            if (index < startWeekday - 1) {
              return const SizedBox.shrink();
            }

            final day = index - (startWeekday - 1) + 1;
            final date = DateTime(
              _selectedMonth.year,
              _selectedMonth.month,
              day,
            );
            final isToday = _isSameDay(date, DateTime.now());
            final isFuture = date.isAfter(DateTime.now());

            // Find attendance record for this date
            AttendanceRecord? record;
            if (!isFuture) {
              try {
                record = _attendanceRecords.firstWhere(
                  (r) => _isSameDay(r.date, date),
                );
              } catch (e) {
                // No record found - attendance not taken
                record = null;
              }
            }

            return _buildDateCell(isDark, day, record, isToday, isFuture);
          },
        ),
      ],
    );
  }

  Widget _buildDateCell(
    bool isDark,
    int day,
    AttendanceRecord? record,
    bool isToday,
    bool isFuture,
  ) {
    Color bgColor;
    Color? borderColor;
    IconData? icon;
    Color? iconColor;
    bool showNoAttendanceCircle = false;

    if (isFuture) {
      // Future dates - grey
      bgColor = isDark ? Colors.grey[900]! : Colors.grey[100]!;
    } else if (record == null) {
      // Attendance not taken - light yellow
      bgColor = const Color(0xFFFFF2C6); // Clear yellow background
      showNoAttendanceCircle = true;
    } else if (record.status == 'present') {
      bgColor = Colors.green.withOpacity(0.2);
      icon = Icons.check;
      iconColor = Colors.green;
    } else if (record.status == 'holiday') {
      bgColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
      borderColor = isDark ? Colors.grey[700] : Colors.grey[400];
    } else {
      // absent
      bgColor = Colors.red.withOpacity(0.1);
      icon = Icons.close;
      iconColor = Colors.red;
    }

    if (isToday && borderColor == null) {
      borderColor = parentGreen;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showNoAttendanceCircle)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFF4B400),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isToday ? parentGreen : const Color(0xFFE39B00),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                day.toString(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          if (!showNoAttendanceCircle)
            Text(
              day.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
          if (icon != null) Icon(icon, size: 16, color: iconColor),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildEmptyState(bool isDark, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
