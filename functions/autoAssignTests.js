/**
 * Cloud Function: Auto-assign tests to students when created
 * Triggers when a new document is added to scheduledTests collection
 * Creates individual assignment documents in testResults for each student in the target class
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Admin SDK if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

exports.autoAssignTestToStudents = functions
  .region('us-central1')
  .firestore
  .document('scheduledTests/{testId}')
  .onCreate(async (snap, context) => {
    const testId = context.params.testId;
    const testData = snap.data();
    
    console.log(`🔔 New test created: ${testId} - ${testData.title}`);
    
    // Only auto-assign if test has className (indicating it's for a specific class)
    const className = testData.class || testData.className;
    const section = testData.section || '';
    const schoolCode = testData.schoolCode || '';
    
    if (!className || !schoolCode) {
      console.log('⚠️ Test missing className or schoolCode, skipping auto-assignment');
      return null;
    }
    
    console.log(`📝 Auto-assigning test to: ${className} - ${section} (School: ${schoolCode})`);
    
    try {
      // Query students in the target class
      let studentsQuery = db.collection('students')
        .where('schoolCode', '==', schoolCode)
        .where('className', '==', className);
      
      if (section) {
        studentsQuery = studentsQuery.where('section', '==', section);
      }
      
      const studentsSnapshot = await studentsQuery.get();
      console.log(`👥 Found ${studentsSnapshot.size} students in class`);
      
      if (studentsSnapshot.empty) {
        console.log('⚠️ No students found in this class');
        return null;
      }
      
      // Create batch for efficient writes
      const batch = db.batch();
      let assignmentCount = 0;
      
      for (const studentDoc of studentsSnapshot.docs) {
        const studentData = studentDoc.data();
        const studentEmail = studentData.email || studentData.studentEmail;
        
        if (!studentEmail) {
          console.log(`⚠️ Student ${studentDoc.id} missing email, skipping`);
          continue;
        }
        
        // Look up user UID from users collection
        const userQuery = await db.collection('users')
          .where('email', '==', studentEmail)
          .limit(1)
          .get();
        
        if (userQuery.empty) {
          console.log(`⚠️ No user found for email ${studentEmail}, skipping`);
          continue;
        }
        
        const userId = userQuery.docs[0].id;
        const userData = userQuery.docs[0].data();
        
        // Create assignment document
        const assignmentRef = db.collection('testResults').doc();
        const assignmentData = {
          testId: testId,
          studentId: userId,
          studentEmail: studentEmail,
          studentName: studentData.name || userData.name || '',
          testTitle: testData.title || testData.testTitle || '',
          subject: testData.subject || '',
          className: className,
          section: section,
          teacherId: testData.teacherId || testData.createdBy || '',
          teacherName: testData.teacherName || '',
          teacherEmail: testData.teacherEmail || '',
          status: 'assigned',
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          startedAt: null,
          submittedAt: null,
          score: null,
          totalMarks: testData.totalMarks || 0,
          totalQuestions: (testData.questions && testData.questions.length) || testData.questionCount || 0,
          totalPoints: 0,
          correctAnswers: 0,
          earnedPoints: 0,
          duration: testData.duration || 60,
          date: testData.date || '',
          startTime: testData.startTime || '',
          timeTaken: 0,
          schoolCode: schoolCode,
          answers: [],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
        
        batch.set(assignmentRef, assignmentData);
        assignmentCount++;
        
        // Also update user's pendingTests counter
        const userRef = db.collection('users').doc(userId);
        batch.update(userRef, {
          pendingTests: admin.firestore.FieldValue.increment(1),
          newNotifications: admin.firestore.FieldValue.increment(1)
        });
      }
      
      // Commit all assignments
      await batch.commit();
      console.log(`✅ Successfully assigned test to ${assignmentCount} students`);
      
      return { success: true, assignedCount: assignmentCount };
      
    } catch (error) {
      console.error('❌ Error auto-assigning test:', error);
      return { success: false, error: error.message };
    }
  });
