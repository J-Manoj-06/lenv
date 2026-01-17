/**
 * Cloudflare Worker: Institute Insights Aggregator
 * Uses Firestore REST API (no firebase-admin to avoid Node.js issues)
 * Runs daily at 2 AM IST
 */

import { SignJWT } from 'jose';

// ==================== FIRESTORE REST API HELPERS ====================

async function getAccessToken(serviceAccountJson) {
  const serviceAccount = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);
  
  // Convert PEM to CryptoKey
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  // Create JWT
  const jwt = await new SignJWT({
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/datastore'
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .sign(privateKey);

  // Exchange JWT for access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`
  });

  const data = await response.json();
  if (!data.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

function pemToArrayBuffer(pem) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// Convert JS object to Firestore fields format
function toFirestoreFields(obj) {
  const fields = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) {
      fields[key] = convertValue(value);
    }
  }
  return fields;
}

function convertValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) 
      ? { integerValue: String(value) } 
      : { doubleValue: value };
  }
  if (typeof value === 'boolean') return { booleanValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(v => convertValue(v)) } };
  }
  if (typeof value === 'object') {
    return { mapValue: { fields: toFirestoreFields(value) } };
  }
  return { stringValue: String(value) };
}

// Convert Firestore fields to JS object
function fromFirestoreFields(fields) {
  if (!fields) return null;
  const obj = {};
  for (const [key, value] of Object.entries(fields)) {
    obj[key] = extractValue(value);
  }
  return obj;
}

function extractValue(value) {
  if (value.stringValue !== undefined) return value.stringValue;
  if (value.integerValue !== undefined) return parseInt(value.integerValue);
  if (value.doubleValue !== undefined) return value.doubleValue;
  if (value.booleanValue !== undefined) return value.booleanValue;
  if (value.timestampValue !== undefined) return new Date(value.timestampValue);
  if (value.nullValue !== undefined) return null;
  if (value.arrayValue) return value.arrayValue.values?.map(v => extractValue(v)) || [];
  if (value.mapValue) return fromFirestoreFields(value.mapValue.fields);
  return null;
}

