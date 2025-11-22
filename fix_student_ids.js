// Run this in Firebase Console → Firestore → Scripts
// Or deploy as a one-time Cloud Function

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function fixStudentIds() {
  console.log('🔄 Starting studentId fix...');
  
  // Get all testResults
  const testResults = await db.collection('testResults').get();
  
  let fixed = 0;
  let skipped = 0;
  
  const batch = db.batch();
  let batchCount = 0;
  
  for (const doc of testResults.docs) {
    const data = doc.data();
    const email = data.studentEmail;
    
    if (!email) {
      skipped++;
      continue;
    }
    
    // Look up correct auth UID from users collection
    const userQuery = await db.collection('users')
      .where('email', '==', email)
      .limit(1)
      .get();
    
    if (userQuery.empty) {
      console.log(`⚠️  No user found for ${email}`);
      skipped++;
      continue;
    }
    
    const correctUid = userQuery.docs[0].data().uid || userQuery.docs[0].id;
    
    // If studentId is wrong, fix it
    if (data.studentId !== correctUid) {
      console.log(`✏️  Fixing ${email}: ${data.studentId} → ${correctUid}`);
      batch.update(doc.ref, { studentId: correctUid });
      batchCount++;
      fixed++;
      
      if (batchCount >= 450) {
        await batch.commit();
        batchCount = 0;
      }
    } else {
      skipped++;
    }
  }
  
  if (batchCount > 0) {
    await batch.commit();
  }
  
  console.log(`✅ Fixed ${fixed} documents, skipped ${skipped}`);
}

fixStudentIds().catch(console.error);
