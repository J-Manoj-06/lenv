# Test Production Cloudflare Worker
# Usage: .\test-production.ps1

$workerUrl = "https://school-management-worker.giridharannj.workers.dev"
$apiKey = Read-Host "Enter your API key (from wrangler secret)"

Write-Host "`n🧪 Testing Production Worker" -ForegroundColor Cyan
Write-Host "URL: $workerUrl`n" -ForegroundColor Gray

# Test 1: Health Check
Write-Host "Test 1: Health Check (/status)" -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$workerUrl/status"
    Write-Host "✅ Status: OK" -ForegroundColor Green
    Write-Host "   Response: $($response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Announcement
Write-Host "`nTest 2: Post Announcement" -ForegroundColor Yellow
try {
    $body = @{
        title = "Test Announcement"
        message = "This is a test announcement from CloudflareWorker"
        targetAudience = "whole_school"
        standard = "10th"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$workerUrl/announcement" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } `
        -Body $body

    Write-Host "✅ Announcement Posted" -ForegroundColor Green
    Write-Host "   ID: $($response.id)" -ForegroundColor Gray
    Write-Host "   Created At: $($response.createdAt)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Group Message
Write-Host "`nTest 3: Post Group Message" -ForegroundColor Yellow
try {
    $body = @{
        groupId = "class_10a"
        senderId = "teacher_001"
        messageText = "Today we will learn about Cloud Storage"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$workerUrl/groupMessage" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } `
        -Body $body

    Write-Host "✅ Message Posted" -ForegroundColor Green
    Write-Host "   ID: $($response.id)" -ForegroundColor Gray
    Write-Host "   Group: $($response.groupId)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Schedule Test
Write-Host "`nTest 4: Schedule Test" -ForegroundColor Yellow
try {
    $body = @{
        classId = "10a"
        subject = "Mathematics"
        date = "2025-12-20"
        time = "10:00"
        duration = 60
        createdBy = "teacher_001"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$workerUrl/scheduleTest" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } `
        -Body $body

    Write-Host "✅ Test Scheduled" -ForegroundColor Green
    Write-Host "   ID: $($response.id)" -ForegroundColor Gray
    Write-Host "   Subject: $($response.subject)" -ForegroundColor Gray
    Write-Host "   Date: $($response.date)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Test File Upload (using curl)
Write-Host "`nTest 5: Upload File" -ForegroundColor Yellow
try {
    # Create a simple test file
    $testFile = "$env:TEMP\test-document.txt"
    "This is a test file for Cloudflare R2 upload" | Out-File $testFile -Encoding UTF8

    # Use curl for multipart upload
    $response = & curl -s -X POST "$workerUrl/uploadFile" `
      -H "Authorization: Bearer $apiKey" `
      -F "file=@$testFile" | ConvertFrom-Json

    Write-Host "✅ File Uploaded" -ForegroundColor Green
    Write-Host "   Name: $($response.fileName)" -ForegroundColor Gray
    Write-Host "   Size: $($response.size) bytes" -ForegroundColor Gray
    Write-Host "   URL: $($response.fileUrl)" -ForegroundColor Gray

    # Cleanup
    Remove-Item $testFile -Force

} catch {
    Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Signed URL
Write-Host "`nTest 6: Get Signed URL" -ForegroundColor Yellow
try {
    # Note: This will fail if no files are uploaded yet, which is expected
    $response = Invoke-RestMethod -Uri "$workerUrl/signedUrl?fileName=test-document.txt" `
        -Headers @{
            "Authorization" = "Bearer $apiKey"
        }

    Write-Host "✅ Signed URL Generated" -ForegroundColor Green
    Write-Host "   Expires In: $($response.expiresIn) seconds" -ForegroundColor Gray
    Write-Host "   URL: $($response.signedUrl.Substring(0, 50))..." -ForegroundColor Gray
} catch {
    # Signed URL endpoint might return 404 if file doesn't exist - that's OK
    if ($_.Exception.Response.StatusCode -eq "NotFound") {
        Write-Host "⚠️  Skipped: No files exist yet (expected on first run)" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n" -ForegroundColor Cyan
Write-Host "✅ All tests completed!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Check Cloudflare dashboard: https://dash.cloudflare.com/" -ForegroundColor Gray
Write-Host "2. View worker logs: npx wrangler tail" -ForegroundColor Gray
Write-Host "3. Monitor costs: Workers > Analytics" -ForegroundColor Gray
