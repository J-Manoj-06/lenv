# 📤 Uploading Rewards to Firestore

This guide shows how to upload your updated rewards JSON to the Firestore `rewards_catalog` collection.

## 🔧 Prerequisites

### 1. Install Node.js & Dependencies
```bash
# If you haven't installed Node.js yet, download from https://nodejs.org/
node --version  # Should be v14+
npm --version

# Install Firebase Admin SDK
npm install firebase-admin
```

### 2. Get Firebase Service Account Key
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Project Settings** → **Service Accounts**
4. Click **Generate New Private Key**
5. Save the JSON file

### 3. Create config Directory
```bash
mkdir -p config
# Place your service account JSON file in config/service-account-key.json
```

## 🚀 How to Upload

### Option 1: Run from Terminal (Recommended)
```bash
cd /home/manoj/Desktop/new_reward

# Run the upload script
node scripts/upload_rewards_to_firestore.js
```

### Option 2: Use npm script (if you have package.json)
Add to `package.json`:
```json
{
  "scripts": {
    "upload:rewards": "node scripts/upload_rewards_to_firestore.js"
  }
}
```

Then run:
```bash
npm run upload:rewards
```

## ✅ What the Script Does

1. **Reads** your `assets/dummy_rewards.json`
2. **Parses** individual JSON objects (even if they're not in a standard array format)
3. **Clears** existing data in Firestore `rewards_catalog` collection
4. **Uploads** each product with:
   - All product details (title, description, price, etc.)
   - Calculated `points_rule` if not provided
   - Server timestamp
5. **Reports** success/failure for each product

## 📊 Output Example

```
📦 Starting rewards upload to Firestore...

✅ Found 10 products to upload

🗑️  Clearing existing rewards_catalog collection...
✅ Deleted 5 existing documents

📤 Uploading products to Firestore...

✅ Uploaded: curioSprout Interactive Alphabet Activity Book (B0FQ337YM6)
✅ Uploaded: Btag Kids Premium Plush Bunny Earmuffs (B0GDQ99YG9)
...
============================================================
📊 Upload Summary:
✅ Successful: 10/10
❌ Failed: 0/10
============================================================

🎉 All rewards uploaded successfully!
✨ The rewards catalog is now live in Firestore.
```

## 🐛 Troubleshooting

### "Cannot find module 'firebase-admin'"
```bash
npm install firebase-admin
```

### "GOOGLE_APPLICATION_CREDENTIALS not set"
Make sure your service account JSON is in `config/service-account-key.json`

### "Permission denied" errors
Check your Firestore security rules allow admin writes to `rewards_catalog`

## 🔄 Verify Upload

### Option 1: Firebase Console
1. Go to Firebase Console
2. Navigate to **Firestore Database**
3. Check the `rewards_catalog` collection
4. Should see all your products listed

### Option 2: In Flutter App
1. Hot restart the app
2. Go to **Rewards Store** page
3. Should see your updated rewards

## 📝 Notes

- **First time?** The script will clear any existing data first
- **Subsequent runs?** Comment out the delete section if you want to merge instead of replace
- **Data format:** Supports both JSON array and individual objects
- **Auto-calculated points:** If `points_rule` is missing, defaults to 0.75 points per rupee

## 🆘 Need Help?

If products don't appear:
1. Check Firestore has the `rewards_catalog` collection
2. Verify products were uploaded (check the collection in Firebase Console)
3. Check `getCatalog()` in the repository is being called
4. Try force refresh: `getCatalog(forceRefresh: true)`

---

**Next Step:** After uploading, the rewards should automatically fetch from Firestore when the user opens the Rewards Store page! 🎉
