/**
 * Cloudflare Worker for Lenv Push Notifications
 * Using direct HTTP APIs - no Firebase Admin SDK
 */

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT: string;
}

interface ChatNotificationRequest {
  type: 'chat';
  messageId: string;
  senderId: string;
  receiverId: string;
  text: string;
  messageType: 'text' | 'image';
}

let serviceAccount: any = null;
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function getServiceAccount(env: Env) {
  if (!serviceAccount) {
    const binaryString = Buffer.from(env.FIREBASE_SERVICE_ACCOUNT, 'base64').toString('utf8');
    serviceAccount = JSON.parse(binaryString);
  }
  return serviceAccount;
}

async function getAccessToken(env: Env): Promise<string> {
  const now = Date.now();
  
  // Return cached token if still valid (with 5 min buffer)
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 300000) {
    return cachedAccessToken.token;
  }

  const sa = getServiceAccount(env);
  
  // Create JWT
  const jwtHeader = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  
  const nowSec = Math.floor(now / 1000);
  const jwtClaim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSec,
    exp: nowSec + 3600,
  };
  
  const jwtClaimBase64 = btoa(JSON.stringify(jwtClaim))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  
  // Import and sign
  const privateKeyPem = sa.private_key;
  const pemContents = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  
  const binaryKey = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));
  
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
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  
  const jwt = `${jwtHeader}.${jwtClaimBase64}.${signature}`;
  
  // Exchange for access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  
  const data: any = await response.json();
  
  if (data.access_token) {
    cachedAccessToken = {
      token: data.access_token,
      expiresAt: now + (data.expires_in * 1000),
    };
    return data.access_token;
  }
  
  throw new Error(`Failed to get access token: ${JSON.stringify(data)}`);
}

async function sendFCMNotification(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
  projectId: string,
  accessToken: string
): Promise<boolean> {
  try {
    const message = {
      message: {
        token: fcmToken,
        notification: { title, body },
        data,
        android: {
          priority: 'high',
          notification: {
            channel_id: 'lenv_channel',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: { sound: 'default', badge: 1 },
          },
        },
      },
    };

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(message),
      }
    );

    if (response.ok) {
      console.log('FCM notification sent successfully');
      return true;
    } else {
      const error = await response.text();
      console.error('FCM error:', error);
      return false;
    }
  } catch (error) {
    console.error('Error sending FCM:', error);
    return false;
  }
}

async function saveToFirestore(
  userId: string,
  title: string,
  body: string,
  type: string,
  referenceId: string,
  data: Record<string, any>,
  projectId: string,
  accessToken: string
): Promise<void> {
  try {
    const doc = {
      fields: {
        userId: { stringValue: userId },
        title: { stringValue: title },
        body: { stringValue: body },
        type: { stringValue: type },
        referenceId: { stringValue: referenceId },
        isRead: { booleanValue: false },
        timestamp: { timestampValue: new Date().toISOString() },
        data: { mapValue: { fields: {} } },
      },
    };

    // Add data fields
    for (const [key, value] of Object.entries(data)) {
      (doc.fields.data.mapValue.fields as any)[key] = { stringValue: String(value) };
    }

    const response = await fetch(
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/notifications`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(doc),
      }
    );

    if (response.ok) {
      console.log('Saved to Firestore');
    } else {
      const error = await response.text();
      console.error('Firestore error:', error);
    }
  } catch (error) {
    console.error('Error saving to Firestore:', error);
  }
}

async function getUserDoc(userId: string, projectId: string, accessToken: string): Promise<any> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${userId}`,
    {
      headers: { 'Authorization': `Bearer ${accessToken}` },
    }
  );

  if (response.ok) {
    const doc = await response.json() as any;
    const fields = doc.fields || {};
    return {
      exists: true,
      name: fields.name?.stringValue || fields.studentName?.stringValue || 'Someone',
      fcmToken: fields.fcmToken?.stringValue,
    };
  }
  
  return { exists: false };
}

async function handleChatNotification(
  request: ChatNotificationRequest,
  env: Env
): Promise<Response> {
  try {
    const { senderId, receiverId, text, messageType, messageId } = request;

    if (senderId === receiverId) {
      return new Response(
        JSON.stringify({ success: false, message: 'Sender and receiver are the same' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const accessToken = await getAccessToken(env);

    // Get sender and receiver details
    const sender = await getUserDoc(senderId, env.FIREBASE_PROJECT_ID, accessToken);
    if (!sender.exists) {
      return new Response(
        JSON.stringify({ success: false, message: 'Sender not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const receiver = await getUserDoc(receiverId, env.FIREBASE_PROJECT_ID, accessToken);
    if (!receiver.exists) {
      return new Response(
        JSON.stringify({ success: false, message: 'Receiver not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!receiver.fcmToken) {
      return new Response(
        JSON.stringify({ success: false, message: 'Receiver has no FCM token' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const notificationTitle = sender.name;
    const notificationBody = messageType === 'image' ? '📷 Sent an image' : text;

    // Send FCM notification
    const sent = await sendFCMNotification(
      receiver.fcmToken,
      notificationTitle,
      notificationBody,
      {
        type: 'chat',
        referenceId: messageId,
        senderId,
        userId: receiverId,
      },
      env.FIREBASE_PROJECT_ID,
      accessToken
    );

    // Save to Firestore
    await saveToFirestore(
      receiverId,
      notificationTitle,
      notificationBody,
      'chat',
      messageId,
      { senderId },
      env.FIREBASE_PROJECT_ID,
      accessToken
    );

    return new Response(
      JSON.stringify({ success: true, sent }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('Error in handleChatNotification:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      const url = new URL(request.url);

      if (url.pathname === '/health') {
        return new Response(
          JSON.stringify({ status: 'ok', service: 'notification-worker' }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (url.pathname === '/notify' && request.method === 'POST') {
        const notificationRequest = await request.json() as ChatNotificationRequest;
        const response = await handleChatNotification(notificationRequest, env);

        const responseHeaders = new Headers(response.headers);
        Object.entries(corsHeaders).forEach(([key, value]) => {
          responseHeaders.set(key, value);
        });

        return new Response(response.body, {
          status: response.status,
          headers: responseHeaders,
        });
      }

      return new Response(
        JSON.stringify({ error: 'Not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } catch (error: any) {
      console.error('Worker error:', error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  },
};
