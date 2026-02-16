/**
 * Simplified Cloudflare Worker for Lenv Push Notifications
 * Using direct FCM HTTP v1 API instead of Firebase Admin SDK
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT: string;
  FIRESTORE_DATABASE_URL: string;
}

interface ChatNotificationRequest {
  type: 'chat';
  messageId: string;
  senderId: string;
  receiverId: string;
  text: string;
  messageType: 'text' | 'image';
}

interface NotificationPayload {
  fcmToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

let firebaseApp: any = null;
let db: any = null;
let serviceAccount: any = null;

function initializeFirebase(env: Env) {
  if (!firebaseApp) {
    try {
      // Decode base64 service account
      const binaryString = Buffer.from(env.FIREBASE_SERVICE_ACCOUNT, 'base64').toString('utf8');
      serviceAccount = JSON.parse(binaryString);

      firebaseApp = initializeApp({
        credential: cert(serviceAccount),
        projectId: env.FIREBASE_PROJECT_ID,
      });

      db = getFirestore(firebaseApp);
      console.log('Firebase initialized successfully');
    } catch (error) {
      console.error('Error initializing Firebase:', error);
      throw error;
    }
  }
  return { db, serviceAccount };
}

async function getAccessToken(serviceAccount: any): Promise<string> {
  const jwtHeader = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  
  const now = Math.floor(Date.now() / 1000);
  const jwtClaim = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  
  const jwtClaimBase64 = Buffer.from(JSON.stringify(jwtClaim)).toString('base64url');
  
  // Import the private key
  const privateKeyPem = serviceAccount.private_key;
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKeyPem),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );
  
  // Sign the JWT
  const signatureArrayBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(`${jwtHeader}.${jwtClaimBase64}`)
  );
  
  const signature = Buffer.from(signatureArrayBuffer).toString('base64url');
  const jwt = `${jwtHeader}.${jwtClaimBase64}.${signature}`;
  
  // Exchange JWT for access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  
  const data: any = await response.json();
  return data.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = Buffer.from(base64, 'base64');
  return binary.buffer.slice(binary.byteOffset, binary.byteOffset + binary.byteLength);
}

async function sendFCMNotificationDirect(
  payload: NotificationPayload,
  projectId: string,
  accessToken: string
): Promise<boolean> {
  try {
    const message = {
      message: {
        token: payload.fcmToken,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: payload.data,
        android: {
          priority: 'high',
          notification: {
            channel_id: 'lenv_channel',
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
      const result = await response.json();
      console.log('Successfully sent notification:', result);
      return true;
    } else {
      const error = await response.text();
      console.error('Error sending notification:', error);
      return false;
    }
  } catch (error) {
    console.error('Error sending notification:', error);
    return false;
  }
}

async function saveNotificationToFirestore(
  userId: string,
  title: string,
  body: string,
  type: string,
  referenceId: string | null,
  data: Record<string, any> = {}
): Promise<void> {
  try {
    await db.collection('notifications').add({
      userId,
      title,
      body,
      type,
      referenceId,
      isRead: false,
      timestamp: Timestamp.now(),
      data,
    });
    console.log('Notification saved to Firestore for user:', userId);
  } catch (error) {
    console.error('Error saving notification to Firestore:', error);
  }
}

async function handleChatNotification(
  request: any,
  projectId: string,
  accessToken: string
): Promise<Response> {
  try {
    const { senderId, receiverId, text, messageType, messageId } = request;

    if (senderId === receiverId) {
      return new Response(JSON.stringify({ success: false, message: 'Sender and receiver are the same' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Get sender details
    const senderDoc = await db.collection('users').doc(senderId).get();
    if (!senderDoc.exists) {
      return new Response(JSON.stringify({ success: false, message: 'Sender not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    const senderName = senderDoc.data()?.name || 'Someone';

    // Get receiver's FCM token
    const receiverDoc = await db.collection('users').doc(receiverId).get();
    if (!receiverDoc.exists) {
      return new Response(JSON.stringify({ success: false, message: 'Receiver not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const fcmToken = receiverDoc.data()?.fcmToken;
    if (!fcmToken) {
      return new Response(JSON.stringify({ success: false, message: 'Receiver has no FCM token' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const notificationTitle = senderName;
    const notificationBody = messageType === 'image' ? '📷 Sent an image' : text;

    // Send notification
    const sent = await sendFCMNotificationDirect(
      {
        fcmToken,
        title: notificationTitle,
        body: notificationBody,
        data: {
          type: 'chat',
          referenceId: messageId,
          senderId,
          userId: receiverId,
        },
      },
      projectId,
      accessToken
    );

    // Save to Firestore
    await saveNotificationToFirestore(
      receiverId,
      notificationTitle,
      notificationBody,
      'chat',
      messageId,
      { senderId }
    );

    return new Response(JSON.stringify({ success: true, sent }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error: any) {
    console.error('Error in handleChatNotification:', error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
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
      const { db, serviceAccount } = initializeFirebase(env);
      const url = new URL(request.url);

      if (url.pathname === '/health') {
        return new Response(JSON.stringify({ status: 'ok', service: 'notification-worker' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (url.pathname === '/notify' && request.method === 'POST') {
        const notificationRequest = await request.json() as ChatNotificationRequest;
        
        // Get access token
        const accessToken = await getAccessToken(serviceAccount);

        let response: Response;

        if (notificationRequest.type === 'chat') {
          response = await handleChatNotification(notificationRequest, env.FIREBASE_PROJECT_ID, accessToken);
        } else {
          response = new Response(
            JSON.stringify({ success: false, message: 'Only chat notifications supported in this version' }),
            { status: 400, headers: { 'Content-Type': 'application/json' } }
          );
        }

        const responseHeaders = new Headers(response.headers);
        Object.entries(corsHeaders).forEach(([key, value]) => {
          responseHeaders.set(key, value);
        });

        return new Response(response.body, {
          status: response.status,
          headers: responseHeaders,
        });
      }

      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } catch (error: any) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  },
};
