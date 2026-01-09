# 🔧 COPY-PASTE CODE BLOCKS

Use this file if you want to manually update your code. Just copy the code blocks below.

---

## 1️⃣ Update `lib/config/cloudflare_config.dart`

Replace the entire CloudflareConfig class with this:

```dart
/// Cloudflare R2 Configuration
///
/// ⚠️ IMPORTANT SECURITY NOTES:
///
/// 1. NEVER hardcode sensitive credentials in production
/// 2. Use secure storage: flutter_secure_storage package
/// 3. For production, generate signed URLs from Firebase Cloud Functions
/// 4. Rotate API tokens regularly
/// 5. Use IP-based restrictions on Cloudflare tokens
///
/// This is a development template - replace with your actual credentials

class CloudflareConfig {
  /// Your Cloudflare Account ID
  /// Found at: https://dash.cloudflare.com → R2 → Copy Account ID
  /// Example: 4c51b62d64def00af4856f10b6104fe2
  static const String accountId = 'YOUR_ACCOUNT_ID_HERE';

  /// Your R2 bucket name
  /// Created in: https://dash.cloudflare.com → R2 → Create Bucket
  /// Example: lenv-storage
  static const String bucketName = 'lenv-storage';

  /// API Token Access Key ID
  /// Created in: https://dash.cloudflare.com → R2 Settings → API Tokens → Create Token
  /// Example: e5606eba19c4cc21cb9493128afc1f01
  static const String accessKeyId = 'YOUR_ACCESS_KEY_ID_HERE';

  /// API Token Secret Access Key
  /// Created in: https://dash.cloudflare.com → R2 Settings → API Tokens → Create Token
  /// ⚠️ Only shown once during creation - save securely!
  /// Example: e060ff4595dd7d3e420eebaa76a5eb9b2d360bb7e078e5b039121dcac6e65e7e
  static const String secretAccessKey = 'YOUR_SECRET_ACCESS_KEY_HERE';

  /// Public domain for accessing files
  /// Options:
  /// 1. Default R2 URL: {bucketName}.{accountId}.r2.cloudflarestorage.com
  /// 2. Custom domain: cdn.yourdomain.com (requires DNS setup in Cloudflare)
  /// 3. Cloudflare Pages: yourdomain.pages.dev
  /// Example: files.lenv1.tech
  static const String r2Domain = 'files.lenv1.tech';

  /// Firebase Cloud Function URL for server-side uploads
  /// Found in: https://console.firebase.google.com → Functions → uploadFileToR2
  /// Format: https://{region}-{projectId}.cloudfunctions.net/uploadFileToR2
  /// Example: https://us-central1-new-reward-prod.cloudfunctions.net/uploadFileToR2
  static const String firebaseCloudFunctionUrl = 'YOUR_CLOUD_FUNCTION_URL_HERE';

  /// API Token Permissions Required:
  /// - s3:PutObject (upload files)
  /// - s3:GetObject (read files)
  /// - s3:ListBucket (list files)
  /// Restricted to: Your bucket only

  /// URL validity duration for signed uploads
  static const Duration signedUrlDuration = Duration(hours: 24);

  /// Maximum file sizes
  static const int maxImageSize = 50 * 1024 * 1024; // 50MB
  static const int maxPdfSize = 100 * 1024 * 1024; // 100MB
}

/// Alternative: Secure Storage Implementation (for production)
/// Use this pattern with flutter_secure_storage
///
/// Example:
/// ```dart
/// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
///
/// class SecureCloudflareConfig {
///   static const _storage = FlutterSecureStorage();
///
///   static Future<String> getAccountId() async {
///     return await _storage.read(key: 'cf_account_id') ?? '';
///   }
///
///   static Future<void> setAccountId(String value) async {
///     await _storage.write(key: 'cf_account_id', value: value);
///   }
/// }
/// ```
```

**What to change:**
1. Replace `YOUR_ACCOUNT_ID_HERE` with your actual Account ID
2. Replace `YOUR_ACCESS_KEY_ID_HERE` with your Access Key ID
3. Replace `YOUR_SECRET_ACCESS_KEY_HERE` with your Secret Access Key
4. Keep `r2Domain` as `files.lenv1.tech` (unless you have a different domain)
5. Replace `YOUR_CLOUD_FUNCTION_URL_HERE` with your Cloud Function URL

---

## 2️⃣ Update `lib/providers/media_chat_provider.dart`

Find the `_uploadMedia` method (around line 120) and replace it with:

```dart
/// Upload media to R2 via Cloud Function
/// This is the recommended approach because:
/// - Server handles Cloudflare credentials (not exposed to client)
/// - Automatic organized folder structure in R2
/// - Server-side validation and error handling
Future<void> _uploadMedia(File file) async {
  try {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    _currentError = null;
    final fileName = file.path.split('/').last;
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Show progress
    _uploadProgress[messageId] = 0;
    notifyListeners();

    print('📤 Starting upload: $fileName');

    // Call Cloud Function to upload
    final result = await _cloudFunctionService.uploadFile(
      file: file,
      fileName: fileName,
      schoolId: 'test-school', // TODO: Get from user's school
      communityId: conversationId, // Use conversation as community
      groupId: 'test-group', // TODO: Get from current group
      messageId: messageId,
      onProgress: (progress) {
        _uploadProgress[messageId] = progress;
        notifyListeners();
      },
    );

    // Create MediaMessage from upload result
    final media = MediaMessage(
      id: messageId,
      fileName: result['fileName'] as String,
      fileType: result['fileType'] as String,
      filePath: result['publicUrl'] as String, // Public URL
      thumbnailPath: result['publicUrl'] as String, // Use same for now
      fileSize: (result['fileSizeKb'] as double).toInt(),
      uploadedBy: currentUser.uid,
      uploadedAt: DateTime.now(),
      width: 0, // Update if image
      height: 0, // Update if image
      conversationId: conversationId,
      senderId: currentUser.uid,
      senderRole: 'teacher', // TODO: Get from auth provider
    );

    // Update list
    _mediaMessages.insert(0, media);
    _uploadProgress.remove(messageId);
    _currentError = null;
    notifyListeners();

    print('✅ Media uploaded: ${media.fileName}');

  } catch (e) {
    _setError('Upload failed: $e');
    print('❌ Upload error: $e');
  }
}
```

---

## 3️⃣ Create `lib/services/cloud_function_upload_service.dart`

Create a new file with this code:

```dart
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
///
/// Flow:
/// 1. Get Firebase ID token (proves user is logged in)
/// 2. Encode file to base64
/// 3. Send to Cloud Function with token
/// 4. Cloud Function uploads to R2
/// 5. Receive public URL back
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
  /// - file: The file to upload (image, PDF, etc)
  /// - fileName: Name for the file (will be saved with this name)
  /// - schoolId: School identifier (for folder organization)
  /// - communityId: Community identifier
  /// - groupId: Group identifier
  /// - messageId: Message identifier (each message has its own folder)
  /// - onProgress: Callback showing upload progress (0-100)
  ///
  /// Returns: Map with:
  /// - publicUrl: The HTTPS URL to access the file
  /// - r2Path: Where it's stored in R2
  /// - fileSizeKb: How big the file is
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
      print('📤 Starting Cloud Function upload');
      print('   File: $fileName');
      print('   School: $schoolId → Community: $communityId');
      print('   Group: $groupId → Message: $messageId');

      // ===== STEP 1: Get Firebase ID Token =====
      // This proves to the Cloud Function that the user is logged in
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated - please login first');
      }

      final token = await currentUser.getIdToken();
      if (token == null) {
        throw Exception('Failed to get authentication token');
      }

      print('✅ Got Firebase token');
      onProgress?.call(10);

      // ===== STEP 2: Read File and Encode to Base64 =====
      // We send the file as base64 text (not binary)
      final fileBytes = await file.readAsBytes();
      final fileBase64 = base64Encode(fileBytes);
      final fileSizeKb = (fileBytes.length / 1024).toStringAsFixed(2);

      print('✅ File encoded to base64 ($fileSizeKb KB)');
      onProgress?.call(30);

      // ===== STEP 3: Get MIME Type =====
      // This tells the Cloud Function what type of file it is
      final mimeType = getMimeType(fileName) ?? 'application/octet-stream';
      print('✅ MIME type: $mimeType');

      // ===== STEP 4: Prepare Request =====
      final requestBody = {
        'fileName': fileName,
        'fileBase64': fileBase64, // The actual file content (text format)
        'fileType': mimeType, // image/jpeg, application/pdf, etc
        'schoolId': schoolId,
        'communityId': communityId,
        'groupId': groupId,
        'messageId': messageId,
      };

      onProgress?.call(50);

      // ===== STEP 5: Call Cloud Function =====
      print('🌐 Calling Cloud Function...');
      print('   URL: $functionUrl');

      final response = await http
          .post(
            Uri.parse(functionUrl),
            headers: {
              'Authorization': 'Bearer $token', // Prove it's this user
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () =>
                throw Exception('Upload timeout (took more than 5 minutes)'),
          );

      print('📥 Cloud Function response: ${response.statusCode}');
      onProgress?.call(80);

      // ===== STEP 6: Handle Response =====
      if (response.statusCode != 200) {
        print('❌ Cloud Function error: ${response.body}');

        // Parse error message if available
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['error'] ?? 'Upload failed');
        } catch (_) {
          throw Exception(
            'Upload failed with status ${response.statusCode}',
          );
        }
      }

      // ===== STEP 7: Parse Success Response =====
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (responseData['success'] != true) {
        throw Exception(responseData['error'] ?? 'Upload failed');
      }

      onProgress?.call(100);

      print('✅ File uploaded successfully!');
      print('   Public URL: ${responseData['publicUrl']}');
      print('   R2 Path: ${responseData['r2Path']}');
      print('   Size: ${responseData['fileSizeKb']} KB');

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
      rethrow; // Re-throw so caller can handle
    }
  }

  /// Get MIME type (file type) from filename
  /// Used to tell the server what kind of file we're sending
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
      'flac': 'audio/flac',
    };

    return mimeTypes[extension];
  }
}
```

---

## 4️⃣ Update `functions/uploadFileToR2.js`

Replace the entire file with the code from **COMPLETE_SETUP_GUIDE.md** section "Cloud Function Setup"

Or use the code block in that document - it's the full Cloud Function.

---

## 🎯 Quick Summary

1. **Update config file** - paste Cloudflare credentials
2. **Create Cloud Function service** - paste new file
3. **Update media provider** - replace _uploadMedia method
4. **Deploy Cloud Function** - run `firebase deploy --only functions:uploadFileToR2`
5. **Test** - follow testing instructions

---

## ⚡ Most Important Values to Get

Before you start, gather these 6 values:

1. **accountId** - from https://dash.cloudflare.com → R2
2. **accessKeyId** - from https://dash.cloudflare.com → R2 Settings → API Tokens
3. **secretAccessKey** - from https://dash.cloudflare.com → R2 Settings → API Tokens
4. **r2Domain** - your custom domain (files.lenv1.tech)
5. **firebaseCloudFunctionUrl** - from https://console.firebase.google.com → Functions
6. **bucketName** - your R2 bucket (lenv-storage)

---

Without these 6 values, nothing will work. Get them first! ⚠️
