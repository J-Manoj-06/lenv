/**
 * Generate Sample Test Data for CSK100 School
 * Creates realistic test results for the last 45 days
 * Uses Firestore REST API (no admin SDK needed)
 */

const https = require('https');
const fs = require('fs');

// Load project config
const googleServices = JSON.parse(fs.readFileSync('./google-services.json', 'utf8'));
const PROJECT_ID = googleServices.project_info.project_id;
const API_KEY = googleServices.client[0].api_key[0].current_key;

console.log('📦 Firebase Project:', PROJECT_ID);

// Sample data
const standards = [6, 7, 8, 9, 10, 11, 12];
const sections = ['A', 'B', 'C'];
const subjects = ['Mathematics', 'Science', 'English', 'Social Studies', 'Computer Science'];

const indianNames = [
  'Aarav Kumar', 'Vivaan Sharma', 'Aditya Patel', 'Vihaan Singh', 'Arjun Reddy',
  'Sai Prasad', 'Ayaan Khan', 'Krishna Rao', 'Ishaan Gupta', 'Reyansh Joshi',
  'Ananya Iyer', 'Diya Mehta', 'Aadhya Nair', 'Saanvi Desai', 'Kiara Pillai',
  'Myra Verma', 'Aaradhya Singh', 'Navya Kumar', 'Anvi Reddy', 'Kavya Patel'
];

function getRandomElement(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function getRandomScore(baseScore = 70) {
  // Generate scores with some variance
  const variance = Math.random() * 30 - 10; // -10 to +20
  return Math.max(35, Math.min(100, baseScore + variance));
}

function getRandomDate(daysBack) {
  const date = new Date();
  date.setDate(date.getDate() - Math.floor(Math.random() * daysBack));
  date.setHours(10, 0, 0, 0);
  return date.toISOString();
}

// Convert JS value to Firestore REST API format
function toFirestoreValue(value) {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) 
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'boolean') return { booleanValue: value };
  if (value instanceof Date || typeof value === 'string' && value.includes('T')) {
    return { timestampValue: typeof value === 'string' ? value : value.toISOString() };
  }
  return { stringValue: String(value) };
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) {
      fields[key] = toFirestoreValue(value);
    }
  }
  return fields;
}

async function writeToFirestore(collectionId, documentId, data) {
  return new Promise((resolve, reject) => {
    const path = `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionId}?documentId=${documentId}&key=${API_KEY}`;
    const body = JSON.stringify({ fields: toFirestoreFields(data) });
    
    const options = {
      hostname: 'firestore.googleapis.com',
      port: 443,
      path: path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function generateTestData() {
  console.log('🎯 Generating sample test data for CSK100...\n');

  let count = 0;
  const totalTests = [];

  // Generate tests for each standard
  for (const standard of standards) {
    console.log(`📚 Generating tests for Standard ${standard}...`);
    
    // Each standard has 15-20 students across sections
    const studentsPerStandard = 15 + Math.floor(Math.random() * 6);
    
    for (let studentIdx = 0; studentIdx < studentsPerStandard; studentIdx++) {
      const studentName = getRandomElement(indianNames) + (studentIdx > 0 ? ` ${studentIdx}` : '');
      const section = getRandomElement(sections);
      const studentId = `CSK100_${standard}${section}_${studentIdx + 1}`;
      const baseScore = 60 + Math.random() * 30; // Students have consistent base performance
      
      // Each student has taken 3-6 tests in last 45 days
      const testCount = 3 + Math.floor(Math.random() * 4);
      
      for (let testIdx = 0; testIdx < testCount; testIdx++) {
        const subject = getRandomElement(subjects);
        const testDate = getRandomDate(45); // Tests from last 45 days
        const score = getRandomScore(baseScore);
        const totalMarks = 100;
        
        const testId = `test_${studentId}_${subject.replace(/\s+/g, '')}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        
        const testData = {
          testId,
          schoolCode: 'CSK100',
          studentId,
          studentName,
          standard: standard,
          section,
          subject,
          score,
          totalMarks,
          percentage: parseFloat(((score / totalMarks) * 100).toFixed(2)),
          completedAt: testDate,
          createdAt: testDate,
          teacherId: `teacher_${standard}_${section}`,
          teacherName: `Teacher ${standard}${section}`,
          testType: 'unit_test',
          duration: 60,
          questionsCount: 20,
          correctAnswers: Math.floor((score / totalMarks) * 20),
          wrongAnswers: 20 - Math.floor((score / totalMarks) * 20)
        };
        
        totalTests.push({ id: testId, data: testData });
        count++;
      }
    }
  }

  console.log(`\n📤 Uploading ${count} test results to Firestore...`);
  
  // Upload in batches
  const batchSize = 10;
  for (let i = 0; i < totalTests.length; i += batchSize) {
    const batch = totalTests.slice(i, i + batchSize);
    await Promise.all(
      batch.map(test => writeToFirestore('test_results', test.id, test.data))
    );
    console.log(`  ✅ Uploaded ${Math.min(i + batchSize, count)}/${count} tests...`);
  }

  console.log(`\n✨ Successfully generated ${count} test results!`);
  
  // Calculate distribution
  const last7Days = new Date();
  last7Days.setDate(last7Days.getDate() - 7);
  const last30Days = new Date();
  last30Days.setDate(last30Days.getDate() - 30);
  
  const recent7 = totalTests.filter(t => new Date(t.data.completedAt) >= last7Days).length;
  const recent30 = totalTests.filter(t => new Date(t.data.completedAt) >= last30Days).length;

  console.log('\n📊 Data Distribution:');
  console.log(`  Last 7 days: ${recent7} tests`);
  console.log(`  Last 30 days: ${recent30} tests`);
  console.log(`  Total: ${count} tests`);
  console.log(`  Standards: ${standards.join(', ')}`);
  console.log(`  Sections: ${sections.join(', ')}`);
  console.log(`  Subjects: ${subjects.join(', ')}`);
}

// Run the script
generateTestData()
  .then(() => {
    console.log('\n✅ All done! Now run aggregation with:');
    console.log('   curl https://insights-aggregator.giridharannj.workers.dev/aggregate-top-performers');
    process.exit(0);
  })
  .catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
  });
