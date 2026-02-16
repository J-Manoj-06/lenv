#!/bin/bash

cd cloudflare-worker

echo "================================================"
echo "  Setting up Cloudflare Worker Environment"
echo "================================================"
echo

# Set project ID
echo "Setting FIREBASE_PROJECT_ID..."
echo "lenv-cb08e" | wrangler secret put FIREBASE_PROJECT_ID

echo
echo "Setting FIRESTORE_DATABASE_URL..."
echo "https://firestore.googleapis.com" | wrangler secret put FIRESTORE_DATABASE_URL

echo
echo "================================================"
echo "  Service Account Setup Required"
echo "================================================"
echo
echo "To set FIREBASE_SERVICE_ACCOUNT:"
echo
echo "1. Download service account from Firebase Console:"
echo "   https://console.firebase.google.com/project/lenv-cb08e/settings/serviceaccounts/adminsdk"
echo
echo "2. Click 'Generate new private key' and save as firebase-service-account.json"
echo
echo "3. Run this command:"
echo "   cat firebase-service-account.json | base64 -w 0 | wrangler secret put FIREBASE_SERVICE_ACCOUNT"
echo
echo "Or use Cloudflare Dashboard:"
echo "   https://dash.cloudflare.com/ > Workers > lenv-notification-worker > Settings > Variables"
echo
