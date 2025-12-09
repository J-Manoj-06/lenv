import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Service to upload files to Cloudflare R2 via Firebase Cloud Function
///
/// This is more secure than client-side uploads because:
/// 1. Credentials are never exposed to the client
/// 2. Files are automatically organized in R2 bucket
/// 3. Server-side validation and error handling
class CloudFunctionUploadService {
  final String functionUrl;
  final FirebaseAuth _auth;

  CloudFunctionUploadService({
    required this.functionUrl,
    required FirebaseAuth auth,
  }) : _auth = auth;

  /// Upload file to R2 via Cloud Function
  ///
  /// Parameters:
  /// - file: File to upload
  /// - fileName: Name for the file in R2
  /// - schoolId: School identifier for folder organization
  /// - communityId: Community identifier
  /// - groupId: Group identifier
  /// - messageId: Message identifier (used as folder name)
  /// - onProgress: Callback for upload progress (0-100)
  ///
  /// Returns: {publicUrl, r2Path, fileSizeKb}
  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String fileName,
    required String schoolId,
    required String communityId,
    required String groupId,
    required String messageId,
    Function(int)? onProgress,
  }) async {
    try {
      // Get Firebase ID token for authentication
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      onProgress?.call(10);

      // Read file and encode to base64
      final fileBytes = await file.readAsBytes();
      final fileBase64 = base64Encode(fileBytes);
      final fileSizeKb = (fileBytes.length / 1024).toStringAsFixed(2);

      onProgress?.call(30);

      // Get MIME type
      final mimeType = getMimeType(fileName) ?? 'application/octet-stream';

      print('📤 Uploading file via Cloud Function');
      print('   File: $fileName ($fileSizeKb KB)');
      print('   Type: $mimeType');
      print(
        '   Path: schools/$schoolId/communities/$communityId/groups/$groupId/messages/$messageId',
      );

      // Prepare request body
      final requestBody = {
        'fileName': fileName,
        'fileBase64': fileBase64,
        'fileType': mimeType,
        'schoolId': schoolId,
        'communityId': communityId,
        'groupId': groupId,
        'messageId': messageId,
      };

      onProgress?.call(50);

      // Call Cloud Function
      final response = await http
          .post(
            Uri.parse(functionUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw Exception('Upload timeout'),
          );

      onProgress?.call(80);

      print('🔄 Cloud Function response: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ Cloud Function error: ${response.body}');
        throw Exception('Upload failed: ${response.statusCode}');
      }

      // Parse response
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Upload failed');
      }

      onProgress?.call(100);

      print('✅ File uploaded successfully');
      print('   Public URL: ${responseData['publicUrl']}');
      print('   R2 Path: ${responseData['r2Path']}');

      return {
        'publicUrl': responseData['publicUrl'] as String,
        'r2Path': responseData['r2Path'] as String,
        'fileName': responseData['fileName'] as String,
        'fileType': responseData['fileType'] as String,
        'fileSizeKb': responseData['fileSizeKb'] as double,
      };
    } catch (e) {
      print('❌ Upload error: $e');
      onProgress?.call(0);
      rethrow;
    }
  }

  /// Get MIME type from file name
  static String? getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    const mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
    };

    return mimeTypes[extension];
  }
}
