# Firestore Security Rules - Index Collections

## Overview
This document provides the security rules for the newly created index collections:
- `teacher_groups/{teacherId}`
- `user_communities/{userId}`

These rules ensure users can only access their own index documents.

---

## Complete Security Rules

Add these rules to your `firestore.rules` file:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // ============================================================
    // TEACHER GROUPS INDEX COLLECTION
    // ============================================================
    // Structure: teacher_groups/{teacherId}
    // Contains: Teacher's subject groups with unread counts
    // Access: Teachers can only read/write their own document
    
    match /teacher_groups/{teacherId} {
      // Teachers can read their own groups document
      allow read: if request.auth != null 
                  && request.auth.uid == teacherId;
      
      // Teachers can update their own groups document
      // (for marking groups as read)
      allow write: if request.auth != null 
                   && request.auth.uid == teacherId;
      
      // System can create/update via service account
      // (for automated index updates from Cloud Functions)
      allow write: if request.auth.token.admin == true;
    }
    
    // ============================================================
    // USER COMMUNITIES INDEX COLLECTION
    // ============================================================
    // Structure: user_communities/{userId}
    // Contains: User's joined communities with unread counts
    // Access: Users can only read/write their own document
    
    match /user_communities/{userId} {
      // Users can read their own communities document
      allow read: if request.auth != null 
                  && request.auth.uid == userId;
      
      // Users can update their own communities document
      // (for marking communities as read)
      allow write: if request.auth != null 
                   && request.auth.uid == userId;
      
      // System can create/update via service account
      // (for automated index updates from Cloud Functions)
      allow write: if request.auth.token.admin == true;
    }
    
    // ============================================================
    // EXISTING COLLECTIONS (keep your current rules)
    // ============================================================
    
    // Your existing rules for:
    // - classes
    // - students
    // - parents
    // - teachers
    // - communities
    // - etc.
    
  }
}
```

---

## Rule Explanation

### Teacher Groups Rules

**Read Access**:
- ✅ Teachers can read their own `teacher_groups/{teacherId}` document
- ❌ Teachers CANNOT read other teachers' documents
- ❌ Students/Parents CANNOT read any teacher_groups documents

**Write Access**:
- ✅ Teachers can update their own document (e.g., marking groups as read)
- ✅ Service account can update any document (for automated syncing)
- ❌ Teachers CANNOT modify other teachers' documents

**Use Cases**:
1. Teacher opens app → reads their teacher_groups document
2. Teacher marks chat as read → updates unreadCount to 0
3. Student sends message → Cloud Function updates teacher's document

---

### User Communities Rules

**Read Access**:
- ✅ Users (students/teachers) can read their own `user_communities/{userId}` document
- ❌ Users CANNOT read other users' documents
- ❌ Unauthenticated users CANNOT read any documents

**Write Access**:
- ✅ Users can update their own document (e.g., marking communities as read)
- ✅ Service account can update any document (for automated syncing)
- ❌ Users CANNOT modify other users' documents

**Use Cases**:
1. Student opens app → reads their user_communities document
2. Student marks community as read → updates unreadCount to 0
3. Teacher sends community message → Cloud Function updates all members' documents

---

## Testing Security Rules

### Test 1: User Can Read Own Document
```javascript
// User ID: teacher123
// Document: teacher_groups/teacher123
// Expected: ALLOW ✅

match /teacher_groups/teacher123 {
  allow read: if request.auth.uid == 'teacher123';
}
```

### Test 2: User Cannot Read Other's Document
```javascript
// User ID: teacher123
// Document: teacher_groups/teacher456
// Expected: DENY ❌

match /teacher_groups/teacher456 {
  allow read: if request.auth.uid == 'teacher123';
  // Evaluates to false → DENY
}
```

### Test 3: Unauthenticated Cannot Read
```javascript
// User ID: null (not logged in)
// Document: teacher_groups/teacher123
// Expected: DENY ❌

match /teacher_groups/teacher123 {
  allow read: if request.auth != null && request.auth.uid == 'teacher123';
  // request.auth is null → DENY
}
```

---

## Deploying Security Rules

### Option 1: Firebase Console (Manual)

1. Open Firebase Console: https://console.firebase.google.com
2. Select your project
3. Navigate to **Firestore Database** → **Rules** tab
4. Copy the rules from above
5. Paste into the rules editor
6. Click **Publish**

### Option 2: Firebase CLI (Automated)

```bash
# Install Firebase CLI (if not installed)
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase in your project (if not done)
firebase init firestore

# Edit firestore.rules file
# (Paste the rules from above)

