/**
 * Firebase Cloud Functions for LenV
 * 
 * This module contains the uploadFileToR2 Cloud Function
 * which handles secure file uploads to Cloudflare R2
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Cloudflare R2 Configuration
// These values come from environment variables (set via Firebase)
const CF_CONFIG = {
  accountId: process.env.CF_ACCOUNT_ID || "4c51b62d64def00af4856f10b6104fe2",
  bucketName: process.env.CF_BUCKET_NAME || "lenv-storage",
  accessKeyId: process.env.CF_ACCESS_KEY_ID || "e5606eba19c4cc21cb9493128afc1f01",
  secretAccessKey: process.env.CF_SECRET_ACCESS_KEY || "e060ff4595dd7d3e420eebaa76a5eb9b2d360bb7e078e5b039121dcac6e65e7e",
  r2Domain: process.env.CF_R2_DOMAIN || "files.lenv1.tech",
};

const REGION = "us-central1";
const RUNTIME_OPTS = { timeoutSeconds: 120, memory: "512MB" };

/**
 * HTTP Cloud Function to upload file to R2
 * 
 * This function:
 * 1. Verifies Firebase authentication
 * 2. Validates file and metadata
 * 3. Uploads file to Cloudflare R2
 * 4. Saves metadata to Firestore
 * 5. Returns public URL
 * 
 * Request format:
 * POST /uploadFileToR2
 * Headers: { Authorization: Bearer {firebase-token} }
 * Body: {
 *   fileName: "photo.jpg",
 *   fileBase64: "iVBORw0KG...",
 *   fileType: "image/jpeg",
 *   schoolId: "CSK100",
 *   communityId: "comm123",
 *   groupId: "group456",
 *   messageId: "msg789"
 * }
 */
