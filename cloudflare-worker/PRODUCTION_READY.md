# 🚀 Production Ready - Complete File Upload & API Guide

## ✅ Your Worker is Live!

**Worker URL:** `https://school-management-worker.giridharannj.workers.dev`  
**R2 Bucket:** `lenv-storage`  
**File Domain:** `https://files.lenv1.tech`

---

## 📤 How to Upload Files (PDFs, Images)

### **Step 1: Get Your API Key**

```powershell
# Your API key is stored in Cloudflare secrets
# Use this in all requests with Authorization header
# Example: Bearer xK9mP2nQ4rS6tU8vW0xY2zA4bC6dE8fG
```

### **Step 2: Upload a File**

**Using PowerShell:**

```powershell
$workerUrl = "https://school-management-worker.giridharannj.workers.dev"
$apiKey = "YOUR-API-KEY"  # Get from Cloudflare secrets

# Upload PDF
$pdf = Get-Item "C:\path\to\file.pdf"
$form = @{
    file = $pdf
}

$response = Invoke-RestMethod -Uri "$workerUrl/uploadFile" `
  -Method Post `
  -Headers @{"Authorization"="Bearer $apiKey"} `
  -Form $form

Write-Host "Uploaded: $($response.fileUrl)"
Write-Host "File Size: $($response.size) bytes"
```

**Using cURL:**

```bash
curl -X POST https://school-management-worker.giridharannj.workers.dev/uploadFile \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -F "file=@/path/to/document.pdf"
```

**Using JavaScript (Browser/Node.js):**

```javascript
const uploadFile = async (file, apiKey) => {
  const formData = new FormData();
  formData.append('file', file);

  const response = await fetch(
    'https://school-management-worker.giridharannj.workers.dev/uploadFile',
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`
      },
      body: formData
    }
  );

  const data = await response.json();
  console.log('File URL:', data.fileUrl);
  return data;
};
```

---

## 📋 API Endpoints Reference

### **1. Upload File**
```http
POST /uploadFile
Content-Type: multipart/form-data
Authorization: Bearer API_KEY

Form Data:
  - file: <binary file>

Response:
{
  "fileUrl": "https://files.lenv1.tech/1733868900000_document.pdf",
  "fileName": "1733868900000_document.pdf",
  "size": 245891,
  "mime": "application/pdf"
}
```

**Allowed Types:** PDF, JPG, PNG  
**Max Size:** 20MB

---

### **2. Delete File**
```http
POST /deleteFile
Content-Type: application/json
Authorization: Bearer API_KEY

Request Body:
{
  "fileName": "1733868900000_document.pdf"
}

Response:
{
  "success": true,
  "deleted": "1733868900000_document.pdf"
}
```

---

### **3. Get Signed URL** (for temporary access)
```http
GET /signedUrl?fileName=1733868900000_document.pdf
Authorization: Bearer API_KEY

Response:
{
  "signedUrl": "https://...(temporary access URL)...",
  "expiresIn": 3600
}
```

---

### **4. Post Announcement**
```http
POST /announcement
Content-Type: application/json
Authorization: Bearer API_KEY

Request Body:
{
  "title": "Important Notice",
  "message": "All students must submit assignments by Friday",
  "targetAudience": "whole_school",
  "standard": "10th",
  "fileUrl": "https://files.lenv1.tech/1733868900000_notice.pdf"
}

Response:
{
  "id": "ann_1234567890",
  "title": "Important Notice",
  "message": "All students must submit assignments by Friday",
  "targetAudience": "whole_school",
  "standard": "10th",
  "fileUrl": "https://files.lenv1.tech/1733868900000_notice.pdf",
  "createdAt": "2025-12-10T12:30:00Z"
}
```

---

### **5. Post Group Message**
```http
POST /groupMessage
Content-Type: application/json
Authorization: Bearer API_KEY

Request Body:
{
  "groupId": "class_10a",
  "senderId": "teacher_001",
  "messageText": "Today's lesson is about chapter 5",
  "fileUrl": "https://files.lenv1.tech/1733868900000_lesson.pdf"
}

Response:
{
  "id": "msg_9876543210",
  "groupId": "class_10a",
  "senderId": "teacher_001",
  "messageText": "Today's lesson is about chapter 5",
  "fileUrl": "https://files.lenv1.tech/1733868900000_lesson.pdf",
  "timestamp": "2025-12-10T12:35:00Z"
}
```

---

### **6. Schedule Test**
```http
POST /scheduleTest
Content-Type: application/json
Authorization: Bearer API_KEY

Request Body:
{
  "classId": "10a",
  "subject": "Mathematics",
  "date": "2025-12-15",
  "time": "10:00",
  "duration": 60,
  "createdBy": "teacher_001"
}

Response:
{
  "id": "test_5555555555",
  "classId": "10a",
  "subject": "Mathematics",
  "date": "2025-12-15",
  "time": "10:00",
  "duration": 60,
  "createdBy": "teacher_001",
  "scheduledAt": "2025-12-10T12:40:00Z"
}
```

---

### **7. Health Check** (No auth required)
```http
GET /status

Response:
{
  "ok": true,
  "timestamp": "2025-12-10T12:45:00Z"
}
```

---

## 🧪 Test All Endpoints Now

### **Option 1: PowerShell Script**
```powershell
cd d:\new_reward\cloudflare-worker
.\test-endpoints.ps1
```

### **Option 2: Browser-based Tester**
Open `test.html` in your browser, paste your API key, and test each endpoint.

### **Option 3: Manual cURL Tests**

```bash
# Health check
curl https://school-management-worker.giridharannj.workers.dev/status

# Test announcement with authentication
curl -X POST https://school-management-worker.giridharannj.workers.dev/announcement \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test",
    "message": "This is a test announcement",
    "targetAudience": "whole_school"
  }'
```

---

## 📱 Flutter App Integration

### **Step 1: Create CloudflareService in Flutter**

Create file: `lib/services/cloudflare_service.dart`

```dart
import 'package:dio/dio.dart';

class CloudflareService {
  static const String baseUrl = 'https://school-management-worker.giridharannj.workers.dev';
  static const String apiKey = 'YOUR-API-KEY'; // Replace with your key
  
  final Dio _dio = Dio();

  Future<String> uploadFile(String filePath) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.post(
        '$baseUrl/uploadFile',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

      return response.data['fileUrl'];
    } catch (e) {
      throw 'File upload failed: $e';
    }
  }

  Future<bool> deleteFile(String fileName) async {
    try {
      await _dio.post(
        '$baseUrl/deleteFile',
        data: {'fileName': fileName},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return true;
    } catch (e) {
      throw 'File deletion failed: $e';
    }
  }

  Future<String> getSignedUrl(String fileName) async {
    try {
      final response = await _dio.get(
        '$baseUrl/signedUrl',
        queryParameters: {'fileName': fileName},
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );
      return response.data['signedUrl'];
    } catch (e) {
      throw 'Failed to get signed URL: $e';
    }
  }

  Future<Map<String, dynamic>> postAnnouncement({
    required String title,
    required String message,
    required String targetAudience,
    String? standard,
    String? fileUrl,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/announcement',
        data: {
          'title': title,
          'message': message,
          'targetAudience': targetAudience,
          if (standard != null) 'standard': standard,
          if (fileUrl != null) 'fileUrl': fileUrl,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to post announcement: $e';
    }
  }

  Future<Map<String, dynamic>> postGroupMessage({
    required String groupId,
    required String senderId,
    required String messageText,
    String? fileUrl,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/groupMessage',
        data: {
          'groupId': groupId,
          'senderId': senderId,
          'messageText': messageText,
          if (fileUrl != null) 'fileUrl': fileUrl,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to post group message: $e';
    }
  }

  Future<Map<String, dynamic>> scheduleTest({
    required String classId,
    required String subject,
    required String date,
    required String time,
    required int duration,
    required String createdBy,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/scheduleTest',
        data: {
          'classId': classId,
          'subject': subject,
          'date': date,
          'time': time,
          'duration': duration,
          'createdBy': createdBy,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to schedule test: $e';
    }
  }

  Future<bool> checkStatus() async {
    try {
      final response = await _dio.get('$baseUrl/status');
      return response.data['ok'] == true;
    } catch (e) {
      return false;
    }
  }
}
```

### **Step 2: Add Dio to pubspec.yaml**

```yaml
dependencies:
  dio: ^5.3.2
```

### **Step 3: Use in Your App**

```dart
class MyApp extends StatelessWidget {
  final cloudflareService = CloudflareService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('File Upload Test')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              // Example: Upload a file
              try {
                final fileUrl = await cloudflareService.uploadFile(
                  '/path/to/your/file.pdf'
                );
                print('Uploaded to: $fileUrl');
              } catch (e) {
                print('Error: $e');
              }
            },
            child: Text('Upload PDF'),
          ),
        ),
      ),
    );
  }
}
```

---

## 🔒 Security Notes

1. **Never hardcode API keys** in your app's source code
2. **Use environment variables** or Firebase Remote Config for keys
3. **Keep API key secret** - don't share it publicly
4. **Rotate API keys** periodically
5. **Monitor usage** in Cloudflare dashboard

---

## 💾 File Storage Details

**Your R2 Bucket:** `lenv-storage`  
**Files Stored at:** `https://files.lenv1.tech/{fileName}`  
**File Naming:** `{timestamp}_{original_filename}`

Example:
- Upload: `homework.pdf`
- Stored as: `1733868900000_homework.pdf`
- Access at: `https://files.lenv1.tech/1733868900000_homework.pdf`

---

## 📊 Cost Breakdown

- **Compute:** FREE (100K requests/day on free tier)
- **R2 Storage:** $0.015/GB/month
- **R2 Operations:** $0.36/million reads, $4.50/million writes

**Example for 1000 students:**
- 1000 announcements × 100KB = 100MB = **$1.50/month**
- 500 lessons × 5MB = 2.5GB = **$37.50/month**

---

## ✅ Checklist

- [ ] API key set in Cloudflare secrets
- [ ] R2_PUBLIC_URL set in Cloudflare secrets
- [ ] Test all 7 endpoints with your API key
- [ ] Update Flutter app with CloudflareService
- [ ] Replace Firebase endpoints with Cloudflare
- [ ] Test file uploads (PDF, JPG, PNG)
- [ ] Monitor costs in Cloudflare dashboard
- [ ] Set up alerts for unusual usage

---

## 🆘 Troubleshooting

### "Unauthorized" Error
```
Check that your Authorization header is correct:
Authorization: Bearer YOUR-ACTUAL-API-KEY
```

### "File type not allowed"
```
Allowed types: application/pdf, image/jpeg, image/png
Check the file MIME type
```

### "File size exceeds 20MB"
```
R2 has a 20MB limit per file
Split large files or compress them
```

### Files not accessible at files.lenv1.tech
```
1. Make sure R2_PUBLIC_URL secret is set correctly
2. Check that custom domain is active in Cloudflare
3. Wait 5-10 minutes for DNS propagation
```

---

## 📞 Next Steps

1. **Set Production API Key:**
   ```powershell
   npx wrangler secret put API_KEY
   ```

2. **Test with PowerShell:**
   ```powershell
   .\test-endpoints.ps1
   ```

3. **Integrate with Flutter:**
   - Copy CloudflareService class above
   - Replace YOUR-API-KEY with your actual key
   - Add to your app

4. **Monitor Usage:**
   - Visit https://dash.cloudflare.com/
   - Navigate to Workers → school-management-worker → Analytics
   - Check R2 → lenv-storage → Metrics

---

**🎉 You're all set! Start uploading files now!**
