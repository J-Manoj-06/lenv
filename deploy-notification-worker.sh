#!/bin/bash

# Deploy Lenv Notification Worker to Cloudflare
# This worker handles push notifications via FCM

echo "================================================"
echo "  Deploying Lenv Notification Worker"
echo "================================================"
echo ""

cd cloudflare-worker

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Deploy the worker
echo "Deploying notification worker..."
npx wrangler deploy --config wrangler-notification.jsonc

echo ""
echo "================================================"
echo "  Deployment Complete!"
echo "================================================"
echo ""
echo "Your notification worker is now live!"
echo ""
echo "Next steps:"
echo "1. Set environment variables in Cloudflare dashboard:"
echo "   - FIREBASE_PROJECT_ID"
echo "   - FIREBASE_SERVICE_ACCOUNT (base64 encoded)"
echo "   - FIRESTORE_DATABASE_URL"
echo ""
echo "2. Update your Flutter app to call this worker endpoint"
echo "   instead of Firebase Functions"
echo ""
echo "3. Test notifications with:"
echo "   curl -X POST https://your-worker.workers.dev/notify \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"type\": \"chat\", ...}'"
echo ""
