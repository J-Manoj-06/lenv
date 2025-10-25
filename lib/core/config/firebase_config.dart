class FirebaseConfig {
  // 🔴 ANDROID CONFIGURATION
  // ⚠️ IMPORTANT: You also need to add google-services.json file!
  // Download from Firebase Console and place in: android/app/google-services.json

  // Go to Firebase Console → Project Settings → Your apps → Android app
  // These values will be automatically used by google-services.json
  // You can also find them inside the google-services.json file

  // Example: apiKey: "AIzaSyAbc123XyZ456..."
  static const String androidApiKey = "AIzaSyDHkJlh_hgesrpO49PY3-9eRb2COckP1ac";

  // Example: projectId: "your-project-id"
  static const String androidProjectId = "lenv-cb08e";

  // Example: storageBucket: "your-project.appspot.com"
  static const String androidStorageBucket = "lenv-cb08e.firebasestorage.app";

  // Example: messagingSenderId: "123456789012"
  static const String androidMessagingSenderId = "527854850261";

  // Example: appId: "1:123456789012:android:abc123def456"
  static const String androidAppId =
      "1:527854850261:android:a95b922873b0780023525c";

  // Package name (must match android/app/build.gradle)
  static const String androidPackageName = "com.lenv.reward";

  // 🟠 WEB CONFIGURATION (fill these to run on Chrome)
  // Get these from Firebase Console → Project Settings → Your Apps (Web) → SDK setup and configuration (Config)
  // It's OK to commit for development, but treat as sensitive in production.
  static const String webApiKey = "AIzaSyCsa_llQygftW7meLRGHbY66B1cJ-nzAFI"; // e.g. AIzaSy...
  static const String webAuthDomain =
      "lenv-cb08e.firebaseapp.com"; // e.g. your-project.firebaseapp.com
  static const String webProjectId = "lenv-cb08e"; // your Firebase project id
  static const String webStorageBucket =
      "lenv-cb08e.firebasestorage.app"; // e.g. your-project.appspot.com
  static const String webMessagingSenderId =
      "527854850261"; // e.g. 1234567890
  static const String webAppId =
      "1:527854850261:web:fff94d3f9eabc03923525c"; // e.g. 1:1234567890:web:abc123
  static const String webMeasurementId = "G-YS604XE79C"; // optional (for analytics)
}
