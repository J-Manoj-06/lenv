# Firebase Storage Setup & Deployment Guide

## Current Issue
❌ Getting 404 errors when uploading announcement images
❌ Error: "Object does not exist at location"

This means **Firebase Storage rules are not deployed** or **Storage is not enabled**.

---

## Step 1: Enable Firebase Storage (If Not Already)

### Via Firebase Console:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click **Storage** in left sidebar
4. Click **Get Started**
5. Choose **Start in production mode**
6. Click **Done**

**Your Storage bucket URL will be:**
```
gs://your-project-id.appspot.com
```

---

## Step 2: Deploy Storage Rules

### Option A: Using Firebase CLI (Recommended)

Open terminal in project root (`d:\new_reward`) and run:

```bash
# Login to Firebase (if not already logged in)
firebase login

# Initialize Firebase (if not already done)
firebase init

# During init, select:
# - Firestore
# - Storage
# - Use existing project

# Deploy only Storage rules
firebase deploy --only storage

# Or deploy both Firestore and Storage
firebase deploy --only firestore,storage
```

### Option B: Manual Deployment via Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Storage** → **Rules** tab
4. Delete existing content
5. Copy **ENTIRE content** from `firebase/storage.rules` file
6. Paste into the editor
7. Click **Publish**

---

## Step 3: Verify Deployment

### Check Storage Rules in Console:
1. Go to **Storage** → **Rules**
2. You should see rules starting with:
   ```
   rules_version = '2';
   service firebase.storage {
   ```

### Check if bucket exists:
1. Go to **Storage** → **Files**
2. Should show empty bucket (not "Get Started" button)
3. URL should be: `gs://your-project-id.appspot.com`

---

## Step 4: Test Upload

1. **Hot restart** your app (not just hot reload)
   ```bash
   # In VS Code terminal:
   r  # (press 'r' to hot restart)
   ```

2. Try creating an announcement with an image

3. Should upload successfully to `institute_announcements/` folder

---

## Troubleshooting

### Still getting 404 errors?

**Problem**: Storage bucket not initialized
**Solution**: 
1. Go to Firebase Console → Storage
2. Click "Get Started" if you see it
3. Accept default rules (we'll override them)
4. Then deploy your rules again

### Error: "No storage bucket found"?

**Problem**: Storage not enabled in Firebase project
**Solution**:
1. Go to Firebase Console → Storage
2. Enable Storage
3. Wait 1-2 minutes for provisioning
4. Deploy rules again

### Error: "Permission denied"?

**Problem**: User role not set correctly
**Solution**: Check that your user has `role: 'principal'` in their Firebase Auth custom claims

To verify user claims in Firebase Console:
1. Go to **Authentication** → **Users**
2. Click on your user
3. Check **Custom claims** section
4. Should show: `{"role": "principal"}`

---

## Quick Copy-Paste Commands

```bash
# Full deployment (from d:\new_reward directory)
cd d:\new_reward
firebase login
firebase deploy --only storage

# Check deployment status
firebase projects:list

# View current rules
firebase deploy --only storage --dry-run
```

---

## What's in the Storage Rules?

The `firebase/storage.rules` file allows:

✅ **Institute Announcements**: Principals can upload to `institute_announcements/`
✅ **Teacher Community**: Teachers can upload to `teacher_community_announcements/`
✅ **Group Chats**: All users can upload to `group_chats/`
✅ **Student Community**: Students can upload to `student_community/`
✅ **Parent-Teacher**: Parents/teachers can upload to `parent_teacher_groups/`
✅ **Profile Pictures**: Users can upload to their own `user_profiles/{uid}/`

🔒 **Security**: Only authenticated users with correct roles can upload

---

## Expected Result After Deployment

✅ Announcements with images work
✅ No more 404 errors
✅ Images visible in Firebase Console Storage
✅ Images display in app

---

## Still Having Issues?

### Check Firebase Project ID
1. Open `android/app/google-services.json`
2. Find `"project_id"` field
3. Verify it matches your Firebase Console project

### Check Storage Bucket Name
In `lib/screens/institute/institute_announcement_compose_screen.dart`:
```dart
final ref = FirebaseStorage.instance.ref().child(
  'institute_announcements/$fileName',
);
```

This should automatically use default bucket: `gs://project-id.appspot.com`

### Enable Debug Logging
Add to main.dart:
```dart
FirebaseStorage.instance.setLogLevel(StorageLogLevel.debug);
```

Then check logs for actual bucket URL being used.
