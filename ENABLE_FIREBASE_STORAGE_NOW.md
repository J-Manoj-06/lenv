# URGENT: Enable Firebase Storage

## Issue Detected
❌ Firebase Storage API is **not enabled** in your project
❌ Error: "Permission denied to get service [firebasestorage.googleapis.com]"

## Solution: Enable Storage Manually

### Step 1: Enable Firebase Storage

1. **Go to Firebase Console**
   - Visit: https://console.firebase.google.com
   - Select project: **lenv-cb08e**

2. **Navigate to Storage**
   - Click **Storage** in left sidebar
   - If you see "Get Started", click it
   - Choose **Production mode** (we'll add rules next)
   - Click **Done**

3. **Wait for provisioning** (30 seconds - 2 minutes)

### Step 2: Deploy Storage Rules via Console

Since CLI deployment failed, use the Console:

1. **Go to Storage → Rules tab**
   - In Firebase Console, click **Storage**
   - Click **Rules** tab at the top

2. **Replace all content** with this:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // Institute announcements - principals can upload
    match /institute_announcements/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                      request.auth.token.role == 'principal';
    }
    
    // Teacher community announcements
    match /teacher_community_announcements/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                      request.auth.token.role == 'teacher';
    }
    
    // Group chat attachments
    match /group_chats/{classId}/{subjectId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // Student community attachments
    match /student_community/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // Teacher community attachments
    match /teacher_community/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // Parent-teacher group chat attachments
    match /parent_teacher_groups/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // User profile pictures
    match /user_profiles/{uid}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                      request.auth.uid == uid;
    }
    
    // Student media uploads
    match /student_uploads/{uid}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                      request.auth.uid == uid;
    }
    
    // Teacher resources
    match /teacher_resources/{uid}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                      request.auth.uid == uid;
    }
    
    // Temporary uploads
    match /temp/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
      allow delete: if request.auth != null;
    }
    
    // Default deny
    match /{allPaths=**} {
      allow read: if false;
      allow write: if false;
    }
  }
}
```

3. **Click Publish**

### Step 3: Verify in App

1. **Hot Restart the App**
   ```
   In VS Code terminal, press: R (capital R for full restart)
   ```

2. **Try uploading an announcement image**
   - Should work now without 404 errors

### Step 4: Verify User Role

Make sure your logged-in user has the **principal** role:

1. Go to **Authentication** → **Users** in Firebase Console
2. Find your user
3. Click on the user
4. Check **Custom claims** section
5. Should show: `{"role": "principal"}`

**If no custom claims:**
- You need to set them via Firebase Admin SDK or Cloud Function
- Or temporarily change the rule to allow any authenticated user for testing:
  ```
  allow write: if request.auth != null;
  ```

---

## Quick Test

After enabling Storage and deploying rules:

1. Open your app
2. Go to **Create Announcement**
3. Add an image
4. Click **Post**
5. ✅ Should upload successfully!

You can verify the upload in Firebase Console:
- Go to **Storage** → **Files**
- Look for `institute_announcements/` folder
- Your uploaded image should be there

---

## Alternative: Enable via Google Cloud Console

If Firebase Console doesn't work:

1. Go to: https://console.cloud.google.com
2. Select project: **lenv-cb08e**
3. Search for **"Cloud Storage"**
4. Click **Enable API**
5. Wait for activation
6. Return to Firebase Console and follow Step 2 above
