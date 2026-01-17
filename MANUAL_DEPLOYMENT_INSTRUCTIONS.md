# Manual Deployment Instructions

## Firebase CLI Not Found

The `firebase` command is not available in your terminal. Here are the deployment options:

---

## Option 1: Install Firebase CLI (Recommended)

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Select your project
firebase use --add

# Deploy the functions
cd functions
npm run deploy
```

---

## Option 2: Deploy from Firebase Console

### Step 1: Install Firebase CLI (if needed)
```bash
sudo npm install -g firebase-tools
```

### Step 2: Deploy Functions
```bash
cd /home/manoj/Desktop/new_reward/functions
npm run deploy
```

---

## Option 3: Use VS Code Firebase Extension

1. Install "Firebase Explorer" extension in VS Code
2. Use the extension to deploy functions
3. Or use the integrated terminal with Firebase CLI

---

## Option 4: Deploy via GitHub Actions / CI/CD

If you're using version control, set up automatic deployment when pushing to main branch.

---

## What Needs to be Deployed

These new Cloud Functions:
- **deleteExpiredInstituteAnnouncements** (scheduled, runs hourly)
- **deleteExpiredInstituteAnnouncementsManual** (callable, manual trigger)

---

## Quick Check - Is Firebase CLI Installed?

```bash
firebase --version
```

If you see a version number, it's installed. If not, install it:

```bash
# For Linux
curl -sL https://firebase.tools | bash

# OR using npm
sudo npm install -g firebase-tools
```

---

## After Firebase CLI is Installed

Simply run:
```bash
cd /home/manoj/Desktop/new_reward
./deploy_institute_announcement_autodelete.sh
```

Or manually:
```bash
cd /home/manoj/Desktop/new_reward/functions
npm run deploy
```

---

## Alternative: Deploy All Functions

```bash
cd /home/manoj/Desktop/new_reward/functions
firebase deploy --only functions
```

---

## Files Are Ready ✅

All the code is written and ready. You just need to deploy it:

1. ✅ Cloud Function code: `functions/deleteExpiredInstituteAnnouncements.js`
2. ✅ Export in index.js: Updated
3. ✅ Package.json: Deploy script updated
4. ✅ Environment variables: Already in `.env`

**You only need to run the deployment command once Firebase CLI is available.**
