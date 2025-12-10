# Quick Test Script for Cloudflare Worker Endpoints
# Run this after starting 'npx wrangler dev'

$baseUrl = "http://localhost:8787"
$apiKey = "dev-school-api-key-12345-change-this"

Write-Host "🧪 Testing Cloudflare Worker Endpoints..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Health Check (No Auth)
Write-Host "1️⃣  Testing /status (no auth required)..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/status" -Method Get
    Write-Host "✅ Status: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: Create Announcement
Write-Host "2️⃣  Testing /announcement (with auth)..." -ForegroundColor Yellow
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type" = "application/json"
}
$body = @{
    title = "Test Announcement"
    message = "This is a test announcement from PowerShell"
    targetAudience = "whole_school"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$baseUrl/announcement" -Method Post -Headers $headers -Body $body
    Write-Host "✅ Announcement created: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 3: Schedule Test
Write-Host "3️⃣  Testing /scheduleTest (with auth)..." -ForegroundColor Yellow
$body = @{
    classId = "class-10a"
    subject = "Mathematics"
    date = "2025-12-15"
    time = "10:00"
    duration = 90
    createdBy = "teacher-123"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$baseUrl/scheduleTest" -Method Post -Headers $headers -Body $body
    Write-Host "✅ Test scheduled: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 4: Group Message
Write-Host "4️⃣  Testing /groupMessage (with auth)..." -ForegroundColor Yellow
$body = @{
    groupId = "group-123"
    senderId = "teacher-456"
    messageText = "Hello from PowerShell test!"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$baseUrl/groupMessage" -Method Post -Headers $headers -Body $body
    Write-Host "✅ Message sent: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Unauthorized Access
Write-Host "5️⃣  Testing auth protection (should fail)..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/announcement" -Method Post -Body $body
    Write-Host "❌ Auth should have blocked this!" -ForegroundColor Red
} catch {
    Write-Host "✅ Auth working correctly - request blocked" -ForegroundColor Green
}
Write-Host ""

Write-Host "🎉 Test complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Test file upload with a tool like Postman or curl"
Write-Host "  2. Set production API key: npx wrangler secret put API_KEY"
Write-Host "  3. Deploy: npx wrangler deploy"
