'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

const PRINCIPAL_ROLES = new Set(['principal', 'institute', 'admin']);
const DEFAULT_TTL_DAYS = 30;

function toBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value.toLowerCase() === 'true';
  return fallback;
}

function asString(value, fallback = '') {
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function asNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeRole(roleRaw) {
  const role = asString(roleRaw).toLowerCase();
  if (role === 'institute_admin') return 'principal';
  if (role === 'institute') return 'principal';
  if (role === 'admin') return 'principal';
  if (role === 'teacher') return 'teacher';
  if (role === 'parent') return 'parent';
  if (role === 'student') return 'student';
  if (role === 'principal') return 'principal';
  return role || 'student';
}

function buildNotificationId(prefix = 'notif') {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
}

function shouldEnableSound({ category, priority, explicitSound }) {
  if (typeof explicitSound === 'boolean') return explicitSound;
  if (priority === 'critical' || priority === 'high') return true;
  return ['messaging', 'rewards', 'alerts', 'tests'].includes(category);
}

function shouldEnableVibration({ category, priority, explicitVibration }) {
  if (typeof explicitVibration === 'boolean') return explicitVibration;
  if (priority === 'critical' || priority === 'high') return true;
  return ['messaging', 'alerts', 'rewards'].includes(category);
}

async function getUserProfile(userId) {
  const snap = await db.collection('users').doc(userId).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  return {
    userId,
    role: normalizeRole(data.role),
    schoolId: asString(data.schoolId || data.schoolCode || data.instituteId),
    standard: asString(data.standard || data.class || data.className),
    section: asString(data.section),
    subject: asString(data.subject),
    groupIds: Array.isArray(data.groupIds) ? data.groupIds.map((x) => String(x)) : [],
    communityIds: Array.isArray(data.communityIds)
      ? data.communityIds.map((x) => String(x))
      : [],
    parentId: asString(data.parentId),
    childIds: Array.isArray(data.childrenIds)
      ? data.childrenIds.map((x) => String(x))
      : [],
    fcmToken: asString(data.fcmToken),
    name: asString(data.name, 'User'),
  };
}

async function getDeviceTokensForUser(userId, userProfile) {
  const tokenSet = new Set();

  if (userProfile && userProfile.fcmToken) {
    tokenSet.add(userProfile.fcmToken);
  }

  const devices = await db
    .collection('user_device_tokens')
    .where('userId', '==', userId)
    .where('active', '==', true)
    .get();

  devices.docs.forEach((doc) => {
    const token = asString(doc.data().deviceToken);
    if (token) tokenSet.add(token);
  });

  return Array.from(tokenSet);
}

async function markInvalidTokens(tokens) {
  if (!tokens.length) return;

  const deviceQuery = await db
    .collection('user_device_tokens')
    .where('deviceToken', 'in', tokens.slice(0, 10))
    .get();

  const batch = db.batch();
  deviceQuery.docs.forEach((doc) => {
    batch.set(
      doc.ref,
      { active: false, lastUpdated: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
  });
  await batch.commit();
}

async function acquireDedupeLock(key) {
  if (!key) return true;
  const ref = db.collection('notification_dedupes').doc(key);
  const snap = await ref.get();
  if (snap.exists) return false;
  await ref.set({
    key,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return true;
}

async function saveNotificationRecord(payload) {
  const notificationId = payload.notificationId || buildNotificationId('notif');
  await db
    .collection('notifications')
    .doc(notificationId)
    .set(
      {
        notificationId,
        userId: payload.userId,
        role: payload.role,
        schoolId: payload.schoolId || '',
        category: payload.category,
        title: payload.title,
        body: payload.body,
        iconType: payload.iconType || payload.category,
        priority: payload.priority || 'normal',
        soundEnabled: payload.soundEnabled === true,
        vibrationEnabled: payload.vibrationEnabled === true,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        targetType: payload.targetType || '',
        targetId: payload.targetId || '',
        deepLinkRoute: payload.deepLinkRoute || '/notifications',
        metadata: payload.metadata || {},
        dedupeKey: payload.dedupeKey || '',
      },
      { merge: true }
    );

  return notificationId;
}

function buildPushMessage({ tokens, title, body, data, soundEnabled, vibrationEnabled, priority }) {
  const isHighPriority = priority === 'high' || priority === 'critical';

  return {
    tokens,
    notification: {
      title,
      body,
    },
    data,
    android: {
      priority: isHighPriority ? 'high' : 'normal',
      notification: {
        channelId: isHighPriority ? 'lenv_high_priority' : 'lenv_default',
        sound: soundEnabled ? 'default' : undefined,
        defaultVibrateTimings: vibrationEnabled,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: soundEnabled ? 'default' : undefined,
          badge: 1,
          contentAvailable: true,
        },
      },
    },
  };
}

async function sendNotificationToUser({
  userId,
  category,
  title,
  body,
  priority = 'normal',
  soundEnabled,
  vibrationEnabled,
  iconType,
  targetType,
  targetId,
  deepLinkRoute,
  metadata = {},
  dedupeKey,
}) {
  if (!userId || !title) return { sent: false, reason: 'missing-user-or-title' };

  const dedupeLockKey = dedupeKey ? `${dedupeKey}_${userId}` : '';
  const canProceed = await acquireDedupeLock(dedupeLockKey);
  if (!canProceed) {
    return { sent: false, reason: 'deduped' };
  }

  const userProfile = await getUserProfile(userId);
  if (!userProfile) {
    return { sent: false, reason: 'user-not-found' };
  }

  const role = normalizeRole(userProfile.role);
  const schoolId = userProfile.schoolId;

  const effectiveSound = shouldEnableSound({
    category,
    priority,
    explicitSound: soundEnabled,
  });
  const effectiveVibration = shouldEnableVibration({
    category,
    priority,
    explicitVibration: vibrationEnabled,
  });

  const notificationId = await saveNotificationRecord({
    notificationId: buildNotificationId('notif'),
    userId,
    role,
    schoolId,
    category,
    title,
    body,
    iconType,
    priority,
    soundEnabled: effectiveSound,
    vibrationEnabled: effectiveVibration,
    targetType,
    targetId,
    deepLinkRoute,
    metadata,
    dedupeKey,
  });

  const tokens = await getDeviceTokensForUser(userId, userProfile);
  if (!tokens.length) {
    return { sent: false, reason: 'no-device-token', notificationId };
  }

  const payloadData = {
    notificationId,
    userId,
    role,
    schoolId,
    category,
    iconType: iconType || category,
    priority,
    soundEnabled: String(effectiveSound),
    vibrationEnabled: String(effectiveVibration),
    targetType: asString(targetType),
    targetId: asString(targetId),
    deepLinkRoute: asString(deepLinkRoute, '/notifications'),
    dedupeKey: asString(dedupeKey),
    ...Object.fromEntries(
      Object.entries(metadata || {}).map(([k, v]) => [k, asString(v)])
    ),
  };

  const message = buildPushMessage({
    tokens,
    title,
    body,
    data: payloadData,
    soundEnabled: effectiveSound,
    vibrationEnabled: effectiveVibration,
    priority,
  });

  const response = await messaging.sendMulticast(message);

  const invalidTokens = [];
  response.responses.forEach((r, idx) => {
    if (!r.success) {
      const code = r.error && r.error.code ? r.error.code : '';
      if (
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-registration-token')
      ) {
        invalidTokens.push(tokens[idx]);
      }
    }
  });

  if (invalidTokens.length) {
    await markInvalidTokens(invalidTokens);
  }

  return {
    sent: response.successCount > 0,
    successCount: response.successCount,
    failureCount: response.failureCount,
    notificationId,
  };
}

function roleMatchesTarget(userRole, targetRole) {
  if (!targetRole || targetRole === 'all') return true;
  if (targetRole === 'principal') return PRINCIPAL_ROLES.has(userRole);
  return userRole === targetRole;
}

function announcementVisibleToUser(announcement, user) {
  const targetRole = normalizeRole(announcement.targetRole || announcement.audienceRole || 'all');
  if (!roleMatchesTarget(user.role, targetRole)) return false;

  const schoolId = asString(announcement.schoolId || announcement.schoolCode || announcement.instituteId);
  if (schoolId && user.schoolId && schoolId !== user.schoolId) return false;

  const standards = Array.isArray(announcement.standards)
    ? announcement.standards.map((x) => asString(x))
    : [];
  if (standards.length && user.standard && !standards.includes(user.standard)) {
    return false;
  }

  const sections = Array.isArray(announcement.sections)
    ? announcement.sections.map((x) => asString(x))
    : [];
  if (sections.length && user.section && !sections.includes(user.section)) {
    return false;
  }

  const groupIds = Array.isArray(announcement.groupIds)
    ? announcement.groupIds.map((x) => asString(x))
    : [];
  if (groupIds.length) {
    const overlap = user.groupIds.some((g) => groupIds.includes(g));
    if (!overlap) return false;
  }

  const communityIds = Array.isArray(announcement.communityIds)
    ? announcement.communityIds.map((x) => asString(x))
    : [];
  if (communityIds.length) {
    const overlap = user.communityIds.some((g) => communityIds.includes(g));
    if (!overlap) return false;
  }

  return true;
}

async function getAnnouncementRecipients(announcement) {
  let query = db.collection('users');
  const schoolId = asString(announcement.schoolId || announcement.schoolCode || announcement.instituteId);
  if (schoolId) {
    query = query.where('schoolId', '==', schoolId);
  }

  const usersSnapshot = await query.get();
  const recipients = [];

  usersSnapshot.docs.forEach((doc) => {
    const raw = doc.data() || {};
    const user = {
      userId: doc.id,
      role: normalizeRole(raw.role),
      schoolId: asString(raw.schoolId || raw.schoolCode || raw.instituteId),
      standard: asString(raw.standard || raw.class || raw.className),
      section: asString(raw.section),
      groupIds: Array.isArray(raw.groupIds) ? raw.groupIds.map((x) => String(x)) : [],
      communityIds: Array.isArray(raw.communityIds)
        ? raw.communityIds.map((x) => String(x))
        : [],
    };

    if (announcementVisibleToUser(announcement, user)) {
      recipients.push(user.userId);
    }
  });

  return recipients;
}

exports.sendChatNotification = functions.firestore
  .document('messages/{messageId}')
  .onCreate(async (snap, context) => {
    const messageData = snap.data() || {};
    const messageId = context.params.messageId;

    const senderId = asString(messageData.senderId);
    const receiverId = asString(messageData.receiverId);

    if (!receiverId || receiverId === senderId) {
      return null;
    }

    const senderProfile = senderId ? await getUserProfile(senderId) : null;
    const senderName = senderProfile ? senderProfile.name : 'New message';

    const body = messageData.type === 'image'
      ? 'Sent an image'
      : asString(messageData.text || messageData.message, 'You received a new message');

    await sendNotificationToUser({
      userId: receiverId,
      category: 'messaging',
      title: senderName,
      body,
      priority: 'high',
      soundEnabled: true,
      vibrationEnabled: true,
      iconType: 'chat',
      targetType: 'chat',
      targetId: messageId,
      deepLinkRoute: '/messages',
      metadata: {
        messageId,
        senderId,
        chatType: asString(messageData.chatType, 'direct'),
        groupId: asString(messageData.groupId),
        communityId: asString(messageData.communityId),
      },
      dedupeKey: `chat_${messageId}`,
    });

    return { success: true };
  });

exports.sendAssignmentNotification = functions.firestore
  .document('assignments/{assignmentId}')
  .onCreate(async (snap, context) => {
    const assignment = snap.data() || {};
    const assignmentId = context.params.assignmentId;
    const schoolId = asString(assignment.schoolId || assignment.schoolCode || assignment.instituteId);
    const standard = asString(assignment.standard || assignment.classId || assignment.className);
    const section = asString(assignment.section);

    let query = db.collection('users').where('role', '==', 'student');
    if (schoolId) query = query.where('schoolId', '==', schoolId);

    const students = await query.get();
    const title = asString(assignment.title, 'New test assigned');
    const dueDate = asString(assignment.dueDate || assignment.deadline);

    const tasks = students.docs
      .filter((doc) => {
        const raw = doc.data() || {};
        const userStandard = asString(raw.standard || raw.class || raw.className);
        const userSection = asString(raw.section);
        if (standard && userStandard && standard !== userStandard) return false;
        if (section && userSection && section !== userSection) return false;
        return true;
      })
      .map((doc) =>
        sendNotificationToUser({
          userId: doc.id,
          category: 'tests',
          title: 'Test assigned',
          body: dueDate ? `${title} • Due ${dueDate}` : title,
          priority: 'high',
          iconType: 'test',
          targetType: 'test',
          targetId: assignmentId,
          deepLinkRoute: '/student-tests',
          metadata: {
            assignmentId,
            standard,
            section,
            schoolId,
          },
          dedupeKey: `assignment_${assignmentId}`,
        })
      );

    await Promise.all(tasks);
    return { success: true, count: tasks.length };
  });

exports.sendAnnouncementNotification = functions.firestore
  .document('announcements/{announcementId}')
  .onCreate(async (snap, context) => {
    const announcement = snap.data() || {};
    const announcementId = context.params.announcementId;
    const important = toBool(announcement.important, false);

    const recipients = await getAnnouncementRecipients(announcement);
    const title = asString(announcement.title, 'Announcement');

    await Promise.all(
      recipients.map((userId) =>
        sendNotificationToUser({
          userId,
          category: 'announcements',
          title: important ? 'Important announcement' : 'Announcement',
          body: title,
          priority: important ? 'high' : 'low',
          soundEnabled: important,
          vibrationEnabled: important,
          iconType: 'announcement',
          targetType: 'announcement',
          targetId: announcementId,
          deepLinkRoute: '/notifications',
          metadata: {
            announcementId,
            important: String(important),
          },
          dedupeKey: `announcement_${announcementId}`,
        })
      )
    );

    return { success: true, count: recipients.length };
  });

exports.sendRewardStatusNotification = functions.firestore
  .document('reward_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeStatus = asString(before.status);
    const afterStatus = asString(after.status);

    if (!afterStatus || beforeStatus === afterStatus) {
      return null;
    }

    const requestId = context.params.requestId;
    const studentId = asString(after.studentId || after.userId);
    const parentId = asString(after.parentId);

    const titleMap = {
      approved: 'Reward request approved',
      rejected: 'Reward request rejected',
      orderPlaced: 'Reward shipped',
      delivered: 'Reward delivered',
    };

    const title = titleMap[afterStatus] || 'Reward update';
    const body = asString(after.productName, 'Your reward request was updated');

    const tasks = [];
    if (studentId) {
      tasks.push(
        sendNotificationToUser({
          userId: studentId,
          category: 'rewards',
          title,
          body,
          priority: 'high',
          soundEnabled: true,
          vibrationEnabled: true,
          iconType: 'reward',
          targetType: 'reward',
          targetId: requestId,
          deepLinkRoute: '/student-rewards',
          metadata: { requestId, status: afterStatus },
          dedupeKey: `reward_${requestId}_${afterStatus}`,
        })
      );
    }

    if (parentId) {
      tasks.push(
        sendNotificationToUser({
          userId: parentId,
          category: 'rewards',
          title,
          body,
          priority: 'high',
          soundEnabled: true,
          vibrationEnabled: true,
          iconType: 'reward',
          targetType: 'reward',
          targetId: requestId,
          deepLinkRoute: '/parent-dashboard',
          metadata: { requestId, status: afterStatus },
          dedupeKey: `reward_parent_${requestId}_${afterStatus}`,
        })
      );
    }

    await Promise.all(tasks);
    return { success: true, sent: tasks.length };
  });

exports.sendPrincipalMissedTestAlert = functions.firestore
  .document('test_summaries/{summaryId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const summary = change.after.data() || {};
    const schoolId = asString(summary.schoolId || summary.schoolCode || summary.instituteId);
    const className = asString(summary.className || summary.standard || summary.classId);
    const section = asString(summary.section);
    const subject = asString(summary.subject, 'Subject');

    const missedPercentage = asNumber(summary.missedPercentage, 0);
    const consecutiveMissedTests = asNumber(summary.consecutiveMissedTests, 0);
    const performanceDropPercent = asNumber(
      summary.performanceDropPercent,
      asNumber(summary.scoreDropPercent, 0)
    );
    const performanceImprovementPercent = asNumber(
      summary.performanceImprovementPercent,
      asNumber(summary.scoreImprovementPercent, 0)
    );

    const shouldMissedAlert =
      missedPercentage > 40 ||
      (missedPercentage > 30 && consecutiveMissedTests >= 2);
    const shouldDropAlert = performanceDropPercent >= 10;
    const shouldImproveAlert = performanceImprovementPercent >= 15;

    if (!shouldMissedAlert && !shouldDropAlert && !shouldImproveAlert) {
      return null;
    }

    const principalUsers = await db
      .collection('users')
      .where('schoolId', '==', schoolId)
      .get();

    const principalIds = principalUsers.docs
      .filter((doc) => PRINCIPAL_ROLES.has(normalizeRole((doc.data() || {}).role)))
      .map((doc) => doc.id);

    if (!principalIds.length) return null;

    const classLabel = [className, section].filter(Boolean).join(' ');
    const fanout = [];

    if (shouldMissedAlert) {
      const body = `Alert: ${missedPercentage.toFixed(0)}% of ${classLabel || 'a class'} students missed the ${subject} test.`;
      principalIds.forEach((userId) => {
        fanout.push(
          sendNotificationToUser({
            userId,
            category: 'alerts',
            title: 'Missed Test Threshold Crossed',
            body,
            priority: 'high',
            soundEnabled: true,
            vibrationEnabled: true,
            iconType: 'alert',
            targetType: 'test_summary',
            targetId: context.params.summaryId,
            deepLinkRoute: '/institute-dashboard',
            metadata: {
              schoolId,
              className,
              section,
              subject,
              missedPercentage: missedPercentage.toFixed(2),
            },
            dedupeKey: `principal_missed_${context.params.summaryId}`,
          })
        );
      });
    }

    if (shouldDropAlert) {
      const body = `${classLabel || 'Class'} average dropped by ${performanceDropPercent.toFixed(1)}% this week.`;
      principalIds.forEach((userId) => {
        fanout.push(
          sendNotificationToUser({
            userId,
            category: 'alerts',
            title: 'Class Performance Drop',
            body,
            priority: 'high',
            soundEnabled: true,
            vibrationEnabled: true,
            iconType: 'trend_down',
            targetType: 'performance_summary',
            targetId: context.params.summaryId,
            deepLinkRoute: '/institute-dashboard',
            metadata: {
              schoolId,
              className,
              section,
              performanceDropPercent: performanceDropPercent.toFixed(2),
            },
            dedupeKey: `principal_drop_${context.params.summaryId}`,
          })
        );
      });
    }

    if (shouldImproveAlert) {
      const body = `${classLabel || 'Class'} improved by ${performanceImprovementPercent.toFixed(1)}% this week.`;
      principalIds.forEach((userId) => {
        fanout.push(
          sendNotificationToUser({
            userId,
            category: 'academic',
            title: 'Class Performance Improvement',
            body,
            priority: 'low',
            soundEnabled: false,
            vibrationEnabled: false,
            iconType: 'trend_up',
            targetType: 'performance_summary',
            targetId: context.params.summaryId,
            deepLinkRoute: '/institute-dashboard',
            metadata: {
              schoolId,
              className,
              section,
              performanceImprovementPercent:
                performanceImprovementPercent.toFixed(2),
            },
            dedupeKey: `principal_improve_${context.params.summaryId}`,
          })
        );
      });
    }

    await Promise.all(fanout);

    return { success: true, count: fanout.length };
  });

exports.weeklyPrincipalSummary = functions.pubsub
  .schedule('0 8 * * 1')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const principals = await db.collection('users').get();
    const principalDocs = principals.docs.filter((doc) =>
      PRINCIPAL_ROLES.has(normalizeRole((doc.data() || {}).role))
    );

    const tasks = principalDocs.map((doc) => {
      const data = doc.data() || {};
      const schoolId = asString(data.schoolId || data.schoolCode || data.instituteId);
      const summaryLines = [
        'Weekly Summary',
        'Class trends updated',
        'Review classes needing attention in dashboard',
      ];

      return sendNotificationToUser({
        userId: doc.id,
        category: 'academic',
        title: 'Weekly Performance Summary',
        body: summaryLines.join(' • '),
        priority: 'low',
        soundEnabled: false,
        vibrationEnabled: false,
        iconType: 'summary',
        targetType: 'weekly_summary',
        targetId: `${schoolId}_${Date.now()}`,
        deepLinkRoute: '/institute-dashboard',
        metadata: { schoolId },
        dedupeKey: `weekly_summary_${doc.id}_${new Date().toISOString().slice(0, 10)}`,
      });
    });

    await Promise.all(tasks);
    return { success: true, count: tasks.length };
  });

exports.cleanupOldNotifications = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - DEFAULT_TTL_DAYS);

    const oldSnapshot = await db
      .collection('notifications')
      .where('isRead', '==', true)
      .where('createdAt', '<', cutoff)
      .limit(500)
      .get();

    if (oldSnapshot.empty) {
      return { success: true, deleted: 0 };
    }

    const batch = db.batch();
    oldSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    return { success: true, deleted: oldSnapshot.size };
  });
