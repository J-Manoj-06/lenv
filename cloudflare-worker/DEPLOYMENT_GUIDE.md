# 🚀 Deployment Guide - Cloudflare Worker

## Quick Start (5 minutes)

### Step 1: Install Wrangler CLI
```bash
npm install -g wrangler

# Or use npx (no global install)
npx wrangler --version
```

### Step 2: Authenticate
```bash
wrangler login
# Opens browser for Cloudflare login
```

### Step 3: Create R2 Bucket
```bash
# Production bucket
wrangler r2 bucket create school-files

# Development bucket
wrangler r2 bucket create school-files-preview
```

### Step 4: Set API Key
```bash
# Production API key
wrangler secret put API_KEY
# Enter: your-super-secure-api-key-12345

# Development API key (create .dev.vars file)
echo 'API_KEY="dev-test-key-12345"' > .dev.vars
```

### Step 5: Deploy
```bash
cd cloudflare-worker
npm install
npm run deploy
```

**✅ Done! Your worker is live at: `https://school-management-worker.YOUR-SUBDOMAIN.workers.dev`**

---

## Testing Your Deployment

### Test Health Check (No Auth)
```bash
curl https://school-management-worker.YOUR-SUBDOMAIN.workers.dev/status
```

Expected response:
```json
{"ok":true,"timestamp":1702223456789}
```

### Test File Upload (With Auth)
```bash
curl -X POST \
  -H "Authorization: Bearer your-super-secure-api-key-12345" \
  -F "file=@test.pdf" \
  https://school-management-worker.YOUR-SUBDOMAIN.workers.dev/uploadFile
```

Expected response:
```json
{
  "fileUrl": "https://your-r2-domain.com/1702223456789_test.pdf",
  "fileName": "1702223456789_test.pdf",
  "size": 1048576,
  "mime": "application/pdf"
}
```

### Test Announcement (With Auth)
```bash
curl -X POST \
  -H "Authorization: Bearer your-super-secure-api-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","message":"Hello","targetAudience":"whole_school"}' \
  https://school-management-worker.YOUR-SUBDOMAIN.workers.dev/announcement
```

---

## Custom Domain Setup (Optional but Recommended)

### Why Use Custom Domain?
- Professional URL: `api.yourschool.com` instead of `worker.workers.dev`
- Custom R2 domain: `files.yourschool.com`
- Better branding and trust

### Step 1: Add Worker Route
```bash
# In Cloudflare dashboard:
# 1. Go to your domain
# 2. Workers Routes > Add Route
# 3. Route: api.yourschool.com/*
# 4. Worker: school-management-worker
```

### Step 2: Configure R2 Custom Domain
```bash
# In Cloudflare dashboard:
# 1. R2 > school-files > Settings
# 2. Custom Domains > Connect Domain
# 3. Enter: files.yourschool.com
```

### Update Worker Code
Replace in `src/index.ts`:
```typescript
// Before
fileUrl: `https://your-r2-domain.com/${fileName}`

// After
fileUrl: `https://files.yourschool.com/${fileName}`
```

Redeploy:
```bash
npm run deploy
```

---

## Environment Variables & Secrets

### Development (.dev.vars file)
```bash
# Create .dev.vars for local testing
cat > .dev.vars << EOF
API_KEY="dev-test-key-12345"
R2_PUBLIC_URL="https://dev-files.yourschool.com"
EOF
```

### Production (Secrets)
```bash
# Set production secrets
wrangler secret put API_KEY
wrangler secret put R2_PUBLIC_URL
```

### Environment Variables (wrangler.toml)
```toml
[vars]
ENVIRONMENT = "production"
MAX_FILE_SIZE = 20971520
```

---

## CI/CD Setup (GitHub Actions)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy Worker

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: |
          cd cloudflare-worker
          npm install
      
      - name: Deploy to Cloudflare
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          workingDirectory: cloudflare-worker
```

### Setup GitHub Secrets
1. Get API Token from Cloudflare:
   - Dashboard > My Profile > API Tokens
   - Create Token > Edit Cloudflare Workers template
   - Copy token

2. Add to GitHub:
   - Repo > Settings > Secrets > New repository secret
   - Name: `CLOUDFLARE_API_TOKEN`
   - Value: (paste token)

---

## Monitoring & Debugging

### Real-time Logs
```bash
# Tail production logs
wrangler tail

# Tail with filtering
wrangler tail --format pretty --status error
```

### Performance Metrics
```bash
# View in Cloudflare dashboard:
# Workers & Pages > school-management-worker > Metrics

# Key metrics to monitor:
# - Requests per second
# - CPU time (target: <10ms)
# - Errors per second
# - Success rate (target: >99.9%)
```

