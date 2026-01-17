#!/bin/bash

# Deploy Institute Announcement Auto-Delete Worker
# Cloudflare Worker that deletes announcements after 24 hours

echo "=================================================="
echo " Institute Announcement Auto-Delete Deployment"
echo " Using Cloudflare Workers (FREE)"
echo "=================================================="
echo ""

cd "$(dirname "$0")" || exit 1

# Check if Firebase API key is set
echo "📋 Checking configuration..."
if ! wrangler secret list --config wrangler-institute-cleanup.jsonc 2>/dev/null | grep -q "FIREBASE_API_KEY"; then
    echo ""
    echo "⚠️  FIREBASE_API_KEY not set!"
    echo ""
    echo "Get your API key from Firebase Console:"
    echo "  1. Go to: https://console.firebase.google.com/project/lenv-cb08e/settings/general"
    echo "  2. Scroll to 'Web API Key'"
    echo "  3. Copy the key"
    echo ""
    echo "Then set it using:"
    echo "  wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc"
    echo ""
    read -p "Do you want to set it now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc
    else
        echo "❌ Deployment cancelled. Set the API key first."
        exit 1
    fi
fi

echo "✅ Configuration verified"
echo ""

# Deploy the worker
echo "🚀 Deploying worker..."
echo ""
wrangler deploy --config wrangler-institute-cleanup.jsonc

if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "  ✅ DEPLOYMENT SUCCESSFUL!"
    echo "=================================================="
    echo ""
    echo "Worker Details:"
    echo "  Name: institute-announcement-cleanup"
    echo "  Schedule: Every 1 hour (0 * * * *)"
    echo "  Retention: 24 hours"
    echo ""
    echo "What it does:"
    echo "  ✅ Deletes announcements older than 24 hours"
    echo "  ✅ Removes all images from R2"
    echo "  ✅ Cleans up views subcollection"
    echo "  ✅ Complete removal from Firestore"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Test manual trigger:"
    echo "   curl -X POST https://institute-announcement-cleanup.YOUR_SUBDOMAIN.workers.dev"
    echo ""
    echo "2. Monitor logs:"
    echo "   wrangler tail --config wrangler-institute-cleanup.jsonc"
    echo ""
    echo "3. View in dashboard:"
    echo "   https://dash.cloudflare.com/"
    echo ""
    echo "Auto-delete is now ACTIVE! 🎉"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Check errors above."
    exit 1
fi
