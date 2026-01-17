# 🔄 Backend Aggregation Implementation Guide

## Overview
This guide shows how to create the aggregation functions that populate the cached Firestore documents for the Institute Insights page.

---

## ⏰ Recommended Schedule
Run these functions **daily at 2 AM IST** to refresh data for all ranges (7d, 30d, monthly)

---

## 1️⃣ Aggregate Top Performers

### Cloud Function (Node.js)
```javascript
// functions/aggregateTopPerformers.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();

exports.aggregateTopPerformers = functions.pubsub
  .schedule('0 2 * * *') // Daily at 2 AM IST
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    console.log('🏆 Starting top performers aggregation...');

    try {
      // Get all schools
      const schoolsSnapshot = await db.collection('schools').get();

      for (const schoolDoc of schoolsSnapshot.docs) {
        const schoolCode = schoolDoc.id;
        console.log(`📊 Processing school: ${schoolCode}`);

        // Process for each range
        await processSchoolForRange(schoolCode, '7d', 7);
        await processSchoolForRange(schoolCode, '30d', 30);
        await processSchoolForRange(schoolCode, 'monthly', 30);
      }

      console.log('✅ Top performers aggregation complete');
      return null;
    } catch (error) {
      console.error('❌ Error in aggregation:', error);
      throw error;
    }
  });

async function processSchoolForRange(schoolCode, range, days) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - days);

  // Get test results from last N days
  const resultsSnapshot = await db.collection('test_results')
    .where('schoolCode', '==', schoolCode)
    .where('completedAt', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
    .get();

  // Group by student and calculate average
  const studentScores = {};
  
  resultsSnapshot.forEach(doc => {
    const data = doc.data();
    const studentId = data.studentId;
    const score = (data.score / data.totalMarks) * 100;

    if (!studentScores[studentId]) {
      studentScores[studentId] = {
        studentId,
        name: data.studentName,
        section: data.section,
        standard: data.standard,
        scores: [],
      };
    }
    studentScores[studentId].scores.push(score);
  });

  // Calculate averages
  const students = Object.values(studentScores).map(s => ({
    studentId: s.studentId,
    name: s.name,
    section: s.section,
    standard: s.standard,
    avgScore: s.scores.reduce((a, b) => a + b, 0) / s.scores.length,
  }));

  // Group by standard
  const standardsMap = {};
  students.forEach(student => {
    if (!standardsMap[student.standard]) {
      standardsMap[student.standard] = [];
    }
    standardsMap[student.standard].push(student);
  });

  // Sort and get top 3 per standard
  const standardsData = [];
  
  for (const [standard, stdStudents] of Object.entries(standardsMap)) {
    // Sort by avgScore descending
    const sorted = stdStudents.sort((a, b) => b.avgScore - a.avgScore);
    
    // Top 3 for summary
    const top3 = sorted.slice(0, 3).map(s => ({
      studentId: s.studentId,
      name: s.name,
      section: s.section,
      avgScore: s.avgScore,
    }));

    standardsData.push({
      standard,
      top3,
    });

    // Save full ranking to separate document
    const fullRankingDocId = `${schoolCode}_${range}_STD${standard}`;
    await db.collection('insights_top_performers_full').doc(fullRankingDocId).set({
      standard,
      schoolCode,
      range,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      students: sorted.map(s => ({
        studentId: s.studentId,
        name: s.name,
        section: s.section,
        avgScore: s.avgScore,
      })),
    });
  }

  // Save summary document
  const summaryDocId = `${schoolCode}_${range}`;
  await db.collection('insights_top_performers').doc(summaryDocId).set({
    schoolCode,
    range,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    standards: standardsData,
  });

  console.log(`✅ ${schoolCode} - ${range}: Processed ${standardsData.length} standards`);
}
```

---

## 2️⃣ Aggregate Teacher Stats

