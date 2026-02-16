#!/bin/bash

# Lenv Notification System - Automated Deployment Script
# This script deploys the complete notification system to Firebase

set -e  # Exit on any error

echo "================================================"
echo "  Lenv Notification System Deployment"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Check if we're in the right directory
echo -e "${BLUE}[1/6]${NC} Checking directory..."
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found. Are you in the Flutter project root?${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Directory check passed${NC}"
echo ""

# Step 2: Install Flutter dependencies
echo -e "${BLUE}[2/6]${NC} Installing Flutter dependencies..."
flutter pub get
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Flutter dependencies installed${NC}"
else
    echo -e "${RED}✗ Failed to install Flutter dependencies${NC}"
    exit 1
fi
echo ""

# Step 3: Check Firebase CLI
echo -e "${BLUE}[3/6]${NC} Checking Firebase CLI..."
if ! command -v firebase &> /dev/null; then
    echo -e "${YELLOW}Firebase CLI not found. Installing...${NC}"
    npm install -g firebase-tools
fi
echo -e "${GREEN}✓ Firebase CLI ready${NC}"
echo ""

# Step 4: Install Cloud Functions dependencies
echo -e "${BLUE}[4/6]${NC} Installing Cloud Functions dependencies..."
cd functions
if [ ! -d "node_modules" ]; then
    npm install
fi
cd ..
echo -e "${GREEN}✓ Cloud Functions dependencies installed${NC}"
echo ""

# Step 5: Deploy Cloud Functions
echo -e "${BLUE}[5/6]${NC} Deploying Cloud Functions..."
echo "This may take a few minutes..."

firebase deploy --only functions:sendChatNotification,functions:sendAssignmentNotification,functions:sendAnnouncementNotification,functions:cleanupOldNotifications

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Cloud Functions deployed successfully${NC}"
else
    echo -e "${RED}✗ Cloud Function deployment failed${NC}"
    exit 1
fi
echo ""

# Step 6: Deploy Firestore configuration
echo -e "${BLUE}[6/6]${NC} Deploying Firestore configuration..."

# Deploy indexes
echo "Deploying Firestore indexes..."
firebase deploy --only firestore:indexes

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Firestore indexes deployed${NC}"
else
    echo -e "${YELLOW}⚠ Firestore indexes deployment had issues (this is sometimes normal)${NC}"
fi

# Deploy rules
echo ""
echo -e "${YELLOW}Note: Firestore rules need to be manually updated${NC}"
echo "Please add the rules from FIRESTORE_NOTIFICATION_RULES.rules to your firestore.rules file"
echo "Then run: firebase deploy --only firestore:rules"
echo ""

# Summary
echo "================================================"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "================================================"
echo ""
echo "✅ Deployed Components:"
echo "   • Flutter packages installed"
echo "   • Cloud Functions (4 functions)"
echo "   • Firestore indexes"
echo ""
echo "⚠ Manual Steps Required:"
echo "   1. Update firestore.rules with notification rules"
echo "   2. Deploy rules: firebase deploy --only firestore:rules"
echo "   3. Run the app: flutter run"
echo "   4. Test notifications"
echo ""
echo "📚 Documentation:"
echo "   • Quick Start: NOTIFICATION_QUICK_START.md"
echo "   • Full Docs: NOTIFICATION_SYSTEM_DOCUMENTATION.md"
echo "   • Summary: NOTIFICATION_IMPLEMENTATION_SUMMARY.md"
echo ""
echo "🎉 Your notification system is ready to use!"
echo ""

# Optional: Build and run the app
echo -e "${BLUE}Would you like to build and run the app now? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Building and running the app..."
    flutter run
fi
