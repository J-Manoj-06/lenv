#!/bin/bash

# Daily Challenge Worker Deployment Script
# Deploys Cloudflare Worker that fetches questions at 2 AM daily

echo "🚀 Daily Challenge Worker Deployment"
echo "===================================="
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ Wrangler CLI not found. Install it first:"
    echo "   npm install -g wrangler"
    exit 1
fi

cd cloudflare-worker

# Step 1: Set Firebase Service Account (only needed once)
echo "📝 Step 1: Configure Firebase Service Account"
echo "Have you already set FIREBASE_SERVICE_ACCOUNT secret? (y/n)"
read -r response

if [[ "$response" != "y" ]]; then
    echo ""
    echo "⚠️  You need to set the FIREBASE_SERVICE_ACCOUNT secret"
    echo ""
    echo "1. Get your Firebase service account JSON from:"
    echo "   https://console.firebase.google.com/project/_/settings/serviceaccounts"
    echo ""
    echo "2. Run this command and paste the entire JSON content:"
    echo "   wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-challenge.jsonc"
    echo ""
    echo "3. Then run this script again"
    exit 1
fi

# Step 2: Deploy worker
echo ""
echo "📦 Step 2: Deploying Daily Challenge Worker..."
echo ""

wrangler deploy --config wrangler-daily-challenge.jsonc

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Daily Challenge Worker deployed successfully!"
    echo ""
    echo "📋 Details:"
    echo "  - Worker Name: daily-challenge-worker"
    echo "  - Schedule: Every day at 2:00 AM IST (8:30 PM UTC)"
    echo "  - Firestore Collection: daily_challenges"
    echo "  - Difficulty Levels: easy (4-6), medium (7-10), hard (11-12)"
    echo ""
    echo "🧪 Test the worker manually:"
    echo "  curl -X POST https://daily-challenge-worker.YOUR_SUBDOMAIN.workers.dev"
    echo ""
    echo "📊 Monitor logs:"
    echo "  wrangler tail --config wrangler-daily-challenge.jsonc"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Check errors above."
    exit 1
fi