// Query Firestore
async function firestoreQuery(projectId, accessToken, collection, filters = []) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;
  
  const structuredQuery = {
    from: [{ collectionId: collection }]
  };

  if (filters.length > 0) {
    if (filters.length === 1) {
      structuredQuery.where = { fieldFilter: filters[0] };
    } else {
      structuredQuery.where = {
        compositeFilter: {
          op: 'AND',
          filters: filters.map(f => ({ fieldFilter: f }))
        }
      };
    }
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ structuredQuery })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Firestore query failed: ${error}`);
  }

  const results = await response.json();
  return results
    .filter(r => r.document)
    .map(r => ({
      id: r.document.name.split('/').pop(),
      data: fromFirestoreFields(r.document.fields)
    }));
}

// Write to Firestore
async function firestoreWrite(projectId, accessToken, collection, docId, data) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}/${docId}`;
  
  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      fields: {
        ...toFirestoreFields(data),
        updatedAt: { timestampValue: new Date().toISOString() }
      }
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Firestore write failed: ${error}`);
  }
  
  return await response.json();
}

// ==================== WORKER ====================

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    if (url.pathname === '/aggregate-top-performers') {
      return await handleTopPerformers(env);
    }
    if (url.pathname === '/aggregate-teacher-stats') {
      return await handleTeacherStats(env);
    }
    if (url.pathname === '/aggregate-metrics') {
      return await handleMetrics(env);
    }
    if (url.pathname === '/aggregate-all') {
      return await handleAll(env);
    }
    if (url.pathname === '/debug-test-data') {
      return await handleDebugTestData(env, url);
    }
    if (url.pathname === '/debug-aggregated') {
      return await handleDebugAggregated(env, url);
    }
    if (url.pathname === '/generate-sample-data') {
      return await handleGenerateSampleData(env);
    }
    
    return new Response(
      'Institute Insights Aggregator\n\n' +
      'Endpoints:\n' +
      '- /aggregate-top-performers\n' +
      '- /aggregate-teacher-stats\n' +
      '- /aggregate-metrics\n' +
      '- /aggregate-all\n' +
      '- /debug-test-data?schoolCode=CSK100\n' +
      '- /debug-aggregated?schoolCode=CSK100&range=7d\n' +
      '- /generate-sample-data (⚠️  WARNING: Generates 500+ test docs)',
      { headers: { 'Content-Type': 'text/plain' } }
    );
  },

  async scheduled(event, env, ctx) {
    console.log('🕐 Cron triggered:', new Date().toISOString());
    ctx.waitUntil(runAllAggregations(env));
  }
};

// ==================== HANDLERS ====================

async function handleAll(env) {
  try {
    await runAllAggregations(env);
    return new Response('✅ All aggregations completed', { status: 200 });
  } catch (error) {
    console.error('Error:', error);
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function handleTopPerformers(env) {
  try {
    const ctx = await initContext(env);
    await aggregateTopPerformers(ctx);
    return new Response('✅ Top performers aggregated', { status: 200 });
  } catch (error) {
    console.error('Error:', error);
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function handleTeacherStats(env) {
  try {
    const ctx = await initContext(env);
    await aggregateTeacherStats(ctx);
    return new Response('✅ Teacher stats aggregated', { status: 200 });
  } catch (error) {
    console.error('Error:', error);
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function handleMetrics(env) {
  try {
    const ctx = await initContext(env);
    await aggregateSchoolMetrics(ctx);
    return new Response('✅ Metrics aggregated', { status: 200 });
  } catch (error) {
    console.error('Error:', error);
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}
async function handleDebugTestData(env, url) {
  try {
    const ctx = await initContext(env);
    const schoolCode = url.searchParams.get('schoolCode') || 'CSK100';
    
    // Get testResults for this school by schoolCode field
    const schoolTests = await firestoreQuery(ctx.projectId, ctx.accessToken, 'testResults', [
      { field: { fieldPath: 'schoolCode' }, op: 'EQUAL', value: { stringValue: schoolCode } }
    ]);

    const now = new Date();
    const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000);
    const thirtyDaysAgo = new Date(now - 30 * 24 * 60 * 60 * 1000);

    let last7d = 0, last30d = 0, older = 0;
    const samples = [];

    for (const doc of schoolTests.slice(0, 5)) {
      const completedAt = new Date(doc.data.completedAt);
      const daysAgo = isNaN(completedAt) ? -1 : Math.floor((now - completedAt) / (24 * 60 * 60 * 1000));
      
      if (!isNaN(completedAt)) {
        if (completedAt >= sevenDaysAgo) last7d++;
        else if (completedAt >= thirtyDaysAgo) last30d++;
        else older++;
      }

      samples.push({
        id: doc.id,
        studentId: doc.data.studentId,
        completedAt: isNaN(completedAt) ? 'Invalid date' : completedAt.toISOString(),
        daysAgo,
        studentName: doc.data.studentName,
        score: doc.data.score
      });
    }

    return new Response(JSON.stringify({
      schoolCode,
      totalTests: schoolTests.length,
      dateDistribution: {
        last7Days: last7d,
        days8to30: last30d,
        olderThan30: older
      },
      sampleTests: samples
    }, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function handleDebugAggregated(env, url) {
  try {
    const ctx = await initContext(env);
    const schoolCode = url.searchParams.get('schoolCode') || 'CSK100';
    const range = url.searchParams.get('range') || '7d';
    
    // Read the aggregated document
    const docPath = `projects/${ctx.projectId}/databases/(default)/documents/insights_top_performers/${schoolCode}_${range}`;
    const response = await fetch(`https://firestore.googleapis.com/v1/${docPath}`, {
      headers: { 'Authorization': `Bearer ${ctx.accessToken}` }
    });

    if (!response.ok) {
      return new Response(`❌ Document not found: ${schoolCode}_${range}`, { status: 404 });
    }

    const doc = await response.json();
    const data = fromFirestoreFields(doc.fields);

    return new Response(JSON.stringify({
      documentId: `${schoolCode}_${range}`,
      data,
      standardsCount: data.standards?.length || 0,
      hasData: (data.standards?.length || 0) > 0
    }, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function handleGenerateSampleData(env) {
  try {
    const ctx = await initContext(env);
    
    const standards = [6, 7, 8, 9, 10, 11, 12];
    const sections = ['A', 'B', 'C'];
    const subjects = ['Mathematics', 'Science', 'English', 'Social Studies', 'Computer Science'];
    const names = [
      'Aarav Kumar', 'Vivaan Sharma', 'Aditya Patel', 'Vihaan Singh', 'Arjun Reddy',
      'Sai Prasad', 'Ayaan Khan', 'Krishna Rao', 'Ishaan Gupta', 'Reyansh Joshi',
      'Ananya Iyer', 'Diya Mehta', 'Aadhya Nair', 'Saanvi Desai', 'Kiara Pillai',
      'Myra Verma', 'Aaradhya Singh', 'Navya Kumar', 'Anvi Reddy', 'Kavya Patel'
    ];

    const getRandomElement = (arr) => arr[Math.floor(Math.random() * arr.length)];
    const getRandomScore = (base = 70) => Math.max(35, Math.min(100, base + Math.random() * 30 - 10));
    const getRandomDate = (daysBack) => {
      const date = new Date();
      date.setDate(date.getDate() - Math.floor(Math.random() * daysBack));
      date.setHours(10, 0, 0, 0);
      return date.toISOString();
    };

    const tests = [];

    // Generate just 35 tests total (5 students per standard, 1 test each = 35 tests)
    // This stays under Cloudflare's 50 subrequest limit
    for (const standard of standards) {
      const studentsPerStandard = 5;
      
      for (let studentIdx = 0; studentIdx < studentsPerStandard; studentIdx++) {
        const studentName = getRandomElement(names) + (studentIdx > 0 ? ` ${studentIdx}` : '');
        const section = getRandomElement(sections);
        const studentId = `CSK100_${standard}${section}_${studentIdx + 1}`;
        const baseScore = 60 + Math.random() * 30;
        
        const subject = getRandomElement(subjects);
        const testDate = getRandomDate(45);
        const score = getRandomScore(baseScore);
        const totalMarks = 100;
        
        const testId = `test_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        
        tests.push({
          id: testId,
          data: {
            testId,
            schoolCode: 'CSK100',
            studentId,
            studentName,
            standard,
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
          }
        });
      }
    }

    // Write in parallel batches of 15
    const batchSize = 15;
    for (let i = 0; i < tests.length; i += batchSize) {
      const batch = tests.slice(i, i + batchSize);
      await Promise.all(
        batch.map(test => firestoreWrite(ctx.projectId, ctx.accessToken, 'testResults', test.id, test.data))
      );
    }

    return new Response(JSON.stringify({
      success: true,
      testsGenerated: tests.length,
      message: `✅ Generated ${tests.length} test results for CSK100 in testResults collection. Now run /aggregate-top-performers`
    }, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(`❌ ${error.message}`, { status: 500 });
  }
}

async function initContext(env) {
  const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const accessToken = await getAccessToken(env.FIREBASE_SERVICE_ACCOUNT);
  return {
    projectId: serviceAccount.project_id,
    accessToken
  };
}

async function runAllAggregations(env) {
  const ctx = await initContext(env);
  console.log('🚀 Starting aggregations...');
  
  await aggregateTopPerformers(ctx);
  await aggregateTeacherStats(ctx);
  await aggregateSchoolMetrics(ctx);
  
  console.log('✅ Complete!');
}

// ==================== TOP PERFORMERS ====================

async function aggregateTopPerformers(ctx) {
  console.log('🏆 Top performers...');
  
  const schools = await firestoreQuery(ctx.projectId, ctx.accessToken, 'schools');

  for (const school of schools) {
    const schoolCode = school.id;
    console.log(`  📊 ${schoolCode}`);
    
    await processSchoolForRange(ctx, schoolCode, '7d', 7);
    await processSchoolForRange(ctx, schoolCode, '30d', 30);
    await processSchoolForRange(ctx, schoolCode, 'monthly', 30);
  }
}

async function processSchoolForRange(ctx, schoolCode, range, days) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  // Fetch ALL testResults for this school (no date filter to avoid index requirement)
  const allTestResults = await firestoreQuery(ctx.projectId, ctx.accessToken, 'testResults', [
    { field: { fieldPath: 'schoolCode' }, op: 'EQUAL', value: { stringValue: schoolCode } }
  ]);

  // Filter by date in memory
  const testResults = allTestResults.filter(doc => {
    const completedAt = new Date(doc.data.completedAt);
    return !isNaN(completedAt) && completedAt >= cutoff;
  });

  const studentScores = {};
  
  testResults.forEach(doc => {
    const d = doc.data;
    // score is already a percentage (0-100) based on totalMarks
    const score = d.score || 0;

    if (!studentScores[d.studentId]) {
      studentScores[d.studentId] = {
        studentId: d.studentId,
        name: d.studentName,
        section: d.section || 'A',
        standard: d.className || d.standard || 'Unknown',
        scores: []
      };
    }
    studentScores[d.studentId].scores.push(score);
  });

  const students = Object.values(studentScores).map(s => ({
    studentId: s.studentId,
    name: s.name,
    section: s.section,
    standard: s.standard,
    avgScore: s.scores.reduce((a, b) => a + b, 0) / s.scores.length
  }));

  const standardsMap = {};
  students.forEach(s => {
    if (!standardsMap[s.standard]) standardsMap[s.standard] = [];
    standardsMap[s.standard].push(s);
  });

  const standardsData = [];
  
  for (const [std, stdStudents] of Object.entries(standardsMap)) {
    const sorted = stdStudents.sort((a, b) => b.avgScore - a.avgScore);
    const top3 = sorted.slice(0, 3).map(s => ({
      studentId: s.studentId,
      name: s.name,
      section: s.section,
      avgScore: s.avgScore
    }));

    standardsData.push({ standard: std, top3 });

    // Full ranking
    await firestoreWrite(ctx.projectId, ctx.accessToken, 
      'insights_top_performers_full', 
      `${schoolCode}_${range}_STD${std}`, 
      {
        standard: std,
        schoolCode,
        range,
        students: sorted.map(s => ({
          studentId: s.studentId,
          name: s.name,
          section: s.section,
          avgScore: s.avgScore
        }))
      }
    );
  }

  // Summary
  await firestoreWrite(ctx.projectId, ctx.accessToken,
    'insights_top_performers',
    `${schoolCode}_${range}`,
    { schoolCode, range, standards: standardsData }
  );
}

// ==================== TEACHER STATS ====================

async function aggregateTeacherStats(ctx) {
  console.log('👨‍🏫 Teacher stats...');
  
  const schools = await firestoreQuery(ctx.projectId, ctx.accessToken, 'schools');

  for (const school of schools) {
    const schoolCode = school.id;
    await processTeacherStats(ctx, schoolCode, '7d', 7);
    await processTeacherStats(ctx, schoolCode, '30d', 30);
    await processTeacherStats(ctx, schoolCode, 'monthly', 30);
  }
}

async function processTeacherStats(ctx, schoolCode, range, days) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  // Fetch ALL testResults for this school (no date filter to avoid index requirement)
  const allTestResults = await firestoreQuery(ctx.projectId, ctx.accessToken, 'testResults', [
    { field: { fieldPath: 'schoolCode' }, op: 'EQUAL', value: { stringValue: schoolCode } }
  ]);

  // Filter by date in memory
  const testResults = allTestResults.filter(doc => {
    const completedAt = new Date(doc.data.completedAt);
    return !isNaN(completedAt) && completedAt >= cutoff;
  });

  // Group by teacherId
  const teacherData = {};
  const teacherTestMap = {};

  testResults.forEach(doc => {
    const d = doc.data;
    const tid = d.teacherId || 'unknown';
    const testId = d.testId;
    const classKey = `${d.className || d.standard || 'N/A'}-${d.section || 'N/A'}`;

    if (!teacherData[tid]) {
      teacherData[tid] = {
        teacherId: tid,
        name: d.teacherName || 'Unknown',
        totalTests: 0,
        classSplit: {},
        testIds: new Set()
      };
    }

    // Track unique tests
    if (!teacherData[tid].testIds.has(testId)) {
      teacherData[tid].testIds.add(testId);
      teacherData[tid].totalTests++;
      teacherData[tid].classSplit[classKey] = (teacherData[tid].classSplit[classKey] || 0) + 1;
    }

    // Group results by testId for averaging
    if (!teacherTestMap[testId]) {
      teacherTestMap[testId] = {
        teacherId: tid,
        title: d.testTitle,
        className: d.className || d.standard,
        section: d.section,
        date: d.completedAt,
        scores: []
      };
    }
    teacherTestMap[testId].scores.push(d.score || 0);
  });

  // Calculate test averages and add to teacher data
  for (const tid in teacherData) {
    teacherData[tid].tests = [];
  }

  for (const [testId, testInfo] of Object.entries(teacherTestMap)) {
    const avgScore = testInfo.scores.reduce((a, b) => a + b, 0) / testInfo.scores.length;
    const tid = testInfo.teacherId;
    
    if (teacherData[tid]) {
      teacherData[tid].tests.push({
        testId,
        title: testInfo.title,
        standard: testInfo.className,
        section: testInfo.section,
        avgScore,
        date: testInfo.date
      });
    }
  }

  // Clean up Set objects before saving
  for (const tid in teacherData) {
    delete teacherData[tid].testIds;
  }

  const teachers = Object.values(teacherData).map(t => ({
    teacherId: t.teacherId,
    name: t.name,
    totalTests: t.totalTests,
    classSplit: t.classSplit
  }));

  await firestoreWrite(ctx.projectId, ctx.accessToken,
    'insights_teacher_stats',
    `${schoolCode}_${range}`,
    { schoolCode, range, teachers }
  );

  for (const [tid, data] of Object.entries(teacherData)) {
    await firestoreWrite(ctx.projectId, ctx.accessToken,
      'insights_teacher_tests',
      `${schoolCode}_${range}_${tid}`,
      {
        teacherId: tid,
        schoolCode,
        range,
        recentTests: data.tests.slice(0, 20)
      }
    );
  }
}

// ==================== METRICS ====================

async function aggregateSchoolMetrics(ctx) {
  console.log('📊 Metrics...');
  
  const schools = await firestoreQuery(ctx.projectId, ctx.accessToken, 'schools');

  for (const school of schools) {
    const schoolCode = school.id;
    await processMetrics(ctx, schoolCode, '7d', 7);
    await processMetrics(ctx, schoolCode, '30d', 30);
    await processMetrics(ctx, schoolCode, 'monthly', 30);
  }
}

async function processMetrics(ctx, schoolCode, range, days) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  await saveMetrics(ctx, schoolCode, range, 'school', null, null, cutoff);

  // Only do per-standard, skip per-section to reduce subrequests
  for (const std of ['6', '7', '8', '9', '10', '11', '12']) {
    await saveMetrics(ctx, schoolCode, range, `STD${std}`, std, null, cutoff);
  }
}

async function saveMetrics(ctx, schoolCode, range, scopeKey, std, sec, cutoff) {
  const filters = [
    { field: { fieldPath: 'schoolCode' }, op: 'EQUAL', value: { stringValue: schoolCode } },
    { field: { fieldPath: 'completedAt' }, op: 'GREATER_THAN_OR_EQUAL', value: { timestampValue: cutoff.toISOString() } }
  ];

  if (std) filters.push({ field: { fieldPath: 'standard' }, op: 'EQUAL', value: { stringValue: std } });
  if (sec) filters.push({ field: { fieldPath: 'section' }, op: 'EQUAL', value: { stringValue: sec } });

  const results = await firestoreQuery(ctx.projectId, ctx.accessToken, 'test_results', filters);

  let totalScore = 0;
  const subjectScores = {};
  const studentScores = {};

  results.forEach(doc => {
    const d = doc.data;
    const score = (d.score / d.totalMarks) * 100;
    totalScore += score;

    const subj = d.subject || 'General';
    if (!subjectScores[subj]) subjectScores[subj] = { total: 0, count: 0 };
    subjectScores[subj].total += score;
    subjectScores[subj].count++;

    if (!studentScores[d.studentId]) studentScores[d.studentId] = [];
    studentScores[d.studentId].push(score);
  });

  const avgScore = results.length > 0 ? totalScore / results.length : 0;

  const subjectAverages = {};
  for (const [subj, data] of Object.entries(subjectScores)) {
    subjectAverages[subj] = data.total / data.count;
  }

  let weakCount = 0;
  for (const scores of Object.values(studentScores)) {
    const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
    if (avg < 50) weakCount++;
  }

  let improversCount = 0;
  for (const scores of Object.values(studentScores)) {
    if (scores.length >= 4) {
      const half = Math.floor(scores.length / 2);
      const first = scores.slice(0, half);
      const second = scores.slice(half);
      const firstAvg = first.reduce((a, b) => a + b, 0) / first.length;
      const secondAvg = second.reduce((a, b) => a + b, 0) / second.length;
      if (secondAvg - firstAvg > 15) improversCount++;
    }
  }

  const attendance = await firestoreQuery(ctx.projectId, ctx.accessToken, 'attendance', [
    { field: { fieldPath: 'schoolCode' }, op: 'EQUAL', value: { stringValue: schoolCode } },
    { field: { fieldPath: 'date' }, op: 'GREATER_THAN_OR_EQUAL', value: { stringValue: cutoff.toISOString().split('T')[0] } }
  ]);

  let present = 0, totalStud = 0;
  attendance.forEach(doc => {
    const students = doc.data.students || {};
    for (const s of Object.values(students)) {
      totalStud++;
      if (s.isPresent) present++;
    }
  });

  const attendanceAvg = totalStud > 0 ? (present / totalStud) * 100 : 0;

  await firestoreWrite(ctx.projectId, ctx.accessToken,
    'insights_metrics',
    `${schoolCode}_${range}_${scopeKey}`,
    {
      schoolCode,
      range,
      scopeKey,
      avgScore,
      attendanceAvg,
      participationAvg: 92.0,
      subjectAverages,
      weakStudentsCount: weakCount,
      topImproversCount: improversCount,
      testCount: results.length
    }
  );
}
