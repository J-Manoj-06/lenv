# 🚀 Quick Start - Cloudflare Worker Deployment

## ✅ What You Have

Your fully cost-optimized Cloudflare Worker is ready! Includes:

- **Ultra-fast API endpoints** (all 7 handlers)
- **R2 bucket integration** for file storage
- **TypeScript** with zero dependencies
- **Development server** ready to test
- **Interactive test UI** (test.html)

## 🎯 Next Steps (5 minutes)

### Step 1: Test Locally (2 minutes)

```powershell
# Start local dev server
npx wrangler dev
```

Wait for: `[wrangler:inf] Ready on http://localhost:8787`

Then in a **new terminal**, run:
```powershell
.\test-endpoints.ps1
```

You should see ✅ for all tests!

### Step 2: Set Production API Key (1 minute)

```powershell
# Generate secure API key (copy this output)
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})

# Set it as secret
npx wrangler secret put API_KEY
# Paste the key when prompted
```

### Step 3: Deploy to Production (2 minutes)

```powershell
npx wrangler deploy
```

**🎉 Done!** Your worker is live at:
```
https://school-management-worker.YOUR-SUBDOMAIN.workers.dev
```

---

## 🧪 Test Production Deployment

Copy your deployed URL and API key, then test:

```powershell
$url = "https://school-management-worker.YOUR-SUBDOMAIN.workers.dev"
$key = "YOUR-API-KEY"

# Test health check
Invoke-RestMethod -Uri "$url/status"

# Test announcement
Invoke-RestMethod -Uri "$url/announcement" `
  -Method Post `
  -Headers @{"Authorization"="Bearer $key"; "Content-Type"="application/json"} `
  -Body '{"title":"Test","message":"Hello","targetAudience":"whole_school"}'
```

---

## 📱 Integrate with Flutter

1. Open `FLUTTER_INTEGRATION.md`
2. Copy `CloudflareService` class
3. Update these values:
   ```dart
   static const String baseUrl = 'YOUR-WORKER-URL';
   static const String apiKey = 'YOUR-API-KEY';
   ```
4. Replace Firebase calls with Cloudflare calls

---

## 🔧 Troubleshooting

### "wrangler not found"
Use `npx wrangler` instead of `wrangler`

### "R2 bucket not found"
```powershell
npx wrangler r2 bucket create school-files
```

### "Unauthorized" error
Check API key in `.dev.vars` or set production secret:
```powershell
npx wrangler secret put API_KEY
```

### Dev server won't start
Close any other process on port 8787:
```powershell
Get-Process -Id (Get-NetTCPConnection -LocalPort 8787).OwningProcess | Stop-Process
```

---

## 📊 View Logs & Metrics

```powershell
# Real-time logs
npx wrangler tail

# View in dashboard
# https://dash.cloudflare.com/workers
```

---

## 💰 Cost Monitoring

**Free Tier Limits:**
- 100,000 requests/day (3M/month)
- 10GB R2 storage free
- 1M R2 read operations/month

**Check usage:**
- Dashboard: https://dash.cloudflare.com/
- R2 → `school-files` → Metrics
- Workers → `school-management-worker` → Analytics

---

## 🎯 Next Steps

1. [ ] Test all endpoints locally
2. [ ] Deploy to production
3. [ ] Test production endpoints
4. [ ] Integrate with Flutter app
5. [ ] Monitor for 24 hours
6. [ ] Migrate users gradually
7. [ ] Celebrate 95% cost savings! 🎉

---

**Need Help?**
- Check `README.md` for detailed docs
- Check `DEPLOYMENT_GUIDE.md` for advanced setup
- Check `FLUTTER_INTEGRATION.md` for app integration
