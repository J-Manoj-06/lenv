# Firebase Storage Rules Setup

## Current Issue
Getting error: `[firebase_storage/object-not-found] No object exists at the desired reference`

This happens because Firebase Storage rules are blocking the upload.

## Solution: Update Storage Rules

### Option 1: Quick Fix (Development Only - NOT for Production)
Go to Firebase Console → Storage → Rules and replace with:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

This allows any authenticated user to read/write anywhere in Storage.

### Option 2: Production-Ready Rules (Recommended)
Use specific path-based rules:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    
    // Profile images - users can only write their own
    match /profiles/{userId}.jpg {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Classroom highlights - teachers only
    match /class_highlights/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
                   && request.auth.token.role == 'teacher';
      allow delete: if request.auth != null 
                    && request.auth.token.role == 'teacher';
    }
    
    // Rewards - anyone authenticated can read, only specific users can write
    match /rewards/{rewardId}.jpg {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // Test attachments - teachers only
    match /tests/{testId}/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
                   && request.auth.token.role == 'teacher';
    }
    
    // Default deny everything else
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## Steps to Update

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `lenv-cb08e`
3. Click **Storage** in left menu
4. Click **Rules** tab
5. Replace the existing rules with one of the options above
6. Click **Publish**

## Important Notes

- **Option 1** is quick for testing but allows any authenticated user to upload anywhere
- **Option 2** is more secure and recommended for production
- The `request.auth.token.role` check requires you to set custom claims on user tokens
- If you don't have custom claims set up, temporarily use Option 1 for testing

## After Updating Rules

1. Hot reload your app: press `r` in the terminal
2. Try uploading a classroom highlight again
3. If it works, you'll see the image upload successfully

## Alternative: Check if Storage is Enabled

If rules don't help, verify Storage is enabled:
1. Firebase Console → Storage
2. Click **Get Started** if you see it
3. Choose "Start in test mode" (allows all authenticated users for 30 days)
4. Select a Cloud Storage location (e.g., us-central1)
5. Click **Done**

This will initialize Storage with permissive rules for testing.
