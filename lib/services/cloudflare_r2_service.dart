import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
      // Sanitize filename for the object key to avoid signature issues with
      // spaces/brackets/special characters. Keep original name for metadata.
      final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final key = 'media/$timestamp/$safeFileName';
      // Use the same segment-wise encoding for the URL as used in signing
      final encodedKey = key.split('/').map(Uri.encodeComponent).join('/');

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
          '$_endpoint/$bucketName/$encodedKey'
          '?X-Amz-Algorithm=${credential['algorithm']}'
          '&X-Amz-Credential=${credential['credential']}'
          '&X-Amz-Date=${credential['date']}'
          '&X-Amz-Expires=${credential['expires']}'
          '&X-Amz-SignedHeaders=${credential['signedHeaders']}'
          '&X-Amz-Signature=${credential['signature']}';

      if (fileName != safeFileName) {}

      return {
        'url': uploadUrl,
        'key': key,
        'expiresAt': expiresAt.toIso8601String(),
        'r2PublicUrl':
            'https://$r2Domain/$key', // Worker domain serves /media/* for free egress
      };
    } catch (e) {
      throw Exception('Failed to generate signed URL: $e');
    }
  }

  /// Upload file using signed URL with retry logic
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
    const maxRetries = 3;
    const initialTimeout = Duration(seconds: 60);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Calculate timeout: 60s, 120s, 180s for retry attempts
        final timeout = initialTimeout * (attempt + 1);

        final request = http.Request('PUT', Uri.parse(signedUrl))
          ..bodyBytes = fileBytes
          ..headers['Content-Type'] = contentType;

        // Simulate progress for PUT request
        onProgress?.call(0);

        // Add timeout to prevent hanging
        final streamedResponse = await request.send().timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              'Upload timed out after ${timeout.inSeconds}s',
            );
          },
        );

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

          // r2Domain already includes https://, so just concatenate
          final publicUrl = '$r2Domain$pathWithoutBucket';
          return publicUrl;
        } else {
          final responseBody = await streamedResponse.stream.bytesToString();

          // Don't retry on client errors (4xx), only server errors (5xx) and network issues
          if (streamedResponse.statusCode >= 400 &&
              streamedResponse.statusCode < 500) {
            throw Exception(
              'Upload failed: ${streamedResponse.statusCode} - $responseBody',
            );
          }

          // Retry on server errors
          if (attempt < maxRetries - 1) {
            await Future.delayed(
              Duration(seconds: (attempt + 1) * 2),
            ); // 2s, 4s, 6s
            continue;
          }
          throw Exception(
            'Upload failed after $maxRetries attempts: ${streamedResponse.statusCode}',
          );
        }
      } on SocketException catch (e) {
        // Network error - retry with exponential backoff
        if (attempt < maxRetries - 1) {
          await Future.delayed(
            Duration(seconds: (attempt + 1) * 2),
          ); // 2s, 4s, 6s
          continue;
        }
        throw Exception('Network error after $maxRetries attempts: $e');
      } on TimeoutException catch (e) {
        // Timeout - retry with longer timeout
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        throw Exception('Upload timeout after $maxRetries attempts: $e');
      } catch (e) {
        // For other errors, don't retry
        throw Exception('Failed to upload file: $e');
      }
    }

    throw Exception('Upload failed after $maxRetries attempts');
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

    // AWS Signature V4 process
    final credentialScope = '$shortDate/auto/s3/aws4_request';
    final credential = '$accessKeyId/$credentialScope';

    // Create canonical request using account-level endpoint
    // Path includes bucket name: /{bucketName}/{key}
    // IMPORTANT: The key in the canonical request must be URL-encoded to match
    // what the HTTP client will send and what R2 will receive
    final encodedCredential = Uri.encodeComponent(credential);
    final encodedKey = key.split('/').map(Uri.encodeComponent).join('/');
    final canonicalQueryString =
        'X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=$encodedCredential&X-Amz-Date=$dateStr&X-Amz-Expires=$expiresAt&X-Amz-SignedHeaders=host';
    final canonicalHeaders = 'host:$uploadHostname';
    final signedHeaders = 'host';
    final hashedPayload = 'UNSIGNED-PAYLOAD'; // For pre-signed URLs

    final canonicalRequest =
        '$method\n/$bucketName/$encodedKey\n$canonicalQueryString\n$canonicalHeaders\n\n$signedHeaders\n$hashedPayload';

    // Debug: Log canonical request for troubleshooting

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
    return '$year$month${day}T$hour$minute${second}Z';
  }

  /// HMAC-SHA256 helper - returns List<int> for chaining
  List<int> _hmacSha256Bytes(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
  }

  /// Delete file from R2 using AWS Signature V4
  Future<void> deleteFile({required String key}) async {
    try {
      if (key.isEmpty) {
        throw Exception('Cannot delete: Empty file key provided');
      }

      // Ensure key is properly encoded
      final keyParts = key.split('/');
      final encodedKey = keyParts.map(Uri.encodeComponent).join('/');

      final uploadHostname = '$accountId.r2.cloudflarestorage.com';

      final credential = await _getSignatureHeaders(
        method: 'DELETE',
        bucketName: bucketName,
        key: key,
        contentType: '',
        expiresAt: '86400', // 24 hours
        uploadHostname: uploadHostname,
      );

      // Build delete URL without adding extra https://
      final deleteUrl =
          'https://$uploadHostname/$bucketName/$encodedKey'
          '?X-Amz-Algorithm=${credential['algorithm']}'
          '&X-Amz-Credential=${credential['credential']}'
          '&X-Amz-Date=${credential['date']}'
          '&X-Amz-Expires=${credential['expires']}'
          '&X-Amz-SignedHeaders=${credential['signedHeaders']}'
          '&X-Amz-Signature=${credential['signature']}';

      final response = await http.delete(Uri.parse(deleteUrl));

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception(
          'Delete failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to delete file from R2: $e');
    }
  }
}
