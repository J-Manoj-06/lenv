/// Cloudflare R2 Configuration
///
/// ⚠️ IMPORTANT SECURITY NOTES:
///
/// 1. NEVER hardcode sensitive credentials in your Flutter app.
/// 2. Use secure storage: flutter_secure_storage package
/// 3. For production, generate signed URLs from Firebase Cloud Functions
/// 4. Rotate API tokens regularly
/// 5. Use IP-based restrictions on Cloudflare tokens
///
/// This is a template - replace with your actual credentials in secure way
class CloudflareConfig {
  /// Your Cloudflare Account ID
  /// Found at: Dashboard → R2 → Copy Account ID
  static const String accountId = '4c51b62d64def00af4856f10b6104fe2';

  /// Your R2 bucket name
  /// Created in: Dashboard → R2 → Create Bucket
  static const String bucketName = 'lenv-storage';

  /// API Token Access Key ID
  /// Created in: R2 Settings → API Tokens → Create Token
  static const String accessKeyId = '986dbaee695efe7655ae25759adc40b6';

  /// API Token Secret Access Key
  /// Created in: R2 Settings → API Tokens → Create Token
  /// ⚠️ Only shown once during creation - save securely
  static const String secretAccessKey =
      '4f0ad48f2941b9a2cb4f524f05707ed136e1826674fe78f3333fb33b66f0f53d';

  /// Public domain for accessing files
  /// Options:
  /// 1. Default R2 URL: {bucketName}.{accountId}.r2.cloudflarestorage.com
  /// 2. Custom domain: cdn.yourdomain.com (requires DNS setup)
  /// 3. Cloudflare Pages: yourdomain.pages.dev
  static const String r2Domain = 'https://files.lenv1.tech';

  /// API Token Permissions Required:
  /// - s3:PutObject (upload files)
  /// - s3:GetObject (read files)
  /// - s3:ListBucket (list files)
  ///
  /// Restricted to: Your bucket only

  /// URL validity duration for signed uploads
  static const Duration signedUrlDuration = Duration(hours: 24);

  /// Maximum file sizes
  static const int maxImageSize = 50 * 1024 * 1024; // 50MB
  static const int maxPdfSize = 100 * 1024 * 1024; // 100MB

  /// Firebase endpoint (if using server-signed URLs)
  static const String firebaseCloudFunctionUrl =
      'https://asia-south1-lenv-cb08e.cloudfunctions.net/uploadFileToR2';
}

/// Alternative: Secure Storage Implementation
/// Use this for production apps
///
/// Example with flutter_secure_storage:
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
///
///   // Similar methods for other credentials
/// }
/// ```

/// Environment-based Configuration
/// Use this pattern for different environments
class CloudflareConfigEnv {
  static const String _env = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'dev',
  );

  static String get accountId {
    switch (_env) {
      case 'prod':
        return 'PROD_ACCOUNT_ID';
      case 'staging':
        return 'STAGING_ACCOUNT_ID';
      default:
        return 'DEV_ACCOUNT_ID';
    }
  }

  static String get r2Domain {
    switch (_env) {
      case 'prod':
        return 'cdn.yourdomain.com';
      case 'staging':
        return 'cdn-staging.yourdomain.com';
      default:
        return 'files.lenv1.tech'; // Worker domain for free-egress media
    }
  }
}

/// Setup Instructions:
/// 
/// 1. Go to: https://dash.cloudflare.com
/// 2. Select your account
/// 3. Go to R2 (Cloudflare's object storage)
/// 4. Click "Create Bucket"
/// 5. Name it: app-media
/// 6. Copy your Account ID from the dashboard
/// 7. Go to R2 Settings → API Tokens
/// 8. Create a new token with:
///    - Token name: flutter-app-upload
///    - Permissions: s3:GetObject, s3:PutObject, s3:ListBucket
///    - Restrict to bucket: app-media
///    - TTL: 10 years
/// 9. Copy Access Key ID and Secret Access Key
/// 10. (Optional) Setup custom domain in R2 Settings
/// 11. Update this file with actual credentials
/// 
/// For Production Security:
/// 1. Use Firebase Cloud Functions to generate signed URLs
/// 2. Store credentials in Cloudflare environment variables
/// 3. Or use Cloudflare Durable Objects for token management
/// 4. Never expose credentials to the client app
