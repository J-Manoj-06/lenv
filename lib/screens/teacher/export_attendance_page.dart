import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';
import 'package:excel/excel.dart' as excel_package;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';

class ExportAttendancePage extends StatefulWidget {
  const ExportAttendancePage({super.key});

  @override
  State<ExportAttendancePage> createState() => _ExportAttendancePageState();
}

class _ExportAttendancePageState extends State<ExportAttendancePage> {
  final TeacherService _teacherService = TeacherService();

  // Form state
  String _selectedScope = 'all'; // 'all' or 'selected'
  Set<String> _selectedClasses = {};
  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedFormat = 'excel'; // 'pdf' or 'excel'
  bool _isExporting = false;

  List<String> _availableClasses = [];
  bool _isLoadingClasses = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableClasses();
  }

  Future<void> _loadAvailableClasses() async {
    try {
      setState(() => _isLoadingClasses = true);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) return;

      final teacherData = await _teacherService.getTeacherByEmail(
        currentUser.email,
      );
      if (teacherData != null) {
        final classes = _teacherService.getTeacherClasses(
          teacherData['classesHandled'],
          teacherData['sections'] ?? teacherData['section'],
          classAssignments: teacherData['classAssignments'],
        );
        setState(() {
          _availableClasses = classes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading classes: $e')));
      }
    } finally {
      setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF7961FF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _fromDate) {
      setState(() => _fromDate = picked);
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: _fromDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF7961FF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _toDate) {
      setState(() => _toDate = picked);
    }
  }

  bool _validateForm() {
    if (_selectedScope == 'selected' && _selectedClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one class')),
      );
      return false;
    }

    if (_fromDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a from date')),
      );
      return false;
    }

    if (_toDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a to date')));
      return false;
    }

    if (_toDate!.isBefore(_fromDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('To date must be after from date')),
      );
      return false;
    }

    return true;
  }

  Future<void> _generateAndDownloadExcel() async {
    if (!_validateForm()) return;

    setState(() => _isExporting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: User not authenticated')),
        );
        return;
      }

      // Determine which classes to export
      List<String> classesToExport = _selectedScope == 'all'
          ? _availableClasses
          : _selectedClasses.toList();

      debugPrint('[ExportAttendance] scope=$_selectedScope');
      debugPrint('[ExportAttendance] classesToExport=$classesToExport');

      if (classesToExport.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No classes to export')));
        return;
      }

      // Create Excel workbook
      final excel = excel_package.Excel.createExcel();

      // For each class, fetch students and create attendance sheet
      for (final className in classesToExport) {
        final parts = className.split(' - ');
        final gradeNum = parts[0].trim();
        final section = parts.length > 1 ? parts[1].trim() : '';
        debugPrint(
          '[ExportAttendance] class=$className grade=$gradeNum section=$section',
        );

        // Get students for this class
        final schoolId = currentUser.instituteId ?? '';
        debugPrint('[ExportAttendance] schoolId=$schoolId');
        final gradeClassName = 'Grade $gradeNum';
        debugPrint('[ExportAttendance] gradeClassName=$gradeClassName');
        final students = await _teacherService.getStudentsByTeacher(schoolId, [
          gradeClassName,
        ], section);
        debugPrint(
          '[ExportAttendance] studentsCount(${className})=${students.length}',
        );

        // Get attendance data for this class
        final attendanceData = await _teacherService.exportClassAttendance(
          schoolCode: schoolId,
          grade: gradeNum,
          section: section,
          students: students,
        );
        debugPrint(
          '[ExportAttendance] attendanceCount(${className})=${attendanceData.length}',
        );

        // Create sheet for this class
        final sheetName = className.replaceAll(' - ', '_').replaceAll(' ', '_');
        debugPrint('[ExportAttendance] sheetName=$sheetName');
        final sheet = excel[sheetName];

        // Add headers
        sheet.appendRow([
          excel_package.TextCellValue('Student Name'),
          excel_package.TextCellValue('Total Days'),
          excel_package.TextCellValue('Present Days'),
          excel_package.TextCellValue('Attendance %'),
        ]);

        // Add student data
        for (final record in attendanceData) {
          sheet.appendRow([
            excel_package.TextCellValue(record['name']?.toString() ?? ''),
            excel_package.IntCellValue(record['total_days'] as int? ?? 0),
            excel_package.IntCellValue(record['present_days'] as int? ?? 0),
            excel_package.TextCellValue(
              record['attendance_percentage']?.toString() ?? '0.00',
            ),
          ]);
        }
      }

      // Remove default/empty sheets (prevents showing Sheet1)
      final sheetsToDelete = <String>[];
      excel.sheets.forEach((name, sheet) {
        final isDefault = name == 'Sheet1';
        final isEmpty = sheet.maxRows == 0;
        if (isDefault || isEmpty) {
          sheetsToDelete.add(name);
        }
      });
      for (final name in sheetsToDelete) {
        excel.delete(name);
      }

      // Save and open file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().split(' ')[0];
      final fileName = 'Attendance_Report_$timestamp.xlsx';
      final filePath = '${directory.path}/$fileName';

      final bytes = excel.save();
      debugPrint('[ExportAttendance] bytesNull=${bytes == null}');
      if (bytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        debugPrint('[ExportAttendance] savedFile=$filePath');

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Report saved: $fileName'),
              backgroundColor: Colors.green[700],
              action: SnackBarAction(
                label: 'Open',
                onPressed: () {
                  OpenFilex.open(filePath);
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Auto-open the file
        await OpenFilex.open(filePath);

        // Navigate back after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1115) : Colors.grey[50];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1A1F2E) : Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Export Attendance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 1: Export Scope
              _buildSectionTitle('Export Scope'),
              const SizedBox(height: 12),
              _buildScopeSelector(),
              const SizedBox(height: 16),

              // Class Selection (visible if "Selected Classes" chosen)
              if (_selectedScope == 'selected') ...[
                _buildClassSelector(isDark),
                const SizedBox(height: 32),
              ],

              // Section 2: Date Range
              _buildSectionTitle('Date Range'),
              const SizedBox(height: 12),
              _buildDateRangePickers(theme, isDark),
              const SizedBox(height: 32),

              // Section 3: Export Format
              _buildSectionTitle('Export Format'),
              const SizedBox(height: 12),
              _buildFormatSelector(isDark),
              const SizedBox(height: 40),

              // Generate Report Button
              _buildGenerateButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: theme.textTheme.bodyLarge?.color,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Column(
      children: [
        _buildScopeOption(
          'all',
          'All Classes',
          'Export attendance for all classes',
        ),
        const SizedBox(height: 12),
        _buildScopeOption(
          'selected',
          'Selected Classes',
          'Choose specific classes to export',
        ),
      ],
    );
  }

  Widget _buildScopeOption(String value, String title, String subtitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedScope == value;

    return InkWell(
      onTap: () => setState(() => _selectedScope = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7961FF).withOpacity(0.1)
              : isDark
              ? const Color(0xFF1A1F2E)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7961FF)
                : isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7961FF)
                      : Colors.grey[400]!,
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFF7961FF)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassSelector(bool isDark) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Select Classes'),
        const SizedBox(height: 12),
        if (_isLoadingClasses)
          Container(
            height: 100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFF7961FF)),
            ),
          )
        else if (_availableClasses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No classes available',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableClasses.map((className) {
              final isSelected = _selectedClasses.contains(className);
              return FilterChip(
                selected: isSelected,
                label: Text(className),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedClasses.add(className);
                    } else {
                      _selectedClasses.remove(className);
                    }
                  });
                },
                backgroundColor: isDark
                    ? const Color(0xFF1A1F2E)
                    : Colors.white,
                selectedColor: const Color(0xFF7961FF).withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected
                      ? const Color(0xFF7961FF)
                      : theme.textTheme.bodySmall?.color,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF7961FF)
                      : isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.2),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildDateRangePickers(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildDateField(
            label: 'From Date',
            date: _fromDate,
            onTap: _selectFromDate,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDateField(
            label: 'To Date',
            date: _toDate,
            onTap: _selectToDate,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: date != null
                ? const Color(0xFF7961FF)
                : isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
            width: date != null ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7961FF),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              date != null
                  ? '${date.day}/${date.month}/${date.year}'
                  : 'Select date',
              style: TextStyle(
                fontSize: 14,
                color: date != null
                    ? theme.textTheme.bodyMedium?.color
                    : theme.textTheme.bodySmall?.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatSelector(bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildFormatOption('pdf', 'PDF', '📄')),
        const SizedBox(width: 12),
        Expanded(child: _buildFormatOption('excel', 'Excel (CSV)', '📊')),
      ],
    );
  }

  Widget _buildFormatOption(String value, String title, String emoji) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedFormat == value;

    return InkWell(
      onTap: () => setState(() => _selectedFormat = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7961FF).withOpacity(0.1)
              : isDark
              ? const Color(0xFF1A1F2E)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7961FF)
                : isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isExporting ? null : _generateAndDownloadExcel,
        icon: _isExporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.download_rounded, size: 20),
        label: Text(
          _isExporting ? 'Generating Report...' : 'Generate Report',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7961FF),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          disabledBackgroundColor: const Color(0xFF7961FF).withOpacity(0.5),
        ),
      ),
    );
  }
}
