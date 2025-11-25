/**
 * Script to fix students with missing section field
 * Run this in Firebase Console -> Firestore -> Rules playground or use Node.js
 */

const admin = require('firebase-admin');

// Initialize if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function fixMissingSections() {
  console.log('🔍 Searching for students with missing/empty section field...');
  
  try {
    const studentsSnapshot = await db.collection('students').get();
    const studentsToFix = [];
    const studentsOk = [];
    
    studentsSnapshot.forEach(doc => {
      const data = doc.data();
      const section = data.section?.toString().trim() || '';
      const className = data.className || '';
      const studentName = data.studentName || 'Unknown';
      
      if (!section) {
        studentsToFix.push({
          id: doc.id,
          name: studentName,
          className: className,
          schoolCode: data.schoolCode || 'Unknown'
        });
      } else {
        studentsOk.push({
          id: doc.id,
          name: studentName,
          className: className,
          section: section
        });
      }
    });
    
    console.log(`\n✅ Students with section field: ${studentsOk.length}`);
    console.log(`❌ Students MISSING section field: ${studentsToFix.length}\n`);
    
    if (studentsToFix.length > 0) {
      console.log('📋 Students that need fixing:');
      console.log('=====================================');
      studentsToFix.forEach((student, index) => {
        console.log(`${index + 1}. ${student.name} (${student.id})`);
        console.log(`   Class: ${student.className}`);
        console.log(`   School: ${student.schoolCode}`);
        console.log(`   Missing: section field\n`);
      });
      
      console.log('\n📝 To fix, you can:');
      console.log('1. Manually add section field in Firebase Console');
      console.log('2. Or run the auto-fix below (uncomment the batch update code)\n');
      
      // UNCOMMENT BELOW TO AUTO-FIX (assigns section "A" by default)
      /*
      const batch = db.batch();
      let updateCount = 0;
      
      studentsToFix.forEach(student => {
        const docRef = db.collection('students').doc(student.id);
        batch.update(docRef, { section: 'A' }); // Default to section A
        updateCount++;
      });
      
      await batch.commit();
      console.log(`✅ Updated ${updateCount} students with default section "A"`);
      */
    } else {
      console.log('✅ All students have section field! No fixes needed.');
    }
    
    // Show sample of working students
    if (studentsOk.length > 0) {
      console.log('\n✅ Sample of students with sections:');
      console.log('=====================================');
      studentsOk.slice(0, 5).forEach(student => {
        console.log(`- ${student.name}: ${student.className} Section ${student.section}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

// Run the script
fixMissingSections()
  .then(() => {
    console.log('\n✅ Script completed');
    process.exit(0);
  })
  .catch(error => {
    console.error('❌ Script failed:', error);
    process.exit(1);
  });
