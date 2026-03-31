# Reward Request Deletion Fix - Instructions

## Problem
Parents getting `PERMISSION_DENIED` error when trying to delete reward requests.

## Root Cause
Original Firestore rules only allowed admins to delete. Also, authentication tokens were cached before the rule update.

## Solution Applied
Updated `/firebase/firestore.rules` line 897-910 to allow:
- Admins (any request)
- Students (their own requests)
- Parents explicitly linked (parent_id field match)
- Any parent role (for managing children's rewards)
- Elevated staff (teachers, principals)
- Users who approved the request (approvedBy field)

**Deployed:** March 31, 2026 ✅

## IMPORTANT: How to Test

### Option 1: Complete App Restart (Recommended)
1. **Force stop the app:**
   - Go to Settings → Apps
   - Find and select your app
   - Tap "Force Stop"

2. **Clear app cache:**
   - Settings → Apps → [App Name] → Storage → Clear Cache
   - (Optional: Clear Data for complete reset)

3. **Restart the app** and sign in again

4. **Try deleting a reward request**

### Option 2: Quick Logout/Login
1. Go to app settings
2. Logout completely
3. Sign in again
4. Try deleting

## Current Delete Rule (in firestore.rules)
```
allow delete: if isSignedIn() && (
  // Admin can delete anything
  isAdmin()
  // Student can delete their own request
  || (resource.data.student_id == request.auth.uid || resource.data.studentId == request.auth.uid)
  // Parent explicitly assigned to this request
  || (resource.data.parent_id == request.auth.uid || resource.data.parentId == request.auth.uid)
  // Any parent role can delete
  || isParent()
  // Elevated staff roles can delete
  || isElevatedApproverRole()
  // Fallback: anyone who approved it
  || resource.data.approvedBy == request.auth.uid
);
```

## If Still Not Working
- Check your user role in Settings/Profile (should be "Parent")
- Try deleting a different reward request
- Check Firebase Console → Firestore → Rules tab to verify deployment
- Look for error details in app logs

## Contact
If issue persists after restart, check Firebase Console for rule deployment status.