exports.uploadFileToR2 = functions
  .region(REGION)
  .runWith(RUNTIME_OPTS)
  .https.onRequest(async (req, res) => {
    // Enable CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      console.log("📨 Upload request received");

      // ============ STEP 1: Verify Firebase Authentication ============
      const token = req.headers.authorization?.split("Bearer ")[1];
      if (!token) {
        console.error("❌ No authorization token");
        return res.status(401).json({ error: "Missing authorization token" });
      }

      let decodedToken;
      try {
        decodedToken = await admin.auth().verifyIdToken(token);
      } catch (error) {
        console.error(`❌ Invalid token: ${error.message}`);
        return res.status(401).json({
          error: "Invalid token",
          details: error.message,
        });
      }

      const userId = decodedToken.uid;
      console.log(`✅ User authenticated: ${userId}`);

      // ============ STEP 2: Validate Request Body ============
      const {
        fileName,
        fileBase64,
        fileType,
        schoolId,
        communityId,
        groupId,
        messageId,
      } = req.body;

      // Validate file fields
      if (!fileName || !fileBase64 || !fileType) {
        console.error("❌ Missing file fields");
        return res.status(400).json({
          error: "Missing required fields: fileName, fileBase64, fileType",
        });
      }

      // Validate path fields
      if (!schoolId || !communityId || !groupId || !messageId) {
        console.error("❌ Missing path fields");
        return res.status(400).json({
          error: "Missing required path: schoolId, communityId, groupId, messageId",
        });
      }

      // ============ STEP 3: Decode and Validate File ============
      let fileBuffer;
      try {
        fileBuffer = Buffer.from(fileBase64, "base64");
      } catch (error) {
        console.error(`❌ Invalid base64: ${error.message}`);
        return res.status(400).json({
          error: "Invalid file encoding",
          details: error.message,
        });
      }

      const fileSizeKb = (fileBuffer.length / 1024).toFixed(2);
      const maxSizeBytes = 50 * 1024 * 1024; // 50MB

      if (fileBuffer.length > maxSizeBytes) {
        console.error(`❌ File too large: ${fileSizeKb}KB`);
        return res.status(400).json({
          error: `File too large. Max 50MB, got ${fileSizeKb}KB`,
        });
      }

      console.log(`📦 File size: ${fileSizeKb}KB, type: ${fileType}`);

      // ============ STEP 4: Build R2 Upload Path ============
      const r2Path = `schools/${schoolId}/communities/${communityId}/groups/${groupId}/messages/${messageId}/${fileName}`;
      const r2FullPath = `/${CF_CONFIG.bucketName}/${r2Path}`;

      console.log(`🗂️  R2 path: ${r2Path}`);

      // ============ STEP 5: Generate AWS Signature ============
      const signatureHeaders = generateSignatureHeaders({
        method: "PUT",
        bucketName: CF_CONFIG.bucketName,
        key: r2Path,
        fileType: fileType,
        fileSize: fileBuffer.length,
      });

      console.log(`🔑 Generated signature headers`);

      // ============ STEP 6: Upload to R2 ============
      const r2Url = `https://${CF_CONFIG.accountId}.r2.cloudflarestorage.com${r2FullPath}`;

      console.log(`🚀 Uploading to: ${r2Url}`);

      const uploadResponse = await axios.put(r2Url, fileBuffer, {
        headers: {
          "Content-Type": fileType,
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

      // ============ STEP 7: Generate Public URL ============
      const publicUrl = `https://${CF_CONFIG.r2Domain}/${r2Path}`;

      console.log(`📎 Public URL: ${publicUrl}`);

      // ============ STEP 8: Save Metadata to Firestore ============
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

      // Store in Firestore
      const fileRef = db
        .collection("schools")
        .doc(schoolId)
        .collection("communities")
        .doc(communityId)
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .doc(messageId)
        .collection("files")
        .doc(fileName);

      await fileRef.set(fileMetadata);

      console.log(`💾 Metadata saved to Firestore`);

      // ============ STEP 9: Return Success ============
      return res.status(200).json({
        success: true,
        fileName: fileName,
        fileType: fileType,
        fileSizeKb: parseFloat(fileSizeKb),
        r2Path: r2Path,
        publicUrl: publicUrl,
        message: "File uploaded successfully",
      });
    } catch (error) {
      console.error("❌ Upload error:", error);
      return res.status(500).json({
        error: "Upload failed",
        details: error.message,
      });
    }
  });

/**
 * Generate AWS Signature V4 headers for R2 upload
 */
function generateSignatureHeaders({ method, bucketName, key, fileType, fileSize }) {
  const date = new Date();
  const amzDate = formatAmzDate(date);
  const shortDate = amzDate.slice(0, 8);

  const credentialScope = `${shortDate}/auto/s3/aws4_request`;
  const credential = `${CF_CONFIG.accessKeyId}/${credentialScope}`;

  const canonicalRequest = `${method}
/${bucketName}/${key}

host:${CF_CONFIG.accountId}.r2.cloudflarestorage.com
content-type:${fileType}
x-amz-content-sha256:UNSIGNED-PAYLOAD
x-amz-date:${amzDate}

content-type;host;x-amz-content-sha256;x-amz-date
UNSIGNED-PAYLOAD`;

  const hashedRequest = crypto
    .createHash("sha256")
    .update(canonicalRequest)
    .digest("hex");

  const stringToSign = `AWS4-HMAC-SHA256
${amzDate}
${credentialScope}
${hashedRequest}`;

  const signature = calculateSignature(stringToSign, shortDate);

  return {
    Authorization: `AWS4-HMAC-SHA256 Credential=${credential}, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=${signature}`,
    "X-Amz-Date": amzDate,
    "X-Amz-Content-Sha256": "UNSIGNED-PAYLOAD",
  };
}

/**
 * Format date for AWS signatures (UTC)
 */
function formatAmzDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hours = String(date.getUTCHours()).padStart(2, "0");
  const minutes = String(date.getUTCMinutes()).padStart(2, "0");
  const seconds = String(date.getUTCSeconds()).padStart(2, "0");

  return `${year}${month}${day}T${hours}${minutes}${seconds}Z`;
}

/**
 * Calculate AWS Signature V4
 */
function calculateSignature(stringToSign, shortDate) {
  const kDate = hmac(`AWS4${CF_CONFIG.secretAccessKey}`, shortDate);
  const kRegion = hmac(kDate, "auto");
  const kService = hmac(kRegion, "s3");
  const kSigning = hmac(kService, "aws4_request");
  const signature = hmac(kSigning, stringToSign);

  return signature;
}

/**
 * HMAC-SHA256
 */
function hmac(key, message) {
  return crypto
    .createHmac("sha256", key)
    .update(message)
    .digest("hex");
}
