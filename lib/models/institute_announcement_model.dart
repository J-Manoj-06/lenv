import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for institute-wide announcements posted by principals
class InstituteAnnouncementModel {
  final String id;
  final String principalId;
  final String principalName;
  final String? principalEmail;
  final String instituteId;
  final String text;
  final String? imageUrl; // Deprecated: use imageCaptions instead
  final List<Map<String, String>>?
  imageCaptions; // New: [{url: '...', caption: '...'}]
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool hasImage;
  final bool hasText;

  // Audience targeting
  final String audienceType; // 'school', 'standard', 'section'
  final List<String> standards; // e.g., ['6', '7', '8']
  final List<String> sections; // e.g., ['10A']
  final String createdByRole; // 'teacher' or 'principal'
  final String scopeType; // 'whole_school', 'standard', 'section'
  final String targetStandard;
  final String targetSection;
  final String schoolId;

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
    this.imageCaptions,
    required this.createdAt,
    required this.expiresAt,
    this.audienceType = 'school',
    this.standards = const [],
    this.sections = const [],
    this.createdByRole = 'principal',
    this.scopeType = 'whole_school',
    this.targetStandard = '',
    this.targetSection = '',
    this.schoolId = '',
  }) : hasImage =
           (imageCaptions != null && imageCaptions.isNotEmpty) ||
           (imageUrl != null && imageUrl.isNotEmpty),
       hasText = text.isNotEmpty;

  /// Create from Firestore document
  factory InstituteAnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    List<Map<String, String>>? imageCaptions;
    if (data['imageCaptions'] != null) {
      imageCaptions = (data['imageCaptions'] as List)
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
    }

    // Parse createdAt first
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return InstituteAnnouncementModel(
      id: doc.id,
      principalId: data['principalId'] ?? '',
      principalName: data['principalName'] ?? 'Principal',
      principalEmail: data['principalEmail'],
      instituteId: data['instituteId'] ?? '',
      text: data['text'] ?? '',
      imageUrl: data['imageUrl'],
      imageCaptions: imageCaptions,
      createdAt: createdAt,
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          createdAt.add(const Duration(hours: 24)),
      audienceType: data['audienceType'] ?? 'school',
      standards: List<String>.from(data['standards'] ?? []),
      sections:
          (data['sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdByRole: data['createdByRole']?.toString() ?? 'principal',
      scopeType:
          data['scopeType']?.toString() ??
          _scopeFromLegacyAudience(
            data['audienceType']?.toString() ?? 'school',
          ),
      targetStandard: data['targetStandard']?.toString() ?? '',
      targetSection: data['targetSection']?.toString() ?? '',
      schoolId:
          data['schoolId']?.toString() ?? data['instituteId']?.toString() ?? '',
    );
  }

  /// Create from plain map (used for offline cache hydration)
  factory InstituteAnnouncementModel.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    List<Map<String, String>>? imageCaptions;
    if (data['imageCaptions'] is List) {
      imageCaptions = (data['imageCaptions'] as List)
          .whereType<Map>()
          .map((item) => Map<String, String>.from(item))
          .toList();
    }

    final createdAt = _parseDate(data['createdAt']) ?? DateTime.now();

    return InstituteAnnouncementModel(
      id: id,
      principalId: data['principalId']?.toString() ?? '',
      principalName: data['principalName']?.toString() ?? 'Principal',
      principalEmail: data['principalEmail']?.toString(),
      instituteId: data['instituteId']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      imageUrl: data['imageUrl']?.toString(),
      imageCaptions: imageCaptions,
      createdAt: createdAt,
      expiresAt:
          _parseDate(data['expiresAt']) ??
          createdAt.add(const Duration(hours: 24)),
      audienceType: data['audienceType']?.toString() ?? 'school',
      standards:
          (data['standards'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      sections:
          (data['sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdByRole: data['createdByRole']?.toString() ?? 'principal',
      scopeType:
          data['scopeType']?.toString() ??
          _scopeFromLegacyAudience(
            data['audienceType']?.toString() ?? 'school',
          ),
      targetStandard: data['targetStandard']?.toString() ?? '',
      targetSection: data['targetSection']?.toString() ?? '',
      schoolId:
          data['schoolId']?.toString() ?? data['instituteId']?.toString() ?? '',
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static String _scopeFromLegacyAudience(String audienceType) {
    switch (audienceType) {
      case 'standard':
        return 'standard';
      case 'section':
        return 'section';
      case 'school':
      default:
        return 'whole_school';
    }
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
      'imageCaptions':
          imageCaptions
              ?.map((item) => {'url': item['url'], 'caption': item['caption']})
              .toList() ??
          [],
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'audienceType': audienceType,
      'standards': standards,
      'sections': sections,
      'createdByRole': createdByRole,
      'scopeType': scopeType,
      'targetStandard': targetStandard,
      'targetSection': targetSection,
      'schoolId': schoolId.isNotEmpty ? schoolId : instituteId,
    };
  }

  bool isVisibleByNewRules({
    required String userRole,
    String userStandard = '',
    String userSection = '',
    List<String> handledStandards = const <String>[],
    List<String> handledSections = const <String>[],
  }) {
    final role = userRole.toLowerCase().trim();
    final creatorRole = createdByRole.toLowerCase().trim();
    final scope = scopeType.toLowerCase().trim();

    if (scope == 'whole_school') {
      return true;
    }

    if (scope == 'standard') {
      final effectiveStandard = targetStandard.isNotEmpty
          ? targetStandard
          : (standards.isNotEmpty ? standards.first : '');
      final isStandardMatch =
          userStandard.isNotEmpty && effectiveStandard == userStandard;
      final isHandledByTeacher = handledStandards.contains(effectiveStandard);

      if (role == 'principal') {
        if (creatorRole == 'teacher') return false;
        return creatorRole == 'principal';
      }
      if (role == 'teacher') {
        return isHandledByTeacher;
      }
      return isStandardMatch;
    }

    if (scope == 'section') {
      String normalizeStandard(String value) {
        return value
            .toUpperCase()
            .replaceAll(RegExp(r'GRADE\s*'), '')
            .replaceAll(' ', '')
            .trim();
      }

      String normalizeToken(String value) {
        return value.toUpperCase().replaceAll(' ', '').trim();
      }

      String normalizeSectionOnly(String sectionValue, String standardValue) {
        final token = normalizeToken(sectionValue).replaceAll('-', '');
        final std = normalizeStandard(standardValue);
        if (std.isNotEmpty &&
            token.startsWith(std) &&
            token.length > std.length) {
          return token.substring(std.length);
        }
        return token;
      }

      final effectiveStandard = targetStandard.isNotEmpty
          ? targetStandard
          : (standards.isNotEmpty ? standards.first : userStandard);
      final effectiveSection = targetSection.isNotEmpty
          ? targetSection
          : (sections.isNotEmpty ? sections.first : userSection);

      final normalizedTargetStandard = normalizeStandard(effectiveStandard);
      final normalizedUserStandard = normalizeStandard(userStandard);
      final normalizedTargetSection = normalizeSectionOnly(
        effectiveSection,
        effectiveStandard,
      );
      final normalizedUserSection = normalizeSectionOnly(
        userSection,
        userStandard,
      );

      final targetCombined =
          '$normalizedTargetStandard$normalizedTargetSection';
      final targetHyphen = '$normalizedTargetStandard-$normalizedTargetSection';
      final userCombined = '$normalizedUserStandard$normalizedUserSection';
      final userHyphen = '$normalizedUserStandard-$normalizedUserSection';

      final isStandardMatch =
          normalizedTargetStandard.isEmpty ||
          normalizedUserStandard.isEmpty ||
          normalizedTargetStandard == normalizedUserStandard;

      final isSectionMatch =
          isStandardMatch &&
          ((normalizedTargetSection == normalizedUserSection) ||
              (targetCombined == userCombined) ||
              (targetHyphen == userHyphen));

      final normalizedHandledSections = handledSections
          .map(normalizeToken)
          .toSet();

      final isHandledByTeacher =
          normalizedHandledSections.contains(
            normalizeToken(effectiveSection),
          ) ||
          normalizedHandledSections.contains(targetCombined) ||
          normalizedHandledSections.contains(targetHyphen) ||
          normalizedHandledSections.contains(normalizedTargetSection);

      if (role == 'principal') {
        if (creatorRole == 'teacher') return false;
        return creatorRole == 'principal';
      }
      if (role == 'teacher') {
        return isHandledByTeacher;
      }
      return isSectionMatch;
    }

    // Legacy fallback
    if (audienceType == 'school') return true;
    if (audienceType == 'standard') {
      if (role == 'teacher') {
        return standards.any(handledStandards.contains);
      }
      return standards.contains(userStandard);
    }
    return false;
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

  /// Check if announcement is still valid (not expired)
  bool get isValid => !isExpired;
}
