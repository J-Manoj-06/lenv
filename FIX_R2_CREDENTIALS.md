# 🔧 Fix R2 Upload Error - Invalid Credentials

## Error You're Seeing
```
❌ HandshakeException: Handshake error in client (OS Error: SSLV3_ALERT_HANDSHAKE_FAILURE)
```

## Root Cause
The Cloudflare R2 credentials in your code are **placeholder/example values**, not real API keys from your Cloudflare account.

---

## ✅ Solution: Get Real Cloudflare R2 Credentials

### Step 1: Go to Cloudflare Dashboard
1. Open https://dash.cloudflare.com
2. Login to your account
3. Click **R2** in the left sidebar
4. Click on your bucket: **lenv-media**

### Step 2: Get Your Account ID
1. In R2 overview page, you'll see **Account ID** at the top
2. Copy it (format: `1234567890abcdef1234567890abcdef`)

### Step 3: Create API Token
1. Click **Manage R2 API Tokens** (right side)
2. Click **Create API Token**
3. Name it: `lenv-app-upload`
4. Permissions: Select **Object Read & Write**
5. Click **Create API Token**
6. **IMPORTANT**: Copy both:
   - **Access Key ID** (starts with letters/numbers)
   - **Secret Access Key** (long string, shown only once!)

### Step 4: Get Your Custom Domain
1. In R2 bucket settings
2. Look for **Public URL** or **Custom Domain**
3. Should be: `https://files.lenv1.tech`

---

## Step 5: Update These 5 Files

Replace the placeholder credentials with your real ones in these files:

### 1. lib/screens/institute/institute_announcement_compose_screen.dart
**Line ~88-95**, replace:
```dart
final r2Service = CloudflareR2Service(
  accountId: 'YOUR_REAL_ACCOUNT_ID_HERE',
  bucketName: 'lenv-media',
  accessKeyId: 'YOUR_REAL_ACCESS_KEY_ID_HERE',
  secretAccessKey: 'YOUR_REAL_SECRET_ACCESS_KEY_HERE',
  r2Domain: 'https://files.lenv1.tech',
);
```

### 2. lib/screens/teacher/teacher_dashboard.dart
**Line ~2767-2774**, same replacement

### 3. lib/screens/messages/community_chat_page.dart
**Line ~245-252**, same replacement

### 4. lib/services/storage_service.dart
**Line ~5-11**, same replacement

### 5. lib/screens/debug/storage_debug_screen.dart
**Line ~33-39**, same replacement

---

## 🔐 Security Note

**DO NOT commit real credentials to Git!**

Better approach: Use environment variables or a config file:

```dart
// Create lib/config/r2_config.dart (add to .gitignore)
class R2Config {
  static const accountId = 'your_real_account_id';
  static const accessKeyId = 'your_real_access_key';
  static const secretAccessKey = 'your_real_secret_key';
}
```

Then import and use:
```dart
import '../config/r2_config.dart';

final r2Service = CloudflareR2Service(
  accountId: R2Config.accountId,
  accessKeyId: R2Config.accessKeyId,
  secretAccessKey: R2Config.secretAccessKey,
  ...
);
```

---

## Alternative: Use Firebase Storage Instead

If you don't want to set up Cloudflare R2, you can:

1. Go to Firebase Console: https://console.firebase.google.com
2. Select your project: **lenv-cb08e**
3. Click **Storage** in left menu
4. Click **Get Started** button
5. Choose **Production mode** → Start

Then the app will work with Firebase Storage (which was the original setup).

---

## Quick Test

After updating credentials:
1. Hot restart: Press `R` in terminal
2. Try uploading an announcement image
3. Check console logs for: `✅ Upload successful!`

If still failing, verify credentials are correct in Cloudflare dashboard.
