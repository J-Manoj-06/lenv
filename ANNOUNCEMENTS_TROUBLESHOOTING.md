# 📢 Announcements Troubleshooting Guide

## Issue: Student Can't See Teacher's Announcement

### Problem Description
- **Teacher**: teacher4@oakridge.edu posted a school-wide announcement
- **Student**: noah.williams@oakridge.edu cannot see the announcement
- **Expected**: Student should see all school-wide announcements

---

## Debugging Steps Added

### 1. Teacher Side Debug Logs
When a teacher posts an announcement, the console will now show:
```
📢 TEACHER DEBUG: Posting announcement with:
   instituteId: "oakridge"
   audienceType: "school"
   standards: []
   sections: []
   text: "Announcement content..."
```

### 2. Student Side Debug Logs
When a student opens their dashboard, the console will show:
```
📢 STUDENT DEBUG: Student schoolId: "oakridge"
📢 STUDENT DEBUG: Student className: "Grade 7 - A"
📢 STUDENT DEBUG: Student email: "noah.williams@oakridge.edu"
📢 STUDENT DEBUG: Querying with schoolId: "oakridge"
📢 DEBUG: Found 5 announcements in database
📢 DEBUG: Student standard: "7", section: "A"
📢 DEBUG: Announcement - audienceType: "school", standards: [], sections: []
📢 DEBUG: Announcement "Welcome to the new..." visible: true
📢 DEBUG: Total visible announcements: 5
```

---

## Common Issues & Solutions

### Issue 1: FieldName Mismatch (MOST LIKELY CAUSE)

**Problem**: Teacher uses `instituteId`, student has `schoolId`

**Check**: Look at the debug logs:
```
Teacher posts with: instituteId: "oakridge"
Student queries with: schoolId: "oakridge_school"
```

**Solution**: Both must match exactly!

**Fix Options**:

#### Option A: Update Student's schoolId in Firestore
```javascript
// In Firebase Console → students collection
{
  "schoolId": "oakridge"  // Must match teacher's instituteId
}
```

#### Option B: Update Teacher's instituteId
```javascript
// In Firebase Console → users/teachers collection
{
  "instituteId": "oakridge_school"  // Must match student's schoolId
}
```

#### Option C: Update All Announcement instituteId Fields
```javascript
// In Firebase Console → class_highlights collection
{
  "instituteId": "oakridge_school"  // Update to match students
}
```

---

### Issue 2: Announcement Expired

**Problem**: Announcements expire after 24 hours

**Check**: Look at the announcement document:
```javascript
{
  "createdAt": "2025-11-02 10:00:00",
  "expiresAt": "2025-11-03 10:00:00",  // Already passed!
  "audienceType": "school"
}
```

**Solution**: Teacher needs to post a new announcement

**Prevention**: In the future, we could extend expiry time:
```dart
// In teacher_dashboard.dart, line ~1750
final expiresAt = now.add(const Duration(hours: 48));  // 48 hours instead of 24
```

---

### Issue 3: Wrong Audience Type

**Problem**: Announcement targeted incorrectly

**Check Debug Log**:
```
📢 DEBUG: Announcement - audienceType: "standard", standards: ["8"], sections: []
📢 DEBUG: Student standard: "7", section: "A"
📢 DEBUG: Announcement "..." visible: false  ← Student is Grade 7, not 8!
```

