const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkFormat() {
  const snapshot = await db.collection('students').limit(5).get();
  
  console.log('\n📋 Sample student documents:');
  snapshot.forEach(doc => {
    const data = doc.data();
    console.log('\n---');
    console.log('className:', data.className);
    console.log('section:', data.section);
    console.log('schoolCode:', data.schoolCode);
  });
}

checkFormat().then(() => process.exit(0));
