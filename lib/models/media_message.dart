import 'package:cloud_firestore/cloud_firestore.dart';

/// Media message metadata stored in Firestore
/// Actual file stored in Cloudflare R2
class MediaMessage {
  final String id;
  final String senderId;
  final String senderRole; // 'teacher', 'parent', 'student'
  final String conversationId;

  // Media info
  final String fileName;
  final String fileType; // 'image/jpeg', 'application/pdf', etc
  final int fileSize; // in bytes
  final String r2Url; // URL from Cloudflare R2
  final String? thumbnailUrl; // Only for images, base64 or R2 URL

  final DateTime createdAt;
  final DateTime? deletedAt; // Soft delete

  // Read status
  final bool readByTeacher;
  final bool readByParent;
  final bool readByStudent;

  // Upload status
  final bool isPending;
  final bool uploadFailed;
  final String? errorMessage;

  // Media dimensions (for images)
  final int? width;
  final int? height;

  MediaMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.conversationId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.r2Url,
    this.thumbnailUrl,
    required this.createdAt,
    this.deletedAt,
    this.readByTeacher = false,
    this.readByParent = false,
    this.readByStudent = false,
    this.isPending = false,
    this.uploadFailed = false,
    this.errorMessage,
    this.width,
    this.height,
  });

  /// Check if this is an image
  bool get isImage => fileType.startsWith('image/');

  /// Check if this is a PDF
  bool get isPdf => fileType == 'application/pdf';

  /// Format file size to readable format (KB, MB, etc)
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Create from Firestore document
  factory MediaMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderRole: data['senderRole'] ?? 'student',
      conversationId: data['conversationId'] ?? '',
      fileName: data['fileName'] ?? 'unknown',
      fileType: data['fileType'] ?? 'application/octet-stream',
      fileSize: data['fileSize'] ?? 0,
      r2Url: data['r2Url'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      readByTeacher: data['readByTeacher'] ?? false,
      readByParent: data['readByParent'] ?? false,
      readByStudent: data['readByStudent'] ?? false,
      isPending: doc.metadata.hasPendingWrites,
      uploadFailed: data['uploadFailed'] ?? false,
      errorMessage: data['errorMessage'],
      width: data['width'],
      height: data['height'],
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'conversationId': conversationId,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'r2Url': r2Url,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'readByTeacher': readByTeacher,
      'readByParent': readByParent,
      'readByStudent': readByStudent,
      'uploadFailed': uploadFailed,
      'errorMessage': errorMessage,
      'width': width,
      'height': height,
    };
  }

  /// Create a copy with updated fields
  MediaMessage copyWith({
    String? id,
    String? senderId,
    String? senderRole,
    String? conversationId,
    String? fileName,
    String? fileType,
    int? fileSize,
    String? r2Url,
    String? thumbnailUrl,
    DateTime? createdAt,
    DateTime? deletedAt,
    bool? readByTeacher,
    bool? readByParent,
    bool? readByStudent,
    bool? isPending,
    bool? uploadFailed,
    String? errorMessage,
    int? width,
    int? height,
  }) {
    return MediaMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      conversationId: conversationId ?? this.conversationId,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      r2Url: r2Url ?? this.r2Url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      readByTeacher: readByTeacher ?? this.readByTeacher,
      readByParent: readByParent ?? this.readByParent,
      readByStudent: readByStudent ?? this.readByStudent,
      isPending: isPending ?? this.isPending,
      uploadFailed: uploadFailed ?? this.uploadFailed,
      errorMessage: errorMessage ?? this.errorMessage,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
