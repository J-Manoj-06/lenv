#!/bin/bash

# Test Daily Challenge Worker
# Manually triggers the worker to fetch and store questions

echo "🧪 Testing Daily Challenge Worker"
echo "================================="
echo ""

cd cloudflare-worker

echo "📦 Step 1: Deploying worker (if not already deployed)..."
wrangler deploy --config wrangler-daily-challenge.jsonc

echo ""
echo "🚀 Step 2: Manually triggering worker..."
echo ""

# Get worker URL (adjust YOUR_SUBDOMAIN to your actual subdomain)
echo "Enter your Cloudflare worker subdomain (e.g., myproject):"
read -r subdomain

WORKER_URL="https://daily-challenge-worker.${subdomain}.workers.dev"

echo ""
echo "Triggering: $WORKER_URL"
echo ""

# Trigger worker
response=$(curl -s -w "\n%{http_code}" -X POST "$WORKER_URL")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

echo "Response:"
echo "$body"
echo ""

if [ "$http_code" -eq 200 ]; then
    echo "✅ SUCCESS! Worker executed successfully."
    echo ""
    echo "📋 Next steps:"
    echo "1. Check Firebase Console → Firestore Database"
    echo "2. Look for 'daily_challenges' collection"
    echo "3. Verify today's date document exists with 3 questions"
    echo ""
    echo "📊 Monitor real-time logs:"
    echo "   wrangler tail --config wrangler-daily-challenge.jsonc"
else
    echo "❌ FAILED with HTTP $http_code"
    echo ""
    echo "🔍 Debug steps:"
    echo "1. Check if FIREBASE_SERVICE_ACCOUNT secret is set"
    echo "2. Verify Firebase service account has Firestore write permissions"
    echo "3. Check worker logs: wrangler tail --config wrangler-daily-challenge.jsonc"
fi

echo ""
