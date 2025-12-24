# 📦 Daily Content Prefetch Worker

Cloudflare Worker that fetches daily content (quote, fact, history) once per day and stores it in Firestore.

## 🚀 Quick Deploy

### Windows
```powershell
.\deploy-daily-content.ps1
```

### Linux/Mac
```bash
chmod +x deploy-daily-content.sh
./deploy-daily-content.sh
```

## 📁 Files

- **src/daily-content-worker.ts** - Main worker logic
- **wrangler-daily-content.jsonc** - Configuration (cron schedule)
- **deploy-daily-content.ps1** - Windows deployment script
- **deploy-daily-content.sh** - Linux/Mac deployment script
- **tsconfig-daily.json** - TypeScript configuration

## ⏰ Schedule

Runs **daily at 2:00 AM Asia/Kolkata** (8:30 PM UTC)

Cron: `30 20 * * *`

## 🔑 Required Secret

```bash
wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-content.jsonc
```

Paste your Firebase service account JSON (entire content as one line).

## 🧪 Manual Test

```bash
# Trigger immediately
curl -X POST https://daily-content-worker.<account>.workers.dev
```

## 📊 Monitor

```bash
# View live logs
wrangler tail --config wrangler-daily-content.jsonc
```

## 📚 Documentation

- **Full Guide**: [../DAILY_CONTENT_SYSTEM_COMPLETE.md](../DAILY_CONTENT_SYSTEM_COMPLETE.md)
- **Quick Start**: [../DAILY_CONTENT_QUICKSTART.md](../DAILY_CONTENT_QUICKSTART.md)
- **Visual Guide**: [../DAILY_CONTENT_VISUAL_GUIDE.md](../DAILY_CONTENT_VISUAL_GUIDE.md)
- **Summary**: [../DAILY_CONTENT_IMPLEMENTATION_SUMMARY.md](../DAILY_CONTENT_IMPLEMENTATION_SUMMARY.md)

## ✅ Status

**Implementation**: Complete  
**Testing**: Ready  
**Production**: Ready to deploy
