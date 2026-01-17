// Quick script to check test_results in Firestore
const admin = require('firebase-admin');
const serviceAccount = require('./google-services-admin.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkTestData() {
  console.log('🔍 Checking test_results collection...\n');

  // Get total count
  const allTests = await db.collection('test_results').get();
  console.log(`Total test_results documents: ${allTests.size}`);

  if (allTests.size === 0) {
    console.log('❌ No test_results documents found in Firestore!');
    process.exit(0);
  }

  // Get tests for CSK100
  const schoolTests = await db.collection('test_results')
    .where('schoolCode', '==', 'CSK100')
    .get();
  
  console.log(`Tests for CSK100: ${schoolTests.size}`);

  if (schoolTests.size === 0) {
    console.log('❌ No tests found for schoolCode="CSK100"');
    console.log('\n📋 Sample document structure from first test:');
    const firstDoc = allTests.docs[0];
    console.log(JSON.stringify(firstDoc.data(), null, 2));
    process.exit(0);
  }

  // Check date ranges
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

  let last7d = 0;
  let last30d = 0;
  let older = 0;

  schoolTests.forEach(doc => {
    const data = doc.data();
    const completedAt = data.completedAt?.toDate?.() || new Date(data.completedAt);
    
    if (completedAt >= sevenDaysAgo) {
      last7d++;
    } else if (completedAt >= thirtyDaysAgo) {
      last30d++;
    } else {
      older++;
    }
  });

  console.log(`\n📊 Date distribution for CSK100:`);
  console.log(`  Last 7 days: ${last7d} tests`);
  console.log(`  Last 30 days (7-30): ${last30d} tests`);
  console.log(`  Older than 30 days: ${older} tests`);

  if (last7d === 0 && last30d === 0) {
    console.log('\n❌ No test data in last 30 days!');
    console.log('\n📋 Sample test from CSK100:');
    const sample = schoolTests.docs[0];
    const sampleData = sample.data();
    console.log(JSON.stringify({
      id: sample.id,
      completedAt: sampleData.completedAt?.toDate?.() || sampleData.completedAt,
      standard: sampleData.standard,
      section: sampleData.section,
      studentName: sampleData.studentName,
      score: sampleData.score
    }, null, 2));
  }

  process.exit(0);
}

checkTestData().catch(console.error);
