#!/bin/bash
# Daily Content Worker Deployment Script
# Run this from cloudflare-worker directory

echo "🚀 Daily Content Worker - Build & Deploy"
echo "========================================="
echo ""

# Step 1: Check TypeScript
echo "📦 Step 1/5: Checking TypeScript..."
if ! command -v tsc &> /dev/null; then
    echo "❌ TypeScript not found. Installing globally..."
    npm install -g typescript
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install TypeScript"
        exit 1
    fi
fi
echo "✅ TypeScript installed: $(tsc --version)"
echo ""

# Step 2: Compile
echo "🔨 Step 2/5: Compiling worker..."
tsc --project tsconfig-daily.json
if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi
echo "✅ Worker compiled"
echo ""

# Step 3: Check secret
echo "🔐 Step 3/5: Checking secret..."
if ! wrangler secret list --config wrangler-daily-content.jsonc 2>&1 | grep -q "FIREBASE_SERVICE_ACCOUNT"; then
    echo "⚠️  FIREBASE_SERVICE_ACCOUNT not set"
    echo ""
    read -p "Set secret now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-content.jsonc
        if [ $? -ne 0 ]; then
            echo "❌ Failed to set secret"
            exit 1
        fi
    else
        echo "❌ Secret required. Aborting."
        exit 1
    fi
fi
echo "✅ Secret configured"
echo ""

# Step 4: Deploy
echo "🚀 Step 4/5: Deploying..."
wrangler deploy --config wrangler-daily-content.jsonc
if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi
echo "✅ Deployed!"
echo ""

# Step 5: Test
echo "🧪 Step 5/5: Testing..."
WORKER_URL=$(wrangler deployments list --config wrangler-daily-content.jsonc 2>&1 | grep -oP 'https://.*?\.workers\.dev' | head -1)
if [ -n "$WORKER_URL" ]; then
    echo "Worker URL: $WORKER_URL"
    curl -X POST "$WORKER_URL" -w "\n"
fi

echo ""
echo "========================================="
echo "🎉 Deployment Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Check Firestore for daily_content collection"
echo "2. Deploy rules: firebase deploy --only firestore:rules"
echo "3. Test Flutter app: flutter run"
echo ""
echo "📚 See: DAILY_CONTENT_SYSTEM_COMPLETE.md"
