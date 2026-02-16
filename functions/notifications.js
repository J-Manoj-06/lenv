/**
 * Firebase Cloud Functions for Lenv Notification System
 * 
 * This file contains all notification-related cloud functions including:
 * 1. sendChatNotification - Triggered when a new chat message is created
 * 2. sendAssignmentNotification - Triggered when a new assignment is created
 * 3. sendAnnouncementNotification - Triggered when a new announcement is created
 * 
 * Each function:
 * - Fetches relevant FCM tokens
 * - Sends push notifications via Firebase Admin SDK
 * - Saves notification records to Firestore
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Admin SDK if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Send notification to a user
 * @param {string} fcmToken - User's FCM token
 * @param {Object} notification - Notification payload
 * @param {Object} data - Additional data for navigation
 */
async function sendNotification(fcmToken, notification, data) {
  if (!fcmToken) {
    console.log('No FCM token provided');
    return null;
  }

  const message = {
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data: data,
    token: fcmToken,
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
  };

  try {
    const response = await messaging.send(message);
    console.log('Successfully sent notification:', response);
    return response;
  } catch (error) {
    console.error('Error sending notification:', error);
    return null;
  }
}

/**
 * Save notification to Firestore
 * @param {string} userId - User ID to receive notification
 * @param {string} title - Notification title
 * @param {string} body - Notification body
 * @param {string} type - Notification type (chat, assignment, announcement)
 * @param {string} referenceId - Reference ID (messageId, assignmentId, etc.)
 * @param {Object} data - Additional data
 */
async function saveNotificationToFirestore(userId, title, body, type, referenceId, data = {}) {
  try {
    await db.collection('notifications').add({
      userId: userId,
      title: title,
      body: body,
      type: type,
      referenceId: referenceId,
      isRead: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      data: data,
    });
    console.log('Notification saved to Firestore for user:', userId);
  } catch (error) {
    console.error('Error saving notification to Firestore:', error);
  }
}

/**
 * Cloud Function: Send Chat Notification
 * Triggered when a new message is created in the 'messages' collection
 */
exports.sendChatNotification = functions.firestore
  .document('messages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      const messageData = snap.data();
      const messageId = context.params.messageId;

      const senderId = messageData.senderId;
      const receiverId = messageData.receiverId;
      const messageText = messageData.text || '';
      const messageType = messageData.type || 'text';

      // Don't send notification to sender
      if (!receiverId || senderId === receiverId) {
        console.log('No receiver or sender is receiver, skipping notification');
        return null;
      }

      // Get sender details
      const senderDoc = await db.collection('users').doc(senderId).get();
      if (!senderDoc.exists) {
        console.log('Sender not found');
        return null;
      }
      const senderName = senderDoc.data().name || 'Someone';

      // Get receiver's FCM token
      const receiverDoc = await db.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) {
        console.log('Receiver not found');
        return null;
      }

      const receiverData = receiverDoc.data();
      const fcmToken = receiverData.fcmToken;

      if (!fcmToken) {
        console.log('Receiver has no FCM token');
        return null;
      }

      // Prepare notification content
      const notificationTitle = senderName;
      const notificationBody = messageType === 'image' ? '📷 Sent an image' : messageText;

      const notificationData = {
        type: 'chat',
        referenceId: messageId,
        senderId: senderId,
        userId: receiverId,
      };

      // Send notification
      await sendNotification(fcmToken, {
        title: notificationTitle,
        body: notificationBody,
      }, notificationData);

      // Save to Firestore
      await saveNotificationToFirestore(
        receiverId,
        notificationTitle,
        notificationBody,
        'chat',
        messageId,
        { senderId: senderId }
      );

      return { success: true };
    } catch (error) {
      console.error('Error in sendChatNotification:', error);
      return { error: error.message };
    }
  });

/**
 * Cloud Function: Send Assignment Notification
 * Triggered when a new assignment is created in the 'assignments' collection
 */
