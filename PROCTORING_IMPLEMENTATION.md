# Test Proctoring System Implementation

## Overview
This document describes the implementation of the automatic proctoring system that monitors student test-taking behavior and auto-submits tests when violations are detected.

## Features Implemented

### 1. **App Lifecycle Monitoring** 
- Uses Flutter's `WidgetsBindingObserver` to detect when the app loses focus
- Monitors these states:
  - `AppLifecycleState.paused` - App moved to background
  - `AppLifecycleState.inactive` - App loses focus (e.g., notification drawer opened)
  - `AppLifecycleState.hidden` - App is hidden from view

### 2. **Automatic Test Submission on Violation**
When tab switching or app leaving is detected:
- Timer is immediately cancelled
- Test is auto-submitted with violation flag
- All answers (complete or incomplete) are saved
- Score is calculated based on answered questions
- Student counters are updated
- Violation is logged in a separate `violations` collection

### 3. **Data Stored in Firebase**

#### Test Results Collection (`testResults`)
```javascript
{
  id: string,
  studentId: string,
  studentName: string,
  studentEmail: string,
  testId: string,
  testTitle: string,
  subject: string,
  score: number (percentage),
  totalQuestions: number,
  correctAnswers: number,
  completedAt: Timestamp,
  timeTaken: number (minutes),
  answers: [
    {
      questionText: string,
      userAnswer: string,
      correctAnswer: string,
      isCorrect: boolean
    }
  ],
  wasProctored: boolean,
  tabSwitchCount: number,
  violationDetected: boolean,
  violationReason: string (optional)
}
```

#### Violations Collection (`violations`)
```javascript
{
  studentId: string,
  studentName: string,
  studentEmail: string,
  testId: string,
  testTitle: string,
  resultId: string,
  violationType: "tab_switch",
  tabSwitchCount: number,
  reason: string,
  timestamp: Timestamp,
  score: number
}
```

#### Updated Student Counters (`users`)
```javascript
{
  completedTests: increment(1),
  pendingTests: increment(-1),
  totalScore: increment(score),
  totalPoints: increment(score)
}
```

#### Updated Test Tracking (`tests`)
```javascript
{
  completedBy: arrayUnion([studentId]),
  completedCount: increment(1)
}
```

## Implementation Details

### Files Modified

1. **`lib/screens/student/test_rules_screen.dart`**
   - Removed AI proctoring and camera monitoring rules
   - Updated rules to focus on:
     - No Tab Switching (auto-submit warning)
     - Stable Connection
     - Timer Cannot Be Paused
     - Stay Focused
     - Academic Integrity

2. **`lib/screens/student/take_test_screen.dart`**
   - Added `WidgetsBindingObserver` mixin
   - Added lifecycle state monitoring
   - Tracks tab switch count
   - Implements `_autoSubmitTestForViolation()` method
   - Updates `_submitTest()` to accept violation parameters
   - Shows violation warnings in result dialog
   - Saves all data to Firebase via `FirestoreService`

3. **`lib/models/test_result_model.dart`**
   - Extended model with proctoring fields:
     - `wasProctored: bool`
     - `tabSwitchCount: int`
     - `violationDetected: bool`
     - `violationReason: String?`
   - Updated `fromFirestore()` and `toFirestore()` methods
   - Maintained backward compatibility with legacy fields

4. **`lib/services/firestore_service.dart`**
   - Added `submitTestResult()` method
   - Saves test result to `testResults` collection
   - Updates student counters (completed, pending, score)
   - Updates test completion tracking
   - Logs violations to `violations` collection
   - Comprehensive logging for debugging

## User Experience

### Normal Test Submission
1. Student completes test
2. Clicks "Submit Test" button
3. Confirmation dialog appears
4. Student confirms submission
5. Score displayed with success icon
6. Navigates back to test list

### Violation Auto-Submission
1. Student switches tabs/apps during test
2. **Immediate detection** - lifecycle observer fires
3. Red snackbar warning appears
4. Timer stops immediately
5. Test auto-submits with violation flag
6. Result dialog shows:
   - Warning icon (orange)
   - "Tab switching detected" message
   - Score calculated from answered questions
   - Tab switch count badge
7. Navigation back to test list

## Testing the System

### To Test Tab Switching Detection:
1. Login as a student
2. Navigate to test list
3. Read rules page
4. Start a test
5. **Switch to another app** or press home button
6. App should immediately:
   - Cancel the timer
   - Show red warning snackbar
   - Auto-submit the test
   - Display results with violation warning

### Expected Console Logs:
```
📝 Submitting test result for student: [Name]
   Test: [Test Title]
   Score: [X]%
   Tab switches: 1
   Violation: true
✅ Test result saved with ID: [doc_id]
✅ Student counters updated
✅ Test completion tracking updated
⚠️ Violation logged
```

## Firestore Rules Recommendations

Add these security rules to protect the data:

```javascript
// Test Results - Students can only create their own
match /testResults/{resultId} {
  allow read: if request.auth != null && 
    (resource.data.studentId == request.auth.uid || 
     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'teacher');
  allow create: if request.auth != null && 
    request.resource.data.studentId == request.auth.uid;
  allow update, delete: if false; // Results are immutable
}

// Violations - Read-only for students, read/write for teachers
match /violations/{violationId} {
  allow read: if request.auth != null && 
    (resource.data.studentId == request.auth.uid || 
     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'teacher');
  allow create: if request.auth != null; // System creates these
  allow update, delete: if get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'teacher';
}
```

## Future Enhancements

1. **Multi-Tab Switch Tolerance**
   - Allow 1 accidental tab switch with warning
   - Auto-submit on 2nd violation

2. **Violation Analytics Dashboard**
   - Teacher view of all violations
   - Filter by student, test, date
   - Violation trends and patterns

3. **Screen Recording Detection**
   - Detect if screen recording apps are active
   - Block test if recording detected

4. **Internet Connectivity Monitoring**
   - Detect network drops
   - Save local cache and sync when restored
   - Auto-submit on prolonged disconnect

5. **Copy/Paste Detection**
   - Monitor clipboard operations
   - Flag suspicious copy events

6. **Browser Tab Detection (Web)**
   - Use Page Visibility API for web builds
   - Detect when browser tab loses focus

## Known Limitations

1. **Single Violation Policy**
   - Currently auto-submits on first tab switch
   - No grace period or warnings

2. **No Local Caching**
   - If network fails during submission, data may be lost
   - Consider adding offline storage

3. **Platform-Specific Behavior**
   - iOS may trigger lifecycle states differently
   - Test thoroughly on all target platforms

4. **Background Notifications**
   - System notifications may trigger false positives
   - Consider filtering transient inactive states

## Conclusion

The proctoring system is now fully functional with:
- ✅ Real-time tab switching detection
- ✅ Automatic test submission on violation
- ✅ Comprehensive Firebase data storage
- ✅ Violation logging and tracking
- ✅ Updated student and test counters
- ✅ User-friendly violation warnings

The system provides a fair and secure testing environment while maintaining a smooth user experience for honest students.
