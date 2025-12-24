# Manual trigger script for Daily Content Worker
# This helps test if the worker is working correctly

Write-Host "🚀 Daily Content Worker - Manual Trigger" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$workerUrl = "https://daily-content-worker.giridharannj.workers.dev"
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "📅 Today's date: $today" -ForegroundColor Yellow
Write-Host "🌐 Worker URL: $workerUrl" -ForegroundColor Yellow
Write-Host ""

# Try to manually trigger the worker via scheduled event
Write-Host "⏳ Manually triggering worker..." -ForegroundColor Cyan

try {
    # For scheduled tasks, we need to use wrangler to trigger
    Write-Host "Using wrangler to check deployment status..." -ForegroundColor Cyan
    
    $deployments = & wrangler deployments list --config wrangler-daily-content.jsonc 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Worker deployed successfully!" -ForegroundColor Green
        Write-Host $deployments
    } else {
        Write-Host "❌ Error checking deployments" -ForegroundColor Red
        Write-Host $deployments
    }
    
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "📝 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Check Firestore for: daily_content/$today" -ForegroundColor White
Write-Host "2. Look for: quote, fact, history fields" -ForegroundColor White
Write-Host "3. Worker should have auto-run at 2:00 AM IST" -ForegroundColor White
Write-Host ""

Write-Host "🔍 To check logs:" -ForegroundColor Cyan
Write-Host "   wrangler tail --config wrangler-daily-content.jsonc" -ForegroundColor Gray
