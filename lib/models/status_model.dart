import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a teacher's classroom highlight/status
class StatusModel {
  final String id;
  final String teacherId;
  final String teacherName;
  final String? teacherEmail;
  final String instituteId;
  final String className;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool hasImage;
  final bool hasText;

  // Audience targeting fields
  final String audienceType; // 'school', 'standard', 'section'
  final List<String> standards; // e.g., ['7', '8']
  final List<String> sections; // e.g., ['A', 'B']

  // Viewing tracking
  final List<String> viewedBy; // List of userIds who have viewed

  StatusModel({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    this.teacherEmail,
    required this.instituteId,
    required this.className,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
    this.audienceType = 'school',
    this.standards = const [],
    this.sections = const [],
    this.viewedBy = const [],
  }) : hasImage = imageUrl != null && imageUrl.isNotEmpty,
       hasText = text.isNotEmpty;

  /// Create from Firestore document
  factory StatusModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StatusModel(
      id: doc.id,
      teacherId: data['teacherId'] ?? '',
      teacherName: data['teacherName'] ?? 'Teacher',
      teacherEmail: data['teacherEmail'],
      instituteId: data['instituteId'] ?? '',
      className: data['className'] ?? '',
      text: data['text'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 24)),
      audienceType: data['audienceType'] ?? 'school',
      standards:
          (data['standards'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sections:
          (data['sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      viewedBy:
          (data['viewedBy'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// Check if status is still valid (not expired)
  bool get isValid => DateTime.now().isBefore(expiresAt);

  /// Get time remaining before expiry
  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  /// Get formatted time remaining
  String get timeRemainingFormatted {
    final duration = timeRemaining;
    if (duration.isNegative) return 'Expired';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  /// Check if a user has viewed this announcement
  bool hasBeenViewedBy(String userId) {
    return viewedBy.contains(userId);
  }

  /// Check if this status is visible to a given user based on audience rules
  bool isVisibleTo({
    required String userStandard,
    required String userSection,
  }) {
    print('🔍 Checking visibility for announcement:');
    print('   audienceType: $audienceType');
    print('   standards: $standards');
    print('   sections: $sections');
    print('   User: Grade $userStandard, Section $userSection');

    if (audienceType == 'school') {
      print('   ✅ Visible (school-wide)');
      return true;
    }
    if (audienceType == 'standard' && standards.contains(userStandard)) {
      print('   ✅ Visible (standard match)');
      return true;
    }
    if (audienceType == 'section') {
      // userSection is just the section letter (e.g., 'A')
      // sections array may contain:
      // - Combined format: "10A", "10B"
      // - Separate format: "A", "B"
      // - Hyphenated format: "10-A", "10-B"
      final combinedSection = '$userStandard$userSection'; // e.g., "10A"
      final hyphenatedSection = '$userStandard-$userSection'; // e.g., "10-A"

      print(
        '   Checking formats: "$userSection", "$combinedSection", "$hyphenatedSection"',
      );

      // Check if any format matches
      for (final section in sections) {
        if (section == userSection || // Just "A"
            section == combinedSection || // "10A"
            section == hyphenatedSection) {
          // "10-A"
          print('   ✅ Visible (section match: $section)');
          return true;
        }
      }
      print('   ❌ Not visible (no section match)');
    }
    return false;
  }

  @override
  String toString() =>
      'Status($id, teacher=$teacherName, text=$text, image=$imageUrl, audience=$audienceType)';
}
