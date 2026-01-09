/**
 * Firebase Cloud Function: uploadFileToR2
 * 
 * HTTP Endpoint for uploading files to Cloudflare R2
 * 
 * Flow:
 * 1. Flutter sends file (base64) + metadata (schoolId, communityId, groupId, messageId)
 * 2. Function uploads to R2 with organized path:
 *    /schools/{schoolId}/communities/{communityId}/groups/{groupId}/messages/{messageId}/{fileName}
 * 3. Returns public URL: https://files.lenv1.tech/schools/.../{fileName}
 * 
 * Deploy:
 * firebase deploy --only functions:uploadFileToR2
 * 
 * Usage from Flutter:
 * POST to: https://region-project.cloudfunctions.net/uploadFileToR2
 * Headers: {
 *   'Authorization': 'Bearer {firebaseToken}',
 *   'Content-Type': 'application/json'
 * }
 * Body: {
 *   'fileName': 'photo.jpg',
 *   'fileBase64': 'base64encodedcontent',
 *   'fileType': 'image/jpeg',
 *   'schoolId': 'CSK100',
 *   'communityId': 'comm123',
 *   'groupId': 'group456',
 *   'messageId': 'msg789'
 * }
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const crypto = require('crypto');

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Cloudflare R2 credentials from environment variables
const CF_CONFIG = {
  accountId: process.env.CF_ACCOUNT_ID,
  bucketName: process.env.CF_BUCKET_NAME,
  accessKeyId: process.env.CF_ACCESS_KEY_ID,
  secretAccessKey: process.env.CF_SECRET_ACCESS_KEY,
  r2Domain: process.env.CF_R2_DOMAIN,
};

const REGION = 'us-central1';
const RUNTIME_OPTS = { timeoutSeconds: 120, memory: '512MB' };

/**
 * HTTP Cloud Function to upload file to R2
 * This is more reliable than client-side uploads because:
 * 1. Server handles R2 authentication (credentials never exposed to client)
 * 2. Automatic organized folder structure
 * 3. Can validate file size and type
 * 4. Can track uploads in Firestore
 */
exports.uploadFileToR2 = functions
  .region(REGION)
  .runWith(RUNTIME_OPTS)
  .https.onRequest(async (req, res) => {
    // Enable CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    try {
      // Verify Firebase authentication
      const token = req.headers.authorization?.split('Bearer ')[1];
      if (!token) {
        return res.status(401).json({ error: 'Missing authorization token' });
      }

      let decodedToken;
      try {
        decodedToken = await admin.auth().verifyIdToken(token);
      } catch (error) {
        return res.status(401).json({ error: 'Invalid token', details: error.message });
      }

      const userId = decodedToken.uid;
      console.log(`📤 Upload request from user: ${userId}`);

      // Validate request body
      const {
        fileName,
        fileBase64,
        fileType,
        schoolId,
        communityId,
        groupId,
        messageId,
      } = req.body;

      if (!fileName || !fileBase64 || !fileType) {
        return res.status(400).json({
          error: 'Missing required fields: fileName, fileBase64, fileType',
        });
      }

      if (!schoolId || !communityId || !groupId || !messageId) {
        return res.status(400).json({
          error: 'Missing required path fields: schoolId, communityId, groupId, messageId',
        });
      }

      // Decode base64 to buffer
      const fileBuffer = Buffer.from(fileBase64, 'base64');
      const fileSizeKb = (fileBuffer.length / 1024).toFixed(2);

      // Validate file size (max 50MB)
      const maxSizeBytes = 50 * 1024 * 1024;
      if (fileBuffer.length > maxSizeBytes) {
        return res.status(400).json({
          error: `File too large. Max size is 50MB, got ${fileSizeKb}KB`,
        });
      }

      console.log(`📦 File size: ${fileSizeKb}KB, type: ${fileType}`);

      // Build organized R2 path
      const r2Path = `schools/${schoolId}/communities/${communityId}/groups/${groupId}/messages/${messageId}/${fileName}`;
      const r2FullPath = `/${CF_CONFIG.bucketName}/${r2Path}`;

      console.log(`🗂️  R2 path: ${r2Path}`);

      // Generate AWS Signature V4 headers for PUT request
      const signatureHeaders = generateSignatureHeaders({
        method: 'PUT',
        bucketName: CF_CONFIG.bucketName,
        key: r2Path,
        fileType: fileType,
        fileSize: fileBuffer.length,
      });

      console.log(`🔑 Generated signature headers`);

      // Upload to R2 using signed request
      const r2Url = `https://${CF_CONFIG.accountId}.r2.cloudflarestorage.com${r2FullPath}`;

      console.log(`🚀 Uploading to: ${r2Url}`);

      const uploadResponse = await axios.put(r2Url, fileBuffer, {
        headers: {
          'Content-Type': fileType,
          ...signatureHeaders,
        },
        maxContentLength: Infinity,
        maxBodyLength: Infinity,
      });

      if (uploadResponse.status !== 200) {
        console.error(`❌ R2 upload failed: ${uploadResponse.status}`);
        return res.status(500).json({
          error: `R2 upload failed with status ${uploadResponse.status}`,
        });
      }

      console.log(`✅ File uploaded to R2: ${r2Path}`);

      // Generate public URL
      const publicUrl = `https://${CF_CONFIG.r2Domain}/${r2Path}`;

      // Save metadata to Firestore
      const fileMetadata = {
        fileName: fileName,
        fileType: fileType,
        fileSizeKb: parseFloat(fileSizeKb),
        r2Path: r2Path,
        publicUrl: publicUrl,
        uploadedBy: userId,
        uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
        schoolId: schoolId,
        communityId: communityId,
        groupId: groupId,
        messageId: messageId,
      };

      // Store in Firestore for tracking
      // Path: schools/{schoolId}/communities/{communityId}/groups/{groupId}/messages/{messageId}/files/{fileId}
      const fileRef = db.collection('schools')
        .doc(schoolId)
        .collection('communities')
        .doc(communityId)
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .collection('files')
        .doc(fileName);

      await fileRef.set(fileMetadata);

      console.log(`💾 Metadata saved to Firestore`);

      return res.status(200).json({
        success: true,
        fileName: fileName,
        fileType: fileType,
        fileSizeKb: parseFloat(fileSizeKb),
        r2Path: r2Path,
        publicUrl: publicUrl,
        message: 'File uploaded successfully',
      });
    } catch (error) {
      console.error('❌ Upload error:', error);
      return res.status(500).json({
        error: 'Upload failed',
        details: error.message,
      });
    }
  });

