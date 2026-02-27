'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

const REGION = 'us-central1';
const REVISION_THRESHOLD = 15;
const REVISION_DURATION_MINUTES = 180; // 3 hours
const REVISION_START_HOUR = 18; // 6 PM
const REVISION_END_HOUR = 21; // 9 PM
const SYSTEM_TEACHER_ID = '__ai_system__';
const SYSTEM_TEACHER_NAME = 'AI System';

function normalizeText(v) {
  return String(v || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function slugify(v) {
  return String(v || 'general')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '') || 'general';
}

function toYmd(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function getIsoWeekKey(inputDate = new Date()) {
  // ISO week (Mon-Sun) in UTC for deterministic server behavior
  const date = new Date(Date.UTC(
    inputDate.getUTCFullYear(),
    inputDate.getUTCMonth(),
    inputDate.getUTCDate(),
  ));

  // Thursday in current week decides the year
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);

  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((date - yearStart) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(weekNo).padStart(2, '0')}`;
}

function parseQuestionType(raw) {
  const type = String(raw || '').toLowerCase();
  if (
    type.includes('multiplechoice') ||
    type.includes('multiple_choice') ||
    type.includes('multiple') ||
    type.includes('mcq')
  ) {
    return 'mcq';
  }
  if (type.includes('truefalse') || type.includes('true_false') || type === 'tf') {
    return 'tf';
  }
  return type;
}

function resolveCorrectFromQuestion(question) {
  if (!question || typeof question !== 'object') return '';

  if (typeof question.correctAnswer === 'string' && question.correctAnswer.trim()) {
    return question.correctAnswer.trim();
  }

  const options = Array.isArray(question.options) ? question.options.map((o) => String(o)) : [];
  const answer = String(question.answer || '').trim();
  if (!answer) return '';

  // Handle A/B/C/D style answers
  const upper = answer.toUpperCase();
  if (upper.length === 1 && upper >= 'A' && upper <= 'D' && options.length) {
    const idx = upper.charCodeAt(0) - 65;
    if (idx >= 0 && idx < options.length) return options[idx].trim();
  }

  return answer;
}

function extractUserAnswer(answer) {
  const keys = [
    'userAnswer',
    'selectedAnswer',
    'selectedOption',
    'selectedLabel',
    'selected',
    'userOption',
    'userLabel',
    'answer',
    'studentAnswer',
  ];
  for (const key of keys) {
    if (answer[key] !== undefined && answer[key] !== null) {
      return String(answer[key]).trim();
    }
  }
  return '';
}

async function sendRevisionNotification({
  studentId,
  title,
  body,
  type,
  referenceId,
  data = {},
}) {
  try {
    const userSnap = await db.collection('users').doc(studentId).get();
    if (!userSnap.exists) return;

    const userData = userSnap.data() || {};
    const fcmToken = userData.fcmToken;

    await db.collection('notifications').add({
      userId: studentId,
      title,
      body,
      type,
      referenceId,
      isRead: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      data,
    });

    await db.collection('users').doc(studentId).set({
      newNotifications: admin.firestore.FieldValue.increment(1),
    }, { merge: true });

    if (!fcmToken) return;

    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data: Object.keys(data).reduce((acc, k) => {
        acc[k] = String(data[k]);
        return acc;
      }, { type: String(type), referenceId: String(referenceId), userId: String(studentId) }),
      android: {
        priority: 'high',
        notification: {
          channelId: 'lenv_channel',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    });
  } catch (e) {
    console.error('sendRevisionNotification error:', e);
  }
}

async function buildQuestionLookup(testId) {
  const lookup = new Map();
  if (!testId) return lookup;

  try {
    const testSnap = await db.collection('scheduledTests').doc(testId).get();
    if (!testSnap.exists) return lookup;

    const data = testSnap.data() || {};
    const questions = Array.isArray(data.questions) ? data.questions : [];

    for (const q of questions) {
      const questionText = String(q.questionText || q.question || '').trim();
      if (!questionText) continue;

      const key = normalizeText(questionText);
      lookup.set(key, {
        questionText,
        type: parseQuestionType(q.type),
        options: Array.isArray(q.options) ? q.options.map((o) => String(o)) : [],
        correctAnswer: resolveCorrectFromQuestion(q),
      });
    }
  } catch (e) {
    console.error('buildQuestionLookup error:', e);
  }

  return lookup;
}

function isAIRevisionTest(resultData) {
  const category = String(resultData.testCategory || '').toLowerCase();
  const title = String(resultData.testTitle || '').toLowerCase();
  return (
    category === 'ai_revision' ||
    resultData.isAIRevision === true ||
    title.includes('ai revision test')
  );
}

exports.trackWeeklyStudentErrors = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 120, memory: '512MB' })
  .firestore.document('testResults/{resultId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    // Process only when a test transitions into completed state
    if (before.status === 'completed' || after.status !== 'completed') {
      return null;
    }

    // Exclude AI revision tests from the source signal
    if (isAIRevisionTest(after)) {
      return null;
    }

    const studentId = String(after.studentId || '').trim();
    const subject = String(after.subject || 'General').trim() || 'General';
    const answers = Array.isArray(after.answers) ? after.answers : [];

    if (!studentId || answers.length === 0) {
      return null;
    }

    const questionLookup = await buildQuestionLookup(after.testId);
    const wrongMcqItems = [];

    for (const answer of answers) {
      if (!answer || typeof answer !== 'object') continue;

      const isCorrect = answer.isCorrect === true;
      if (isCorrect) continue;

      const questionText = String(answer.questionText || '').trim();
      if (!questionText) continue;

      const normalizedQuestion = normalizeText(questionText);
      const qMeta = questionLookup.get(normalizedQuestion) || {};

      const answerType = parseQuestionType(answer.questionType || qMeta.type || '');
      const answerOptions = Array.isArray(answer.options)
        ? answer.options.map((o) => String(o))
        : (Array.isArray(qMeta.options) ? qMeta.options : []);

      const looksLikeMcq = answerType === 'mcq' || answerOptions.length >= 2;
      if (!looksLikeMcq) {
        continue;
      }

      const correctAnswer = String(
        answer.correctAnswer || qMeta.correctAnswer || '',
      ).trim();

      wrongMcqItems.push({
        questionKey: normalizedQuestion,
        questionText,
        options: answerOptions,
        correctAnswer,
        userAnswer: extractUserAnswer(answer),
        sourceTestId: String(after.testId || ''),
        sourceResultId: String(context.params.resultId || ''),
        capturedAt: admin.firestore.Timestamp.now(),
      });
    }

    if (wrongMcqItems.length === 0) {
      return null;
    }

    const weekKey = getIsoWeekKey(new Date());
    const vaultId = `${studentId}_${slugify(subject)}_${weekKey}`;
    const vaultRef = db.collection('revision_error_vaults').doc(vaultId);

    let shouldSendPreparationNotification = false;
    let notificationPayload = null;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(vaultRef);
      const existing = snap.exists ? (snap.data() || {}) : {};

      const existingQuestions = Array.isArray(existing.errorQuestions)
        ? existing.errorQuestions
        : [];

      const mergedQuestions = [...existingQuestions];
      for (const item of wrongMcqItems) {
        const idx = mergedQuestions.findIndex(
          (q) => q && q.questionKey === item.questionKey,
        );

        if (idx >= 0) {
          const prev = mergedQuestions[idx] || {};
          mergedQuestions[idx] = {
            ...prev,
            questionText: item.questionText,
            options: item.options,
            correctAnswer: item.correctAnswer,
            userAnswer: item.userAnswer,
            sourceTestId: item.sourceTestId,
            sourceResultId: item.sourceResultId,
            lastSeenAt: admin.firestore.Timestamp.now(),
            mistakeFrequency: (Number(prev.mistakeFrequency) || 1) + 1,
          };
        } else {
          mergedQuestions.push({
            ...item,
            firstSeenAt: admin.firestore.Timestamp.now(),
            lastSeenAt: admin.firestore.Timestamp.now(),
            mistakeFrequency: 1,
          });
        }
      }

      const previousCount = Number(existing.errorCount) || 0;
      const nextCount = previousCount + wrongMcqItems.length;
      const alreadyPrepared = existing.revisionPrepared === true;
      const alreadyNotified = existing.preparationNotificationSent === true;

      const update = {
        studentId,
        subject,
        weekKey,
        schoolCode: String(after.schoolCode || existing.schoolCode || '').trim(),
        className: String(after.className || existing.className || '').trim(),
        section: String(after.section || existing.section || '').trim(),
        studentName: String(after.studentName || existing.studentName || '').trim(),
        studentEmail: String(after.studentEmail || existing.studentEmail || '').trim(),
        lastResultId: String(context.params.resultId || ''),
        lastTestId: String(after.testId || ''),
        errorCount: nextCount,
        threshold: REVISION_THRESHOLD,
        errorQuestions: mergedQuestions,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        weekClosed: false,
      };

      if (!snap.exists) {
        update.createdAt = admin.firestore.FieldValue.serverTimestamp();
      }

      if (!alreadyPrepared && nextCount >= REVISION_THRESHOLD) {
        update.revisionPrepared = true;
        update.preparedAt = admin.firestore.FieldValue.serverTimestamp();
        update.preparationReason = 'threshold_reached';

        if (!alreadyNotified) {
          update.preparationNotificationSent = true;
          shouldSendPreparationNotification = true;
          notificationPayload = {
            studentId,
            subject,
            weekKey,
            vaultId,
          };
        }
      }

      tx.set(vaultRef, update, { merge: true });
    });

    if (shouldSendPreparationNotification && notificationPayload) {
      await sendRevisionNotification({
        studentId: notificationPayload.studentId,
        title: 'AI Revision Test Scheduled',
        body: `${notificationPayload.subject}: AI Revision Test scheduled for Sunday evening (6:00 PM - 9:00 PM).`,
        type: 'ai_revision_prepared',
        referenceId: notificationPayload.vaultId,
        data: {
          weekKey: notificationPayload.weekKey,
          subject: notificationPayload.subject,
          vaultId: notificationPayload.vaultId,
        },
      });
    }

    return null;
  });

exports.weeklyRevisionSweep = functions
  .region(REGION)
  .pubsub.schedule('45 17 * * 0') // Sunday 5:45 PM
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const weekKey = getIsoWeekKey(new Date());
    const snap = await db
      .collection('revision_error_vaults')
      .where('weekKey', '==', weekKey)
      .get();

    if (snap.empty) {
      return null;
    }

    const updates = [];

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const errorCount = Number(data.errorCount) || 0;
      const prepared = data.revisionPrepared === true;
      const notified = data.preparationNotificationSent === true;

      if (errorCount >= REVISION_THRESHOLD) {
        const patch = {
          revisionPrepared: true,
          weekClosed: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (!prepared) {
          patch.preparedAt = admin.firestore.FieldValue.serverTimestamp();
          patch.preparationReason = 'weekly_sweep';
        }

        if (!notified) {
          patch.preparationNotificationSent = true;
          await sendRevisionNotification({
            studentId: String(data.studentId || ''),
            title: 'AI Revision Test Scheduled',
            body: `${String(data.subject || 'Subject')}: AI Revision Test scheduled for Sunday evening (6:00 PM - 9:00 PM).`,
            type: 'ai_revision_prepared',
            referenceId: doc.id,
            data: {
              weekKey,
              subject: String(data.subject || 'General'),
              vaultId: doc.id,
            },
          });
        }

        updates.push(doc.ref.set(patch, { merge: true }));
      } else {
        updates.push(doc.ref.set({
          revisionPrepared: false,
          weekClosed: true,
          closedReason: 'threshold_not_met',
          resetAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }));
      }
    }

    await Promise.all(updates);
    return null;
  });

exports.generateSundayEveningRevisionTests = functions
  .region(REGION)
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('0 18 * * 0') // Sunday 6:00 PM
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const now = new Date();
    const weekKey = getIsoWeekKey(now);

    const startDate = new Date(now);
    startDate.setHours(REVISION_START_HOUR, 0, 0, 0);

    const endDate = new Date(now);
    endDate.setHours(REVISION_END_HOUR, 0, 0, 0);

    const dateStr = toYmd(startDate);

    const vaultSnap = await db
      .collection('revision_error_vaults')
      .where('weekKey', '==', weekKey)
      .where('revisionPrepared', '==', true)
      .get();

    if (vaultSnap.empty) {
      return null;
    }

    const tasks = [];

    for (const vaultDoc of vaultSnap.docs) {
      tasks.push((async () => {
        // Production safety: claim this vault atomically to avoid duplicate generation
        const claimedVault = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(vaultDoc.ref);
          if (!fresh.exists) return null;

          const current = fresh.data() || {};
          if (
            current.revisionGenerated === true ||
            current.weekClosed === true ||
            current.generationInProgress === true
          ) {
            return null;
          }

          tx.set(vaultDoc.ref, {
            generationInProgress: true,
            generationStartedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          return current;
        });

        if (!claimedVault) {
          return;
        }

        const vault = claimedVault;

        const studentId = String(vault.studentId || '').trim();
        const subject = String(vault.subject || 'General').trim() || 'General';
        const errorCount = Number(vault.errorCount) || 0;

        if (!studentId || errorCount < REVISION_THRESHOLD) {
          await vaultDoc.ref.set({
            weekClosed: true,
            closedReason: 'threshold_not_met',
            generationInProgress: false,
            resetAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return;
        }

        const rawQuestions = Array.isArray(vault.errorQuestions)
          ? vault.errorQuestions
          : [];

        // Prioritize higher mistake frequency and cap to keep test practical
        rawQuestions.sort((a, b) => {
          const af = Number(a?.mistakeFrequency) || 0;
          const bf = Number(b?.mistakeFrequency) || 0;
          return bf - af;
        });

        const selected = rawQuestions
          .filter((q) => q && q.questionText)
          .slice(0, 25)
          .map((q, i) => {
            const opts = Array.isArray(q.options) && q.options.length >= 2
              ? q.options.map((o) => String(o))
              : [
                String(q.correctAnswer || 'Option 1'),
                'Option 2',
                'Option 3',
                'Option 4',
              ];

            return {
              id: `rev_q_${i + 1}`,
              type: 'mcq',
              questionText: String(q.questionText),
              options: opts,
              correctAnswer: String(q.correctAnswer || opts[0]),
              marks: 1,
              source: 'student_error_vault',
            };
          });

        if (selected.length === 0) {
          await vaultDoc.ref.set({
            weekClosed: true,
            closedReason: 'no_valid_questions',
            generationInProgress: false,
            resetAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return;
        }

        // Create isolated scheduled test instance (student-specific)
        const testRef = db.collection('scheduledTests').doc();
        const testId = testRef.id;

        const testDoc = {
          id: testId,
          title: 'AI Revision Test',
          description: `Automated ${subject} revision generated from your weekly incorrect answers.`,
          testTitle: 'AI Revision Test',
          subject,
          class: String(vault.className || ''),
          className: String(vault.className || ''),
          section: String(vault.section || ''),
          schoolCode: String(vault.schoolCode || ''),
          teacherId: SYSTEM_TEACHER_ID,
          teacherName: SYSTEM_TEACHER_NAME,
          teacherEmail: '',
          studentId,
          visibility: 'student_only',
          skipAutoAssign: true,
          testCategory: 'ai_revision',
          isAIRevision: true,
          revisionWeekKey: weekKey,
          sourceVaultId: vaultDoc.id,
          date: dateStr,
          startTime: '18:00',
          endTime: '21:00',
          duration: REVISION_DURATION_MINUTES,
          startDate: admin.firestore.Timestamp.fromDate(startDate),
          endDate: admin.firestore.Timestamp.fromDate(endDate),
          status: 'published',
          questionCount: selected.length,
          totalMarks: selected.length,
          questions: selected,
          autoPublished: false,
          resultsPublished: false,
          assignedStudentIds: [studentId],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        const assignmentRef = db.collection('testResults').doc();
        const questionOrder = Array.from({ length: selected.length }, (_, i) => i);
        for (let i = questionOrder.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [questionOrder[i], questionOrder[j]] = [questionOrder[j], questionOrder[i]];
        }

        const assignmentDoc = {
          answers: [],
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          className: String(vault.className || ''),
          correctAnswers: 0,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          date: dateStr,
          duration: REVISION_DURATION_MINUTES,
          earnedPoints: 0,
          schoolCode: String(vault.schoolCode || ''),
          score: 0,
          section: String(vault.section || ''),
          startTime: '18:00',
          startedAt: null,
          status: 'assigned',
          studentEmail: String(vault.studentEmail || ''),
          studentId,
          studentName: String(vault.studentName || ''),
          subject,
          submittedAt: null,
          teacherEmail: '',
          teacherId: SYSTEM_TEACHER_ID,
          teacherName: SYSTEM_TEACHER_NAME,
          testId,
          testTitle: 'AI Revision Test',
          testCategory: 'ai_revision',
          isAIRevision: true,
          timeTaken: 0,
          totalMarks: selected.length,
          totalPoints: 0,
          totalQuestions: selected.length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          questionOrder,
          sourceVaultId: vaultDoc.id,
          revisionWeekKey: weekKey,
        };

        const batch = db.batch();
        batch.set(testRef, testDoc);
        batch.set(assignmentRef, assignmentDoc);
        batch.set(vaultDoc.ref, {
          revisionGenerated: true,
          generatedTestId: testId,
          generatedResultId: assignmentRef.id,
          generationInProgress: false,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          weekClosed: true,
          closedReason: 'revision_generated',
          resetAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await batch.commit();

        await sendRevisionNotification({
          studentId,
          title: 'AI Revision Test Available',
          body: `${subject}: Your AI Revision Test is now live (6:00 PM - 9:00 PM).`,
          type: 'ai_revision_live',
          referenceId: assignmentRef.id,
          data: {
            testId,
            resultId: assignmentRef.id,
            subject,
            weekKey,
            testCategory: 'ai_revision',
          },
        });
      })().catch(async (err) => {
        console.error('generateSundayEveningRevisionTests task error:', err);
        try {
          await vaultDoc.ref.set({
            generationInProgress: false,
            generationFailedAt: admin.firestore.FieldValue.serverTimestamp(),
            generationFailureReason: String(err && err.message ? err.message : err),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        } catch (unlockErr) {
          console.error('Failed to release generation lock:', unlockErr);
        }
      }));
    }

    await Promise.all(tasks);
    return null;
  });
