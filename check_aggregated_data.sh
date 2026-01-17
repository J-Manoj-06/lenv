#!/bin/bash

echo "🔍 Checking aggregated insights data..."
echo ""

# Get Firebase project from google-services.json
PROJECT_ID=$(grep -o '"project_id": "[^"]*' google-services.json | cut -d'"' -f4)

if [ -z "$PROJECT_ID" ]; then
  echo "❌ Could not find project_id in google-services.json"
  exit 1
fi

echo "📦 Firebase Project: $PROJECT_ID"
echo ""

# Check if we have access token (would need gcloud auth)
echo "To check the actual Firestore data, please:"
echo "1. Go to Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID/firestore/databases/-default-/data/~2Finsights_top_performers"
echo "2. Look for documents: CSK100_7d, CSK100_30d, CSK100_monthly"
echo "3. Check if the 'standards' array has any data"
echo ""
echo "OR check via Worker logs by querying Firestore REST API:"
echo ""

# Alternative: Use the worker to fetch the data
echo "curl -s 'https://insights-aggregator.giridharannj.workers.dev/debug-data?schoolCode=CSK100&range=7d'"
