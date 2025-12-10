# 🚀 QUICK REFERENCE CARD

## Your Worker is Live! 
**URL:** `https://school-management-worker.giridharannj.workers.dev`

---

## ⚡ Quick Commands

### Set API Key (DO THIS FIRST!)
```powershell
npx wrangler secret put API_KEY
# Enter: xK9mP2nQ4rS6tU8vW0xY2zA4bC6dE8fG (or any secure key)
```

### Test Everything
```powershell
.\test-production.ps1
```

### Deploy Changes
```powershell
npm run build
npx wrangler deploy
```

### View Live Logs
```powershell
npx wrangler tail
```

---

## 📤 Upload File Example

**PowerShell:**
```powershell
$form = @{ file = Get-Item "C:\document.pdf" }
$response = Invoke-RestMethod -Uri "https://school-management-worker.giridharannj.workers.dev/uploadFile" `
  -Method Post `
  -Headers @{"Authorization"="Bearer YOUR-API-KEY"} `
  -Form $form
echo $response.fileUrl  # Returns: https://files.lenv1.tech/1733868900000_document.pdf
```

**JavaScript:**
```javascript
const form = new FormData();
form.append('file', fileInput.files[0]);

const response = await fetch(
  'https://school-management-worker.giridharannj.workers.dev/uploadFile',
  {
    method: 'POST',
    headers: {'Authorization': 'Bearer YOUR-API-KEY'},
    body: form
  }
);
const data = await response.json();
console.log(data.fileUrl);
```

**Flutter:**
```dart
final cloudflare = CloudflareService();
final fileUrl = await cloudflare.uploadFile('/path/to/file.pdf');
print('Uploaded: $fileUrl');
```

---

## 📋 All 7 Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/uploadFile` | POST | ✅ | Upload PDF/JPG/PNG |
| `/deleteFile` | POST | ✅ | Delete file |
| `/signedUrl` | GET | ✅ | Get temp access link |
| `/announcement` | POST | ✅ | Create announcement |
| `/groupMessage` | POST | ✅ | Send class message |
| `/scheduleTest` | POST | ✅ | Schedule test |
| `/status` | GET | ❌ | Health check |

---

## 🔐 Headers Required

All endpoints except `/status` need:
```
Authorization: Bearer YOUR-API-KEY
Content-Type: application/json
```

---

## 💾 File Limits

- **Max Size:** 20MB
- **Allowed Types:** PDF, JPG, PNG
- **Storage:** lenv-storage R2 bucket
- **URL Pattern:** `https://files.lenv1.tech/{timestamp}_{filename}`

---

## 🎯 Announcement Example

```bash
curl -X POST https://school-management-worker.giridharannj.workers.dev/announcement \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Assignment Due",
    "message": "Submit by Friday",
    "targetAudience": "whole_school",
    "standard": "10th",
    "fileUrl": "https://files.lenv1.tech/1733868900000_assignment.pdf"
  }'
```

---

## 👥 Group Message Example

```bash
curl -X POST https://school-management-worker.giridharannj.workers.dev/groupMessage \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "groupId": "class_10a",
    "senderId": "teacher_001",
    "messageText": "Todays lesson covers Cloud Storage",
    "fileUrl": "https://files.lenv1.tech/1733868900000_lesson.pdf"
  }'
```

---

## 📅 Schedule Test Example

```bash
curl -X POST https://school-management-worker.giridharannj.workers.dev/scheduleTest \
  -H "Authorization: Bearer YOUR-API-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "classId": "10a",
    "subject": "Mathematics",
    "date": "2025-12-20",
    "time": "10:00",
    "duration": 60,
    "createdBy": "teacher_001"
  }'
```

---

## 🧪 Health Check (No Auth!)

```bash
curl https://school-management-worker.giridharannj.workers.dev/status
# Returns: {"ok":true,"timestamp":"2025-12-10T12:45:00Z"}
```

---

## 📱 Flutter Service (Copy-Ready)

```dart
class CloudflareService {
  static const baseUrl = 'https://school-management-worker.giridharannj.workers.dev';
  static const apiKey = 'YOUR-API-KEY';
  
  final Dio _dio = Dio();

  Future<String> uploadFile(String path) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path),
    });
    final res = await _dio.post(
      '$baseUrl/uploadFile',
      data: form,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    return res.data['fileUrl'];
  }

  Future<Map> postAnnouncement({
    required String title,
    required String message,
    required String targetAudience,
    String? fileUrl,
  }) async {
    final res = await _dio.post(
      '$baseUrl/announcement',
      data: {'title': title, 'message': message, 'targetAudience': targetAudience, 'fileUrl': fileUrl},
      options: Options(headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'}),
    );
    return res.data;
  }
}
```

---

## 🔑 API Key Locations

✅ **Production Secret:** Set via `npx wrangler secret put API_KEY`  
✅ **Dev Secret:** In `.dev.vars` file  
✅ **Flutter App:** In CloudflareService class (or use Remote Config)

---

## 📊 Dashboard Links

- **Cloudflare:** https://dash.cloudflare.com/
- **Workers Analytics:** Workers → school-management-worker → Analytics
- **R2 Metrics:** R2 → lenv-storage → Metrics
- **Logs:** `npx wrangler tail`

---

## ⚠️ Common Errors & Fixes

| Error | Fix |
|-------|-----|
| `401 Unauthorized` | Check API key in Authorization header |
| `File type not allowed` | Use PDF, JPG, or PNG only |
| `File size exceeds 20MB` | Compress file or split into parts |
| `R2 bucket not found` | Bucket configured in wrangler.jsonc |
| `CORS error` | Check Origin header, worker allows all |

---

## 💰 Cost Check

```
100K requests/day = FREE
1GB storage = $0.015/month
1000 PDFs (1MB each) = ~$0.02/month

VS Firebase: 95% CHEAPER! 🎉
```

---

## ✅ Setup Checklist

- [ ] API key set: `npx wrangler secret put API_KEY`
- [ ] Test health: `curl https://...giridharannj.workers.dev/status`
- [ ] Test upload: `.\test-production.ps1`
- [ ] Copy CloudflareService to Flutter
- [ ] Update API key in Flutter
- [ ] Test file upload from app
- [ ] Monitor: https://dash.cloudflare.com/

---

**Ready to go! 🚀**

Upload your first file now! 📄
