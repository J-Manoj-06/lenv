import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// Top-level function for background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
  debugPrint('Data: ${message.data}');

  // Save notification to Firestore if needed
  if (message.data.isNotEmpty) {
    await NotificationService._saveNotificationFromBackground(message);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notificationTapStream =>
      _notificationTapController.stream;

  bool _isInitialized = false;
  static const int _communityUploadNotificationId = 700001;
  int? _lastCommunityUploadPercent;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('NotificationService already initialized');
      return;
    }

    try {
      // Request permission
      await requestPermission();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get and save FCM token
      await _initializeFCMToken();

      // Setup message listeners
      _setupMessageListeners();

      _isInitialized = true;
      debugPrint('NotificationService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Request notification permissions
  Future<bool> requestPermission() async {
    try {
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      debugPrint(
        'Notification permission status: ${settings.authorizationStatus}',
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    debugPrint('Local notifications initialized');
  }

  /// Initialize FCM token and save to Firestore
  Future<void> _initializeFCMToken() async {
    try {
      final token = await getToken();
      if (token != null) {
        await saveTokenToFirestore(token);
      }

      // Listen to token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM token refreshed: $newToken');
        saveTokenToFirestore(newToken);
      });
    } catch (e) {
      debugPrint('Error initializing FCM token: $e');
    }
  }

  /// Get FCM token
  Future<String?> getToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $token');
      return token;
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to Firestore
  Future<void> saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in, cannot save token');
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
      );

      debugPrint('FCM token saved to Firestore for user: ${user.uid}');
    } catch (e) {
      debugPrint('Error saving token to Firestore: $e');
    }
  }

  /// Setup message listeners
  void _setupMessageListeners() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background messages (app opened but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if app was opened from terminated state by notification
    _checkInitialMessage();
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message received: ${message.messageId}');

    // Save to Firestore
    await _saveNotificationToFirestore(message);

    // Show local notification
    await _showLocalNotification(message);
  }

  /// Handle message when app opened from background
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('Message opened app: ${message.messageId}');
    _handleNotificationNavigation(message.data);
  }

  /// Check if app was opened from terminated state
  Future<void> _checkInitialMessage() async {
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();

    if (initialMessage != null) {
      debugPrint(
        'App opened from terminated state: ${initialMessage.messageId}',
      );
      _handleNotificationNavigation(initialMessage.data);
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'lenv_channel',
          'Lenv Notifications',
          channelDescription: 'Notifications for Lenv education app',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      notificationDetails,
      payload: jsonEncode(message.data),
    );
  }

  /// Handle notification tap
  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _handleNotificationNavigation(data);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  /// Handle notification navigation
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    debugPrint('Handling notification navigation: $data');
    _notificationTapController.add(data);
  }

  /// Save notification to Firestore
  static Future<void> _saveNotificationToFirestore(
    RemoteMessage message,
  ) async {
    try {
      final userId = message.data['userId'];
      if (userId == null) {
        debugPrint('No userId in notification data');
        return;
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'title': message.notification?.title ?? '',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'referenceId': message.data['referenceId'],
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'data': message.data,
      });

      debugPrint('Notification saved to Firestore');
    } catch (e) {
      debugPrint('Error saving notification to Firestore: $e');
    }
  }

  /// Save notification from background handler
  static Future<void> _saveNotificationFromBackground(
    RemoteMessage message,
  ) async {
    try {
      await _saveNotificationToFirestore(message);
    } catch (e) {
      debugPrint('Error saving background notification: $e');
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});

      debugPrint('Notification marked as read: $notificationId');
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Get unread notification count
  Future<int> getUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;

      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  /// Stream of unread notification count
  Stream<int> unreadCountStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();

      debugPrint('Notification deleted: $notificationId');
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }

  /// Clear all notifications for current user
  Future<void> clearAllNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint('All notifications cleared');
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
    }
  }

  /// Show/update Android status bar notification for upload progress.
  /// Uses throttling so progress updates don't spam the notification manager.
  Future<void> showUploadProgressNotification({
    required double progress,
    required int activeUploads,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      final percent = (progress.clamp(0.0, 1.0) * 100).round();
      final previous = _lastCommunityUploadPercent;
      if (previous != null && percent < 100 && (percent - previous).abs() < 5) {
        return;
      }
      _lastCommunityUploadPercent = percent;

      final subtitle = activeUploads > 1
          ? '$activeUploads uploads • $percent%'
          : '$percent%';

      final androidDetails = AndroidNotificationDetails(
        'lenv_upload_channel',
        'Upload Status',
        channelDescription: 'Shows media upload progress and completion status',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: percent,
        ongoing: percent < 100,
        onlyAlertOnce: true,
      );

      final details = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        _communityUploadNotificationId,
        'Uploading media',
        subtitle,
        details,
      );
    } catch (e) {
      debugPrint('Error showing upload progress notification: $e');
    }
  }

  /// Show upload completion notification.
  Future<void> showUploadCompletedNotification() async {
    if (!Platform.isAndroid) return;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      _lastCommunityUploadPercent = null;

      const androidDetails = AndroidNotificationDetails(
        'lenv_upload_channel',
        'Upload Status',
        channelDescription: 'Shows media upload progress and completion status',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: false,
      );

      const details = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        _communityUploadNotificationId,
        'Upload completed',
        'Media upload completed',
        details,
      );
    } catch (e) {
      debugPrint('Error showing upload completed notification: $e');
    }
  }

  /// Clear upload notification (used on failure/cancel cleanup).
  Future<void> clearUploadNotification() async {
    if (!Platform.isAndroid) return;
    try {
      _lastCommunityUploadPercent = null;
      await _localNotifications.cancel(_communityUploadNotificationId);
    } catch (e) {
      debugPrint('Error clearing upload notification: $e');
    }
  }

  /// Dispose
  void dispose() {
    _notificationTapController.close();
  }
}