### Debug Mode
Add to your worker for debugging:
```typescript
console.log('Debug info:', { fileName, size, mime });
```

Then tail logs:
```bash
wrangler tail --format pretty
```

---

## Cost Optimization Checklist

✅ **Workers Free Tier**: 100,000 requests/day
- Monitor: Dashboard > Workers > Analytics
- Alert if approaching 100K/day limit

✅ **R2 Free Tier**: 10GB storage, 1M Class B operations/month
- Monitor: Dashboard > R2 > school-files > Metrics
- Alert if approaching limits

✅ **Optimize File Sizes**
```typescript
// Add image compression before upload (in Flutter app)
if (file.size > 5 * 1024 * 1024) { // 5MB
  compressImage(file);
}
```

✅ **Cache Frequently Accessed Files**
```typescript
// Add cache headers to R2 objects
await env.R2_BUCKET.put(fileName, file.stream(), {
  httpMetadata: {
    contentType: file.type,
    cacheControl: 'public, max-age=31536000' // 1 year
  }
});
```

✅ **Use Signed URLs for Private Files**
```typescript
// Don't make bucket public, use signed URLs instead
const signedUrl = await env.R2_BUCKET.createSignedUrl(fileName, 3600);
```

---

## Rollback Plan

### If Deployment Fails
```bash
# View deployment history
wrangler deployments list

# Rollback to previous version
wrangler rollback
```

### If Issues in Production
```bash
# Quick rollback
wrangler rollback

# Or deploy previous version
git checkout previous-commit
npm run deploy
```

### Emergency: Keep Firebase Functions
Keep Firebase Functions running during migration:
1. Deploy Cloudflare Worker
2. Test thoroughly with small user group
3. Gradually migrate traffic
4. Monitor for 48 hours
5. Decommission Firebase Functions

---

## Troubleshooting

### Error: "API Key not found"
```bash
# Verify secret is set
wrangler secret list

# Reset secret
wrangler secret put API_KEY
```

### Error: "R2 bucket not found"
```bash
# List buckets
wrangler r2 bucket list

# Create if missing
wrangler r2 bucket create school-files
```

### Error: "Authorization failed"
- Check API key in request headers
- Verify Bearer token format: `Bearer YOUR_KEY`
- Check .dev.vars for local testing

### Error: "File too large"
- Increase MAX_FILE_SIZE in worker
- Or compress files client-side before upload

### Error: "CORS blocked"
- CORS headers are already configured
- Check browser console for actual error
- Verify request method matches handler

---

## Performance Benchmarks

### Target Metrics
- **Cold Start**: 0ms (Workers have no cold starts)
- **Avg Response Time**: <50ms globally
- **P99 Latency**: <100ms
- **CPU Time**: <10ms per request
- **Success Rate**: >99.9%

### Load Testing
```bash
# Install artillery
npm install -g artillery

# Create load-test.yml
cat > load-test.yml << EOF
config:
  target: "https://school-management-worker.YOUR-SUBDOMAIN.workers.dev"
  phases:
    - duration: 60
      arrivalRate: 100
scenarios:
  - flow:
      - get:
          url: "/status"
EOF

# Run load test
artillery run load-test.yml
```

---

## Security Hardening

### 1. Rate Limiting (via Cloudflare)
```toml
# Add to wrangler.toml
[limits]
# 1000 requests per minute per IP
rate_limit = { requests = 1000, period = 60 }
```

### 2. IP Allowlisting (Optional)
```typescript
// Add to authenticate() function
const allowedIPs = ['203.0.113.1', '203.0.113.2'];
const clientIP = request.headers.get('CF-Connecting-IP');
if (!allowedIPs.includes(clientIP)) {
  return errorResponse('IP not allowed', 403);
}
```

### 3. Request Size Limits
```typescript
// Already implemented for files (20MB)
// Add for JSON payloads:
const contentLength = request.headers.get('Content-Length');
if (contentLength && parseInt(contentLength) > 1024 * 1024) { // 1MB
  return errorResponse('Payload too large', 413);
}
```

### 4. Rotate API Keys Monthly
```bash
# Generate new key
openssl rand -base64 32

# Update secret
wrangler secret put API_KEY

# Update in Flutter app config
```

---

## Next Steps After Deployment

1. ✅ Test all endpoints with Postman/curl
2. ✅ Update Flutter app to use new API
3. ✅ Monitor logs for 24 hours
4. ✅ Set up alerts for errors
5. ✅ Document new endpoints for team
6. ✅ Train team on new infrastructure
7. ✅ Decommission Firebase Functions (after 7 days)

**🎉 Congratulations! Your cost-optimized backend is live!**
