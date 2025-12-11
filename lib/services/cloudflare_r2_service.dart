import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Service to handle Cloudflare R2 authentication and uploads
///
/// Cloudflare R2 is S3-compatible, so it uses the same authentication
/// method as AWS S3. Your app uses your R2 credentials (not AWS) to
/// sign upload requests, allowing direct uploads from Flutter to R2
/// without needing a backend server.
class CloudflareR2Service {
  final String accountId;
  final String bucketName;
  final String accessKeyId;
  final String secretAccessKey;
  final String r2Domain;

  /// Account-level R2 endpoint (most reliable)
  late String _endpoint;

  CloudflareR2Service({
    required this.accountId,
    required this.bucketName,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.r2Domain,
  }) {
    // Use account-level endpoint: https://{accountId}.r2.cloudflarestorage.com
    _endpoint = 'https://$accountId.r2.cloudflarestorage.com';
  }

  /// Generate a signed URL for direct upload to R2
  /// This allows client-side upload without exposing credentials
  ///
  /// Duration: time the URL is valid for (default 1 hour, max 7 days)
  ///
  /// Returns: {url, key, expires_at}
  Future<Map<String, dynamic>> generateSignedUploadUrl({
    required String fileName,
    required String fileType,
    Duration validFor = const Duration(hours: 1),
  }) async {
    try {
      // Ensure expiry is within R2 limits (max 7 days = 604800 seconds)
      final maxExpiry = const Duration(days: 7);
      final expiryDuration = validFor.inSeconds > maxExpiry.inSeconds
          ? maxExpiry
          : validFor;

      // Generate unique key with timestamp to prevent collisions
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Encode only the file name portion so spaces/special chars sign correctly
      final encodedFileName = Uri.encodeComponent(fileName);
      final key = 'media/$timestamp/$encodedFileName';

      final expiresAt = DateTime.now().add(expiryDuration);
      // X-Amz-Expires is the DURATION in seconds, not Unix timestamp
      final expiresDurationSeconds = expiryDuration.inSeconds.toString();

      // AWS Signature Version 4 signing process
      // Using account-level endpoint: https://{accountId}.r2.cloudflarestorage.com/{bucketName}/{key}
      final uploadHostname = '$accountId.r2.cloudflarestorage.com';

      final credential = await _getSignatureHeaders(
        method: 'PUT',
        bucketName: bucketName,
        key: key,
        contentType: fileType,
        expiresAt: expiresDurationSeconds,
        uploadHostname: uploadHostname,
      );

      // URL format: https://{accountId}.r2.cloudflarestorage.com/{bucketName}/{key}?params
      // IMPORTANT: Query parameters in the URL must match the canonical request exactly
      final uploadUrl =
          '$_endpoint/$bucketName/$key'
          '?X-Amz-Algorithm=${credential['algorithm']}'
          '&X-Amz-Credential=${credential['credential']}'
          '&X-Amz-Date=${credential['date']}'
          '&X-Amz-Expires=${credential['expires']}'
          '&X-Amz-SignedHeaders=${credential['signedHeaders']}'
          '&X-Amz-Signature=${credential['signature']}';

      print('✅ Signed URL generated');
      print('🔍 Key: $key');
      print(
        '🔍 Expires In: ${expiryDuration.inSeconds} seconds (${(expiryDuration.inHours)} hours)',
      );
      print('🔍 Upload endpoint: $_endpoint');
      print(
        '🔍 Upload URL format: {accountId}/r2.cloudflarestorage.com/{bucket}/{key}',
      );

      return {
        'url': uploadUrl,
        'key': key,
        'expiresAt': expiresAt.toIso8601String(),
        'r2PublicUrl':
            'https://$r2Domain/$key', // Custom domain already points to bucket root
      };
    } catch (e) {
      throw Exception('Failed to generate signed URL: $e');
    }
  }