/**
 * Generate AWS Signature V4 headers for PUT request to R2
 */
function generateSignatureHeaders({ method, bucketName, key, fileType, fileSize }) {
  const date = new Date();
  const amzDate = formatAmzDate(date);
  const shortDate = amzDate.slice(0, 8);

  // Credential scope
  const credentialScope = `${shortDate}/auto/s3/aws4_request`;
  const credential = `${CF_CONFIG.accessKeyId}/${credentialScope}`;

  // Create canonical request
  const canonicalRequest = `${method}
/${bucketName}/${key}

host:${CF_CONFIG.accountId}.r2.cloudflarestorage.com
content-type:${fileType}
x-amz-content-sha256:UNSIGNED-PAYLOAD
x-amz-date:${amzDate}

content-type;host;x-amz-content-sha256;x-amz-date
UNSIGNED-PAYLOAD`;

  // Create string to sign
  const hashedRequest = crypto
    .createHash('sha256')
    .update(canonicalRequest)
    .digest('hex');

  const stringToSign = `AWS4-HMAC-SHA256
${amzDate}
${credentialScope}
${hashedRequest}`;

  // Calculate signature
  const signature = calculateSignature(stringToSign, shortDate);

  return {
    Authorization: `AWS4-HMAC-SHA256 Credential=${credential}, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=${signature}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Content-Sha256': 'UNSIGNED-PAYLOAD',
  };
}

/**
 * Format date for AWS signatures (UTC)
 */
function formatAmzDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  const hours = String(date.getUTCHours()).padStart(2, '0');
  const minutes = String(date.getUTCMinutes()).padStart(2, '0');
  const seconds = String(date.getUTCSeconds()).padStart(2, '0');

  return `${year}${month}${day}T${hours}${minutes}${seconds}Z`;
}

/**
 * Calculate AWS Signature V4
 */
function calculateSignature(stringToSign, shortDate) {
  const kDate = hmac(`AWS4${CF_CONFIG.secretAccessKey}`, shortDate);
  const kRegion = hmac(kDate, 'auto');
  const kService = hmac(kRegion, 's3');
  const kSigning = hmac(kService, 'aws4_request');
  const signature = hmac(kSigning, stringToSign);

  return signature;
}

/**
 * HMAC-SHA256
 */
function hmac(key, message) {
  if (typeof key === 'string') {
    key = Buffer.from(key, 'utf-8');
  }

  return crypto.createHmac('sha256', key).update(message).digest('hex');
}
