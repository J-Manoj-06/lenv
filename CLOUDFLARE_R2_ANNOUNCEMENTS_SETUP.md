# Cloudflare R2 Setup for Announcements

## Configuration Status

Your `institute_announcement_compose_screen.dart` now uses **Cloudflare R2** instead of Firebase Storage.

## Required Cloudflare R2 Credentials

Replace these values in `institute_announcement_compose_screen.dart` (around line 95):

```dart
final r2Service = CloudflareR2Service(
  accountId: 'YOUR_ACCOUNT_ID', // ← Replace
  bucketName: 'lenv-media',
  accessKeyId: 'YOUR_API_TOKEN', // ← Replace
  secretAccessKey: 'YOUR_SECRET', // ← Replace
  r2Domain: 'https://files.lenv1.tech',
);
```

### How to Get Your Cloudflare R2 Credentials

#### 1. Get Account ID
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Bottom left → Click your account name
3. Go to **Account Settings**
4. Copy **Account ID** (looks like: `8e3e4c3c27f74e76e85a75e51e8ac0c5`)

#### 2. Create R2 API Token
1. Go to **R2** in left sidebar
2. Click **Settings** at bottom
3. Click **Create API token**
4. Choose **Edit (All Buckets)** or create custom permissions
5. Copy:
   - **Access Key ID** (like: `ae58fa3c9d19493c8e3dd83bbdd7a32b`)
   - **Secret Access Key** (like: `f4f39d5aef9b3e80b5...`)

#### 3. Verify R2 Domain
1. Go to **R2** → **Settings**
2. Look for **Custom Domain** section
3. Should be: `https://files.lenv1.tech`

---

## Testing Announcement Upload

After adding your credentials:

1. **Hot restart app** (press `R` in terminal)
2. Go to **Create Announcement**
3. Add text + image
4. Click **Post**
5. Watch console for:
   ```
   📤 Starting Cloudflare R2 upload...
   📂 Uploading to: announcements/announcement_...jpg
   ✅ Upload successful! URL: https://files.lenv1.tech/announcements/...
   ```

---

## What Happens Now

✅ **Images upload to Cloudflare R2** (not Firebase)
✅ **URLs stored in Firestore** (metadata only)
✅ **Faster delivery** via Cloudflare's CDN
✅ **Cost effective** compared to Firebase Storage

---

## Other Announcements Uploads

If you have multiple announcement screens, apply the same change to:
- Teacher announcements
- Community announcements
- Other media uploads

---

## Firestore Storage Rules (No Longer Needed)

You can now safely ignore/delete the Firebase Storage rules file since all media goes to Cloudflare R2.

---

## Troubleshooting

### Error: "Account ID not set"
- Replace `'YOUR_ACCOUNT_ID'` with actual ID from Cloudflare Dashboard

### Error: "Invalid API credentials"
- Verify API token has **Edit** permissions
- Check Account ID matches Cloudflare Dashboard
- Ensure no extra spaces in credentials

### Error: "Bucket not found"
- Verify bucket name is `lenv-media`
- Check bucket exists in R2 console

### Files not uploading
- Check internet connection
- Verify credentials are correct
- Check Cloudflare R2 API is not rate-limited
- Look at console logs for exact error message
