import 'package:cloud_firestore/cloud_firestore.dart';

enum RewardType { badge, points, certificate, gift, custom }

enum RewardStatus { pending, accepted, rejected }

class RewardModel {
  final String id;
  final String studentId;
  final String studentName;
  final String senderId; // Parent or Teacher ID
  final String senderName;
  final String senderRole; // 'parent' or 'teacher'
  final RewardType type;
  final String title;
  final String description;
  final String? imageUrl;
  final int? points;
  final RewardStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  RewardModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.type,
    required this.title,
    required this.description,
    this.imageUrl,
    this.points,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'studentName': studentName,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'type': type.toString().split('.').last,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'points': points,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
    };
  }

  factory RewardModel.fromJson(Map<String, dynamic> json) {
    return RewardModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      senderRole: json['senderRole'] ?? '',
      type: RewardType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => RewardType.custom,
      ),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'],
      points: json['points'],
      status: RewardStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => RewardStatus.pending,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      acceptedAt: json['acceptedAt'] != null
          ? (json['acceptedAt'] as Timestamp).toDate()
          : null,
    );
  }

  RewardModel copyWith({
    String? id,
    String? studentId,
    String? studentName,
    String? senderId,
    String? senderName,
    String? senderRole,
    RewardType? type,
    String? title,
    String? description,
    String? imageUrl,
    int? points,
    RewardStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
  }) {
    return RewardModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      points: points ?? this.points,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