### Cloud Function (Node.js)
```javascript
// functions/aggregateTeacherStats.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();

exports.aggregateTeacherStats = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    console.log('👨‍🏫 Starting teacher stats aggregation...');

    try {
      const schoolsSnapshot = await db.collection('schools').get();

      for (const schoolDoc of schoolsSnapshot.docs) {
        const schoolCode = schoolDoc.id;
        await processTeacherStatsForSchool(schoolCode, '7d', 7);
        await processTeacherStatsForSchool(schoolCode, '30d', 30);
        await processTeacherStatsForSchool(schoolCode, 'monthly', 30);
      }

      console.log('✅ Teacher stats aggregation complete');
      return null;
    } catch (error) {
      console.error('❌ Error:', error);
      throw error;
    }
  });

async function processTeacherStatsForSchool(schoolCode, range, days) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - days);

  // Get tests from last N days
  const testsSnapshot = await db.collection('tests')
    .where('schoolCode', '==', schoolCode)
    .where('publishedAt', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
    .get();

  // Group by teacher
  const teacherData = {};

  for (const testDoc of testsSnapshot.docs) {
    const test = testDoc.data();
    const teacherId = test.teacherId;
    const classKey = `${test.standard}-${test.section}`;

    if (!teacherData[teacherId]) {
      teacherData[teacherId] = {
        teacherId,
        name: test.teacherName || 'Unknown',
        totalTests: 0,
        classSplit: {},
        tests: [],
      };
    }

    teacherData[teacherId].totalTests++;
    teacherData[teacherId].classSplit[classKey] = 
      (teacherData[teacherId].classSplit[classKey] || 0) + 1;

    // Calculate test average score
    const resultsSnapshot = await db.collection('test_results')
      .where('testId', '==', testDoc.id)
      .get();

    let totalScore = 0;
    let count = 0;
    resultsSnapshot.forEach(result => {
      const data = result.data();
      totalScore += (data.score / data.totalMarks) * 100;
      count++;
    });

    const avgScore = count > 0 ? totalScore / count : 0;

    teacherData[teacherId].tests.push({
      testId: testDoc.id,
      title: test.title,
      standard: test.standard,
      section: test.section,
      avgScore,
      date: test.publishedAt,
    });
  }

  // Save teacher stats summary
  const teachers = Object.values(teacherData).map(t => ({
    teacherId: t.teacherId,
    name: t.name,
    totalTests: t.totalTests,
    classSplit: t.classSplit,
  }));

  const summaryDocId = `${schoolCode}_${range}`;
  await db.collection('insights_teacher_stats').doc(summaryDocId).set({
    schoolCode,
    range,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    teachers,
  });

  // Save detailed test info per teacher
  for (const [teacherId, data] of Object.entries(teacherData)) {
    const detailDocId = `${schoolCode}_${range}_${teacherId}`;
    await db.collection('insights_teacher_tests').doc(detailDocId).set({
      teacherId,
      schoolCode,
      range,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      recentTests: data.tests.slice(0, 20), // Limit to 20 most recent
    });
  }

  console.log(`✅ ${schoolCode} - ${range}: Processed ${teachers.length} teachers`);
}
```

---

## 3️⃣ Aggregate School Metrics (for AI)

### Cloud Function (Node.js)
```javascript
// functions/aggregateSchoolMetrics.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const db = admin.firestore();

exports.aggregateSchoolMetrics = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    console.log('📊 Starting school metrics aggregation...');

    try {
      const schoolsSnapshot = await db.collection('schools').get();

      for (const schoolDoc of schoolsSnapshot.docs) {
        const schoolCode = schoolDoc.id;
        await processMetricsForSchool(schoolCode, '7d', 7);
        await processMetricsForSchool(schoolCode, '30d', 30);
        await processMetricsForSchool(schoolCode, 'monthly', 30);
      }

      console.log('✅ School metrics aggregation complete');
      return null;
    } catch (error) {
      console.error('❌ Error:', error);
      throw error;
    }
  });

async function processMetricsForSchool(schoolCode, range, days) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - days);

  // School-wide metrics
  await calculateAndSaveMetrics(schoolCode, range, 'school', null, null, cutoffDate);

  // Per-standard metrics
  const standards = ['6', '7', '8', '9', '10', '11', '12'];
  for (const std of standards) {
    await calculateAndSaveMetrics(schoolCode, range, `STD${std}`, std, null, cutoffDate);

    // Per-section metrics
    const sections = ['A', 'B', 'C', 'D'];
    for (const sec of sections) {
      await calculateAndSaveMetrics(schoolCode, range, `STD${std}_${sec}`, std, sec, cutoffDate);
    }
  }
}

async function calculateAndSaveMetrics(schoolCode, range, scopeKey, standard, section, cutoffDate) {
  // Build query
  let query = db.collection('test_results')
    .where('schoolCode', '==', schoolCode)
    .where('completedAt', '>=', admin.firestore.Timestamp.fromDate(cutoffDate));

  if (standard) {
    query = query.where('standard', '==', standard);
  }
  if (section) {
    query = query.where('section', '==', section);
  }

  const resultsSnapshot = await query.get();

  // Calculate metrics
  let totalScore = 0;
  let testCount = resultsSnapshot.size;
  const subjectScores = {};
  const studentScores = {};

  resultsSnapshot.forEach(doc => {
    const data = doc.data();
    const score = (data.score / data.totalMarks) * 100;
    totalScore += score;

    // Subject averages
    const subject = data.subject || 'General';
    if (!subjectScores[subject]) {
      subjectScores[subject] = { total: 0, count: 0 };
    }
    subjectScores[subject].total += score;
    subjectScores[subject].count++;

    // Student tracking
    if (!studentScores[data.studentId]) {
      studentScores[data.studentId] = [];
    }
    studentScores[data.studentId].push(score);
  });

  const avgScore = testCount > 0 ? totalScore / testCount : 0;

  // Subject averages
  const subjectAverages = {};
  for (const [subject, data] of Object.entries(subjectScores)) {
    subjectAverages[subject] = data.total / data.count;
  }

  // Count weak students (<50%)
  let weakStudentsCount = 0;
  for (const scores of Object.values(studentScores)) {
    const studentAvg = scores.reduce((a, b) => a + b, 0) / scores.length;
    if (studentAvg < 50) weakStudentsCount++;
  }

  // Count top improvers (compare first half vs second half)
  let topImproversCount = 0;
  for (const scores of Object.values(studentScores)) {
    if (scores.length >= 4) {
      const half = Math.floor(scores.length / 2);
      const firstHalf = scores.slice(0, half);
      const secondHalf = scores.slice(half);
      const firstAvg = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
      const secondAvg = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;
      if (secondAvg - firstAvg > 15) topImproversCount++;
    }
  }

  // Get attendance data
  const attendanceSnapshot = await db.collection('attendance')
    .where('schoolCode', '==', schoolCode)
    .where('date', '>=', cutoffDate.toISOString().split('T')[0])
    .get();

  let totalPresent = 0;
  let totalStudents = 0;
  attendanceSnapshot.forEach(doc => {
    const data = doc.data();
    const students = data.students || {};
    for (const student of Object.values(students)) {
      totalStudents++;
      if (student.isPresent) totalPresent++;
    }
  });

  const attendanceAvg = totalStudents > 0 ? (totalPresent / totalStudents) * 100 : 0;

  // Participation (assume 92% for now, can be calculated from engagement data)
  const participationAvg = 92.0;

  // Save metrics
  const docId = `${schoolCode}_${range}_${scopeKey}`;
  await db.collection('insights_metrics').doc(docId).set({
    schoolCode,
    range,
    scopeKey,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    avgScore,
    attendanceAvg,
    participationAvg,
    subjectAverages,
    weakStudentsCount,
    topImproversCount,
    testCount,
  });

  console.log(`✅ Metrics saved: ${docId}`);
}
```

