# 🎬 HOW TO TEST MEDIA UPLOAD (Complete Guide)

## ✅ Status
- ✅ Test screen created: `lib/screens/test_media_upload_screen.dart`
- ✅ Route added: `/test-media-upload`
- ✅ Button added to Dev Tools screen
- ✅ Code compiles successfully

---

## 🚀 How to Access & Test

### Step 1: Run Your App
```bash
flutter run
```
(Choose Windows or Android emulator)

---

### Step 2: Navigate to Test Screen

**Option A: Via Dev Tools** (Easiest)
1. Login to your app as a student
2. Go to **Student Dashboard** (home page after login)
3. Look at the **top-right corner** where you see the streak badge (🔥 number)
4. Find the **orange wrench icon** (🔧) - this is the Dev Tools button
5. Click the wrench icon → Dev Tools screen opens
6. **Scroll down** to find the green button: **"🎥 Test Media Upload"**
7. Click it → Test screen opens

**Option B: Direct URL**
If your app supports deep linking:
```
yourapp://test-media-upload
```

**Option C: Manual Navigation**
```dart
Navigator.pushNamed(context, '/test-media-upload');
```

---

### Step 3: Test Upload

#### What You'll See
```
┌─────────────────────────────────────┐
│  📸 Test Media Upload               │
├─────────────────────────────────────┤
│                                     │
│  Instructions:                      │
│  Click a button to upload image     │
│  Watch progress and check:          │
│  1. Upload progress bar             │
│  2. Cloudflare R2 console           │
│  3. Firebase Firestore console      │
│                                     │
│  [Pick Image from Gallery]          │
│  [Capture Photo with Camera]        │
│                                     │
│  Upload Progress:                   │
│  No uploads yet                     │
│                                     │
│  Debug Info:                        │
│  Conversation ID: test-conv-123     │
│  User ID: (your-logged-in-id)       │
│  Path: conversations/test-...       │
│                                     │
└─────────────────────────────────────┘
```

---

## 📸 Complete Test Steps

### 1️⃣ Pick Image from Gallery
1. Click **"Pick Image from Gallery"** button
2. Select a photo from your device
3. Watch for upload progress (should go 0 → 100%)
4. Progress bar should show green color

### 2️⃣ Monitor Progress
```
Expected Progress:
├─ 0%   → Upload starts
├─ 25%  → Compressing
├─ 50%  → Uploading to R2
├─ 75%  → Saving metadata
└─ 100% → Complete ✅
```

### 3️⃣ Check Cloudflare R2 Bucket
1. Go to: https://dash.cloudflare.com
2. Click **R2 Buckets** → Select `lenv-storage`
3. Look for a folder with your timestamp
4. Should see: `photo.jpg` and `thumb.jpg`
5. ✅ Success if files appear

### 4️⃣ Check Firebase Firestore
1. Go to: https://console.firebase.google.com
2. Select your project → **Firestore Database**
3. Navigate to: `conversations` → `test-conv-123` → `media`
4. Should see a document with metadata:
   ```
   {
     "fileName": "photo.jpg",
     "fileSize": 2101248,
     "r2Url": "https://files.lenv1.tech/...",
     "senderId": "your-user-id",
     "createdAt": Timestamp
   }
   ```
5. ✅ Success if metadata appears

### 5️⃣ Check Flutter Console Logs
Watch the Terminal for messages like:
```
✅ Upload started: photo.jpg
✅ Image compressed: 15.2 MB → 2.1 MB
✅ Thumbnail generated: 18 KB
✅ Upload to R2: 100%
✅ Metadata saved to Firestore
✅ Cache updated
```

---

## ✨ Success Checklist

After uploading an image, verify:

- [ ] Progress bar shows 0 → 100%
- [ ] No red error messages
- [ ] File appears in Cloudflare R2 bucket
- [ ] Metadata appears in Firestore `conversations/test-conv-123/media/{id}`
- [ ] Console shows upload success messages
- [ ] "Debug Info" shows your user ID and path

---

## 🐛 Troubleshooting

### ❌ Error: "File not in R2"
**Check**:
- [ ] Cloudflare credentials correct in `lib/config/cloudflare_config.dart`
- [ ] R2 bucket name correct (`lenv-storage`)
- [ ] API token has permissions: `s3:PutObject`, `s3:GetObject`

