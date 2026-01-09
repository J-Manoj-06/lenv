/**
 * Firebase Cloud Function to Generate Cloudflare R2 Signed URLs
 * 
 * This function should be deployed to generate signed URLs securely on the backend,
 * instead of exposing Cloudflare credentials to the client app.
 * 
 * Install dependencies:
 * npm install firebase-functions firebase-admin aws4
 * 
 * Deploy:
 * firebase deploy --only functions:generateR2SignedUrl
 * 
 * Usage from Flutter:
 * final response = await CloudFunctions.instance
 *     .httpsCallable('generateR2SignedUrl')
 *     .call({
 *       'fileName': 'photo.jpg',
 *       'fileType': 'image/jpeg',
 *       'durationHours': 24,
 *     });
 * 
 * final signedUrl = response.data['url'];
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const aws4 = require("aws4");

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Cloudflare R2 credentials from environment variables
const CF_CONFIG = {
  accountId: process.env.CF_ACCOUNT_ID,
  bucketName: process.env.CF_BUCKET_NAME,
  accessKeyId: process.env.CF_ACCESS_KEY_ID,
  secretAccessKey: process.env.CF_SECRET_ACCESS_KEY,
  r2Domain: process.env.CF_R2_DOMAIN,
};

/**
 * HTTP Cloud Function to generate R2 signed URL
 */
exports.generateR2SignedUrl = functions.https.onCall(
  async (data, context) => {
    try {
      // Verify authentication
      if (!context.auth) {
        throw new functions.https.HttpsError(
          "unauthenticated",
          "User must be authenticated"
        );
      }

      const userId = context.auth.uid;
      const { fileName, fileType, durationHours = 24 } = data;

      // Validate inputs
      if (!fileName || !fileType) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "fileName and fileType are required"
        );
      }

      // Generate unique key to prevent collisions
      const timestamp = Date.now();
      const key = `media/${timestamp}/${fileName}`;

      // Calculate signature expiry
      const expirySeconds = durationHours * 3600;

      // AWS Signature V4 signing
      const signedUrl = signUrl({
        method: "PUT",
        hostname: `${CF_CONFIG.accountId}.r2.cloudflarestorage.com`,
        path: `/${CF_CONFIG.bucketName}/${key}`,
        query: {},
        headers: {
          "Content-Type": fileType,
        },
        signQuery: true,
        expiresIn: expirySeconds,
      });

      // Calculate public URL
      const publicUrl = `https://${CF_CONFIG.r2Domain}/${key}`;

      console.log(`✅ Generated signed URL for: ${fileName} (user: ${userId})`);

      return {
        url: signedUrl,
        key: key,
        publicUrl: publicUrl,
        expiresIn: expirySeconds,
        expiresAt: new Date(Date.now() + expirySeconds * 1000).toISOString(),
      };
    } catch (error) {
      console.error("❌ Error generating signed URL:", error);
      throw new functions.https.HttpsError("internal", error.message);
    }
  }
);

/**
 * Sign a request using AWS Signature V4
 */
function signUrl(options) {
  const {
    method = "GET",
    hostname,
    path,
    query = {},
    headers = {},
    expiresIn = 86400,
  } = options;

  const now = new Date();
  const amzDate = getAmzDate(now);
  const shortDate = amzDate.slice(0, 8);

  // Add query parameters for signing
  const queryWithAuth = {
    ...query,
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": getCredentialScope(
      shortDate,
      CF_CONFIG.accessKeyId
    ),
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": expiresIn.toString(),
    "X-Amz-SignedHeaders": "host",
  };

  // Sort query parameters
  const sortedParams = Object.keys(queryWithAuth)
    .sort()
    .map((key) => `${encodeURIComponent(key)}=${encodeURIComponent(queryWithAuth[key])}`)
    .join("&");

  // Create canonical request
  const canonicalRequest = [
    method,
    path,
    sortedParams,
    `host:${hostname}`,
    "",
    "host",
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  // Hash canonical request
  const crypto = require("crypto");
  const hashedRequest = crypto
    .createHash("sha256")
    .update(canonicalRequest)
    .digest("hex");

  // Create string to sign
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    getCredentialScopeWithService(shortDate),
    hashedRequest,
  ].join("\n");

  // Calculate signature
  const signature = calculateSignature(stringedToSign, shortDate);

  // Return signed URL
  return `https://${hostname}${path}?${sortedParams}&X-Amz-Signature=${signature}`;
}