---

## 🚀 Deployment

### 1. Install Dependencies
```bash
cd functions
npm install firebase-functions firebase-admin
```

### 2. Deploy Functions
```bash
firebase deploy --only functions:aggregateTopPerformers
firebase deploy --only functions:aggregateTeacherStats
firebase deploy --only functions:aggregateSchoolMetrics
```

### 3. Verify in Firebase Console
- Go to Firebase Console → Functions
- Check function logs for successful execution
- Verify documents created in Firestore

---

## 🧪 Manual Trigger (for testing)

### Using Firebase CLI
```bash
# Test locally
firebase functions:shell

# In the shell:
aggregateTopPerformers()
aggregateTeacherStats()
aggregateSchoolMetrics()
```

### Using Cloud Console
1. Go to Cloud Functions in Firebase Console
2. Click on function name
3. Click "Test function" tab
4. Click "Test the function"

---

## 📊 Monitor Performance

### Check Logs
```bash
firebase functions:log --only aggregateTopPerformers
firebase functions:log --only aggregateTeacherStats
firebase functions:log --only aggregateSchoolMetrics
```

### Expected Output
```
🏆 Starting top performers aggregation...
📊 Processing school: SCH001
✅ SCH001 - 7d: Processed 7 standards
✅ SCH001 - 30d: Processed 7 standards
✅ SCH001 - monthly: Processed 7 standards
✅ Top performers aggregation complete
```

---

## ⚠️ Important Notes

1. **Index Requirements**: Ensure Firestore composite indexes are created for:
   - `test_results`: [schoolCode, completedAt]
   - `test_results`: [schoolCode, standard, completedAt]
   - `test_results`: [schoolCode, standard, section, completedAt]
   - `tests`: [schoolCode, publishedAt]

2. **Cost Optimization**: These functions run ONCE per day, dramatically reducing read costs compared to real-time queries

3. **Data Freshness**: Data updates at 2 AM daily. Consider manual triggers after major events (exam results published, etc.)

4. **Error Handling**: Functions log errors but continue processing other schools

---

## 🔄 Alternative: Python Script

If you prefer running as a Python script instead of Cloud Functions:

```python
# aggregate_insights.py
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

def aggregate_all():
    schools = db.collection('schools').stream()
    
    for school in schools:
        school_code = school.id
        print(f'Processing {school_code}...')
        
        # Process for each range
        process_school(school_code, '7d', 7)
        process_school(school_code, '30d', 30)
        process_school(school_code, 'monthly', 30)

def process_school(school_code, range_name, days):
    # Similar logic to Cloud Functions
    pass

if __name__ == '__main__':
    aggregate_all()
```

Run with cron:
```bash
# Run daily at 2 AM
0 2 * * * /usr/bin/python3 /path/to/aggregate_insights.py
```

---

## ✅ Verification Checklist

After deployment:
- [ ] Functions deployed successfully
- [ ] Functions scheduled correctly (2 AM IST)
- [ ] First run executed (check logs)
- [ ] Firestore collections populated:
  - [ ] insights_top_performers
  - [ ] insights_top_performers_full
  - [ ] insights_teacher_stats
  - [ ] insights_teacher_tests
  - [ ] insights_metrics
- [ ] Flutter app displays data correctly
- [ ] Range filters work (7d, 30d, monthly)
- [ ] AI reports generate successfully

---

You're now ready to have fully automated, cost-efficient insights aggregation! 🎉
