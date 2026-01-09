import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityMemberModel {
  final String userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final String userGrade;
  final String userSection;
  final String schoolCode;
  final String avatarUrl;
  final DateTime joinedAt;
  final String status;
  final bool isModerator;
  final DateTime? lastReadAt;
  final int unreadCount;
  final int messageCount;
  final bool muteNotifications;
  final bool favorited;

  CommunityMemberModel({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.userGrade,
    required this.userSection,
    required this.schoolCode,
    required this.avatarUrl,
    required this.joinedAt,
    required this.status,
    required this.isModerator,
    this.lastReadAt,
    required this.unreadCount,
    required this.messageCount,
    required this.muteNotifications,
    required this.favorited,
  });

  factory CommunityMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityMemberModel(
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userEmail: data['userEmail'] ?? '',
      userRole: data['userRole'] ?? 'student',
      userGrade: data['userGrade'] ?? '',
      userSection: data['userSection'] ?? '',
      schoolCode: data['schoolCode'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      status: data['status'] ?? 'active',
      isModerator: data['isModerator'] ?? false,
      lastReadAt: data['lastReadAt'] != null
          ? (data['lastReadAt'] as Timestamp).toDate()
          : null,
      unreadCount: data['unreadCount'] ?? 0,
      messageCount: data['messageCount'] ?? 0,
      muteNotifications: data['muteNotifications'] ?? false,
      favorited: data['favorited'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'userRole': userRole,
      'userGrade': userGrade,
      'userSection': userSection,
      'schoolCode': schoolCode,
      'avatarUrl': avatarUrl,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'status': status,
      'isModerator': isModerator,
      'lastReadAt': lastReadAt != null ? Timestamp.fromDate(lastReadAt!) : null,
      'unreadCount': unreadCount,
      'messageCount': messageCount,
      'muteNotifications': muteNotifications,
      'favorited': favorited,
    };
  }
}
