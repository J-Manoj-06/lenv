import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for institute-wide announcements posted by principals
class InstituteAnnouncementModel {
  final String id;
  final String principalId;
  final String principalName;
  final String? principalEmail;
  final String instituteId;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool hasImage;
  final bool hasText;

  // Audience targeting
  final String audienceType; // 'school', 'standard'
  final List<String> standards; // e.g., ['6', '7', '8']

  // Viewing tracking is now stored in views subcollection
  // Access via: announcements/{docId}/views/{userId}

  InstituteAnnouncementModel({
    required this.id,
    required this.principalId,
    required this.principalName,
    this.principalEmail,
    required this.instituteId,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    required this.expiresAt,
    this.audienceType = 'school',
    this.standards = const [],
  }) : hasImage = imageUrl != null && imageUrl.isNotEmpty,
       hasText = text.isNotEmpty;

  /// Create from Firestore document
  factory InstituteAnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InstituteAnnouncementModel(
      id: doc.id,
      principalId: data['principalId'] ?? '',
      principalName: data['principalName'] ?? 'Principal',
      principalEmail: data['principalEmail'],
      instituteId: data['instituteId'] ?? '',
      text: data['text'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 24)),
      audienceType: data['audienceType'] ?? 'school',
      standards: List<String>.from(data['standards'] ?? []),
    );
  }

  /// Convert to Firestore document
  /// Note: viewedBy tracking is now handled via subcollection 'views/{userId}'
  /// Uses server timestamp for consistency and cost optimization (no duplicate client timestamp)
  Map<String, dynamic> toFirestore() {
    return {
      'principalId': principalId,
      'principalName': principalName,
      'principalEmail': principalEmail,
      'instituteId': instituteId,
      'text': text,
      'imageUrl': imageUrl ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'audienceType': audienceType,
      'standards': standards,
    };
  }

  /// Getter for view count - should be calculated from subcollection
  /// This avoids storing unbounded arrays
  Future<int> getViewCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(id)
          .collection('views')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Check if an announcement has been viewed by a user via subcollection
  static Future<bool> hasBeenViewedBy(
    String announcementId,
    String userId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .doc(userId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Check if announcement is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
