# Testing Student Dashboard with Firebase

## Overview
The Student Dashboard is now fully integrated with Firebase! This guide will help you test all the features with real data.

## Step 1: Create Test Student Account

1. Run the app on your Android emulator
2. Navigate to Student Login
3. Create a new student account:
   - Email: `alex.student@oakridge.edu`
   - Password: `password123`
   - School: Oakridge International Academy

## Step 2: Seed Test Data

### Option A: Using Dev Tools Screen (Recommended)
1. After logging in, manually navigate to the Dev Tools screen:
   - In your code, temporarily add a button or directly navigate
   - Or use: `Navigator.pushNamed(context, '/dev-tools');`

2. The Dev Tools screen will show:
   - Your current user UID (auto-filled)
   - "Seed Test Data" button - Click this!
   - "Clear Test Data" button - Use to reset

3. Click "Seed Test Data" and wait for success message

### Option B: Using Flutter DevTools Console
1. Open Flutter DevTools
2. In the console, run:
```dart
import 'package:new_reward/utils/seed_data.dart';
await FirestoreSeedData.seedCurrentUser();
```

## Step 3: Test Dashboard Features

After seeding data, the dashboard will display:

### ✅ Real Data Display
- **Profile Photo**: Shows real photo from Firestore (or fallback icon)
- **Welcome Text**: Shows real student name "Welcome, Alex Johnson!"
- **Daily Challenge Card**: 
  - Question: "What is the chemical symbol for gold?"
  - Options: Au, Ag, Fe, Cu
  - Tap to answer and earn 50 points
- **Monthly Target**: 
  - Shows 85% progress towards 90% target
  - Calculates tests needed dynamically
- **Stats Grid**:
  - Pending Tests: 2
  - Reward Points: 1250
  - Class Rank: #5
  - New Notifications: 3

### ✅ Interactive Features
1. **Pull to Refresh**: Swipe down to reload all data from Firebase
2. **Daily Challenge**: 
   - Tap the challenge card
   - Select an answer from the dialog
   - Correct answer (Au) awards 50 points
   - Incorrect answer shows correct answer
   - Card shows "COMPLETED" after submission
3. **Stat Cards**: All cards are tappable (routes not created yet)
4. **Bottom Navigation**: Switches between tabs (other screens not created yet)

### ✅ Real-time Updates
- Changes in Firestore are reflected immediately
- Pull to refresh updates all data
- Challenge completion updates points in real-time

## Step 4: Verify Firebase Data

### Check Firestore Console
Go to Firebase Console → Firestore Database → Collections:

1. **users/{uid}**:
```json
{
  "name": "Alex Johnson",
  "email": "alex.student@oakridge.edu",
  "schoolId": "oakridge",
  "rewardPoints": 1250,
  "classRank": 5,
  "monthlyProgress": 85,
  "monthlyTarget": 90,
  "pendingTests": 2,
  "completedTests": 15,
  "newNotifications": 3
}
```

2. **dailyChallenges/{today's date}**:
```json
{
  "question": "What is the chemical symbol for gold?",
  "correctAnswer": "Au",
  "options": ["Au", "Ag", "Fe", "Cu"],
  "subject": "Chemistry",
  "points": 50
}
```

3. **notifications** (4 documents):
- 3 unread notifications
- 1 read notification

4. **tests** (3 documents):
- math-quiz-5 (due tomorrow)
- science-test-4 (due in 3 days)
- english-essay-2 (due in 7 days)

5. **testResults** (3 documents):
- Math: 88%
- Science: 92%
- English: 75%

## Step 5: Test Challenge Submission

1. Tap the Daily Challenge card
2. Select "Au" (correct answer)
3. Check that:
   - Success message appears: "🎉 Correct! You earned points!"
   - Challenge card shows "COMPLETED - COMPLETED"
   - Card is grayed out
   - Points are awarded

4. Try selecting wrong answer on a fresh challenge:
   - Error message appears: "❌ Incorrect. The correct answer is: Au"
   - Still marks as attempted

5. Verify in Firestore:
   - Check `challengeAttempts` collection for new document
   - Check `users/{uid}` for updated `rewardPoints`

## Troubleshooting

### Dashboard shows loading forever
- Check that student UID matches the seeded data
- Verify Firestore has data for this UID
- Check console for Firebase errors

### Challenge doesn't appear
- Verify `dailyChallenges` collection has document with today's date
- Date format: `YYYY-MM-DD` (e.g., `2025-01-15`)
- Re-run seed script if needed

### Stats show 0 or null
- Check that student document has all required fields
- Run seed script again
- Pull down to refresh

### Challenge submission fails
- Check Firebase Auth is working
- Verify student has valid UID
- Check Firestore security rules allow writes

## What's Seeded

The seed script creates:
- ✅ Student document with stats (points: 1250, rank: 5, progress: 85%)
- ✅ Today's daily challenge (Chemistry question)
- ✅ 4 notifications (3 unread, 1 read)
- ✅ 3 pending tests (Math, Science, English)
- ✅ 3 completed test results (88%, 92%, 75%)
- ✅ Profile photo URL

## Next Steps

After verifying the dashboard works with real data:

1. **Create remaining student screens** (all with Firebase integration):
   - Tests Screen - show pending/completed tests from Firestore
   - Rewards Screen - display points and redemption
   - Leaderboard Screen - show class rankings
   - Profile Screen - edit student info
   - Notifications Screen - list and manage notifications
   - SWOT Reports Screen - analyze performance

2. **Test complete student flow**:
   - Login → Dashboard → Tests → Take Test → See Results → Earn Points

3. **Add more features**:
   - Badge system
   - Achievement unlocking
   - Point redemption
   - Performance analytics

## Clean Up

To reset test data:
1. Go to Dev Tools screen
2. Click "Clear Test Data"
3. Confirm deletion
4. Re-seed if needed

Or manually delete collections in Firestore Console.