# Deploy rules
firebase deploy --only firestore:rules
```

---

## Verification Steps

After deploying rules, verify they work correctly:

### 1. Test Read Access (Flutter App)

```dart
// Should succeed - user reading their own document
final teacherDoc = await FirebaseFirestore.instance
    .collection('teacher_groups')
    .doc(currentUserId)
    .get();

print('Read own document: ${teacherDoc.exists}'); // Should print true

// Should fail - user trying to read another user's document
try {
  final otherDoc = await FirebaseFirestore.instance
      .collection('teacher_groups')
      .doc('someOtherUserId')
      .get();
  print('ERROR: Should have been denied!');
} catch (e) {
  print('Correctly denied: $e'); // Should catch permission error
}
```

### 2. Test Write Access

```dart
// Should succeed - user updating their own document
await FirebaseFirestore.instance
    .collection('teacher_groups')
    .doc(currentUserId)
    .set({
      'groups': {
        'someGroupId': {
          'unreadCount': 0,
        }
      }
    }, SetOptions(merge: true));

print('Successfully updated own document ✅');
```

### 3. Check Firebase Console Logs

1. Go to Firebase Console → Firestore Database
2. Try to manually edit a document
3. Check the Console logs for any permission errors

---

## Common Issues & Solutions

### Issue 1: "Missing or insufficient permissions"

**Cause**: User trying to access a document they don't own.

**Solution**: 
- Verify `request.auth.uid` matches document ID
- Check user is authenticated
- Ensure document ID format matches user ID format

### Issue 2: Cloud Functions Can't Update Index

**Cause**: Service account doesn't have admin token.

**Solution**:
```javascript
// In your Cloud Function, use admin SDK
const admin = require('firebase-admin');
admin.initializeApp();

// Admin SDK bypasses security rules
await admin.firestore()
  .collection('teacher_groups')
  .doc(teacherId)
  .set(data, { merge: true });
```

### Issue 3: Rules Not Taking Effect

**Cause**: Rules not deployed or cached.

**Solution**:
1. Check rules are published in Firebase Console
2. Wait 1-2 minutes for propagation
3. Restart your app to clear any caches

---

## Security Best Practices

### ✅ DO:
- Always validate `request.auth != null` first
- Use `request.auth.uid` to match document IDs
- Keep index documents small (<1MB per document)
- Log security rule violations for monitoring

### ❌ DON'T:
- Don't allow public read access to index collections
- Don't use `allow read, write: if true` (security risk!)
- Don't expose sensitive user data in index documents
- Don't create index documents for unauthenticated users

---

## Monitoring & Alerts

Set up monitoring for security rule violations:

1. **Firebase Console** → **Firestore** → **Usage** tab
   - Check for unusual spikes in denied requests

2. **Cloud Functions** → **Logs**
   - Search for "PERMISSION_DENIED" errors

3. **Set Up Alerts**:
   ```javascript
   // Example: Alert on repeated denied requests
   if (deniedRequests > 100) {
     sendAlert('High number of permission denied errors');
   }
   ```

---

## Additional Security Layers

### 1. Rate Limiting
Consider adding rate limiting for index updates:

```javascript
match /teacher_groups/{teacherId} {
  allow write: if request.auth.uid == teacherId
               && request.time > resource.data.lastUpdated + duration.value(1, 's');
  // Prevents spam updates (1 second cooldown)
}
```

### 2. Data Validation
Validate data structure on write:

```javascript
match /teacher_groups/{teacherId} {
  allow write: if request.auth.uid == teacherId
               && request.resource.data.keys().hasAll(['groups', 'lastUpdated'])
               && request.resource.data.groups is map;
  // Ensures correct data structure
}
```

---

## Testing Checklist

Before deploying to production:

- [ ] Rules deployed to Firebase Console
- [ ] Teacher can read their own teacher_groups document
- [ ] Teacher cannot read other teachers' documents
- [ ] Student can read their own user_communities document
- [ ] Student cannot read other students' documents
- [ ] Unauthenticated users denied access
- [ ] Cloud Functions can update documents (if implemented)
- [ ] No security warnings in Firebase Console
- [ ] Performance impact acceptable (<100ms per request)

---

## Support & Documentation

**Firebase Security Rules Docs**: https://firebase.google.com/docs/firestore/security/get-started  
**Testing Rules**: https://firebase.google.com/docs/firestore/security/test-rules-emulator  
**Best Practices**: https://firebase.google.com/docs/firestore/security/best-practices

---

**Last Updated**: Current session  
**Status**: ✅ READY TO DEPLOY  
**Priority**: HIGH (required for Phase 1 completion)
