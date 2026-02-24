# Teacher Announcement Expiry Fix

## Issue
Teacher announcements in the principal dashboard were not disappearing after 24 hours.

## Root Cause
In `lib/models/status_model.dart`, the `fromFirestore` factory method had a logic error:

```dart
// ❌ WRONG - Always returns a NEW 24-hour expiration from "now"
expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? 
           DateTime.now().add(const Duration(hours: 24)),
```

**Problem:** When loading older announcements that were created before the `expiresAt` field was added to the database, the code would calculate a **fresh 24-hour expiration from the current time** each time the document was loaded. This meant:

- An announcement created **48 hours ago** without an `expiresAt` field would load as:
  - `expiresAt = now + 24 hours` (not the original `createdAt + 24 hours`)
  - The announcement would never expire because expiration keeps getting recalculated

## Solution
Changed the fallback logic to calculate `expiresAt` based on `createdAt` instead of current time:

```dart
// ✅ CORRECT - Expires 24 hours after creation
final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? 
           createdAt.add(const Duration(hours: 24)),
```

## How It Works Now

1. **Old announcements (no expiresAt field):**
   - Get expiration calculated as: `createdAt + 24 hours`
   - If older than 24 hours, `expiresAt` is in the past

2. **Firestore Query (Principal Dashboard):**
   - Filters: `expiresAt > now()` only shows non-expired announcements
   - Old announcements with expired `expiresAt` are automatically hidden

3. **Cloud Function (Auto-Delete):**
   - Runs every hour
   - Finds announcements where `expiresAt < now()`
   - Deletes them along with all images from Cloudflare R2

## Files Modified
- `lib/models/status_model.dart` - Fixed the `fromFirestore` factory method

## Testing
To verify the fix works:
1. Create a teacher announcement
2. Wait 24+ hours
3. Check the principal dashboard - announcement should disappear
4. Check Firebase Console - announcement should be deleted by the Cloud Function

## Impact
- ✅ Existing old announcements will now correctly expire
- ✅ Firestore storage reduced (expired docs are deleted)
- ✅ Cloudflare R2 storage reduced (media is deleted)
- ✅ No UI changes needed
