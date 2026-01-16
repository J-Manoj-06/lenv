import '../models/attendance_summary_model.dart';
import '../models/class_attendance_model.dart';
import '../models/student_attendance_model.dart';

class AttendanceService {
  /// Get yesterday's date
  DateTime getYesterdayDate() {
    return DateTime.now().subtract(const Duration(days: 1));
  }

  /// Get attendance summary for a specific date
  Future<AttendanceSummaryModel> getAttendanceSummary(DateTime date) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data - In production, this would fetch from Firebase/API
    return AttendanceSummaryModel(
      date: date,
      totalStudents: 128,
      totalPresent: 115,
      totalAbsent: 13,
      percentage: 89.84,
    );
  }

  /// Get class-wise attendance for a specific date
  Future<List<ClassAttendanceModel>> getClassWiseAttendance(
    DateTime date,
  ) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Mock data - In production, this would fetch from Firebase/API
    return [
      ClassAttendanceModel(
        classId: '1',
        className: 'Class 10 - A',
        totalStudents: 32,
        presentCount: 30,
        absentCount: 2,
        percentage: 93.75,
        students: _generateMockStudents('10-A', 32, 30),
      ),
      ClassAttendanceModel(
        classId: '2',
        className: 'Class 10 - B',
        totalStudents: 28,
        presentCount: 24,
        absentCount: 4,
        percentage: 85.71,
        students: _generateMockStudents('10-B', 28, 24),
      ),
      ClassAttendanceModel(
        classId: '3',
        className: 'Class 9 - A',
        totalStudents: 30,
        presentCount: 26,
        absentCount: 4,
        percentage: 86.67,
        students: _generateMockStudents('9-A', 30, 26),
      ),
      ClassAttendanceModel(
        classId: '4',
        className: 'Class 9 - B',
        totalStudents: 25,
        presentCount: 22,
        absentCount: 3,
        percentage: 88.00,
        students: _generateMockStudents('9-B', 25, 22),
      ),
      ClassAttendanceModel(
        classId: '5',
        className: 'Class 8 - A',
        totalStudents: 13,
        presentCount: 13,
        absentCount: 0,
        percentage: 100.00,
        students: _generateMockStudents('8-A', 13, 13),
      ),
    ];
  }

  /// Generate mock students for a class
  List<StudentAttendanceModel> _generateMockStudents(
    String classPrefix,
    int total,
    int present,
  ) {
    final students = <StudentAttendanceModel>[];
    final absentReasons = [
      'Sick leave',
      'Family function',
      'Medical appointment',
      null,
    ];

    for (int i = 1; i <= total; i++) {
      final isPresent = i <= present;
      students.add(
        StudentAttendanceModel(
          studentId: '$classPrefix-$i',
          name: 'Student ${String.fromCharCode(64 + i)}',
          rollNo: i.toString().padLeft(2, '0'),
          isPresent: isPresent,
          absentReason: isPresent
              ? null
              : absentReasons[i % absentReasons.length],
        ),
      );
    }

    return students;
  }
}
