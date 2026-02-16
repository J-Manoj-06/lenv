#!/bin/bash

echo "================================================"
echo "  Encode Firebase Service Account"
echo "================================================"
echo

# Check if service account file exists
if [ ! -f "firebase-service-account.json" ]; then
  echo "❌ Error: firebase-service-account.json not found!"
  echo "   Please download it from Firebase Console:"
  echo "   1. Go to Project Settings > Service Accounts"
  echo "   2. Click 'Generate new private key'"
  echo "   3. Save as firebase-service-account.json in this directory"
  exit 1
fi

echo "✅ Found service account file"
echo

# Base64 encode the file
ENCODED=$(cat firebase-service-account.json | base64 -w 0)

echo "================================================"
echo "  Encoded Service Account (copy this value)"
echo "================================================"
echo
echo "$ENCODED"
echo
echo "================================================"
echo "  Next Steps"
echo "================================================"
echo
echo "1. Go to Cloudflare Dashboard:"
echo "   https://dash.cloudflare.com/"
echo
echo "2. Navigate to:"
echo "   Workers & Pages > lenv-notification-worker > Settings > Variables"
echo
echo "3. Add these environment variables:"
echo
echo "   FIREBASE_PROJECT_ID"
echo "   Value: $(jq -r .project_id firebase-service-account.json 2>/dev/null || echo '[your-project-id]')"
echo
echo "   FIREBASE_SERVICE_ACCOUNT"
echo "   Value: [paste the encoded value above]"
echo
echo "   FIRESTORE_DATABASE_URL"
echo "   Value: https://firestore.googleapis.com"
echo
echo "4. Save changes and your worker will restart automatically"
echo
