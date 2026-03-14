/**
 * Cloudflare Worker for Lenv push notifications.
 * Uses Firebase OAuth + Firestore REST + FCM HTTP v1.
 */

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT: string;
}

interface JsonMap {
  [key: string]: any;
}

interface UserProfile {
  id: string;
  name: string;
  role: string;
  schoolId: string;
  standard: string;
  section: string;
  fcmToken: string;
}

let serviceAccount: JsonMap | null = null;
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}

function jsonResponse(body: JsonMap, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders(),
    },
  });
}

function asString(value: unknown, fallback = ''): string {
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
}

function normalizeRole(value: unknown): string {
  const role = asString(value).toLowerCase();
  if (role === 'admin' || role === 'institute' || role === 'institute_admin') {
    return 'principal';
  }
  return role;
}

function normalizeClass(value: unknown): string {
  const input = asString(value);
  if (!input) return '';
  const match = input.match(/\d+/);
  if (match) return match[0];
  return input
    .replace(/grade\s+/i, '')
    .replace(/class\s+/i, '')
    .trim()
    .toLowerCase();
}

function truncate(value: string, max = 120): string {
  if (value.length <= max) return value;
  return `${value.substring(0, max - 3)}...`;
}

function buildNotificationId(prefix: string, userId: string, dedupeKey?: string): string {
  if (dedupeKey) {
    return `${prefix}_${userId}_${dedupeKey}`.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 140);
  }
  return `${prefix}_${userId}_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
}

function getServiceAccount(env: Env): JsonMap {
  if (!serviceAccount) {
    const binaryString = Buffer.from(env.FIREBASE_SERVICE_ACCOUNT, 'base64').toString('utf8');
    serviceAccount = JSON.parse(binaryString);
  }
  return serviceAccount;
}

async function getAccessToken(env: Env): Promise<string> {
  const now = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 300000) {
    return cachedAccessToken.token;
  }

  const sa = getServiceAccount(env);
  const jwtHeader = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

  const nowSec = Math.floor(now / 1000);
  const jwtClaim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSec,
    exp: nowSec + 3600,
  };

  const jwtClaimBase64 = btoa(JSON.stringify(jwtClaim))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

  const privateKeyPem = sa.private_key;
  const pemContents = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(`${jwtHeader}.${jwtClaimBase64}`)
  );

  const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBuffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

  const jwt = `${jwtHeader}.${jwtClaimBase64}.${signature}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = (await response.json()) as JsonMap;
  if (!data.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(data)}`);
  }

  cachedAccessToken = {
    token: data.access_token as string,
    expiresAt: now + ((data.expires_in as number) * 1000),
  };
  return data.access_token as string;
}

function encodeFirestoreValue(value: any): JsonMap {
  if (value === null || value === undefined) return { nullValue: null };
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((entry) => encodeFirestoreValue(entry)),
      },
    };
  }
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'object') {
    const fields: JsonMap = {};
    Object.entries(value).forEach(([key, entry]) => {
      fields[key] = encodeFirestoreValue(entry);
    });
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

function decodeFirestoreValue(value: JsonMap | undefined): any {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('mapValue' in value) {
    const output: JsonMap = {};
    const fields = value.mapValue?.fields || {};
    Object.entries(fields).forEach(([key, entry]) => {
      output[key] = decodeFirestoreValue(entry as JsonMap);
    });
    return output;
  }
  if ('arrayValue' in value) {
    return (value.arrayValue?.values || []).map((entry: JsonMap) => decodeFirestoreValue(entry));
  }
  return null;
}

function decodeFirestoreDocument(doc: JsonMap): JsonMap {
  const result: JsonMap = {
    id: asString(doc.name).split('/').pop() || '',
  };
  const fields = doc.fields || {};
  Object.entries(fields).forEach(([key, value]) => {
    result[key] = decodeFirestoreValue(value as JsonMap);
  });
  return result;
}

async function firestoreGetDocument(
  collection: string,
  docId: string,
  env: Env,
  accessToken: string
): Promise<JsonMap | null> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    }
  );

  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Failed to fetch ${collection}/${docId}: ${await response.text()}`);
  }

  return decodeFirestoreDocument((await response.json()) as JsonMap);
}