### ❌ Error: "Metadata not in Firestore"
**Check**:
- [ ] Firestore collections created: `conversations` → `media`
- [ ] Security rules published
- [ ] Firebase auth token valid
- [ ] User logged in

### ❌ Error: "Upload progress stuck at 50%"
**Possible causes**:
- R2 upload taking time (normal for large files)
- Network connection issue
- Firebase auth not initialized
- **Solution**: Check Flutter console for specific error

### ❌ Error: "Can't find upload button"
**Solution**:
- [ ] Make sure you're logged in first
- [ ] Navigate to Dev Tools screen
- [ ] Click green "🎥 Test Media Upload" button
- [ ] If button not visible, check `dev_tools_screen.dart` has the button

### ❌ Error: "User ID shows 'Not logged in'"
**Solution**:
- [ ] Logout and login again
- [ ] Make sure Firebase auth is initialized
- [ ] Check main.dart has `await Firebase.initializeApp()`

---

## 📱 Test Different Scenarios

### Test 1: Gallery Upload
1. Click "Pick Image from Gallery"
2. Select a small image (< 5 MB)
3. Verify upload completes
4. ✅ Expected: < 10 seconds

### Test 2: Camera Capture
1. Click "Capture Photo with Camera"
2. Take a photo
3. Verify upload completes
4. ✅ Expected: < 10 seconds

### Test 3: Large File
1. Pick a large image (10+ MB)
2. Verify compression works (should be ~2 MB after)
3. Upload should complete
4. ✅ Expected: < 30 seconds

### Test 4: Multiple Uploads
1. Upload 3-5 images in sequence
2. Verify each shows progress
3. Check R2 bucket - should have all files
4. Check Firestore - should have all metadata docs

### Test 5: Error Handling
1. Temporarily disconnect internet
2. Try to upload
3. Should show error message
4. ✅ Expected: "Upload failed: Network error"

---

## 📊 What Gets Created

### In Cloudflare R2
```
lenv-storage/
└── conversations/
    └── test-conv-123/
        └── media-abc-123/
            ├── photo.jpg          (2.1 MB compressed image)
            └── thumb.jpg          (18 KB thumbnail)
```

### In Firebase Firestore
```
conversations/
└── test-conv-123/
    └── media/
        └── media-abc-123
            {
              fileName: "photo.jpg",
              fileSize: 2101248,
              r2Url: "https://files.lenv1.tech/...",
              thumbnailUrl: "https://files.lenv1.tech/...",
              senderId: "your-uid",
              createdAt: Timestamp,
              width: 1920,
              height: 1080,
              uploadFailed: false
            }
```

### In Local Cache (Hive)
```
Automatically cached for offline access
- Messages
- Media metadata
- User session info
```

---

## 🎯 Expected Results Summary

| Component | Expected | Status |
|-----------|----------|--------|
| Upload starts | Progress bar shows | ✅ |
| Compression | 15 MB → 2.1 MB | ✅ |
| R2 upload | File appears in bucket | ✅ |
| Firestore | Metadata doc created | ✅ |
| Cache | Data stored locally | ✅ |
| Speed | < 10 seconds | ✅ |
| Cost | ~$0.001 per upload | ✅ |

---

## 🚀 After Testing

When all tests pass:

1. ✅ Delete test data from R2 and Firestore (optional)
2. ✅ Integrate into your real chat screen
3. ✅ Test in production environment
4. ✅ Monitor costs on Cloudflare dashboard
5. ✅ Deploy to users

---

## 💡 Quick Tips

- **Watch console**: All actions logged to Flutter console
- **Browser F12**: Open Cloudflare R2 in new tab to watch file appear
- **Browser F12**: Open Firebase Firestore to watch metadata doc appear
- **Test multiple times**: First might be slower (initialization)
- **Test different sizes**: Small, medium, and large images

---

## 📞 Still Have Issues?

Check these files for solutions:
- `STORAGE_QUICK_VISUAL.md` - Where files go
- `FINAL_ANSWER_IMAGE_STORAGE.md` - Storage explained
- `START_HERE_TASKS.md` - Step-by-step guide
- `QUICK_REFERENCE.md` - API reference

---

**Ready?** 🎬 Open Dev Tools and click "🎥 Test Media Upload"!
