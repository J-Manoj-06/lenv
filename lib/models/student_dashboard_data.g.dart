// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'student_dashboard_data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StudentDashboardDataAdapter extends TypeAdapter<StudentDashboardData> {
  @override
  final int typeId = 10;

  @override
  StudentDashboardData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StudentDashboardData(
      studentId: fields[0] as String,
      studentName: fields[1] as String,
      messages: (fields[2] as List).cast<MessageItem>(),
      assignments: (fields[3] as List).cast<AssignmentItem>(),
      announcements: (fields[4] as List).cast<AnnouncementItem>(),
      attendance: fields[5] as AttendanceSummary,
      cachedAt: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, StudentDashboardData obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.studentId)
      ..writeByte(1)
      ..write(obj.studentName)
      ..writeByte(2)
      ..write(obj.messages)
      ..writeByte(3)
      ..write(obj.assignments)
      ..writeByte(4)
      ..write(obj.announcements)
      ..writeByte(5)
      ..write(obj.attendance)
      ..writeByte(6)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentDashboardDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageItemAdapter extends TypeAdapter<MessageItem> {
  @override
  final int typeId = 11;

  @override
  MessageItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MessageItem(
      id: fields[0] as String,
      senderName: fields[1] as String,
      message: fields[2] as String,
      timestamp: fields[3] as DateTime,
      isRead: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, MessageItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.senderName)
      ..writeByte(2)
      ..write(obj.message)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.isRead);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AssignmentItemAdapter extends TypeAdapter<AssignmentItem> {
  @override
  final int typeId = 12;

  @override
  AssignmentItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssignmentItem(
      id: fields[0] as String,
      title: fields[1] as String,
      subject: fields[2] as String,
      dueDate: fields[3] as DateTime,
      status: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AssignmentItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.subject)
      ..writeByte(3)
      ..write(obj.dueDate)
      ..writeByte(4)
      ..write(obj.status);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AnnouncementItemAdapter extends TypeAdapter<AnnouncementItem> {
  @override
  final int typeId = 13;

  @override
  AnnouncementItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AnnouncementItem(
      id: fields[0] as String,
      title: fields[1] as String,
      content: fields[2] as String,
      postedAt: fields[3] as DateTime,
      priority: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AnnouncementItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.postedAt)
      ..writeByte(4)
      ..write(obj.priority);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnouncementItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AttendanceSummaryAdapter extends TypeAdapter<AttendanceSummary> {
  @override
  final int typeId = 14;

  @override
  AttendanceSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AttendanceSummary(
      percentage: fields[0] as double,
      totalDays: fields[1] as int,
      presentDays: fields[2] as int,
      absentDays: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, AttendanceSummary obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.percentage)
      ..writeByte(1)
      ..write(obj.totalDays)
      ..writeByte(2)
      ..write(obj.presentDays)
      ..writeByte(3)
      ..write(obj.absentDays);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceSummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
