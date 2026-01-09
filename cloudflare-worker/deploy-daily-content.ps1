# Daily Content Worker Deployment Script
# Run this from cloudflare-worker directory

Write-Host "🚀 Daily Content Worker - Build & Deploy" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if TypeScript is installed
Write-Host "📦 Step 1/5: Checking TypeScript..." -ForegroundColor Yellow
$tscVersion = & tsc --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ TypeScript not found. Installing globally..." -ForegroundColor Red
    npm install -g typescript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to install TypeScript. Please run: npm install -g typescript" -ForegroundColor Red
        exit 1
    }
}
Write-Host "✅ TypeScript installed: $tscVersion" -ForegroundColor Green
Write-Host ""

# Step 2: Compile worker
Write-Host "🔨 Step 2/5: Compiling worker..." -ForegroundColor Yellow
tsc --project tsconfig-daily.json
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Compilation failed. Check errors above." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Worker compiled successfully" -ForegroundColor Green
Write-Host ""

# Step 3: Check if secret is set
Write-Host "🔐 Step 3/5: Checking Firebase service account secret..." -ForegroundColor Yellow
$secrets = & wrangler secret list --config wrangler-daily-content.jsonc 2>&1 | Out-String
if ($secrets -notmatch "FIREBASE_SERVICE_ACCOUNT") {
    Write-Host "⚠️  FIREBASE_SERVICE_ACCOUNT secret not found!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please set it now:" -ForegroundColor Cyan
    Write-Host "  wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-content.jsonc" -ForegroundColor White
    Write-Host ""
    $response = Read-Host "Set secret now? (y/n)"
    if ($response -eq "y") {
        wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-content.jsonc
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to set secret. Aborting." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "❌ Secret required for deployment. Aborting." -ForegroundColor Red
        exit 1
    }
}
Write-Host "✅ Secret configured" -ForegroundColor Green
Write-Host ""

# Step 4: Deploy worker
Write-Host "🚀 Step 4/5: Deploying to Cloudflare..." -ForegroundColor Yellow
wrangler deploy --config wrangler-daily-content.jsonc
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed. Check errors above." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Worker deployed successfully!" -ForegroundColor Green
Write-Host ""

# Step 5: Test deployment
Write-Host "🧪 Step 5/5: Testing worker..." -ForegroundColor Yellow
Write-Host "Triggering manual fetch (this may take 10-15 seconds)..." -ForegroundColor Cyan

# Get worker URL from wrangler output
$workerUrl = & wrangler deployments list --config wrangler-daily-content.jsonc 2>&1 | 
    Select-String -Pattern "https://.*\.workers\.dev" | 
    ForEach-Object { $_.Matches[0].Value } | 
    Select-Object -First 1

if ($workerUrl) {
    Write-Host "Worker URL: $workerUrl" -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri $workerUrl -Method POST -TimeoutSec 30
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Worker test successful!" -ForegroundColor Green
            Write-Host "Response: $($response.Content)" -ForegroundColor White
        }
    } catch {
        Write-Host "⚠️  Worker deployed but test failed (this is normal on first run)" -ForegroundColor Yellow
        Write-Host "Error: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  Could not determine worker URL. Check manually in Cloudflare Dashboard." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🎉 Deployment Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Check Firestore: firebase.google.com/console" -ForegroundColor White
Write-Host "   Look for collection: daily_content" -ForegroundColor White
Write-Host "   Document: $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor White
Write-Host ""
Write-Host "2. Deploy security rules:" -ForegroundColor White
Write-Host "   cd .." -ForegroundColor Gray
Write-Host "   firebase deploy --only firestore:rules" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Test Flutter app:" -ForegroundColor White
Write-Host "   flutter pub get" -ForegroundColor Gray
Write-Host "   flutter run" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Monitor logs:" -ForegroundColor White
Write-Host "   wrangler tail --config wrangler-daily-content.jsonc" -ForegroundColor Gray
Write-Host ""
Write-Host "📚 Full documentation: DAILY_CONTENT_SYSTEM_COMPLETE.md" -ForegroundColor Cyan
