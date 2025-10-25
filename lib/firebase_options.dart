import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'core/config/firebase_config.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // Return Web options using FirebaseConfig. Ensure values are filled in firebase_config.dart
      final missing = [
        FirebaseConfig.webApiKey,
        FirebaseConfig.webAuthDomain,
        FirebaseConfig.webProjectId,
        FirebaseConfig.webStorageBucket,
        FirebaseConfig.webMessagingSenderId,
        FirebaseConfig.webAppId,
      ].any((v) => v.isEmpty || v.startsWith('PASTE_'));

      if (missing) {
        throw UnsupportedError(
          'Firebase Web configuration is missing.\n\n'
          'Do this once to run on Chrome:\n'
          '1) In Firebase Console → Project Settings → Your apps (</>) → SDK setup (Config)\n'
          '2) Copy apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId\n'
          '3) Paste into lib/core/config/firebase_config.dart (web* fields)\n\n'
          'Alternatively, run: flutterfire configure --platforms=web,android',
        );
      }

      return FirebaseOptions(
        apiKey: FirebaseConfig.webApiKey,
        authDomain: FirebaseConfig.webAuthDomain,
        projectId: FirebaseConfig.webProjectId,
        storageBucket: FirebaseConfig.webStorageBucket,
        messagingSenderId: FirebaseConfig.webMessagingSenderId,
        appId: FirebaseConfig.webAppId,
        measurementId: FirebaseConfig.webMeasurementId.isEmpty
            ? null
            : FirebaseConfig.webMeasurementId,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: FirebaseConfig.androidApiKey,
    appId: FirebaseConfig.androidAppId,
    messagingSenderId: FirebaseConfig.androidMessagingSenderId,
    projectId: FirebaseConfig.androidProjectId,
    storageBucket: FirebaseConfig.androidStorageBucket,
  );
}
