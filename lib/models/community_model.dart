import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityModel {
  final String id;
  final String name;
  final String slug;
  final String description;
  final List<String> standards;
  final List<String> audienceRoles;
  final String schoolCode;
  final String scope;
  final String visibility;
  final String joinMode;
  final bool isActive;
  final int memberCount;
  final int messageCount;
  final DateTime? lastMessageAt;
  final String lastMessageBy;
  final String lastMessagePreview;
  final String avatarUrl;
  final String coverImage;
  final String category;
  final List<String> tags;
  final String createdBy;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String rules;
  final bool allowImages;
  final bool allowLinks;

  CommunityModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.standards,
    required this.audienceRoles,
    required this.schoolCode,
    required this.scope,
    required this.visibility,
    required this.joinMode,
    required this.isActive,
    required this.memberCount,
    required this.messageCount,
    this.lastMessageAt,
    required this.lastMessageBy,
    required this.lastMessagePreview,
    required this.avatarUrl,
    required this.coverImage,
    required this.category,
    required this.tags,
    required this.createdBy,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    required this.updatedAt,
    required this.rules,
    required this.allowImages,
    required this.allowLinks,
  });

  factory CommunityModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityModel(
      id: doc.id,
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      description: data['description'] ?? '',
      standards: List<String>.from(data['standards'] ?? []),
      audienceRoles: List<String>.from(data['audienceRoles'] ?? []),
      schoolCode: data['schoolCode'] ?? '',
      scope: data['scope'] ?? 'global',
      visibility: data['visibility'] ?? 'public',
      joinMode: data['joinMode'] ?? 'open',
      isActive: data['isActive'] ?? true,
      memberCount: data['memberCount'] ?? 0,
      messageCount: data['messageCount'] ?? 0,
      lastMessageAt: data['lastMessageAt'] != null
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      lastMessageBy: data['lastMessageBy'] ?? '',
      lastMessagePreview: data['lastMessagePreview'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      coverImage: data['coverImage'] ?? '',
      category: data['category'] ?? 'general',
      tags: List<String>.from(data['tags'] ?? []),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdByRole: data['createdByRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      rules: data['rules'] ?? '',
      allowImages: data['allowImages'] ?? false,
      allowLinks: data['allowLinks'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'slug': slug,
      'description': description,
      'standards': standards,
      'audienceRoles': audienceRoles,
      'schoolCode': schoolCode,
      'scope': scope,
      'visibility': visibility,
      'joinMode': joinMode,
      'isActive': isActive,
      'memberCount': memberCount,
      'messageCount': messageCount,
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : null,
      'lastMessageBy': lastMessageBy,
      'lastMessagePreview': lastMessagePreview,
      'avatarUrl': avatarUrl,
      'coverImage': coverImage,
      'category': category,
      'tags': tags,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'rules': rules,
      'allowImages': allowImages,
      'allowLinks': allowLinks,
    };
  }

  // ✅ For offline caching
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'standards': standards,
      'audienceRoles': audienceRoles,
      'schoolCode': schoolCode,
      'scope': scope,
      'visibility': visibility,
      'joinMode': joinMode,
      'isActive': isActive,
      'memberCount': memberCount,
      'messageCount': messageCount,
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'lastMessageBy': lastMessageBy,
      'lastMessagePreview': lastMessagePreview,
      'avatarUrl': avatarUrl,
      'coverImage': coverImage,
      'category': category,
      'tags': tags,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'rules': rules,
      'allowImages': allowImages,
      'allowLinks': allowLinks,
    };
  }

  factory CommunityModel.fromJson(Map<String, dynamic> json) {
    return CommunityModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'] ?? '',
      standards: List<String>.from(json['standards'] ?? []),
      audienceRoles: List<String>.from(json['audienceRoles'] ?? []),
      schoolCode: json['schoolCode'] ?? '',
      scope: json['scope'] ?? 'global',
      visibility: json['visibility'] ?? 'public',
      joinMode: json['joinMode'] ?? 'open',
      isActive: json['isActive'] ?? true,
      memberCount: json['memberCount'] ?? 0,
      messageCount: json['messageCount'] ?? 0,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'])
          : null,
      lastMessageBy: json['lastMessageBy'] ?? '',
      lastMessagePreview: json['lastMessagePreview'] ?? '',
      avatarUrl: json['avatarUrl'] ?? '',
      coverImage: json['coverImage'] ?? '',
      category: json['category'] ?? 'general',
      tags: List<String>.from(json['tags'] ?? []),
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
      createdByRole: json['createdByRole'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      rules: json['rules'] ?? '',
      allowImages: json['allowImages'] ?? false,
      allowLinks: json['allowLinks'] ?? true,
    );
  }

  // Get icon based on category
  String getCategoryIcon() {
    switch (category.toLowerCase()) {
      case 'academic':
        return '📚';
      case 'sports':
        return '⚽';
      case 'arts':
        return '🎨';
      case 'technology':
        return '💻';
      case 'science':
        return '🔬';
      case 'music':
        return '🎵';
      default:
        return '👥';
    }
  }
}
