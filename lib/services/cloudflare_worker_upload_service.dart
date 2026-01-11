import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Service to upload files to Cloudflare R2 via Cloudflare Worker
/// (Replaces Firebase Cloud Function for simpler architecture)
///
/// Benefits:
/// 1. No serverless compute cold starts (Workers always hot)
/// 2. No Firebase dependency (pure Cloudflare stack)
/// 3. Automatic free egress when Worker fetches from R2
/// 4. Simpler debugging and monitoring
class CloudflareWorkerUploadService {
  final String
  workerUrl; // e.g., https://whatsapp-media-worker.giridharannj.workers.dev
  final FirebaseAuth _auth;

  CloudflareWorkerUploadService({
    required this.workerUrl,
    required FirebaseAuth auth,
  }) : _auth = auth;

  /// Upload file to R2 via Cloudflare Worker
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
  /// Returns: {publicUrl, key, fileName, fileSize, expiresAt}
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
      // Get Firebase ID token for authentication (optional, but good practice)
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      onProgress?.call(10);

      // Read file
      final fileBytes = await file.readAsBytes();
      final fileSizeKb = (fileBytes.length / 1024).toStringAsFixed(2);

      onProgress?.call(20);

      // Get MIME type
      final mimeType = _getMimeType(fileName) ?? 'application/octet-stream';


      // Prepare multipart form data
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$workerUrl/upload'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer $token';

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: null, // Let the request infer it
        ),
      );

      // Add metadata
      request.fields['schoolId'] = schoolId;
      request.fields['communityId'] = communityId;
      request.fields['groupId'] = groupId;
      request.fields['messageId'] = messageId;

      onProgress?.call(50);

      // Send request with streaming response for progress
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw Exception('Upload timeout'),
      );

      onProgress?.call(80);


      // Get response body
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = _parseJsonResponse(responseBody);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Upload failed: ${streamedResponse.statusCode}');
      }

      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Upload failed');
      }

      onProgress?.call(100);


      return {
        'publicUrl': responseData['publicUrl'] as String,
        'key': responseData['key'] as String,
        'fileName': responseData['fileName'] as String,
        'fileSize': responseData['fileSize'] as int,
        'expiresAt': responseData['expiresAt'] as String,
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Get MIME type from filename
  String? _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    final mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
    };
    return mimeTypes[ext];
  }

  /// Parse JSON response safely
  Map<String, dynamic> _parseJsonResponse(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': 'Invalid response format', 'raw': body};
    }
  }
}
