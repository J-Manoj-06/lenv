#!/bin/bash

# Deploy Teacher Announcement Auto-Delete Cloud Function
# This function automatically deletes teacher announcements after 24 hours
# including all images from Cloudflare R2 and metadata from Firebase

echo "🚀 Deploying Teacher Announcement Auto-Delete Cloud Function..."
echo ""
echo "This function will:"
echo "  ✅ Delete expired teacher announcements (class_highlights collection)"
echo "  ✅ Delete all images from Cloudflare R2 (imageCaptions array + legacy imageUrl)"
echo "  ✅ Delete metadata from Firebase Firestore"
echo "  ✅ Run automatically every 1 hour"
echo ""

# Check if .env file exists in functions directory
if [ ! -f "functions/.env" ]; then
    echo "❌ Error: functions/.env file not found"
    echo "Please create functions/.env with the following variables:"
    echo "  CLOUDFLARE_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com"
    echo "  CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key_id"
    echo "  CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_access_key"
    echo "  CLOUDFLARE_R2_BUCKET_NAME=your_bucket_name"
    exit 1
fi

echo "📦 Installing dependencies..."
cd functions
npm install @aws-sdk/client-s3
cd ..

echo ""
echo "🔧 Deploying Cloud Functions..."
firebase deploy --only functions:deleteExpiredTeacherAnnouncements,functions:deleteExpiredTeacherAnnouncementsManual

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment successful!"
    echo ""
    echo "📋 Summary:"
    echo "  Function Name: deleteExpiredTeacherAnnouncements"
    echo "  Schedule: Every 1 hour"
    echo "  Region: us-central1"
    echo "  Collection: class_highlights"
    echo "  Storage: Cloudflare R2"
    echo ""
    echo "🧪 Test the function manually:"
    echo "  1. Go to Firebase Console > Functions"
    echo "  2. Find 'deleteExpiredTeacherAnnouncementsManual'"
    echo "  3. Click 'Test' to run a manual cleanup"
    echo ""
    echo "📊 Monitor the function:"
    echo "  View logs: firebase functions:log --only deleteExpiredTeacherAnnouncements"
    echo ""
else
    echo ""
    echo "❌ Deployment failed!"
    echo "Please check the error messages above and try again."
    exit 1
fi
