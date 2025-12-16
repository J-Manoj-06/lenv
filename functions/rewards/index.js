const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ============================================
// Constants
// ============================================

const AFFILIATE_TAG = process.env.AFFILIATE_TAG || 'lenv-21';
const REMINDER_DAYS = [3, 7, 14]; // Days before expiry
const LOCK_EXPIRY_DAYS = 21;

// ============================================
// Trigger: On reward request created
// ============================================

exports.onRewardRequestCreated = functions.firestore
  .document('reward_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const requestData = snap.data();

    try {
      console.log(`[Rewards] New request created: ${requestId}`);
      console.log(`  Student: ${requestData.student_id}`);
      console.log(`  Points locked: ${requestData.points.locked}`);
      console.log(`  Lock expires: ${requestData.timestamps.lock_expires_at}`);

      // TODO: Schedule reminder pubsub tasks for REMINDER_DAYS
      // For now, just log the creation
      
      // Create initial notification
      await db.collection('notifications').add({
        receiver: requestData.parent_id,
        type: 'reward_request_new',
        request_id: requestId,
        title: 'New Reward Request',
        body: `${requestData.product_snapshot.title} requested by student`,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });

      // Write audit log
      await db.collection('audit_logs').add({
        action: 'reward_request_created',
        actor: requestData.student_id,
        request_id: requestId,
        metadata: {
          points_locked: requestData.points.locked,
          product_id: requestData.product_snapshot.product_id,
        },
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true, requestId };
    } catch (error) {
      console.error(`❌ Error in onRewardRequestCreated: ${error.message}`);
      return { success: false, error: error.message };
    }
  });

// ============================================
// Scheduled: Daily check for expired locks
// ============================================

exports.checkExpiredRequests = functions.pubsub
  .schedule('every day 00:00')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    
    try {
      console.log(`[Rewards] Running daily expiry check at ${new Date().toISOString()}`);

      // Find all pending requests with expired locks
      const query = await db.collection('reward_requests')
        .where('status', 'in', [
          'pending_parent_approval',
          'approved_purchase_in_progress',
          'awaiting_delivery_confirmation'
        ])
        .where('timestamps.lock_expires_at', '<=', now)
        .get();

      console.log(`Found ${query.docs.length} requests to auto-resolve`);

      // Process each expired request
      const batch = db.batch();
      
      for (const doc of query.docs) {
        const requestData = doc.data();
        const studentRef = db.collection('students').doc(requestData.student_id);
        
        // Use transaction to safely update points
        await db.runTransaction(async (transaction) => {
          const studentSnap = await transaction.get(studentRef);
          const studentData = studentSnap.data() || {};
          
          const lockedPoints = requestData.points.locked;
          const currentLocked = (studentData.locked_points || 0) - lockedPoints;
          const currentAvailable = (studentData.available_points || 0) + lockedPoints;

          // Update student points
          transaction.update(studentRef, {
            locked_points: Math.max(0, currentLocked),
            available_points: currentAvailable,
          });

          // Update request status
          transaction.update(doc.ref, {
            status: 'expired_or_auto_resolved',
            'audit': admin.firestore.FieldValue.arrayUnion([{
              actor: 'system',
              action: 'expired_or_auto_resolved',
              timestamp: now,
              metadata: { auto_resolved: true }
            }]),
          });

          // Create notification for parent
          const notificationData = {
            receiver: requestData.parent_id,
            type: 'reward_request_expired',
            request_id: doc.id,
            title: 'Reward Request Expired',
            body: `Request for ${requestData.product_snapshot.title} has expired`,
            created_at: now,
            read: false,
          };
          
          db.collection('notifications').add(notificationData);

          console.log(`  ✅ Auto-resolved request: ${doc.id}, refunded ${lockedPoints} points`);
        });
      }

      return { success: true, processedCount: query.docs.length };
    } catch (error) {
      console.error(`❌ Error in checkExpiredRequests: ${error.message}`);
      return { success: false, error: error.message };
    }
  });

// ============================================
// HTTPS: Send parent reminder (manual)
// ============================================