**Solution**: Teacher should:
1. Delete the old announcement (if they're the owner)
2. Create a new one with correct audience:
   - Select "School" for all students
   - Or select the correct standards/sections

---

### Issue 4: Empty schoolId/instituteId

**Problem**: One of the IDs is null or empty

**Check Debug Log**:
```
📢 TEACHER DEBUG: instituteId: ""  ← EMPTY!
or
📢 STUDENT DEBUG: Student schoolId: "null"  ← NULL!
```

**Solution**: Update the user document in Firestore:

**For Teacher**:
```javascript
// users collection → teacher document
{
  "instituteId": "oakridge",
  "schoolCode": "oakridge"  // Fallback field
}
```

**For Student**:
```javascript
// students collection → student document
{
  "schoolId": "oakridge"
}
```

---

### Issue 5: Case Sensitivity

**Problem**: "Oakridge" vs "oakridge"

**Check**:
```
Teacher: instituteId: "Oakridge"
Student: schoolId: "oakridge"
```

**Solution**: Make both lowercase or both match exactly:
```javascript
{
  "instituteId": "oakridge"  // All lowercase
}
```

---

### Issue 6: Firestore Query Not Returning Results

**Problem**: Query syntax issue or index missing

**Debug Log Shows**:
```
📢 DEBUG: Found 0 announcements in database
📢 DEBUG: No announcements found for instituteId: "oakridge"
```

**Possible Causes**:
1. No announcements actually posted
2. All announcements expired
3. Firestore index missing (check Firebase Console errors)
4. Security rules blocking read access

**Check Security Rules** (`firestore.rules`):
```javascript
match /class_highlights/{docId} {
  // Students should be able to read all announcements for their school
  allow read: if request.auth != null;
  
  // Teachers can create/update/delete their own
  allow create: if request.auth != null && request.auth.token.role == 'teacher';
  allow update, delete: if request.auth != null && 
                         request.auth.uid == resource.data.teacherId;
}
```

---

## Step-by-Step Debugging Process

### Step 1: Run the App
```bash
flutter run
```

### Step 2: Teacher Posts Announcement
1. Login as teacher4@oakridge.edu
2. Go to dashboard
3. Click "+" to create announcement
4. Select "School" audience
5. Add text: "Test announcement"
6. Click "Post"
7. **Watch console for debug logs**

Expected output:
```
📢 TEACHER DEBUG: Posting announcement with:
   instituteId: "oakridge"
   audienceType: "school"
   standards: []
   sections: []
   text: "Test announcement"
```

### Step 3: Student Opens Dashboard
1. Login as noah.williams@oakridge.edu
2. Open dashboard
3. **Watch console for debug logs**

Expected output:
```
📢 STUDENT DEBUG: Student schoolId: "oakridge"
📢 STUDENT DEBUG: Querying with schoolId: "oakridge"
📢 DEBUG: Found 1 announcements in database
📢 DEBUG: Announcement - audienceType: "school", standards: [], sections: []
📢 DEBUG: Announcement "Test announcement..." visible: true
📢 DEBUG: Total visible announcements: 1
```

### Step 4: Compare the IDs
**IF teacher's instituteId == student's schoolId → Should work!**
**IF they don't match → That's the problem!**

---

## Quick Fix Checklist

Run through this checklist in order:

- [ ] **Check Console Logs**: Are debug logs showing up?
- [ ] **Compare IDs**: Does teacher's `instituteId` match student's `schoolId`?
- [ ] **Check Expiry**: Is the announcement still valid (< 24 hours old)?
- [ ] **Check Audience**: Is `audienceType` set to "school"?
- [ ] **Check Firestore**: Does the document exist in `class_highlights` collection?
- [ ] **Check Auth**: Is the student properly authenticated?
- [ ] **Check Network**: Is the device connected to the internet?
- [ ] **Check Security Rules**: Can students read announcements?

---

## How to Fix the ID Mismatch Issue

### Best Solution: Update Student's schoolId

1. Open Firebase Console
2. Go to Firestore Database
3. Navigate to `students` collection
4. Find noah.williams@oakridge.edu's document
5. Edit the `schoolId` field to match the teacher's `instituteId`

Example:
```javascript
Before:
{
  "email": "noah.williams@oakridge.edu",
  "schoolId": "oakridge_school"  // Wrong!
}

After:
{
  "email": "noah.williams@oakridge.edu",
  "schoolId": "oakridge"  // Matches teacher's instituteId
}
```

### Alternative: Batch Update All Students

If all students in the school have the wrong `schoolId`:

```javascript
// Firebase Console → Firestore → Run query
// Find all students with schoolId: "oakridge_school"
// Update to: "oakridge"
```

---

## Prevention for Future

### 1. Standardize ID Format
Decide on one format and use it everywhere:
- Format: `schoolname` (all lowercase, no spaces)
- Example: "oakridge", "westminster", "stmarys"

### 2. Validate on User Creation
Add validation when creating teacher/student accounts:
```dart
// Ensure both use the same field and format
final instituteId = schoolName.toLowerCase().replaceAll(' ', '');
```

### 3. Add Admin Check Feature
Create an admin page to check for ID mismatches:
```dart
// Query all students
// Query all teachers
// Compare schoolId vs instituteId
// Show warnings for mismatches
```

---

## Expected Console Output (Success Case)

```
📢 TEACHER DEBUG: Posting announcement with:
   instituteId: "oakridge"
   audienceType: "school"
   standards: []
   sections: []
   text: "Important school announcement"

📢 STUDENT DEBUG: Student schoolId: "oakridge"
📢 STUDENT DEBUG: Student className: "Grade 7 - A"
📢 STUDENT DEBUG: Student email: "noah.williams@oakridge.edu"
📢 STUDENT DEBUG: Querying with schoolId: "oakridge"
📢 DEBUG: Found 1 announcements in database
📢 DEBUG: Student standard: "7", section: "A"
📢 DEBUG: Announcement - audienceType: "school", standards: [], sections: []
📢 DEBUG: Announcement "Important school ann..." visible: true
📢 DEBUG: Total visible announcements: 1
```

---

## Summary

The most common reason a student can't see a school-wide announcement is:

**instituteId ≠ schoolId**

The fix is simple:
1. Check debug logs
2. Compare the IDs
3. Update Firestore to make them match

With the debug logs now in place, you can easily identify and fix the issue! 🎯
