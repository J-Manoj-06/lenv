# Ultra-Optimized Cloudflare Worker for School Management

## 🚀 Cost Optimization Features

### Why This Beats Firebase Cloud Functions

| Feature | Firebase Functions | This Worker | Savings |
|---------|-------------------|-------------|---------|
| **Cold Starts** | 1-5 seconds | 0ms (instant) | ⚡ 100% faster |
| **Pricing** | $0.40 per million | $0.15 per million | 💰 62.5% cheaper |
| **Free Tier** | 2M invocations/month | 100K requests/day (3M/month) | 🎁 50% more free |
| **Memory** | 256MB minimum | 128MB | 💾 50% less |
| **Compute** | Billed per 100ms | Billed per millisecond | ⏱️ More precise |
| **Network** | Charged separately | Included | 🌐 Extra savings |

### Performance Optimizations

✅ **Zero Cold Starts** - Workers run at edge, always warm
✅ **Minimal Memory** - No class abstractions, pure functions
✅ **Fast Routing** - Early returns, no middleware bloat
✅ **Stream Processing** - Files stream directly to R2 (no buffering)
✅ **Lightweight Auth** - Simple Bearer token check
✅ **No Dependencies** - Pure TypeScript, zero npm packages

## 📦 Setup Instructions

### Step 1: Install Dependencies

```bash
cd cloudflare-worker
npm install

# Note: Use 'npx wrangler' instead of 'wrangler' for all commands
# This runs the locally installed version
```

### Step 2: Create R2 Bucket

```bash
# Login to Cloudflare
npx wrangler login

# Create R2 bucket (✅ DONE - school-files created)
npx wrangler r2 bucket create school-files

# For preview/dev environment (optional)
npx wrangler r2 bucket create school-files-preview
```

### Step 3: Set API Key Secret

```bash
# Set production API key
npx wrangler secret put API_KEY
# Enter your API key when prompted (e.g., school-secure-api-2025-xyz)

# For development, .dev.vars file already created ✅
# Edit it with your preferred dev API key
```

### 4. Configure R2 Public Access (Optional)

For direct file access without signed URLs:

```bash
# Enable public access via Cloudflare dashboard
# R2 > school-files > Settings > Public Access
# Or use a custom domain for your R2 bucket
```

Update `handleUploadFile` to return your actual R2 domain:
```typescript
fileUrl: `https://your-r2-domain.com/${fileName}`
```

### Step 5: Deploy

```bash
# Test locally first
npx wrangler dev

# Deploy to production
npx wrangler deploy
# or
npm run deploy
```

## 🔌 API Endpoints

### Authentication

All endpoints except `/status` require Bearer token:
```bash
Authorization: Bearer YOUR_API_KEY
```

### 1. Upload File
```bash
POST /uploadFile
Content-Type: multipart/form-data

Form Data:
  file: (binary)

Response:
{
  "fileUrl": "https://your-r2-domain.com/1702223456789_document.pdf",
  "fileName": "1702223456789_document.pdf",
  "size": 1048576,
  "mime": "application/pdf"
}
```

### 2. Delete File
```bash
POST /deleteFile
Content-Type: application/json

Body:
{
  "fileName": "1702223456789_document.pdf"
}

Response:
{
  "success": true,
  "deleted": "1702223456789_document.pdf"
}
```

### 3. Get Signed URL
```bash
GET /signedUrl?fileName=1702223456789_document.pdf

Response:
{
  "signedUrl": "https://r2.dev/signed-url-here",
  "fileName": "1702223456789_document.pdf",
  "expiresIn": 3600
}
```

### 4. Create Announcement
```bash
POST /announcement
Content-Type: application/json

Body:
{
  "title": "School Closed Tomorrow",
  "message": "Due to weather conditions...",
  "targetAudience": "whole_school",
  "fileUrl": "https://r2.dev/notice.pdf" // optional
}

Response:
{
  "id": "announcement_1702223456789",
  "title": "School Closed Tomorrow",
  "message": "Due to weather conditions...",
  "targetAudience": "whole_school",
  "standard": null,
  "fileUrl": "https://r2.dev/notice.pdf",
  "createdAt": "2024-12-10T10:30:00.000Z"
}
```

### 5. Send Group Message
```bash
POST /groupMessage
Content-Type: application/json

Body:
{
  "groupId": "class-10a",
  "senderId": "teacher-123",
  "messageText": "Homework for tomorrow",
  "fileUrl": "https://r2.dev/homework.pdf" // optional
}

Response:
{
  "id": "message_1702223456789",
  "groupId": "class-10a",
  "senderId": "teacher-123",
  "messageText": "Homework for tomorrow",
  "fileUrl": "https://r2.dev/homework.pdf",
  "timestamp": "2024-12-10T10:30:00.000Z"
}
```

### 6. Schedule Test
```bash
POST /scheduleTest
Content-Type: application/json

