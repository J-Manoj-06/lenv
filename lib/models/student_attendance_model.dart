class StudentAttendanceModel {
  final String studentId;
  final String name;
  final String rollNo;
  final bool isPresent;
  final String? absentReason;

  StudentAttendanceModel({
    required this.studentId,
    required this.name,
    required this.rollNo,
    required this.isPresent,
    this.absentReason,
  });

  factory StudentAttendanceModel.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceModel(
      studentId: json['studentId'] as String,
      name: json['name'] as String,
      rollNo: json['rollNo'] as String,
      isPresent: json['isPresent'] as bool,
      absentReason: json['absentReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'rollNo': rollNo,
      'isPresent': isPresent,
      'absentReason': absentReason,
    };
  }
}