async function firestoreCreateOrReplaceDocument(
  collection: string,
  docId: string,
  data: JsonMap,
  env: Env,
  accessToken: string
): Promise<void> {
  const fields: JsonMap = {};
  Object.entries(data).forEach(([key, value]) => {
    fields[key] = encodeFirestoreValue(value);
  });

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to write ${collection}/${docId}: ${await response.text()}`);
  }
}

async function firestorePatchDocument(
  collection: string,
  docId: string,
  data: JsonMap,
  env: Env,
  accessToken: string
): Promise<void> {
  const fields: JsonMap = {};
  Object.entries(data).forEach(([key, value]) => {
    fields[key] = encodeFirestoreValue(value);
  });

  const mask = Object.keys(data)
    .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`)
    .join('&');

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?${mask}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields }),
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to patch ${collection}/${docId}: ${await response.text()}`);
  }
}

async function firestoreRunQuery(
  structuredQuery: JsonMap,
  env: Env,
  accessToken: string
): Promise<JsonMap[]> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ structuredQuery }),
    }
  );

  if (!response.ok) {
    throw new Error(`Firestore query failed: ${await response.text()}`);
  }

  const rows = (await response.json()) as JsonMap[];
  return rows
    .filter((row) => row.document)
    .map((row) => decodeFirestoreDocument(row.document as JsonMap));
}

function equalsFilter(field: string, value: any): JsonMap {
  return {
    fieldFilter: {
      field: { fieldPath: field },
      op: 'EQUAL',
      value: encodeFirestoreValue(value),
    },
  };
}

async function getUserProfile(userId: string, env: Env, accessToken: string): Promise<UserProfile | null> {
  const user = await firestoreGetDocument('users', userId, env, accessToken);
  if (!user) return null;

  return {
    id: userId,
    name:
      asString(user.name) ||
      asString(user.studentName) ||
      asString(user.teacherName) ||
      asString(user.parentName) ||
      'Lenv',
    role: normalizeRole(user.role),
    schoolId: asString(user.schoolId || user.schoolCode || user.instituteId),
    standard: asString(user.standard || user.class || user.className),
    section: asString(user.section),
    fcmToken: asString(user.fcmToken),
  };
}

async function getActiveDeviceTokens(userId: string, env: Env, accessToken: string): Promise<string[]> {
  const profile = await getUserProfile(userId, env, accessToken);
  const tokenSet = new Set<string>();
  if (profile?.fcmToken) tokenSet.add(profile.fcmToken);

  const devices = await firestoreRunQuery(
    {
      from: [{ collectionId: 'user_device_tokens' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [equalsFilter('userId', userId), equalsFilter('active', true)],
        },
      },
    },
    env,
    accessToken
  );

  devices.forEach((device) => {
    const token = asString(device.deviceToken);
    if (token) tokenSet.add(token);
  });

  return Array.from(tokenSet);
}

async function deactivateDeviceToken(
  deviceToken: string,
  env: Env,
  accessToken: string
): Promise<void> {
  const devices = await firestoreRunQuery(
    {
      from: [{ collectionId: 'user_device_tokens' }],
      where: equalsFilter('deviceToken', deviceToken),
      limit: 10,
    },
    env,
    accessToken
  );

  await Promise.all(
    devices.map((device) =>
      firestorePatchDocument(
        'user_device_tokens',
        device.id,
        {
          active: false,
          lastUpdated: new Date(),
        },
        env,
        accessToken
      )
    )
  );
}

async function sendFcmToToken(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  priority: 'normal' | 'high',
  soundEnabled: boolean,
  env: Env,
  accessToken: string
): Promise<boolean> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: priority === 'high' ? 'high' : 'normal',
            notification: {
              channel_id: priority === 'high' ? 'lenv_high_priority' : 'lenv_default',
              sound: soundEnabled ? 'default' : undefined,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: soundEnabled ? 'default' : undefined,
                badge: 1,
              },
            },
          },
        },
      }),
    }
  );

  if (response.ok) return true;

  const errorText = await response.text();
  if (
    errorText.includes('registration-token-not-registered') ||
    errorText.includes('UNREGISTERED') ||
    errorText.includes('invalid-registration-token')
  ) {
    await deactivateDeviceToken(token, env, accessToken);
  }
  console.error('FCM send failed', errorText);
  return false;
}

async function sendNotificationToUser({
  userId,
  title,
  body,
  category,
  deepLinkRoute,
  targetType,
  targetId,
  metadata,
  priority = 'normal',
  soundEnabled = false,
  vibrationEnabled = false,
  iconType,
  dedupeKey,
  env,
  accessToken,
}: {
  userId: string;
  title: string;
  body: string;
  category: string;
  deepLinkRoute: string;
  targetType: string;
  targetId: string;
  metadata?: JsonMap;
  priority?: 'normal' | 'high';
  soundEnabled?: boolean;
  vibrationEnabled?: boolean;
  iconType?: string;
  dedupeKey?: string;
  env: Env;
  accessToken: string;
}): Promise<JsonMap> {
  if (!userId) return { sent: false, reason: 'missing-user' };

  const user = await getUserProfile(userId, env, accessToken);
  if (!user) return { sent: false, reason: 'user-not-found' };

  const notificationId = buildNotificationId('notif', userId, dedupeKey);
  const existing = await firestoreGetDocument('notifications', notificationId, env, accessToken);
  if (existing) {
    return { sent: false, reason: 'deduped', notificationId };
  }

  await firestoreCreateOrReplaceDocument(
    'notifications',
    notificationId,
    {
      notificationId,
      userId,
      role: user.role,
      schoolId: user.schoolId,
      category,
      title,
      body,
      iconType: iconType || category,
      priority,
      soundEnabled,
      vibrationEnabled,
      isRead: false,
      createdAt: new Date(),
      timestamp: new Date(),
      type: category,
      referenceId: targetId,
      data: metadata || {},
      targetType,
      targetId,
      deepLinkRoute,
      metadata: metadata || {},
      dedupeKey: dedupeKey || '',
    },
    env,
    accessToken
  );

  const tokens = await getActiveDeviceTokens(userId, env, accessToken);
  if (!tokens.length) {
    return { sent: false, reason: 'no-tokens', notificationId };
  }

  const payloadData: Record<string, string> = {
    notificationId,
    userId,
    category,
    deepLinkRoute,
    targetType,
    targetId,
    priority,
    soundEnabled: String(soundEnabled),
    vibrationEnabled: String(vibrationEnabled),
    ...Object.fromEntries(
      Object.entries(metadata || {}).map(([key, value]) => [key, asString(value)])
    ),
  };

  const results = await Promise.all(
    tokens.map((token) =>
      sendFcmToToken(token, title, body, payloadData, priority, soundEnabled, env, accessToken)
    )
  );

  return {
    sent: results.some(Boolean),
    notificationId,
    successCount: results.filter(Boolean).length,
    failureCount: results.filter((result) => !result).length,
  };
}

function previewForMessage(content: string, messageType: string): string {
  switch (messageType) {
    case 'image':
      return 'Sent a photo';
    case 'audio':
      return 'Sent an audio message';
    case 'pdf':
    case 'file':
    case 'media':
      return 'Sent an attachment';
    default:
      return truncate(content || 'New message');
  }
}

async function handleDirectChat(request: JsonMap, env: Env, accessToken: string): Promise<Response> {
  const senderId = asString(request.senderId);
  const recipientId = asString(request.recipientId || request.receiverId);
  const messageId = asString(request.messageId);
  if (!senderId || !recipientId || !messageId) {
    return jsonResponse({ success: false, message: 'Missing direct chat fields' }, 400);
  }

  const sender = await getUserProfile(senderId, env, accessToken);
  const senderName = sender?.name || 'New message';
  const body = previewForMessage(asString(request.text), asString(request.messageType, 'text'));

  const result = await sendNotificationToUser({
    userId: recipientId,
    title: senderName,
    body,
    category: 'messaging',
    priority: 'high',
    soundEnabled: true,
    vibrationEnabled: true,
    iconType: 'chat',
    targetType: 'chat',
    targetId: messageId,
    deepLinkRoute: asString(request.deepLinkRoute, '/messages'),
    metadata: {
      messageId,
      senderId,
      ...(request.metadata || {}),
    },
    dedupeKey: `direct_${messageId}`,
    env,
    accessToken,
  });

  return jsonResponse({ success: true, result });
}

async function handleGroupMessage(request: JsonMap, env: Env, accessToken: string): Promise<Response> {
  const messageId = asString(request.messageId);
  const senderId = asString(request.senderId);
  const senderName = asString(request.senderName, 'New message');
  const groupId = asString(request.groupId);
  const groupType = asString(request.groupType, 'group');
  const recipientIds = Array.isArray(request.recipientIds)
    ? request.recipientIds.map((entry: unknown) => asString(entry)).filter(Boolean)
    : [];

  if (!messageId || !senderId || !groupId || !recipientIds.length) {
    return jsonResponse({ success: false, message: 'Missing group message fields' }, 400);
  }

  const body = previewForMessage(asString(request.content), asString(request.messageType, 'text'));
  const title = asString(request.groupName) || senderName;
  const results = await Promise.all(
    recipientIds.map((userId) =>
      sendNotificationToUser({
        userId,
        title,
        body: `${senderName}: ${body}`,
        category: 'messaging',
        priority: 'high',
        soundEnabled: true,
        vibrationEnabled: true,
        iconType: groupType === 'community' ? 'community' : 'chat',
        targetType: groupType,
        targetId: groupId,
        deepLinkRoute: asString(request.deepLinkRoute, '/notifications'),
        metadata: {
          messageId,
          senderId,
          groupId,
          groupType,
          ...(request.metadata || {}),
        },
        dedupeKey: `${groupType}_${messageId}`,
        env,
        accessToken,
      })
    )
  );

  return jsonResponse({ success: true, count: results.length, results });
}

async function handleRewardStatus(request: JsonMap, env: Env, accessToken: string): Promise<Response> {
  const requestId = asString(request.requestId);
  const status = asString(request.status);
  const studentId = asString(request.studentId);
  const parentId = asString(request.parentId);
  if (!requestId || !status || !studentId) {
    return jsonResponse({ success: false, message: 'Missing reward status fields' }, 400);
  }

  const statusTitleMap: Record<string, string> = {
    approved: 'Reward request approved',
    rejected: 'Reward request rejected',
    orderPlaced: 'Reward shipped',
    delivered: 'Reward delivered',
  };
  const title = statusTitleMap[status] || 'Reward update';
  const body = truncate(asString(request.productName, 'Your reward request was updated'));
  const recipientIds = [studentId, parentId].filter(Boolean);

  const results = await Promise.all(
    recipientIds.map((userId) =>
      sendNotificationToUser({
        userId,
        title,
        body,
        category: 'rewards',
        priority: 'high',
        soundEnabled: true,
        vibrationEnabled: true,
        iconType: 'reward',
        targetType: 'reward',
        targetId: requestId,
        deepLinkRoute: asString(request.deepLinkRoute, '/student-rewards'),
        metadata: {
          requestId,
          status,
          ...(request.metadata || {}),
        },
        dedupeKey: `reward_${requestId}_${status}`,
        env,
        accessToken,
      })
    )
  );

  return jsonResponse({ success: true, results });
}

async function handleTestAssignment(request: JsonMap, env: Env, accessToken: string): Promise<Response> {
  const testId = asString(request.testId || request.assignmentId);
  const studentIds = Array.isArray(request.studentIds)
    ? request.studentIds.map((entry: unknown) => asString(entry)).filter(Boolean)
    : [];
  if (!testId || !studentIds.length) {
    return jsonResponse({ success: false, message: 'Missing test assignment fields' }, 400);
  }

  const title = truncate(asString(request.title, 'New test assigned'));
  const subject = asString(request.subject);
  const teacherName = asString(request.teacherName, 'Teacher');
  const className = asString(request.className);
  const section = asString(request.section);
  const body = truncate(
    [title, subject && `Subject: ${subject}`, className && `Class: ${[className, section].filter(Boolean).join(' ')}`]
      .filter(Boolean)
      .join(' • ')
  );

  const results = await Promise.all(
    studentIds.map((userId) =>
      sendNotificationToUser({
        userId,
        title: 'Test assigned',
        body,
        category: 'tests',
        priority: 'high',
        soundEnabled: true,
        vibrationEnabled: false,
        iconType: 'test',
        targetType: 'test',
        targetId: testId,
        deepLinkRoute: asString(request.deepLinkRoute, '/student-tests'),
        metadata: {
          testId,
          teacherName,
          className,
          section,
          schoolCode: asString(request.schoolCode),
          ...(request.metadata || {}),
        },
        dedupeKey: `test_${testId}`,
        env,
        accessToken,
      })
    )
  );

  return jsonResponse({ success: true, results });
}

async function getAnnouncementRecipients(request: JsonMap, env: Env, accessToken: string): Promise<string[]> {
  const schoolId = asString(request.schoolId);
  if (!schoolId) return [];

  const schoolQueries = ['schoolId', 'schoolCode', 'instituteId'];
  const users = new Map<string, JsonMap>();

  for (const field of schoolQueries) {
    const results = await firestoreRunQuery(
      {
        from: [{ collectionId: 'users' }],
        where: equalsFilter(field, schoolId),
      },
      env,
      accessToken
    );

    results.forEach((user) => {
      if (user.id) users.set(user.id, user);
    });
  }

  const standards = Array.isArray(request.standards)
    ? request.standards.map((entry: unknown) => normalizeClass(entry)).filter(Boolean)
    : [];
  const sections = Array.isArray(request.sections)
    ? request.sections.map((entry: unknown) => asString(entry)).filter(Boolean)
    : [];
  const createdBy = asString(request.createdBy);
  const audienceType = asString(request.audienceType, 'school').toLowerCase();

  return Array.from(users.values())
    .filter((user) => user.id !== createdBy)
    .filter((user) => {
      const role = normalizeRole(user.role);
      if (!role || role === 'guest') return false;

      const userStandard = normalizeClass(user.standard || user.className || user.class);
      const userSection = asString(user.section);

      if (audienceType === 'standard' && standards.length) {
        return standards.includes(userStandard);
      }

      if (audienceType === 'section') {
        const standardMatch = standards.length ? standards.includes(userStandard) : true;
        const sectionMatch = sections.length ? sections.includes(userSection) : true;
        return standardMatch && sectionMatch;
      }

      return true;
    })
    .map((user) => user.id);
}

async function handleAnnouncement(request: JsonMap, env: Env, accessToken: string): Promise<Response> {
  const announcementId = asString(request.announcementId);
  if (!announcementId) {
    return jsonResponse({ success: false, message: 'Missing announcementId' }, 400);
  }

  const recipientIds = Array.isArray(request.recipientIds)
    ? request.recipientIds.map((entry: unknown) => asString(entry)).filter(Boolean)
    : await getAnnouncementRecipients(request, env, accessToken);

  if (!recipientIds.length) {
    return jsonResponse({ success: true, count: 0, message: 'No recipients resolved' });
  }

  const important = request.important === true || asString(request.important) === 'true';
  const title = asString(request.title, important ? 'Important announcement' : 'Announcement');
  const text = asString(request.text || request.description);
  const body = truncate(text || 'You have a new announcement');

  const results = await Promise.all(
    recipientIds.map((userId) =>
      sendNotificationToUser({
        userId,
        title,
        body,
        category: 'announcements',
        priority: important ? 'high' : 'normal',
        soundEnabled: important,
        vibrationEnabled: important,
        iconType: 'announcement',
        targetType: asString(request.collection, 'announcement'),
        targetId: announcementId,
        deepLinkRoute: asString(request.deepLinkRoute, '/notifications'),
        metadata: {
          announcementId,
          audienceType: asString(request.audienceType),
          schoolId: asString(request.schoolId),
          ...(request.metadata || {}),
        },
        dedupeKey: `announcement_${announcementId}`,
        env,
        accessToken,
      })
    )
  );

  return jsonResponse({ success: true, count: results.length, results });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') {
      return jsonResponse({ status: 'ok', service: 'lenv-notification-worker' });
    }

    if (request.method !== 'POST' || url.pathname !== '/notify') {
      return jsonResponse({ success: false, message: 'Not found' }, 404);
    }

    try {
      const payload = (await request.json()) as JsonMap;
      const type = asString(payload.type);
      const accessToken = await getAccessToken(env);

      switch (type) {
        case 'chat':
        case 'direct_chat':
          return await handleDirectChat(payload, env, accessToken);
        case 'group_message':
          return await handleGroupMessage(payload, env, accessToken);
        case 'reward_status':
          return await handleRewardStatus(payload, env, accessToken);
        case 'assignment':
        case 'test_assignment':
          return await handleTestAssignment(payload, env, accessToken);
        case 'announcement':
          return await handleAnnouncement(payload, env, accessToken);
        default:
          return jsonResponse({ success: false, message: `Unsupported type: ${type}` }, 400);
      }
    } catch (error: any) {
      console.error('Notification worker error', error);
      return jsonResponse({ success: false, error: error?.message || String(error) }, 500);
    }
  },
};
