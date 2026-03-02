import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'media_repository.dart';

/// Background download service with notification progress
class BackgroundDownloadService {
  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();
  factory BackgroundDownloadService() => _instance;
  BackgroundDownloadService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final MediaRepository _repository = MediaRepository();

  // Track active downloads
  final Map<String, _DownloadTask> _activeDownloads = {};
  int _notificationId = 1000;
  bool _isInitialized = false;

  /// Initialize notification channels
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'downloads',
      'Downloads',
      description: 'Media download progress notifications',
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _isInitialized = true;
  }

  /// Start downloading multiple files with notification progress
  Future<Map<int, String>> downloadMultipleImages({
    required List<String> urls,
    required Function(int downloaded, int total, double progress) onProgress,
  }) async {
    if (!_isInitialized) await initialize();

    final notificationId = _notificationId++;
    final results = <int, String>{};

    // Count files that need downloading
    final toDownload = <int>[];
    for (int i = 0; i < urls.length; i++) {
      final r2Key = _extractR2Key(urls[i]);
      final isDownloaded = await _repository.isDownloaded(r2Key);
      if (!isDownloaded) {
        toDownload.add(i);
      } else {
        // Already downloaded - get path
        final path = await _repository.getLocalFilePath(r2Key);
        if (path != null) {
          results[i] = path;
        }
      }
    }

    if (toDownload.isEmpty) {
      // All files already downloaded
      return results;
    }

    final totalFiles = toDownload.length;
    int downloadedFiles = 0;

    // Show initial notification
    await _showProgressNotification(
      notificationId,
      downloadedFiles,
      totalFiles,
      0.0,
    );

    // Download each file
    for (final index in toDownload) {
      final url = urls[index];
      final r2Key = _extractR2Key(url);

      try {
        final result = await _repository.downloadMedia(
          r2Key: r2Key,
          fileName: 'image_$index.jpg',
          mimeType: 'image/jpeg',
          onProgress: (fileProgress) {
            // Update notification with overall progress
            final overallProgress =
                (downloadedFiles + fileProgress) / totalFiles;
            _showProgressNotification(
              notificationId,
              downloadedFiles,
              totalFiles,
              overallProgress,
            );
            onProgress(downloadedFiles, totalFiles, overallProgress);
          },
        );

        if (result.success && result.localPath != null) {
          results[index] = result.localPath!;
        }
      } catch (e) {
        print('❌ Download failed for image $index: $e');
      }

      downloadedFiles++;

      // Update notification
      if (downloadedFiles < totalFiles) {
        await _showProgressNotification(
          notificationId,
          downloadedFiles,
          totalFiles,
          downloadedFiles / totalFiles,
        );
      }

      onProgress(downloadedFiles, totalFiles, downloadedFiles / totalFiles);
    }

    // Show completion notification
    await _showCompletionNotification(notificationId, totalFiles);

    return results;
  }

  /// Show progress notification
  Future<void> _showProgressNotification(
    int id,
    int downloaded,
    int total,
    double progress,
  ) async {
    final progressPercent = (progress * 100).toInt();

    await _notifications.show(
      id,
      'Downloading images',
      '$downloaded of $total files • $progressPercent%',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'downloads',
          'Downloads',
          channelDescription: 'Media download progress notifications',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: 100,
          progress: progressPercent,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Show completion notification
  Future<void> _showCompletionNotification(int id, int totalFiles) async {
    await _notifications.show(
      id,
      'Download complete',
      '$totalFiles ${totalFiles == 1 ? 'file' : 'files'} downloaded',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'downloads',
          'Downloads',
          channelDescription: 'Media download progress notifications',
          importance: Importance.low,
          priority: Priority.low,
          autoCancel: true,
          timeoutAfter: 3000,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      _notifications.cancel(id);
    });
  }

  /// Extract R2 key from URL
  String _extractR2Key(String url) {
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      return uri.path.replaceFirst('/', '');
    }
    return url;
  }

  /// Cancel all downloads
  Future<void> cancelAllDownloads() async {
    _activeDownloads.clear();
    await _notifications.cancelAll();
  }
}

class _DownloadTask {
  final String url;
  final int notificationId;
  double progress;
  bool isCompleted;

  _DownloadTask({required this.url, required this.notificationId})
    : progress = 0.0,
      isCompleted = false;
}
