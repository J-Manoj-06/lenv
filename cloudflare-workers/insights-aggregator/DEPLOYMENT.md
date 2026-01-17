# 🚀 Cloudflare Worker Deployment Guide
## Institute Insights Aggregator

This replaces Firebase Cloud Functions (which need paid subscription) with free Cloudflare Workers.

---

## 📋 Prerequisites

1. **Cloudflare Account** (Free tier works!)
   - Sign up at https://dash.cloudflare.com/sign-up

2. **Wrangler CLI** (Cloudflare's deployment tool)
   ```bash
   npm install -g wrangler
   ```

3. **Firebase Service Account Key**
   - Go to Firebase Console → Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file (you'll need it)

---

## 🔧 Setup Steps

### 1. Install Dependencies
```bash
cd cloudflare-workers/insights-aggregator
npm install
```

### 2. Login to Cloudflare
```bash
wrangler login
```
This opens a browser to authenticate.

### 3. Set Firebase Credentials
```bash
# Copy your Firebase service account JSON content
wrangler secret put FIREBASE_SERVICE_ACCOUNT
```

When prompted, paste the **entire JSON content** from your Firebase service account file:
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com",
  ...
}
```

### 4. Deploy Worker
```bash
npm run deploy
```

Output should show:
```
✅ Uploaded insights-aggregator
✅ Published insights-aggregator
   https://insights-aggregator.your-subdomain.workers.dev
```

### 5. Verify Deployment
```bash
# Check worker status
wrangler deployments list

# View logs in real-time
wrangler tail
```

---

## ⏰ Cron Schedule

The worker runs **automatically daily at 2:00 AM IST** (8:30 PM UTC).

Schedule is configured in `wrangler.toml`:
```toml
[triggers]
crons = ["30 20 * * *"]  # 8:30 PM UTC = 2:00 AM IST
```

To change timing:
1. Edit `wrangler.toml`
2. Run `npm run deploy` again

**Cron Syntax:** `minute hour day month day-of-week`

Examples:
- `0 2 * * *` = 2:00 AM UTC daily
- `0 */6 * * *` = Every 6 hours
- `0 0 * * 0` = Every Sunday at midnight

---

## 🧪 Manual Testing

### Test All Aggregations
```bash
curl https://insights-aggregator.your-subdomain.workers.dev/aggregate-all
```

### Test Individual Functions
```bash
# Top performers only
curl https://insights-aggregator.your-subdomain.workers.dev/aggregate-top-performers

# Teacher stats only
curl https://insights-aggregator.your-subdomain.workers.dev/aggregate-teacher-stats

# Metrics only
curl https://insights-aggregator.your-subdomain.workers.dev/aggregate-metrics
```

### View Real-Time Logs
```bash
wrangler tail
```
Then trigger a manual run to see logs.

---

## 📊 Verify Data in Firestore

After running aggregation, check these collections in Firebase Console:

1. **insights_top_performers**
   - Documents: `{schoolCode}_{range}` (e.g., `SCH001_7d`)
   - Should contain: standards array with top3 students

2. **insights_top_performers_full**
   - Documents: `{schoolCode}_{range}_STD{standard}` (e.g., `SCH001_7d_STD6`)
   - Contains full ranking for standard

3. **insights_teacher_stats**
   - Documents: `{schoolCode}_{range}` (e.g., `SCH001_30d`)
   - Contains teacher test counts and class splits

4. **insights_teacher_tests**
   - Documents: `{schoolCode}_{range}_{teacherId}`
   - Contains recent tests for each teacher

5. **insights_metrics**
   - Documents: `{schoolCode}_{range}_{scopeKey}` (e.g., `SCH001_7d_school`)
   - Contains aggregated metrics for AI analysis

---

## 🔄 Update Deployment

When you make changes to the worker:

```bash
cd cloudflare-workers/insights-aggregator
npm run deploy
```

No need to re-add secrets, they persist across deployments.

---

## 💰 Costs

**Cloudflare Workers Free Tier:**
- ✅ **100,000 requests/day** - FREE
- ✅ **Cron triggers** - FREE
- ✅ **Unlimited deployments** - FREE

**Your usage:** ~3 requests/day (one per school if you have 1 school)

**Result:** COMPLETELY FREE ✨

---

## 🐛 Troubleshooting

### Issue: "Error: Firebase credentials not found"
**Solution:** Re-add the secret:
```bash
wrangler secret put FIREBASE_SERVICE_ACCOUNT
```

### Issue: "Worker deployment failed"
**Solution:** Check you're logged in:
```bash
wrangler whoami
wrangler login
```

### Issue: "No data appearing in Firestore"
**Solutions:**
1. Check worker logs: `wrangler tail`
2. Manually trigger: `curl https://your-worker.workers.dev/aggregate-all`
3. Verify Firebase credentials are correct
4. Check you have test_results data in Firestore

### Issue: "Cron not running"
**Solution:** View cron status:
```bash
wrangler deployments list
```
Check "Triggers" section shows your cron schedule.

---

## 📝 Firestore Index Requirements

The worker needs these composite indexes. Firebase will prompt you to create them automatically when queries fail, or add manually:

1. `test_results`:
   - Fields: `schoolCode` (Ascending), `completedAt` (Ascending)
   
2. `test_results`:
   - Fields: `schoolCode` (Ascending), `standard` (Ascending), `completedAt` (Ascending)
   
3. `test_results`:
   - Fields: `schoolCode` (Ascending), `standard` (Ascending), `section` (Ascending), `completedAt` (Ascending)
   
4. `tests`:
   - Fields: `schoolCode` (Ascending), `publishedAt` (Ascending)

5. `attendance`:
   - Fields: `schoolCode` (Ascending), `date` (Ascending)

**To add indexes:**
1. Go to Firebase Console → Firestore Database → Indexes
2. Click "Add Index"
3. Add fields as specified above
4. Click "Create Index"

Or wait for automatic prompts in worker logs.

---

## ✅ Verification Checklist

After deployment:
- [ ] Worker deployed successfully (`wrangler deployments list`)
- [ ] Cron trigger configured (check wrangler.toml)
- [ ] Firebase secret added (`wrangler secret list` shows FIREBASE_SERVICE_ACCOUNT)
- [ ] Manual test successful (`curl .../aggregate-all`)
- [ ] Firestore collections populated (check Firebase Console)
- [ ] Flutter app shows data in insights page
- [ ] Logs show no errors (`wrangler tail`)

---

## 🎯 What This Does

**Before (without aggregation):**
- Every insights page load → 1000+ Firestore reads
- Slow loading (2-3 seconds)
- High Firebase costs

**After (with this worker):**
- Insights page load → 3-6 Firestore reads only
- Fast loading (<500ms)
- Near-zero Firebase costs
- Data refreshes daily automatically

---

## 🔗 Useful Commands

```bash
# Deploy worker
npm run deploy

# View logs in real-time
npm run tail

# Test locally
npm run dev

# List all deployments
wrangler deployments list

# View secrets
wrangler secret list

# Delete a secret
wrangler secret delete FIREBASE_SERVICE_ACCOUNT

# View worker details
wrangler whoami
```

---

You're all set! 🎉

The worker will now:
1. ✅ Run automatically every day at 2 AM IST
2. ✅ Aggregate data for all schools
3. ✅ Update Firestore with cached results
4. ✅ Keep your insights page fast and cheap