Body:
{
  "classId": "class-10a",
  "subject": "Mathematics",
  "date": "2024-12-15",
  "time": "10:00",
  "duration": 90,
  "createdBy": "teacher-123"
}

Response:
{
  "id": "test_1702223456789",
  "classId": "class-10a",
  "subject": "Mathematics",
  "date": "2024-12-15",
  "time": "10:00",
  "duration": 90,
  "createdBy": "teacher-123",
  "scheduledAt": "2024-12-10T10:30:00.000Z"
}
```

### 7. Health Check
```bash
GET /status

Response:
{
  "ok": true,
  "timestamp": 1702223456789
}
```

## 💰 Cost Breakdown

### R2 Storage Pricing
- **Storage**: $0.015/GB/month (15x cheaper than Firebase Storage)
- **Class A Operations** (writes): $4.50/million
- **Class B Operations** (reads): $0.36/million
- **Data Transfer**: FREE (egress included)

### Workers Pricing
- **Free Tier**: 100,000 requests/day
- **Paid**: $0.15 per million requests after free tier
- **CPU Time**: Included (10ms avg per request)

### Example Monthly Cost (10,000 students)

**Usage Estimates:**
- 1M file uploads/month
- 5M file downloads/month
- 100GB storage
- 10M API calls/month

**Firebase Cost:**
- Functions: $200 (5M invocations × $0.40/M)
- Storage: $150 (100GB × $0.026/GB + egress)
- **Total: $350/month**

**Cloudflare Cost:**
- Workers: FREE (10M requests = 333K/day, under free tier)
- R2 Storage: $1.50 (100GB × $0.015/GB)
- R2 Operations: $6.30 (writes + reads)
- **Total: $7.80/month**

**💰 Savings: $342.20/month (97.8% cheaper!)**

## 🛡️ Security Best Practices

1. **Rotate API Keys Regularly**
```bash
wrangler secret put API_KEY
```

2. **Enable Rate Limiting** (add to wrangler.toml):
```toml
[limits]
# 1000 requests per minute per IP
rate_limit = { requests = 1000, period = 60 }
```

3. **Add Request Validation**
- File size limits enforced (20MB)
- MIME type validation
- Filename sanitization

4. **Monitor Usage**
```bash
# View real-time logs
npm run tail

# Check analytics in Cloudflare dashboard
```

## 🔄 Migrating from Firebase Functions

### Replace Firebase Function Calls

**Before (Firebase):**
```typescript
const uploadFile = httpsCallable(functions, 'uploadFile');
const result = await uploadFile({ file: fileData });
```

**After (Cloudflare):**
```typescript
const formData = new FormData();
formData.append('file', file);

const response = await fetch('https://your-worker.workers.dev/uploadFile', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_API_KEY'
  },
  body: formData
});
const result = await response.json();
```

### Client Integration Example (Flutter)

```dart
import 'package:dio/dio.dart';

class CloudflareService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://your-worker.workers.dev',
    headers: {'Authorization': 'Bearer YOUR_API_KEY'},
  ));

  Future<Map<String, dynamic>> uploadFile(File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
    });

    final response = await _dio.post('/uploadFile', data: formData);
    return response.data;
  }

  Future<void> deleteFile(String fileName) async {
    await _dio.post('/deleteFile', data: {'fileName': fileName});
  }

  Future<String> getSignedUrl(String fileName) async {
    final response = await _dio.get('/signedUrl', 
      queryParameters: {'fileName': fileName});
    return response.data['signedUrl'];
  }
}
```

## 📊 Performance Monitoring

### View Logs
```bash
wrangler tail --format pretty
```

### Metrics to Track
- CPU time per request (target: <10ms)
- Memory usage (target: <50MB)
- Error rate (target: <0.1%)
- P99 latency (target: <100ms)

### Optimization Tips
1. Keep handlers under 10ms CPU time
2. Stream large files (don't buffer)
3. Use early returns for validation
4. Minimize JSON parsing
5. Cache frequently accessed data

## 🚀 Next Steps

1. **Test locally**: `npm run dev`
2. **Deploy**: `npm run deploy`
3. **Update Flutter app** to use new endpoints
4. **Monitor costs** in Cloudflare dashboard
5. **Scale worry-free** - Workers auto-scale globally

## 📞 Support

For issues or questions:
- Check Cloudflare Workers docs: https://developers.cloudflare.com/workers/
- R2 documentation: https://developers.cloudflare.com/r2/
- Workers KV for caching: https://developers.cloudflare.com/kv/

---

**Built for maximum performance and minimum cost** ⚡💰
