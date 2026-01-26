#!/usr/bin/env node

/**
 * Upload Rewards JSON to Firestore rewards_catalog collection
 * Usage: node scripts/upload_rewards_to_firestore.js
 * 
 * Prerequisites:
 * 1. Install Firebase Admin SDK: npm install firebase-admin
 * 2. Set GOOGLE_APPLICATION_CREDENTIALS environment variable to your service account JSON file
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin SDK
// Make sure you have GOOGLE_APPLICATION_CREDENTIALS set to your service account file
try {
  const serviceAccount = require('../config/service-account-key.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
} catch (error) {
  console.error('❌ Error initializing Firebase Admin SDK:');
  console.error('   Make sure GOOGLE_APPLICATION_CREDENTIALS is set or service-account-key.json exists in config/');
  console.error('   Error:', error.message);
  process.exit(1);
}

const db = admin.firestore();
const CATALOG_COLLECTION = 'rewards_catalog';

async function uploadRewardsToCatalog() {
  try {
    console.log('📦 Starting rewards upload to Firestore...\n');

    // Read the JSON file
    const jsonPath = path.join(__dirname, '../assets/dummy_rewards.json');
    const fileContent = fs.readFileSync(jsonPath, 'utf8');
    
    // Parse the JSON - handling both array and individual objects format
    let products = [];
    
    // Try to parse as array first
    try {
      const parsed = JSON.parse(fileContent);
      if (Array.isArray(parsed)) {
        products = parsed;
      } else {
        // If it's a single object, wrap in array
        products = [parsed];
      }
    } catch (e) {
      // If the file has multiple JSON objects (not valid JSON), split and parse each
      const jsonObjects = fileContent.split(/\n\n+/); // Split by empty lines
      for (const obj of jsonObjects) {
        const trimmed = obj.trim();
        if (trimmed) {
          try {
            products.push(JSON.parse(trimmed));
          } catch (parseError) {
            console.warn(`⚠️  Skipping invalid JSON object: ${trimmed.substring(0, 50)}...`);
          }
        }
      }
    }

    if (products.length === 0) {
      console.error('❌ No valid products found in JSON file');
      process.exit(1);
    }

    console.log(`✅ Found ${products.length} products to upload\n`);

    // Delete existing collection (optional - comment out if you want to merge)
    console.log('🗑️  Clearing existing rewards_catalog collection...');
    const snapshot = await db.collection(CATALOG_COLLECTION).get();
    const batch = db.batch();
    snapshot.forEach((doc) => {
      batch.delete(doc.ref);
    });
    await batch.commit();
    console.log(`✅ Deleted ${snapshot.size} existing documents\n`);

    // Upload each product
    console.log('📤 Uploading products to Firestore...\n');
    let successCount = 0;
    let errorCount = 0;

    for (const product of products) {
      try {
        const productId = product.product_id || product.id;
        if (!productId) {
          console.warn('⚠️  Skipping product without product_id:', product.title);
          errorCount++;
          continue;
        }

        // Ensure required fields exist
        const docData = {
          ...product,
          product_id: productId,
          // Add derived fields for points calculation
          price: {
            currency: product.price?.currency || 'INR',
            estimated_price: product.price?.discounted_price || product.price?.original_price || 0,
            original_price: product.price?.original_price || 0,
          },
          points_rule: product.points_rule || {
            points_per_rupee: 0.75,
            max_points: Math.floor((product.price?.discounted_price || 0) * 0.75),
          },
          status: product.status || 'active',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection(CATALOG_COLLECTION).doc(productId).set(docData);
        console.log(`✅ Uploaded: ${product.title} (${productId})`);
        successCount++;
      } catch (error) {
        console.error(`❌ Error uploading product:`, error.message);
        errorCount++;
      }
    }

    console.log(`\n${'='.repeat(60)}`);
    console.log(`📊 Upload Summary:`);
    console.log(`✅ Successful: ${successCount}/${products.length}`);
    console.log(`❌ Failed: ${errorCount}/${products.length}`);
    console.log(`${'='.repeat(60)}\n`);

    if (successCount === products.length) {
      console.log('🎉 All rewards uploaded successfully!');
      console.log('✨ The rewards catalog is now live in Firestore.');
    } else {
      console.warn('⚠️  Some products failed to upload. Check errors above.');
    }

  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    process.exit(1);
  } finally {
    // Close the Firebase connection
    await admin.app().delete();
    process.exit(0);
  }
}

// Run the upload
uploadRewardsToCatalog();
