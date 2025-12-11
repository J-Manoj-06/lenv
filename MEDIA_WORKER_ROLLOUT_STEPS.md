# Media Worker Rollout Steps (One-Worker, Free-Egress)

## Prereqs (no new bucket)
- Bucket: **lenv-storage** (already exists)
- Worker: **whatsapp-media-worker** (single worker)
- Bindings in `cloudflare-worker/wrangler-media.jsonc`:
  - `MEDIA_BUCKET` → `lenv-storage`
  - `MEDIA_METADATA` → KV namespace ID (paste your actual ID)
- Custom domain: `files.lenv1.tech` must point to the Worker (not the bucket).

## 1) Update wrangler-media.jsonc
- Open `cloudflare-worker/wrangler-media.jsonc` and set:
  - `kv_namespaces[0].id` = your MEDIA_METADATA KV ID.
  - (Optional) `vars.ADMIN_TOKEN` = a strong bearer token (for /admin/cleanup).

## 2) Deploy the Worker
```powershell
cd d:\new_reward\cloudflare-worker
npm install   # first time only
npm run deploy  # uses wrangler-media.jsonc
```

## 3) Bind the custom domain to the Worker
In Cloudflare Dashboard:
1. Workers & Pages → **whatsapp-media-worker** → **Triggers** → **Add Route**.
2. Route: `files.lenv1.tech/*` (or `files.lenv1.tech/media/*` if you prefer scoped).
3. Select **whatsapp-media-worker**. Save.

## 4) Verify free-egress path
```powershell
curl -I https://files.lenv1.tech/media/test-key-that-exists
```
- Expect `200` and headers from the Worker (Cache-Control, ETag). No redirects to r2.dev or r2.cloudflarestorage.com.

## 5) Client/config checks
- Flutter/Dart: `CloudflareConfig.r2Domain` should be `files.lenv1.tech`.
- All public URLs must be `https://files.lenv1.tech/media/{key}` (no pub-*.r2.dev, no *.r2.cloudflarestorage.com).

## 6) Upload flow (unchanged)
- Uploads still use R2 S3 API (signed PUT) via the app/backend.
- The Worker is only for public GET (and optional POST /upload).

## 7) Expiry/cleanup
- Scheduled cron runs daily (per wrangler-media.jsonc).
- Optional on-demand cleanup:
  ```powershell
  curl -X POST https://files.lenv1.tech/admin/cleanup -H "Authorization: Bearer <ADMIN_TOKEN>"
  ```

## 8) Smoke tests
1. Upload an image/PDF (app/backend) → confirm 200 upload.
2. Open `https://files.lenv1.tech/media/{key}` → should render/download (200) with Worker headers.
3. Try a missing key → 404; expired/deleted → 410.

## 9) Roll-forward checklist
- KV ID set in wrangler-media.jsonc
- Worker deployed
- Domain route added to Worker
- App config uses `files.lenv1.tech`
- Test download returns 200 via Worker

## 10) Rollback (if needed)
- Remove the route from `files.lenv1.tech` to the Worker.
- Re-point to prior serving mechanism (if any). Note: this will reintroduce egress costs if using direct bucket URLs.
