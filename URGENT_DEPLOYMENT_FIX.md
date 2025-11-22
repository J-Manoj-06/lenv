# URGENT DEPLOYMENT FIX - Test Assignment Issue

## Problem Identified
Tests created from website appear in teacher dashboard but NOT in student's "Assigned Tests" page.

**Root Cause:** Website creates test in `scheduledTests` but doesn't create individual assignment documents in `testResults` collection.

---

## SOLUTION 1: Deploy Cloud Function (FASTEST - Do This Tonight)

This Cloud Function automatically creates student assignments whenever a new test is added to `scheduledTests`.

### Deploy Steps:

```bash
cd d:\new_reward\functions
firebase deploy --only functions:autoAssignTestToStudents
```

### What It Does:
- ✅ Triggers automatically when test is created
- ✅ Finds all students in target class (by schoolCode + className + section)
- ✅ Creates assignment document in `testResults` for each student
- ✅ Sets status to 'assigned'
- ✅ Updates student's pendingTests counter
- ✅ Works for both app and website test creation

### Testing After Deployment:
1. Wait 2-3 minutes for function to deploy
2. Create a new test from website for "Grade 10 - B"
3. Check student Kirti's app → Test should appear in "Assigned Tests"
4. Check Firestore → `testResults` collection should have new documents

---

## SOLUTION 2: Fix Website Code (Long-term Solution)

Your brother needs to add this code to the website when creating tests:

```javascript
// After creating test in scheduledTests
async function assignTestToStudents(testId, testData) {
  const { className, section, schoolCode } = testData;
  
  // Query students
  let query = db.collection('students')
    .where('schoolCode', '==', schoolCode)
    .where('className', '==', className);
  
  if (section) {
    query = query.where('section', '==', section);
  }
  
  const students = await query.get();
  
  // Create assignments
  const batch = db.batch();
  
  for (const studentDoc of students.docs) {
    const studentData = studentDoc.data();
    
    // Get user UID
    const userQuery = await db.collection('users')
      .where('email', '==', studentData.email)
      .limit(1)
      .get();
    
    if (userQuery.empty) continue;
    
    const userId = userQuery.docs[0].id;
    
    // Create assignment
    const assignmentRef = db.collection('testResults').doc();
    batch.set(assignmentRef, {
      testId: testId,
      studentId: userId,  // Firebase Auth UID!
      studentEmail: studentData.email,
      studentName: studentData.name || '',
      testTitle: testData.title,
      subject: testData.subject,
      className: className,
      section: section,
      teacherId: testData.teacherId,
      teacherName: testData.teacherName,
      teacherEmail: testData.teacherEmail,
      status: 'assigned',
      assignedAt: firebase.firestore.FieldValue.serverTimestamp(),
      startedAt: null,
      submittedAt: null,
      score: null,
      totalMarks: testData.totalMarks,
      totalQuestions: testData.questions?.length || 0,
      totalPoints: 0,
      correctAnswers: 0,
      earnedPoints: 0,
      duration: testData.duration,
      date: testData.date,
      startTime: testData.startTime,
      timeTaken: 0,
      schoolCode: schoolCode,
      answers: [],
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
  }
  
  await batch.commit();
  console.log(`✅ Assigned to ${students.size} students`);
}
```

---

## QUICK FIX FOR EXISTING TESTS (Manual)

For the test "Lenv founder manoj" that already exists:

### Option A: Re-create the test
1. Delete test from teacher dashboard
2. Create it again (Cloud Function will handle assignment)

### Option B: Manually create assignments (Firebase Console)
1. Go to Firestore → `testResults` collection
2. For each student in Grade 10 - B:
   - Add document with structure from SOLUTION 2
   - Use student's Firebase Auth UID as `studentId`

---

## VERIFICATION CHECKLIST

After deploying Cloud Function:

- [ ] Run: `firebase deploy --only functions:autoAssignTestToStudents`
- [ ] Wait 2-3 minutes for deployment
- [ ] Create new test from website
- [ ] Check Firebase Console → Cloud Functions logs
- [ ] Check Firestore → `testResults` collection has new docs
- [ ] Open student app → Navigate to Tests page
- [ ] Verify test appears in "Assigned Tests"

---

## EMERGENCY CONTACT

If deployment fails or tests still don't appear:
1. Check Cloud Functions logs in Firebase Console
2. Verify `studentId` in testResults matches Firebase Auth UID (not Firestore doc ID)
3. Check student's schoolCode matches test's schoolCode
4. Ensure className format matches exactly (e.g., "Grade 10" not "grade 10")

---

**Time to deploy: ~5 minutes**
**Status: READY FOR PRODUCTION**