exports.sendAssignmentNotification = functions.firestore
  .document('assignments/{assignmentId}')
  .onCreate(async (snap, context) => {
    try {
      const assignmentData = snap.data();
      const assignmentId = context.params.assignmentId;

      const title = assignmentData.title || 'New Assignment';
      const classId = assignmentData.classId;
      const createdBy = assignmentData.createdBy;

      if (!classId) {
        console.log('No class ID specified');
        return null;
      }

      // Get all students in the class
      const studentsSnapshot = await db.collection('users')
        .where('role', '==', 'student')
        .where('classId', '==', classId)
        .get();

      if (studentsSnapshot.empty) {
        console.log('No students found in class');
        return null;
      }

      const notificationTitle = 'New Assignment';
      const notificationBody = title;

      const notificationData = {
        type: 'assignment',
        referenceId: assignmentId,
        classId: classId,
      };

      // Send notifications to all students
      const promises = [];
      studentsSnapshot.forEach((doc) => {
        const studentId = doc.id;
        const studentData = doc.data();
        const fcmToken = studentData.fcmToken;

        // Don't send to assignment creator
        if (studentId === createdBy) return;

        if (fcmToken) {
          // Send notification
          promises.push(
            sendNotification(fcmToken, {
              title: notificationTitle,
              body: notificationBody,
            }, { ...notificationData, userId: studentId })
          );

          // Save to Firestore
          promises.push(
            saveNotificationToFirestore(
              studentId,
              notificationTitle,
              notificationBody,
              'assignment',
              assignmentId,
              { classId: classId }
            )
          );
        }
      });

      await Promise.all(promises);
      console.log(`Sent assignment notifications to ${studentsSnapshot.size} students`);

      return { success: true, count: studentsSnapshot.size };
    } catch (error) {
      console.error('Error in sendAssignmentNotification:', error);
      return { error: error.message };
    }
  });

/**
 * Cloud Function: Send Announcement Notification
 * Triggered when a new announcement is created in the 'announcements' collection
 */
exports.sendAnnouncementNotification = functions.firestore
  .document('announcements/{announcementId}')
  .onCreate(async (snap, context) => {
    try {
      const announcementData = snap.data();
      const announcementId = context.params.announcementId;

      const title = announcementData.title || 'New Announcement';
      const description = announcementData.description || '';
      const createdBy = announcementData.createdBy;
      const targetRole = announcementData.targetRole; // 'student', 'parent', 'all'

      // Prepare query based on target role
      let query = db.collection('users');

      if (targetRole && targetRole !== 'all') {
        query = query.where('role', '==', targetRole);
      }

      const usersSnapshot = await query.get();

      if (usersSnapshot.empty) {
        console.log('No users found for announcement');
        return null;
      }

      const notificationTitle = 'Announcement';
      const notificationBody = title;

      const notificationData = {
        type: 'announcement',
        referenceId: announcementId,
      };

      // Send notifications to all targeted users
      const promises = [];
      usersSnapshot.forEach((doc) => {
        const userId = doc.id;
        const userData = doc.data();
        const fcmToken = userData.fcmToken;

        // Don't send to announcement creator
        if (userId === createdBy) return;

        if (fcmToken) {
          // Send notification
          promises.push(
            sendNotification(fcmToken, {
              title: notificationTitle,
              body: notificationBody,
            }, { ...notificationData, userId: userId })
          );

          // Save to Firestore
          promises.push(
            saveNotificationToFirestore(
              userId,
              notificationTitle,
              notificationBody,
              'announcement',
              announcementId,
              {}
            )
          );
        }
      });

      await Promise.all(promises);
      console.log(`Sent announcement notifications to ${usersSnapshot.size} users`);

      return { success: true, count: usersSnapshot.size };
    } catch (error) {
      console.error('Error in sendAnnouncementNotification:', error);
      return { error: error.message };
    }
  });

/**
 * Cloud Function: Clean up old notifications (Optional utility function)
 * Run this periodically to delete old read notifications
 * Schedule: Every day at 2 AM
 */
exports.cleanupOldNotifications = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('America/New_York')
  .onRun(async (context) => {
    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const oldNotificationsSnapshot = await db.collection('notifications')
        .where('isRead', '==', true)
        .where('timestamp', '<', thirtyDaysAgo)
        .get();

      if (oldNotificationsSnapshot.empty) {
        console.log('No old notifications to delete');
        return null;
      }

      const batch = db.batch();
      oldNotificationsSnapshot.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      console.log(`Deleted ${oldNotificationsSnapshot.size} old notifications`);

      return { success: true, deleted: oldNotificationsSnapshot.size };
    } catch (error) {
      console.error('Error in cleanupOldNotifications:', error);
      return { error: error.message };
    }
  });
