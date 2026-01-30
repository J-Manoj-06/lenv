#!/bin/bash

# DeepSeek AI Worker Deployment Script
# Deploys the secure Cloudflare Worker for DeepSeek API proxy

set -e  # Exit on error

echo "🚀 DeepSeek AI Worker Deployment"
echo "================================="
echo ""

# Navigate to cloudflare-worker directory
cd "$(dirname "$0")"

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ Wrangler CLI not found!"
    echo "📦 Install with: npm install -g wrangler"
    exit 1
fi

echo "✅ Wrangler CLI found"
echo ""

# Check if DEEPSEEK_API_KEY secret is set
echo "🔐 Checking API Key Secret..."
echo ""
echo "⚠️  IMPORTANT: Your DeepSeek API key must be configured as a Wrangler secret"
echo ""
read -p "Have you already set the DEEPSEEK_API_KEY secret? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "📝 Setting up DEEPSEEK_API_KEY secret..."
    echo ""
    echo "You'll be prompted to enter your DeepSeek API key"
    echo "Get your key from: https://platform.deepseek.com/api_keys"
    echo ""
    
    wrangler secret put DEEPSEEK_API_KEY --config wrangler-deepseek.jsonc
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to set API key secret"
        exit 1
    fi
    
    echo "✅ API key secret configured"
    echo ""
fi

# Deploy the worker
echo "📦 Deploying DeepSeek AI Worker..."
echo ""

wrangler deploy --config wrangler-deepseek.jsonc

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo ""
echo "✅ Deployment successful!"
echo ""
echo "🎉 DeepSeek AI Worker is now live!"
echo ""
echo "📍 Worker URL: https://deepseek-ai.YOUR_ACCOUNT.workers.dev"
echo ""
echo "🧪 Test your deployment:"
echo ""
echo "  # Health Check"
echo "  curl https://deepseek-ai.YOUR_ACCOUNT.workers.dev/health"
echo ""
echo "  # Test AI Request"
echo '  curl -X POST https://deepseek-ai.YOUR_ACCOUNT.workers.dev/chat \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{'
echo '      "model": "deepseek-chat",'
echo '      "messages": [{"role": "user", "content": "Say hello"}]'
echo '    }'"'"
echo ""
echo "📝 Next Steps:"
echo "  1. Test the health endpoint"
echo "  2. Test a chat request"
echo "  3. Update your Flutter app's worker URL if different from default"
echo "  4. Run your Flutter app and test AI features"
echo ""
echo "🔒 Security: Your API key is stored securely as a Wrangler secret"
echo "   and is never exposed in your code or to clients"
echo ""
