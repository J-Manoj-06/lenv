/**
 * Script to setup class subjects in Firestore
 * Run this in Firebase Console or using Node.js with Firebase Admin SDK
 */

const admin = require('firebase-admin');
// Initialize if not already initialized
// admin.initializeApp();
const db = admin.firestore();

async function setupClassSubjects() {
  console.log('🚀 Setting up class subjects...');

  // Define subjects for each class
  const classSubjects = {
    // Grade 10-A subjects
    '10-A': [
      { id: 'english', name: 'English', teacherName: 'Mr. Rajesh Kumar', icon: '📖' },
      { id: 'hindi', name: 'Hindi', teacherName: 'Mr. Rajesh Kumar', icon: '📚' },
      { id: 'mathematics', name: 'Mathematics', teacherName: 'Ms. Priya Singh', icon: '🔢' },
      { id: 'science', name: 'Science', teacherName: 'Dr. Amit Patel', icon: '🔬' },
      { id: 'social_studies', name: 'Social Studies', teacherName: 'Mrs. Anita Sharma', icon: '🌍' },
    ],
    
    // Grade 10-B subjects
    '10-B': [
      { id: 'english', name: 'English', teacherName: 'Ms. Sarah Thomas', icon: '📖' },
      { id: 'hindi', name: 'Hindi', teacherName: 'Mr. Vikram Rao', icon: '📚' },
      { id: 'mathematics', name: 'Mathematics', teacherName: 'Mr. Ravi Kumar', icon: '🔢' },
      { id: 'science', name: 'Science', teacherName: 'Dr. Sneha Desai', icon: '🔬' },
      { id: 'social_studies', name: 'Social Studies', teacherName: 'Mrs. Kavita Nair', icon: '🌍' },
    ],

    // Grade 11-A subjects
    '11-A': [
      { id: 'english', name: 'English', teacherName: 'Mr. John Wilson', icon: '📖' },
      { id: 'physics', name: 'Physics', teacherName: 'Dr. Ramesh Reddy', icon: '⚡' },
      { id: 'chemistry', name: 'Chemistry', teacherName: 'Dr. Lakshmi Iyer', icon: '🧪' },
      { id: 'mathematics', name: 'Mathematics', teacherName: 'Mr. Suresh Gupta', icon: '🔢' },
      { id: 'biology', name: 'Biology', teacherName: 'Dr. Meera Joshi', icon: '🧬' },
      { id: 'computer_science', name: 'Computer Science', teacherName: 'Mr. Arjun Mehta', icon: '💻' },
    ],

    // Add more classes as needed
  };

  const batch = db.batch();
  let count = 0;

  for (const [classId, subjects] of Object.entries(classSubjects)) {
    console.log(`\n📚 Setting up subjects for class ${classId}...`);
    
    for (const subject of subjects) {
      const ref = db.collection('classes').doc(classId).collection('subjects').doc(subject.id);
      batch.set(ref, {
        name: subject.name,
        teacherName: subject.teacherName,
        icon: subject.icon,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
      console.log(`  ✅ ${subject.name} (${subject.teacherName})`);
    }
  }

  await batch.commit();
  console.log(`\n✨ Successfully created ${count} subjects across ${Object.keys(classSubjects).length} classes!`);
}

// Run the setup
setupClassSubjects()
  .then(() => {
    console.log('\n🎉 Setup complete!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Error:', error);
    process.exit(1);
  });