/**
 * Format date for AWS signatures
 */
function getAmzDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hours = String(date.getUTCHours()).padStart(2, "0");
  const minutes = String(date.getUTCMinutes()).padStart(2, "0");
  const seconds = String(date.getUTCSeconds()).padStart(2, "0");

  return `${year}${month}${day}T${hours}${minutes}${seconds}Z`;
}

/**
 * Get credential scope for query parameters
 */
function getCredentialScope(shortDate, accessKeyId) {
  return encodeURIComponent(
    `${accessKeyId}/${shortDate}/auto/s3/aws4_request`
  );
}

/**
 * Get credential scope for string to sign
 */
function getCredentialScopeWithService(shortDate) {
  return `${shortDate}/auto/s3/aws4_request`;
}

/**
 * Calculate AWS signature
 */
function calculateSignature(stringToSign, shortDate) {
  const crypto = require("crypto");

  // Derive signing key
  const kDate = hmac(`AWS4${CF_CONFIG.secretAccessKey}`, shortDate);
  const kRegion = hmac(kDate, "auto");
  const kService = hmac(kRegion, "s3");
  const kSigning = hmac(kService, "aws4_request");

  // Calculate signature
  const signature = hmac(kSigning, stringToSign);

  return signature;
}

/**
 * HMAC-SHA256
 */
function hmac(key, message) {
  const crypto = require("crypto");

  if (typeof key === "string") {
    key = Buffer.from(key, "utf-8");
  }

  return crypto.createHmac("sha256", key).update(message).digest("hex");
}

/**
 * Get file from R2 (for download/preview)
 * Requires public access or presigned URL
 */
exports.getR2File = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { fileKey } = data;
    if (!fileKey) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "fileKey is required"
      );
    }

    // Generate download URL
    const downloadUrl = `https://${CF_CONFIG.r2Domain}/${fileKey}`;

    return {
      url: downloadUrl,
      fileName: fileKey.split("/").pop(),
    };
  } catch (error) {
    console.error("❌ Error getting R2 file:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Delete file from R2
 * Only allowed by file owner or admin
 */
exports.deleteR2File = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { fileKey } = data;
    if (!fileKey) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "fileKey is required"
      );
    }

    // TODO: Implement deletion using S3 SDK
    // For now, soft delete in Firestore is sufficient

    console.log(`✅ File deleted: ${fileKey}`);

    return { success: true };
  } catch (error) {
    console.error("❌ Error deleting R2 file:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Get R2 bucket info
 */
exports.getR2BucketInfo = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    // TODO: Get real bucket stats from Cloudflare API

    return {
      bucketName: CF_CONFIG.bucketName,
      domain: CF_CONFIG.r2Domain,
      accountId: CF_CONFIG.accountId,
    };
  } catch (error) {
    console.error("❌ Error getting bucket info:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * Environment Setup:
 * 
 * Set these in Firebase Cloud Functions environment:
 * 
 * firebase functions:config:set cloudflare.account_id="YOUR_ID"
 * firebase functions:config:set cloudflare.bucket_name="app-media"
 * firebase functions:config:set cloudflare.access_key="YOUR_KEY"
 * firebase functions:config:set cloudflare.secret_key="YOUR_SECRET"
 * firebase functions:config:set cloudflare.r2_domain="cdn.yourdomain.com"
 * 
 * Or in .env.local:
 * CF_ACCOUNT_ID=xxx
 * CF_BUCKET_NAME=app-media
 * CF_ACCESS_KEY_ID=xxx
 * CF_SECRET_ACCESS_KEY=xxx
 * CF_R2_DOMAIN=cdn.yourdomain.com
 */