exports.sendParentReminder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User not authenticated');
  }

  const { requestId } = data;

  try {
    const requestDoc = await db.collection('reward_requests').doc(requestId).get();
    
    if (!requestDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Request not found');
    }

    const requestData = requestDoc.data();

    // Verify requester is the parent
    if (context.auth.uid !== requestData.parent_id) {
      throw new functions.https.HttpsError('permission-denied', 'Only parent can request reminder');
    }

    // Create notification
    await db.collection('notifications').add({
      receiver: requestData.parent_id,
      type: 'reward_request_reminder',
      request_id: requestId,
      title: 'Reminder: Pending Reward Request',
      body: `You have a pending request for ${requestData.product_snapshot.title}`,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    });

    console.log(`[Rewards] Manual reminder sent for request: ${requestId}`);

    return { success: true, message: 'Reminder sent' };
  } catch (error) {
    console.error(`❌ Error in sendParentReminder: ${error.message}`);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// ============================================
// Trigger: On request status update
// ============================================

exports.onRewardRequestUpdated = functions.firestore
  .document('reward_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const requestId = context.params.requestId;

    try {
      // Detect status change
      if (beforeData.status !== afterData.status) {
        console.log(`[Rewards] Request ${requestId} status: ${beforeData.status} → ${afterData.status}`);

        // Create audit entry
        await db.collection('audit_logs').add({
          action: `status_changed_to_${afterData.status}`,
          actor: afterData.audit[afterData.audit.length - 1]?.actor || 'system',
          request_id: requestId,
          previous_status: beforeData.status,
          new_status: afterData.status,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Notify relevant parties based on new status
        if (afterData.status === 'approved_purchase_in_progress') {
          // Notify student that parent approved
          await db.collection('notifications').add({
            receiver: afterData.student_id,
            type: 'reward_request_approved',
            request_id: requestId,
            title: 'Reward Request Approved!',
            body: 'Parent approved your reward request',
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
        } else if (afterData.status === 'completed') {
          // Notify student that order is confirmed
          await db.collection('notifications').add({
            receiver: afterData.student_id,
            type: 'reward_request_completed',
            request_id: requestId,
            title: 'Order Confirmed!',
            body: 'Your reward has been confirmed',
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
        }
      }

      return { success: true };
    } catch (error) {
      console.error(`❌ Error in onRewardRequestUpdated: ${error.message}`);
      return { success: false, error: error.message };
    }
  });

// ============================================
// HTTPS: Confirm delivery (parent action)
// ============================================

exports.confirmDelivery = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User not authenticated');
  }

  const { requestId, confirmedPrice } = data;

  try {
    const requestRef = db.collection('reward_requests').doc(requestId);
    const requestDoc = await requestRef.get();

    if (!requestDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Request not found');
    }

    const requestData = requestDoc.data();

    // Verify requester is parent
    if (context.auth.uid !== requestData.parent_id) {
      throw new functions.https.HttpsError('permission-denied', 'Only parent can confirm');
    }

    // Use transaction to update request and student points
    await db.runTransaction(async (transaction) => {
      const studentRef = db.collection('students').doc(requestData.student_id);
      const studentSnap = await transaction.get(studentRef);
      const studentData = studentSnap.data() || {};

      const lockedPoints = requestData.points.locked;
      let deductedPoints = lockedPoints; // Default: deduct all locked points

      // If manual price provided, recalculate deducted points
      if (confirmedPrice && typeof confirmedPrice === 'number') {
        const pointsPerRupee = requestData.product_snapshot.points_rule.points_per_rupee;
        deductedPoints = Math.round(confirmedPrice * pointsPerRupee);
        deductedPoints = Math.min(deductedPoints, lockedPoints);
      }

      const releasedPoints = lockedPoints - deductedPoints;

      // Update student points
      transaction.update(studentRef, {
        locked_points: (studentData.locked_points || 0) - lockedPoints,
        deducted_points: (studentData.deducted_points || 0) + deductedPoints,
      });

      // Update request status
      transaction.update(requestRef, {
        status: 'completed',
        'confirmation': {
          type: confirmedPrice ? 'manual' : 'amazon',
          confirmed_price: confirmedPrice,
          confirmed_by: context.auth.uid,
          confirmed_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        'points.deducted': deductedPoints,
        'audit': admin.firestore.FieldValue.arrayUnion([{
          actor: context.auth.uid,
          action: 'completed',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: { 
            deducted_points: deductedPoints,
            released_points: releasedPoints 
          }
        }]),
      });
    });

    console.log(`[Rewards] Delivery confirmed for request: ${requestId}`);

    return { success: true, message: 'Delivery confirmed' };
  } catch (error) {
    console.error(`❌ Error in confirmDelivery: ${error.message}`);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