  /// Upload file using signed URL
  ///
  /// fileBytes: raw file data
  /// signedUrl: from generateSignedUploadUrl
  /// contentType: MIME type
  /// onProgress: callback for upload progress (0-100)
  Future<String> uploadFileWithSignedUrl({
    required List<int> fileBytes,
    required String signedUrl,
    required String contentType,
    Function(int)? onProgress,
  }) async {
    try {
      print('🔍 R2 Upload: Starting upload');
      print('🔍 R2 Upload: Content-Type: $contentType');
      print('🔍 R2 Upload: File size: ${fileBytes.length} bytes');

      final request = http.Request('PUT', Uri.parse(signedUrl))
        ..bodyBytes = fileBytes
        ..headers['Content-Type'] = contentType;

      // Simulate progress for PUT request
      onProgress?.call(0);
      print('🔍 R2 Upload: Sending request...');

      final streamedResponse = await request.send();

      print('🔍 R2 Upload: Response status: ${streamedResponse.statusCode}');

      if (streamedResponse.statusCode == 200) {
        // Simulate progress completion
        onProgress?.call(100);

        // Extract public URL from signed URL
        final uri = Uri.parse(signedUrl);
        final pathWithoutQuery = uri.path;

        // Remove bucket name from path since custom domain points to bucket root
        // Path format: /lenv-storage/media/... → /media/...
        final pathWithoutBucket = pathWithoutQuery.replaceFirst(
          '/$bucketName/',
          '/',
        );

        final publicUrl = 'https://$r2Domain$pathWithoutBucket';
        print('✅ R2 Upload: Success! URL: $publicUrl');
        return publicUrl;
      } else {
        print('❌ R2 Upload: Failed with status ${streamedResponse.statusCode}');
        final responseBody = await streamedResponse.stream.bytesToString();
        print('❌ R2 Upload: Response: $responseBody');
        throw Exception('Upload failed: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print('❌ R2 Upload: Exception: $e');
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Get AWS Signature V4 headers for signing
  /// This is used internally for generating signed URLs
  Future<Map<String, String>> _getSignatureHeaders({
    required String method,
    required String bucketName,
    required String key,
    required String contentType,
    required String expiresAt,
    required String uploadHostname,
  }) async {
    final date = DateTime.now().toUtc();
    final dateStr = _formatAmzDate(date);
    final shortDate = dateStr.substring(0, 8);

    print('🕐 Device local time: ${DateTime.now()}');
    print('🕐 UTC time used for signature: $dateStr');
    print(
      '⚠️ If you see 403 RequestTimeTooSkewed, your device clock is out of sync',
    );
    print(
      '⚠️ FIX: Settings → Date & Time → Turn OFF "Set automatically", wait 5s, turn it back ON',
    );

    // AWS Signature V4 process
    final credentialScope = '$shortDate/auto/s3/aws4_request';
    final credential = '$accessKeyId/$credentialScope';

    // Create canonical request using account-level endpoint
    // Path includes bucket name: /{bucketName}/{key}
    // AWS Signature V4 format requires exact structure:
    // For presigned URLs, query parameters MUST be in sorted order
    // and credentials must use RFC 3986 encoding (%XX format)
    final encodedCredential = Uri.encodeComponent(credential);
    final canonicalQueryString =
        'X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=$encodedCredential&X-Amz-Date=$dateStr&X-Amz-Expires=$expiresAt&X-Amz-SignedHeaders=host';
    final canonicalHeaders = 'host:$uploadHostname';
    final signedHeaders = 'host';
    final hashedPayload = 'UNSIGNED-PAYLOAD'; // For pre-signed URLs

    final canonicalRequest =
        '$method\n/$bucketName/$key\n$canonicalQueryString\n$canonicalHeaders\n\n$signedHeaders\n$hashedPayload';

    // Debug: Log canonical request for troubleshooting
    print('🔐 Debug - Canonical Request (escaped):');
    print('---');
    print(canonicalRequest.replaceAll('\n', '\\n'));
    print('---');
    print('🔐 Debug - uploadHostname: $uploadHostname');
    print('🔐 Debug - bucketName: $bucketName');

    // Create string to sign
    final hashedRequest = sha256
        .convert(utf8.encode(canonicalRequest))
        .toString();
    final stringToSign =
        'AWS4-HMAC-SHA256\n$dateStr\n$credentialScope\n$hashedRequest';

    // Calculate signature using proper AWS Signature V4 key derivation
    // Each step uses the previous result as the key
    final kDate = _hmacSha256Bytes(
      utf8.encode('AWS4$secretAccessKey'),
      shortDate,
    );
    final kRegion = _hmacSha256Bytes(kDate, 'auto');
    final kService = _hmacSha256Bytes(kRegion, 's3');
    final kSigning = _hmacSha256Bytes(kService, 'aws4_request');
    final signatureBytes = _hmacSha256Bytes(kSigning, stringToSign);
    final signature = signatureBytes
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();

    return {
      'algorithm': 'AWS4-HMAC-SHA256',
      'credential': encodedCredential,
      'date': dateStr,
      'expires': expiresAt,
      'signedHeaders': 'host',
      'signature': signature,
    };
  }

  /// Format date for AWS signatures
  String _formatAmzDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '${year}${month}${day}T${hour}${minute}${second}Z';
  }

  /// HMAC-SHA256 helper - returns List<int> for chaining
  List<int> _hmacSha256Bytes(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
  }

  /// Delete file from R2
  /// This is a backend operation - requires server-side authentication
  Future<void> deleteFile({required String key}) async {
    try {
      final url = '$_endpoint/$bucketName/$key';
      final response = await http.delete(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_generateAuthToken()'},
      );

      if (response.statusCode != 204) {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  /// Generate authentication token (placeholder - implement with your auth system)
  String _generateAuthToken() {
    // This should be obtained from your backend
    // For now, returning empty - implement based on your auth system
    return '';
  }
}
