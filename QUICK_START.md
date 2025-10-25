# Quick Start Guide - Student Dashboard

## Ready to Test! ✅

Your Student Dashboard is now **fully functional** with complete Firebase integration. Here's how to test it in 5 minutes:

## Step 1: Run the App (30 seconds)

```powershell
# Make sure Android emulator is running
flutter run
```

## Step 2: Create Student Account (1 minute)

1. When app opens, tap "I'M A STUDENT"
2. Tap "Sign Up" at the bottom
3. Fill in:
   - **Email**: `test.student@oakridge.edu`
   - **Password**: `test123456`
   - **School**: Oakridge International Academy
4. Tap "Sign Up"
5. You'll be auto-redirected to dashboard

## Step 3: Seed Test Data (1 minute)

### Quick Method:
Add this temporary button to your dashboard or run from console:

```dart
// Temporary: Add to student dashboard initState or create a floating button
import 'package:new_reward/utils/seed_data.dart';

// Then call:
await FirestoreSeedData.seedCurrentUser();
```

### Better Method - Use Dev Tools:
1. Navigate to dev tools: `Navigator.pushNamed(context, '/dev-tools');`
2. Click "Seed Test Data"
3. Wait for success message

## Step 4: Test Features (2 minutes)

After seeding, you should see:

### ✅ Profile Section
- Profile photo (or fallback icon)
- "Welcome, Alex Johnson!"

### ✅ Daily Challenge Card (Orange)
- Question: "What is the chemical symbol for gold?"
- Tap to answer
- Select "Au" (correct) → Get 50 points!
- Card shows "COMPLETED" after answering

### ✅ Monthly Target Card
- Shows: 85% progress
- Target: 90%
- "Complete 5 more tests to reach your goal!"
- Animated progress bar

### ✅ Stats Grid (4 Cards)
- **Tests**: 2 Pending
- **Rewards**: 1250 Points (gold color)
- **Leaderboard**: #5 Class Rank
- **Notifications**: 3 New (with badge)

### ✅ Pull to Refresh
- Swipe down anywhere to reload data
- Shows loading spinner
- Updates all stats

## Step 5: Verify Firebase Data (1 minute)

Go to [Firebase Console](https://console.firebase.google.com/):

1. Select project: `lenv-cb08e`
2. Go to Firestore Database
3. Check collections:
   - `users/{your-uid}` - Student profile
   - `dailyChallenges/{today}` - Today's challenge
   - `notifications` - 4 notifications (3 unread)
   - `tests` - 3 pending tests
   - `testResults` - 3 completed results

## What You Can Test

### ✅ Working Features
- ✅ Login with Firebase Auth
- ✅ Dashboard loads real data from Firestore
- ✅ Profile photo displays (with fallback)
- ✅ Welcome text shows real name
- ✅ Daily challenge displays question
- ✅ Challenge submission awards points
- ✅ Monthly progress calculates dynamically
- ✅ All stats show real numbers
- ✅ Pull-to-refresh reloads data
- ✅ Loading states during data fetch
- ✅ Error handling with fallbacks
- ✅ Dark mode support

### ⏳ Not Yet Created (Coming Next)
- Student Tests Screen
- Student Rewards Screen
- Student Leaderboard Screen
- Student Profile Screen
- Student Notifications Screen
- Student SWOT Reports Screen

## Common Issues

### Dashboard stuck on loading?
**Solution**: 
1. Check that you seeded data for the correct user UID
2. Verify Firebase connection
3. Check console for errors

### Challenge card doesn't show?
**Solution**: 
1. Make sure daily challenge exists in Firestore
2. Date must match today: `YYYY-MM-DD`
3. Re-run seed script

### Stats show 0 or null?
**Solution**: 
1. Student document needs all fields
2. Run seed script again
3. Pull down to refresh

### Can't seed data?
**Solution**: 
1. Make sure you're logged in as student
2. Check Firebase connection
3. Verify Firestore security rules allow writes

## Quick Seed Data (Copy-Paste)

If you want to manually add data in Firestore Console:

### User Document (`users/{uid}`)
```json
{
  "name": "Test Student",
  "email": "test.student@oakridge.edu",
  "photoUrl": "https://i.pravatar.cc/150?img=12",
  "schoolId": "oakridge",
  "schoolName": "Oakridge International Academy",
  "role": "student",
  "rewardPoints": 1250,
  "classRank": 5,
  "monthlyProgress": 85,
  "monthlyTarget": 90,
  "pendingTests": 2,
  "completedTests": 15,
  "newNotifications": 3
}
```

### Daily Challenge (`dailyChallenges/2025-01-15`) - Use today's date!
```json
{
  "date": "2025-01-15",
  "question": "What is the chemical symbol for gold?",
  "correctAnswer": "Au",
  "options": ["Au", "Ag", "Fe", "Cu"],
  "subject": "Chemistry",
  "points": 50
}
```

## Next Steps

1. **Test Everything** - Try all features listed above
2. **Check Firebase Console** - Verify data is being created
3. **Create More Screens** - Tests, Rewards, Leaderboard, etc.
4. **Add More Features** - Badges, achievements, analytics

## Files Reference

- **Dashboard UI**: `lib/screens/student/student_dashboard_screen.dart`
- **Models**: `lib/models/student_model.dart`
- **Service**: `lib/services/student_service.dart`
- **Provider**: `lib/providers/student_provider.dart`
- **Seed Script**: `lib/utils/seed_data.dart`
- **Dev Tools**: `lib/screens/dev/dev_tools_screen.dart`

## Architecture

```
User Taps Challenge
       ↓
Dashboard calls submitChallengeAnswer()
       ↓
StudentProvider.submitChallengeAnswer()
       ↓
StudentService.submitChallengeAnswer()
       ↓
Firebase Firestore (updates points)
       ↓
StudentProvider notifies listeners
       ↓
Dashboard rebuilds with new data
```

## Success Criteria

You know it's working when:
- ✅ Dashboard loads without errors
- ✅ Student name appears in welcome text
- ✅ Challenge shows real question
- ✅ Tapping challenge lets you answer
- ✅ Correct answer awards points
- ✅ Stats show real numbers from Firestore
- ✅ Pull-to-refresh updates everything
- ✅ Challenge card shows "COMPLETED" after answering

## Get Help

See detailed documentation:
- `TESTING_STUDENT_DASHBOARD.md` - Complete testing guide
- `STUDENT_DASHBOARD_SUMMARY.md` - Technical overview
- `ANDROID_EMULATOR_SETUP.md` - Android emulator setup

## Ready? Let's Go! 🚀

```powershell
flutter run
```

Then follow Steps 1-5 above. You should have a fully working student dashboard in under 5 minutes!
