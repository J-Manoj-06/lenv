#!/bin/bash

# Institute Announcement Auto-Delete Deployment Script
# This script deploys the Cloud Functions for automatic 24-hour announcement deletion

echo "=================================================="
echo "  Institute Announcement Auto-Delete Deployment"
echo "=================================================="
echo ""

# Navigate to functions directory
cd "$(dirname "$0")/functions" || exit 1

echo "✅ Current directory: $(pwd)"
echo ""

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ ERROR: .env file not found!"
    echo ""
    echo "Please create .env file with these variables:"
    echo "CLOUDFLARE_R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com"
    echo "CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key"
    echo "CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_key"
    echo "CLOUDFLARE_R2_BUCKET_NAME=your_bucket_name"
    echo ""
    exit 1
fi

echo "✅ .env file found"
echo ""

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo ""
fi

echo "✅ Dependencies installed"
echo ""

# Deploy functions
echo "🚀 Deploying Cloud Functions..."
echo ""
echo "Functions being deployed:"
echo "  - generateQuestions"
echo "  - onScheduledTestCreate"
echo "  - uploadFileToR2"
echo "  - deleteExpiredAnnouncements"
echo "  - deleteExpiredMediaAnnouncements"
echo "  - deleteExpiredInstituteAnnouncements (NEW)"
echo "  - deleteExpiredInstituteAnnouncementsManual (NEW)"
echo ""

firebase deploy --only functions:generateQuestions,functions:onScheduledTestCreate,functions:uploadFileToR2,functions:deleteExpiredAnnouncements,functions:deleteExpiredMediaAnnouncements,functions:deleteExpiredInstituteAnnouncements,functions:deleteExpiredInstituteAnnouncementsManual

if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "  ✅ DEPLOYMENT SUCCESSFUL!"
    echo "=================================================="
    echo ""
    echo "Next steps:"
    echo "1. Verify functions are deployed:"
    echo "   firebase functions:list | grep deleteExpiredInstitute"
    echo ""
    echo "2. Monitor the scheduled function (runs every hour):"
    echo "   firebase functions:log --only deleteExpiredInstituteAnnouncements --follow"
    echo ""
    echo "3. Test manual trigger:"
    echo "   firebase functions:call deleteExpiredInstituteAnnouncementsManual"
    echo ""
    echo "Auto-delete is now ACTIVE! Announcements will be deleted after 24 hours."
    echo ""
else
    echo ""
    echo "=================================================="
    echo "  ❌ DEPLOYMENT FAILED!"
    echo "=================================================="
    echo ""
    echo "Please check the error messages above and:"
    echo "1. Ensure you're logged in: firebase login"
    echo "2. Verify project is set: firebase use --add"
    echo "3. Check .env file has correct R2 credentials"
    echo ""
    exit 1
fi
