# Fix PDF 404 Error - Enable R2 Public Access

## Problem
PDFs upload successfully to R2 but return 404 when accessed:
```
✅ Upload: https://files.lenv1.tech/media/1765447663188/DepositOpeningReceipt_200013501.pdf
❌ Fetch: HTTP 404 (not found)
```

**Root Cause**: `files.lenv1.tech` domain is not connected to R2 bucket yet.

---

## Solution: Connect Custom Domain to R2

### Step 1: Enable R2 Public Access
1. Go to https://dash.cloudflare.com
2. Click **R2** in left sidebar
3. Click your bucket: **lenv-storage**
4. Click **Settings** tab
5. Scroll to **Public Access** section
6. Click **Allow Access**
7. Confirm the action

### Step 2: Connect Custom Domain
1. In same Settings tab, scroll to **Custom Domains**
2. Click **Connect Domain**
3. Enter: `files.lenv1.tech`
4. Click **Continue**
5. Cloudflare will automatically:
   - Create DNS records
   - Issue SSL certificate
   - Connect domain to bucket
6. Wait 1-2 minutes for DNS propagation

### Step 3: Test
```bash
# Should return your PDF (no 404)
curl -I https://files.lenv1.tech/media/1765447663188/DepositOpeningReceipt_200013501.pdf
```

Expected response:
```
HTTP/2 200
content-type: application/pdf
content-length: 21605
```

---

## Recommendation

Use the Worker domain for all public downloads:

```
https://files.lenv1.tech/media/{key}
```

Ensure `files.lenv1.tech` points to the Worker (not the bucket URL or pub-*.r2.dev). This keeps egress free because the Worker reads from R2 internally.

---

## Quick Test Commands

After enabling public access:

```bash
# Test PDF access
curl -I https://files.lenv1.tech/media/1765447663188/DepositOpeningReceipt_200013501.pdf

# If 404, check DNS:
nslookup files.lenv1.tech

# Should show Cloudflare IPs like:
# 104.18.x.x
# 172.64.x.x
```

---

## Summary

1. ✅ Upload is working perfectly (HTTP 200)
2. ❌ Download fails because domain not connected
3. ⏱️ Fix: Connect `files.lenv1.tech` to R2 bucket (2 minutes)
4. ✅ Then PDFs will be publicly accessible immediately

**No code changes needed** - just Cloudflare dashboard configuration.
